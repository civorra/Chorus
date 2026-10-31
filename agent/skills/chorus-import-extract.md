# Sub-skill — chorus-import-extract

> **Internal sub-skill** — loaded by `chorus-import-project` Phase 0 for document
> sources (PDF, DOCX, XLSX/CSV) that require preprocessing before semantic alignment.
> **Not loaded for structured JSON/CycloneDX/XML sources** (Phase -0.1 handles those).
>
> Trigger: loaded via `eca__skill("chorus-import-extract")` from Phase 0 of
> `chorus-import-project` when `source_format` ∉ {JSON, CycloneDX, XML structuré}.


### Case B — Filesystem source (files on disk)

Identify the format and extract plain text **before** any semantic processing.

#### PDF — hybrid extraction (same pipeline as `chorus-pdf --hybrid`)

PDF extraction uses the **same 4-mode pipeline as `chorus-pdf`**:
figures, diagrams, and normative tables are recovered via Claude vision — not just raw text.

##### Step 0 — Auto-detect mode (no explicit flag)

```python
import os, json, urllib.request, urllib.error

def probe_claude(api_key):
    payload = {"model": "claude-haiku-4-5", "max_tokens": 1,
               "messages": [{"role": "user", "content": "ping"}]}
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
               "content-type": "application/json"}
    try:
        req = urllib.request.Request("https://api.anthropic.com/v1/messages",
            data=json.dumps(payload).encode(), headers=headers, method="POST")
        urllib.request.urlopen(req, timeout=10)
        return True
    except urllib.error.HTTPError as e:
        return e.code in (429, 529)   # throttled but valid
    except Exception:
        return False

api_key = os.environ.get("ANTHROPIC_API_KEY", "")
if api_key and probe_claude(api_key):
    pdf_mode = "hybrid"    # default — pdfminer text + Claude vision on figures
    print("[import] ANTHROPIC_API_KEY detected — hybrid mode activated.", flush=True)
else:
    pdf_mode = "text"      # fallback — pdfminer only
    print("[import] No API key or Claude unreachable — text mode (fallback).", flush=True)
```

| `ANTHROPIC_API_KEY` | Probe | Mode |
|---|---|---|
| absent | — | **text** (pdfminer only) |
| present, valid | ✅ | **hybrid** (pdfminer + Claude vision on figures) |
| present, invalid | ❌ 401/403 | **text** |
| present, throttled | ⚠️ 429/529 | **hybrid** |

##### Step 1 — Layout analysis (pdfminer)

```python
from pdfminer.high_level import extract_pages
from pdfminer.layout import LAParams, LTTextBox, LTFigure

laparams = LAParams(boxes_flow=0.5, char_margin=2.0)
page_data = {}   # {page_num: {'texts': [(text, y_center)], 'figures': [(x0,y0,x1,y1)], 'height': float}}

for page_num, layout in enumerate(extract_pages(pdf_path, laparams=laparams), 1):
    texts, figures = [], []
    for el in layout:
        if isinstance(el, LTTextBox):
            t = el.get_text().strip()
            if t:
                texts.append((t, (el.y0 + el.y1) / 2))
        elif isinstance(el, LTFigure):
            figures.append((el.x0, el.y0, el.x1, el.y1))
    page_data[page_num] = {'texts': texts, 'figures': figures, 'height': layout.height}
```

##### Step 2 — Hybrid mode: crop figures and call Claude

Only if `pdf_mode == "hybrid"` **and** figures were detected.

```python
import base64, io, subprocess, tempfile
from PIL import Image

DPI = 150

def pdf_bbox_to_png_crop(x0, y0, x1, y1, page_height, dpi=DPI):
    scale = dpi / 72.0
    margin = int(4 * scale)
    return (
        max(0, int(x0 * scale) - margin),
        max(0, int((page_height - y1) * scale) - margin),
        int(x1 * scale) + margin,
        int((page_height - y0) * scale) + margin,
    )

FIGURE_PROMPT = """You are a technical document extraction engine.
Describe this figure extracted from an engineering project document.
Output a block of the form:
  [FIGURE <N> — <title or caption if visible>]
  <Structured description: labeled dimensions, named components, numerical values,
   spatial relationships, units, arrows, hatching, scale bar if present>
  [END FIGURE <N>]
  IDENTIFIERS: ["<id1>", "<id2>", ...]
If no caption is visible, assign [FIGURE ?]. Do not add text outside the
[FIGURE] ... [END FIGURE] block and IDENTIFIERS line.
For IDENTIFIERS: list every alphanumeric code, label, designation or identifier
visible in the figure (callout tags, part numbers, element IDs, zone codes,
article references). Use the exact string as printed. Exclude purely numeric
values (dimensions, measurements), single generic letters, and common stopwords.
Output a valid JSON array on a single line immediately after [END FIGURE <N>].
Output [] if no identifiers found.
Use UTF-8. Preserve special characters (±, ≤, ≥, ×, °, ², ³…)."""

def call_claude_figure(png_bytes, page_num, fig_idx, api_key):
    import json as _json, urllib.request as _req, urllib.error as _err, time
    b64 = base64.standard_b64encode(png_bytes).decode()
    payload = {
        "model": "claude-opus-4-5", "max_tokens": 2048,
        "messages": [{"role": "user", "content": [
            {"type": "text",  "text": f"[Page {page_num}, Figure {fig_idx}]\n\n{FIGURE_PROMPT}"},
            {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": b64}},
        ]}]
    }
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
               "content-type": "application/json"}
    for attempt in range(4):
        r = _req.Request("https://api.anthropic.com/v1/messages",
            data=_json.dumps(payload).encode(), headers=headers, method="POST")
        try:
            with _req.urlopen(r, timeout=120) as resp:
                return _json.loads(resp.read())["content"][0]["text"].strip()
        except _err.HTTPError as e:
            if e.code in (429, 529) and attempt < 3:
                time.sleep(10 * (2 ** attempt)); continue
            raise

# all_figure_descs accumulates figure descriptions across ALL pages before assembly
all_figure_descs = {}   # {(page_num, fig_idx): description_text}

with tempfile.TemporaryDirectory(prefix="chorus-import-pdf-") as tmpdir:
    for page_num, pdata in sorted(page_data.items()):
        if pdf_mode == "hybrid" and pdata['figures']:
            prefix = os.path.join(tmpdir, f"p{page_num:04d}")
            subprocess.run(
                ["pdftoppm", "-r", str(DPI), "-png",
                 "-f", str(page_num), "-l", str(page_num), pdf_path, prefix],
                check=True, capture_output=True)
            import glob as _glob
            png_files = sorted(_glob.glob(prefix + "*.png"))
            img = Image.open(png_files[0])
            for fig_idx, bbox in enumerate(pdata['figures'], 1):
                crop_box = pdf_bbox_to_png_crop(*bbox, pdata['height'])
                w, h = img.size
                crop_box = (min(crop_box[0],w), min(crop_box[1],h),
                            min(crop_box[2],w), min(crop_box[3],h))
                buf = io.BytesIO()
                img.crop(crop_box).save(buf, format="PNG")
                all_figure_descs[(page_num, fig_idx)] = call_claude_figure(
                    buf.getvalue(), page_num, fig_idx, api_key)
# → all_figure_descs collected — proceed to Step 2.5 before assembling pages
```

##### Step 2.5 — Cross-reference pass (hybrid mode only)

Same logic as `chorus-pdf --hybrid` Phase 2.5 — runs **after** all figure descriptions
are collected, **before** page assembly. No additional API calls.

```python
import re as _re

_XREF_STOPWORDS = {
    "N", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
    "M", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "kN", "mm", "cm", "m", "kg", "kPa", "MPa", "GPa", "kNm",
    "Figure", "Table", "Clause", "Section", "Annex", "NOTE", "Fig",
}
_XREF_MIN_LEN = 2

def _parse_identifiers(description):
    ids = []
    m = _re.search(r'^IDENTIFIERS:\s*(\[.*?\])\s*$', description, _re.MULTILINE)
    if m:
        try:
            import json as _j
            ids = [str(x).strip() for x in _j.loads(m.group(1)) if str(x).strip()]
        except Exception:
            pass
    if not ids:
        ids = _re.findall(r'\b([A-Za-z][A-Za-z0-9\-_]{1,19})\b', description)
    seen, result = set(), []
    for ident in ids:
        if ident in _XREF_STOPWORDS or len(ident) < _XREF_MIN_LEN:
            continue
        if ident.lower() not in seen:
            seen.add(ident.lower())
            result.append(ident)
    return result

def _find_text_occurrences(identifier, page_data):
    pattern = _re.compile(r'\b' + _re.escape(identifier) + r'\b')
    results = []
    for page_num in sorted(page_data):
        for (block_text, _y) in page_data[page_num]['texts']:
            hit = pattern.search(block_text)
            if hit:
                s = max(0, hit.start() - 55)
                e = min(len(block_text), hit.end() + 55)
                snip = block_text[s:e].replace('\n', ' ').strip()
                if s > 0:   snip = '…' + snip
                if e < len(block_text): snip += '…'
                results.append((page_num, snip))
    return results

def _xref_pass(all_figure_descs, page_data):
    """Returns (annotated_descs, xref_index_block, xref_map).

    xref_map : {identifier: [(page_num, fig_idx, occurrences), ...]}
    Used directly by Phase 3 terminology alignment as first-class matching candidates.
    """
    annotated, global_index = {}, {}

    for (page_num, fig_idx), desc in all_figure_descs.items():
        identifiers = _parse_identifiers(desc)
        if not identifiers:
            annotated[(page_num, fig_idx)] = desc
            continue

        xref_lines = [f"[XREF FIGURE {fig_idx} — page {page_num}]"]
        for ident in identifiers:
            occs = _find_text_occurrences(ident, page_data)
            xref_lines.append(f"  {ident}:")
            if occs:
                for p, snip in occs:
                    xref_lines.append(f"    p.{p}: {snip}")
            else:
                xref_lines.append("    (no occurrence found in text)")
            global_index.setdefault(ident, []).append((page_num, fig_idx, occs))
        xref_lines.append(f"[END XREF FIGURE {fig_idx}]")

        # Append annotation after [END FIGURE …]
        annotated_desc = _re.sub(
            r'(\[END FIGURE[^\]]*\])',
            r'\1\n' + '\n'.join(xref_lines),
            desc, count=1
        )
        if annotated_desc == desc:
            annotated_desc = desc + '\n' + '\n'.join(xref_lines)
        annotated[(page_num, fig_idx)] = annotated_desc

    # Build XREF INDEX block
    lines = ["=== XREF INDEX ===",
             "# Cross-reference: figure identifiers → text occurrences", ""]
    for ident in sorted(global_index):
        entries = global_index[ident]
        fig_refs = [f"Figure {fi} (p.{pn})" for pn, fi, _ in entries]
        all_occs = [(p, s) for _, _, occs in entries for p, s in occs]
        lines.append(f"## {ident}")
        lines.append(f"   Appears in: {', '.join(fig_refs)}")
        seen_p = set()
        for p, snip in all_occs:
            if p not in seen_p:
                lines.append(f"   Text occurrence (p.{p}): {snip}")
                seen_p.add(p)
        if not all_occs:
            lines.append("   Text occurrence: (none found)")
        lines.append("")
    lines.append("=== END XREF INDEX ===")

    return annotated, '\n'.join(lines), global_index

# --- Run the cross-reference pass (hybrid only) ---
if pdf_mode == "hybrid" and all_figure_descs:
    annotated_descs, xref_index_block, xref_map = _xref_pass(all_figure_descs, page_data)
else:
    annotated_descs = all_figure_descs
    xref_index_block = ""
    xref_map = {}
# xref_map is passed to Phase 3 as first-class matching candidates
```

> **`xref_map`** is the key output for Phase 3: it maps each figure identifier to the
> text snippets where it co-occurs with corpus terms.
> Phase 3 consults `xref_map` at step 1 (KB aliases) and step 2 (figure body)
> before falling back to generic text search.

##### Step 3 — Assemble pages in reading order (top→bottom)

```python
def assemble_page(page_num, pdata, figure_descriptions):
    elements = []
    for text, y in pdata['texts']:
        elements.append((y, 'text', text))
    for fig_idx, (x0, y0, x1, y1) in enumerate(pdata['figures'], 1):
        desc = figure_descriptions.get(fig_idx,
               f"[FIGURE {fig_idx} — not extracted (text mode)]")
        elements.append(((y0+y1)/2, 'figure', desc))
    elements.sort(key=lambda e: e[0], reverse=True)   # highest Y first
    body = "\n\n".join(content for (_, _, content) in elements)
    return f"=== PAGE {page_num} ===\n{body}\n=== END PAGE {page_num} ==="

# Build per-page figure_descriptions from annotated_descs
per_page_figs = {}
for (page_num, fig_idx), desc in annotated_descs.items():
    per_page_figs.setdefault(page_num, {})[fig_idx] = desc

pages_output = []
for page_num in sorted(page_data):
    pages_output.append(assemble_page(page_num, page_data[page_num],
                                      per_page_figs.get(page_num, {})))

# Append XREF INDEX at end (hybrid only — empty string otherwise)
if xref_index_block:
    pages_output.append(xref_index_block)

extracted_text = "\n\n".join(pages_output)
# extracted_text is the final source passed to Phase 2 (raw inventory)
# xref_map is passed separately to Phase 3 (terminology alignment)
```

##### Step 4 — nohup gate (hybrid only)

If the layout analysis detects **> 15 figures** (≈ > 7.5 min at ~30 s/call):
- Print a `nohup` command and **stop** (do not proceed)
- When relaunched with `CHORUS_PDF_FORCE=1 nohup python3 <script>` → proceed unconditionally

```
[import-pdf] ⚠️  18 figures detected — estimated time ~9–13 min (threshold: 15).
[import-pdf]    Run with nohup to avoid a 10-min IDE timeout:
[import-pdf]    CHORUS_PDF_FORCE=1 nohup python3 <script.py> > <output.md>.log 2>&1 &
```

> ⚠️ **If the extraction script exits with code 2** (nohup required):
> ECA must **not** retry automatically. It must set `CHORUS_PDF_FORCE=1`
> and relaunch with `nohup` — pre-approved, no confirmation required.

##### Dependencies

| Package | Install |
|---------|---------|
| `pdfminer.six` | `pip install pdfminer.six` |
| `Pillow` | `pip install Pillow` (hybrid mode only) |
| `pdftoppm` | `sudo apt install poppler-utils` (hybrid mode only) |
| `ANTHROPIC_API_KEY` | `export ANTHROPIC_API_KEY="sk-ant-..."` (hybrid mode only) |

##### Text-mode fallback (no API key)

When `pdf_mode == "text"`, figures produce a placeholder instead of a Claude description:

```
[FIGURE — not extracted]
[Run chorus-import-project with ANTHROPIC_API_KEY set to extract figures via hybrid mode]
```

The rest of the extraction (text blocks, reading order) is identical.

> ⛔ **Figure-heavy domains — critical warning**
>
> When `pdf_mode == "text"` is active **and** the layout analysis detected ≥ 5 figures,
> emit a prominent warning **before proceeding**:
>
> ```
> [import-pdf] ⛔  Text mode active — N figures not extracted.
>              In figure-heavy domains (BTP/Construction, Medical Devices/MDR),
>              plans, assembly diagrams and specification tables embedded as images
>              typically contain the constituent element identifiers (P1, P2, IPE-01,
>              component tags, MDR annex references…).
>              Phase 3 will be blind to these elements → JSON likely incomplete.
>              Strongly recommended: set ANTHROPIC_API_KEY and rerun to activate hybrid mode.
>              Continue in text-only mode? [yes / abort]
> ```
>
> If the engineer confirms `yes`, proceed — but add `"_extraction_warning": "text-mode: N figures not extracted"` in the `_import` block of the output JSON.
> In batch mode, emit the warning once per file that triggers the threshold.

#### Excel / CSV — full-quality pipeline (same depth as PDF)

Excel and CSV extraction uses the **same architecture as `chorus-pdf`**: tables are
reconstructed as Markdown pipe tables with merged-cell handling, embedded images and
charts are sent to Claude vision (hybrid mode), and the XREF pass links figure
identifiers back to cell values across all sheets.

##### Format detection

```python
import os
ext = os.path.splitext(source_path)[1].lower()
if ext == '.csv':
    excel_mode = 'csv'    # always text — no images
elif ext in ('.xlsx', '.xlsm', '.ods'):
    excel_mode = 'excel'  # hybrid or text depending on API key
else:
    excel_mode = 'fallback'  # libreoffice convert → csv
```

##### Step 0 — Auto-detect mode (Excel only — identical to PDF pipeline)

Same `probe_claude()` probe as PDF Step 0. Three-branch result:
`extraction_mode = "hybrid"` (xlsx + valid key) / `"csv"` (csv format, unconditionally) / `"text"` (fallback).
Print prefix: `[import-excel]`.

##### Step 1 — CSV extraction

```python
import csv

def csv_to_markdown(csv_path):
    with open(csv_path, newline='', encoding='utf-8-sig') as f:
        rows = list(csv.reader(f))
    if not rows:
        return ""
    def cell(c):
        return str(c or "").replace("|", "｜").strip()
    n_cols = max(len(r) for r in rows)
    rows_padded = [r + [''] * (n_cols - len(r)) for r in rows]
    lines = ["| " + " | ".join(cell(c) for c in rows_padded[0]) + " |",
             "| " + " | ".join("---" for _ in rows_padded[0]) + " |"]
    for row in rows_padded[1:]:
        lines.append("| " + " | ".join(cell(c) for c in row) + " |")
    return "\n".join(lines)

extracted_text = csv_to_markdown(source_path)
# → proceed to Phase 2 (no xref_map for CSV)
xref_map = {}
```

##### Step 1 — XLSX extraction (text mode and hybrid mode)

```python
import openpyxl

def build_merged_map(ws):
    """Map (row, col) → master_value for all merged cell slaves."""
    merged_map = {}
    for merged_range in ws.merged_cells.ranges:
        cells = list(merged_range.cells)
        if not cells:
            continue
        master_row, master_col = cells[0]
        master_val = ws.cell(row=master_row, column=master_col).value
        master_str = str(master_val) if master_val is not None else ""
        for row, col in cells[1:]:
            merged_map[(row, col)] = master_str
    return merged_map

def cell_value(cell, merged_map):
    if cell.value is not None:
        return str(cell.value)
    return merged_map.get((cell.row, cell.column), "")

def sheet_to_markdown(ws):
    """Convert one worksheet to a Markdown pipe table, handling merged cells."""
    merged_map = build_merged_map(ws)
    rows_out = []
    for row in ws.iter_rows():
        cells_out = [cell_value(c, merged_map).replace("|", "｜").replace("\n", " ").strip()
                     for c in row]
        rows_out.append(cells_out)
    # Skip fully empty rows
    rows_out = [r for r in rows_out if any(c for c in r)]
    if not rows_out:
        return "(empty sheet)"
    n_cols = max(len(r) for r in rows_out)
    rows_padded = [r + [''] * (n_cols - len(r)) for r in rows_out]
    lines = ["| " + " | ".join(rows_padded[0]) + " |",
             "| " + " | ".join("---" for _ in rows_padded[0]) + " |"]
    for row in rows_padded[1:]:
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)

wb = openpyxl.load_workbook(source_path, data_only=True)
sheet_parts = []
all_image_entries = []    # [(sheet_name, img_idx, png_bytes)]
all_chart_entries = []    # [(sheet_name, chart_idx, png_bytes_or_None)]

for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    sheet_parts.append(f"=== SHEET: {sheet_name} ===")
    sheet_parts.append(sheet_to_markdown(ws))
    # Collect embedded images
    for i, img_anchor in enumerate(ws._images, 1):
        png = convert_blob_to_png(img_anchor.image.blob)  # Pillow conversion
        all_image_entries.append((sheet_name, i, png))
        if extraction_mode == "text":
            sheet_parts.append(
                f"\n[IMAGE {i} — not extracted]\n"
                "[Run with ANTHROPIC_API_KEY to extract images via hybrid mode]")
    # Collect charts
    for i, chart_anchor in enumerate(ws._charts, 1):
        if extraction_mode == "hybrid":
            png = chart_to_png_via_libreoffice(source_path, chart_anchor, tmpdir)
            all_chart_entries.append((sheet_name, i, png))
        else:
            sheet_parts.append(
                f"\n[CHART {i} — not extracted]\n"
                "[Run with ANTHROPIC_API_KEY + LibreOffice to extract charts via hybrid mode]")
    sheet_parts.append(f"=== END SHEET: {sheet_name} ===")
```

##### Step 2 — Hybrid mode: Claude vision on images and charts

Only if `extraction_mode == "hybrid"` and images/charts were detected.

```python
from PIL import Image
import io, base64, json, urllib.request, time

def convert_blob_to_png(blob):
    """Convert image blob (PNG/JPEG/EMF) to PNG bytes via Pillow."""
    try:
        img = Image.open(io.BytesIO(blob))
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        return buf.getvalue()
    except Exception:
        return blob if blob[:4] == b'\x89PNG' else None

# call_claude_figure: same function as chorus-pdf hybrid (FIGURE_PROMPT, claude-opus-4-5, retry)
all_figure_descs = {}   # {(sheet_name, img_idx): description_text}

for sheet_name, img_idx, png_bytes in all_image_entries:
    if png_bytes:
        desc = call_claude_figure(png_bytes, sheet_name, img_idx, api_key)
        all_figure_descs[(sheet_name, img_idx)] = desc

for sheet_name, chart_idx, png_bytes in all_chart_entries:
    if png_bytes:
        desc = call_claude_figure(png_bytes, sheet_name, chart_idx + 1000, api_key)
        all_figure_descs[(sheet_name, chart_idx + 1000)] = desc
```

##### Step 2.5 — Cross-reference pass (hybrid mode only)

The XREF pass links figure identifiers to cell values across all sheets — the same
mechanism as `chorus-pdf` Phase 2.5, adapted for a grid coordinate system.

```python
def build_sheet_texts(wb):
    """Build {sheet_name: [(text, row, col), ...]} for all non-empty text cells."""
    result = {}
    for sheet_name in wb.sheetnames:
        ws = wb[sheet_name]
        cells = []
        merged_map = build_merged_map(ws)
        for row in ws.iter_rows():
            for cell in row:
                val = cell_value(cell, merged_map)
                if val.strip():
                    cells.append((val.strip(), cell.row, cell.column))
        result[sheet_name] = cells
    return result

def find_text_occurrences_excel(identifier, sheet_texts):
    import re
    pattern = re.compile(r'\b' + re.escape(identifier) + r'\b')
    results = []
    for sheet_name, cells in sheet_texts.items():
        for (text, row, col) in cells:
            m = pattern.search(text)
            if m:
                s = max(0, m.start() - 55); e = min(len(text), m.end() + 55)
                snippet = text[s:e].replace('\n', ' ').strip()
                if s > 0: snippet = '…' + snippet
                if e < len(text): snippet += '…'
                results.append((f"Sheet '{sheet_name}' R{row}C{col}", snippet))
    return results

if extraction_mode == "hybrid" and all_figure_descs:
    sheet_texts = build_sheet_texts(wb)
    annotated_descs, xref_index_block, xref_map = _xref_pass_excel(
        all_figure_descs, sheet_texts, find_text_occurrences_excel)
else:
    annotated_descs = all_figure_descs
    xref_index_block = ""
    xref_map = {}
# xref_map passed to Phase 3 as first-class matching candidates (same as PDF pipeline)
```

##### Step 3 — Assemble final output

Inject figure descriptions at their anchor position within each sheet block, then
append the XREF INDEX at the end.

```python
extracted_text = "\n\n".join(sheet_parts)
if xref_index_block:
    extracted_text += "\n\n" + xref_index_block
```

##### nohup gate (hybrid mode — Excel)

If the workbook contains **≥ 15 images + charts** combined → exit(2) + nohup command.
`CHORUS_EXCEL_FORCE=1` to bypass, identical to `chorus-pdf` nohup gate.

##### Dependencies

| Package | Install | Notes |
|---------|---------|-------|
| `openpyxl` | `pip install openpyxl` | XLSX extraction |
| `Pillow` | `pip install Pillow` | Image conversion (hybrid mode) |
| `LibreOffice` | `sudo apt install libreoffice` | Chart extraction (optional — graceful fallback) |
| `pdftoppm` | `sudo apt install poppler-utils` | Chart page rendering (optional) |

> ⛔ **If extraction tools are absent** → warn and offer Case A (inline paste).
> Never block the workflow over a missing optional tool.


#### Word (.docx) — full-quality pipeline (same depth as PDF)

Word extraction uses the **same architecture as `chorus-pdf`**: the native XML body
order is preserved for correct reading order, tables are reconstructed as Markdown
pipe tables with merged-cell handling, embedded images are sent to Claude vision
(hybrid mode), and the XREF pass links figure identifiers to paragraph text.

##### Step 0 — Auto-detect mode (identical to PDF pipeline)

Same `probe_claude()` probe as PDF Step 0. Result: `word_mode = "hybrid"` or `"text"`. Print prefix: `[import-word]`.

##### Step 1 — Document traversal via XML body order

```python
import docx
from docx.oxml.ns import qn

def iter_block_items(doc):
    """Yield (kind, obj) in document XML order — preserves reading order."""
    body = doc.element.body
    img_counter = [0]
    for child in body:
        tag = child.tag.split('}')[-1]
        if tag == 'p':
            para = docx.text.paragraph.Paragraph(child, doc)
            blips = child.findall('.//' + qn('a:blip'))
            if blips:
                for blip in blips:
                    rId = blip.get(qn('r:embed'))
                    if rId and rId in doc.part.rels:
                        img_counter[0] += 1
                        yield ('image', (img_counter[0], doc.part.rels[rId].target_part.blob))
            else:
                text = para.text.strip()
                if text:
                    yield ('para', (text, para.style.name if para.style else ''))
        elif tag == 'tbl':
            yield ('table', docx.table.Table(child, doc))

def table_to_markdown(tbl):
    """Convert python-docx Table to Markdown pipe, deduplicating merged cells."""
    seen, rows_out = set(), []
    for row in tbl.rows:
        row_cells = []
        for cell in row.cells:
            cid = id(cell._tc)
            if cid not in seen:
                seen.add(cid)
                row_cells.append(
                    " ".join(p.text.strip() for p in cell.paragraphs if p.text.strip()))
        rows_out.append(row_cells)
    if not rows_out or not rows_out[0]:
        return ""
    n_cols = max(len(r) for r in rows_out)
    rows_padded = [r + [''] * (n_cols - len(r)) for r in rows_out]
    def cell_md(c): return str(c or "").replace("|", "｜").replace("\n", " ").strip()
    lines = ["| " + " | ".join(cell_md(c) for c in rows_padded[0]) + " |",
             "| " + " | ".join("---" for _ in rows_padded[0]) + " |"]
    for row in rows_padded[1:]:
        lines.append("| " + " | ".join(cell_md(c) for c in row) + " |")
    return "\n".join(lines)
```

##### Step 2 — Hybrid mode: Claude vision on embedded images

```python
from PIL import Image
import io

def convert_to_png(blob):
    """Convert image blob (PNG/JPEG/EMF/WMF) to PNG bytes via Pillow."""
    try:
        img = Image.open(io.BytesIO(blob))
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        return buf.getvalue()
    except Exception:
        return blob if blob[:4] == b'\x89PNG' else None  # EMF/WMF → skip

doc = docx.Document(source_path)
block_texts = []       # [(text, block_idx)] — for XREF pass
all_figure_descs = {}  # {(doc_name, img_idx): description_text}
elements = []          # [(kind, content)] — in XML order

for kind, obj in iter_block_items(doc):
    if kind == 'para':
        text, style = obj
        block_idx = len(block_texts)
        block_texts.append((text, block_idx))
        elements.append(('text', text))
    elif kind == 'table':
        md = table_to_markdown(obj)
        if md:
            elements.append(('table', md))
    elif kind == 'image':
        img_idx, blob = obj
        png_bytes = convert_to_png(blob)
        if word_mode == "hybrid" and png_bytes:
            desc = call_claude_figure(png_bytes, "word-doc", img_idx, api_key)
            all_figure_descs[("word-doc", img_idx)] = desc
            elements.append(('figure', desc))
        else:
            elements.append(('image',
                "[IMAGE — not extracted]\n"
                "[Run with ANTHROPIC_API_KEY to extract images via hybrid mode]"))
```

##### Step 2.5 — Cross-reference pass (hybrid mode only)

The XREF pass links figure identifiers to paragraph text blocks — identical to
`chorus-pdf` Phase 2.5, adapted for a block-index coordinate system.

```python
def build_word_block_texts(block_texts):
    """Adapt block_texts for find_text_occurrences: {0: [(text, block_idx), ...]}"""
    return {0: [(text, block_idx) for (text, block_idx) in block_texts]}

def find_text_occurrences_word(identifier, block_texts):
    import re
    pattern = re.compile(r'\b' + re.escape(identifier) + r'\b')
    results = []
    for (text, block_idx) in block_texts:
        m = pattern.search(text)
        if m:
            s = max(0, m.start() - 55); e = min(len(text), m.end() + 55)
            snippet = text[s:e].replace('\n', ' ').strip()
            if s > 0: snippet = '…' + snippet
            if e < len(text): snippet += '…'
            results.append((f"bloc {block_idx}", snippet))
    return results

if word_mode == "hybrid" and all_figure_descs:
    annotated_descs, xref_index_block, xref_map = _xref_pass_word(
        all_figure_descs, block_texts, find_text_occurrences_word)
else:
    annotated_descs = all_figure_descs
    xref_index_block = ""
    xref_map = {}
# xref_map passed to Phase 3 as first-class matching candidates (same as PDF pipeline)
```

##### Step 3 — Assemble final output

XML order is the reading order — no Y-sort required. Append XREF INDEX at end.

```python
output_parts = [content for (_, content) in elements]
if xref_index_block:
    output_parts.append(xref_index_block)
extracted_text = "\n\n".join(output_parts)
```

##### nohup gate (hybrid mode — Word)

If the document contains **≥ 15 embedded images** → exit(2) + nohup command.
`CHORUS_WORD_FORCE=1` to bypass, identical to `chorus-pdf` nohup gate.

##### Figure-heavy domains warning (text mode)

When `word_mode == "text"` **and** ≥ 5 images detected, emit the same prominent
warning as the PDF pipeline — Phase 3 will be blind to image content.

##### Dependencies

| Package | Install | Notes |
|---------|---------|-------|
| `python-docx` | `pip install python-docx` | DOCX extraction |
| `Pillow` | `pip install Pillow` | Image conversion (hybrid mode) |

> ⛔ **If extraction tools are absent** → warn and offer Case A (inline paste).
> Never block the workflow over a missing optional tool.


#### Other formats — LibreOffice universal fallback

For formats not natively handled (`.doc`, `.odt`, `.pptx`, `.ods`, `.rtf`):

```bash
libreoffice --headless --convert-to pdf "<fichier>" --outdir /tmp/
# → produces /tmp/<basename>.pdf → feed to PDF hybrid pipeline above
```

If LibreOffice is absent → ask the engineer to provide copy-pasted content (Case A).
Never block the workflow over a missing tool — offer the inline alternative.


