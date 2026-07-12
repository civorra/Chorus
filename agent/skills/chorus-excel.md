# Skill — chorus-excel

> Trigger: `chorus-excel <sandbox-name> <file.xlsx|file.csv> [--out <slug>] [--sheet <name>] [--batch]`
> Agent: `architect`
>
> `<sandbox-name>`: name of the sandbox directory under `$SANDBOXES/`
> `<file.xlsx|file.csv>`: path to the spreadsheet — absolute, or relative to `$SANDBOX/corpus/`
> `--out <slug>`: override the output filename stem (default: derived from input filename)
> `--sheet <name>`: process only this sheet (default: all sheets)
> `--batch`: process all `*.xlsx` and `*.csv` files found in `$SANDBOX/corpus/`
>
> **Single responsibility: produce an enriched text file from an Excel or CSV spreadsheet.**
> Extracts tables (with merged cell handling), embedded images, and chart descriptions
> that naive `openpyxl` dumps and LibreOffice conversions silently discard or flatten.
>
> Output format depends on mode and format:
> - Hybrid mode (default when API key available + XLSX): `corpus/<NNN>-<slug>-vision.md` — openpyxl tables + Claude vision on images/charts
> - Text mode (fallback — no API key + XLSX): `corpus/<NNN>-<slug>-text.txt` — Markdown pipe tables, image/chart placeholders
> - CSV mode (auto-detected on `.csv` extension): `corpus/<NNN>-<slug>-text.txt` — Markdown pipe table
>
> This skill must be run **before** `chorus-feed` when the corpus contains `.xlsx` or `.csv` files.
> `chorus-feed` then takes the output file as its corpus input.
>
> ⚠️ **Run `chorus-excel` before `chorus-import-project`** when the source project documents
> include `.xlsx` or `.csv` files — `chorus-import-project`'s built-in Excel handler is
> minimal (tab-separated dump). `chorus-excel` preserves structure, merges, images and charts.


## ⛔ Strict sandbox isolation

Never read any KB, YAML, or artifact from a sandbox other than `<sandbox-name>`.
This skill operates exclusively on the `corpus/` directory of the target sandbox.


## Overview

Naive Excel-to-text conversions (`libreoffice --headless --convert-to csv`, basic
`openpyxl` dumps) silently discard merged cells (losing their master value), embedded
images (PNG/JPEG blobs attached to worksheets), and charts (openpyxl exposes anchor
positions but not pixel data). This skill provides three extraction modes of increasing
capability:

### Extraction modes

| Mode | Flag | Engine | API key | Images | Charts | Tables | Output |
|------|------|--------|---------|--------|--------|--------|--------|
| **Hybrid** (**default**) | *(none — auto-detected)* | openpyxl + Claude vision | ✅ `ANTHROPIC_API_KEY` | ✅ described | ✅ via LibreOffice (graceful fallback) | ✅ Markdown pipe | `<slug>-vision.md` |
| **Text** (fallback) | *(none — no API key)* | openpyxl only | ❌ not required | `[IMAGE — not extracted]` | `[CHART — not extracted]` | ✅ Markdown pipe | `<slug>-text.txt` |
| **CSV** | auto-detected on `.csv` | `csv.reader` | — | N/A | N/A | ✅ Markdown pipe | `<slug>-text.txt` |
| **Batch** | `--batch` | process all `*.xlsx`/`*.csv` in `corpus/` | per-file | per-file | per-file | ✅ | idem per file |

**Choosing a mode:**

```
No flag provided
  → Phase 0.0 auto-detects format and ANTHROPIC_API_KEY
  → .csv extension → CSV mode (always text — no images)
  → .xlsx/.xlsm + key valid   : hybrid mode activated automatically  ← DEFAULT
  → .xlsx/.xlsm + key absent/invalid : text mode (fallback)

API key available, XLSX with embedded images or charts
  → (default — hybrid activated automatically)

No API key available, or CSV file
  → (default text/CSV mode — forced fallback)
```


## Phase 0.0 — Auto-detect mode (no explicit flag)

This phase runs **only when no mode was explicitly forced**.
Its goal: activate hybrid mode automatically if Claude is available **and** the file is XLSX.

### 0.0.1 Check file format

```python
import os

file_ext = os.path.splitext(file_path)[1].lower()
if file_ext == '.csv':
    mode = "csv"
    print("[chorus-excel] CSV format detected — csv mode (no API probe needed).", file=sys.stderr)
    # Skip to Phase 0 — no probe needed for CSV
```

If `.xlsx` or `.xlsm` → proceed to 0.0.2.

### 0.0.2 Check API key presence

```python
API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
if not API_KEY:
    mode = "text"
    print("[chorus-excel] No ANTHROPIC_API_KEY — text mode.", file=sys.stderr)
```

If a key is present → proceed to 0.0.3.

### 0.0.3 Probe Claude availability

Send a minimal request to verify the key is valid and the API reachable.
Use `claude-haiku-4-5` (cheapest model, ~1 token, <1s, cost negligible).

```python
def probe_claude(api_key):
    """Probe Claude availability with a minimal 1-token request.
    Returns True  if the key is valid and the API is reachable.
    Returns False if the key is invalid (401/403) or network unreachable.
    Returns True  on rate-limit (429/529) — key is valid, just throttled.
    """
    import json, urllib.request, urllib.error

    payload = {
        "model": "claude-haiku-4-5",
        "max_tokens": 1,
        "messages": [{"role": "user", "content": "ping"}]
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
    try:
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST"
        )
        urllib.request.urlopen(req, timeout=10)
        return True
    except urllib.error.HTTPError as e:
        if e.code in (429, 529):
            return True   # throttled but key is valid
        return False      # 401 Unauthorized / 403 Forbidden
    except Exception:
        return False      # network error, timeout
```

### 0.0.4 Decision table

| File ext | `ANTHROPIC_API_KEY` | Probe result | Mode activated | Message |
|---|---|---|---|---|
| `.csv` | any | — | **csv** | `CSV format detected — csv mode.` |
| `.xlsx` | absent | — | **text** | `No ANTHROPIC_API_KEY — text mode.` |
| `.xlsx` | present | ✅ valid | **hybrid** | `ANTHROPIC_API_KEY detected — Claude available ✅ — hybrid mode activated.` |
| `.xlsx` | present | ❌ invalid (401/403) | **text** | `ANTHROPIC_API_KEY set but key is invalid (HTTP 4xx) — falling back to text mode.` |
| `.xlsx` | present | ❌ unreachable | **text** | `Claude unreachable (network error) — falling back to text mode.` |
| `.xlsx` | present | ⚠️ throttled (429/529) | **hybrid** | `ANTHROPIC_API_KEY detected — Claude available (throttled) ✅ — hybrid mode activated.` |

Print the selected mode to stderr before proceeding to Phase 0.1.


## Phase 0 — Resolve inputs

### 0.1 Resolve the sandbox path

```
SANDBOX = $SANDBOXES/<sandbox-name>
```

Verify that `$SANDBOX/corpus/` exists. If not, abort with:
```
⛔ Sandbox '<sandbox-name>' does not exist or has no corpus/ directory.
   Create corpus/ manually or run chorus-feed first to initialize the sandbox.
```

### 0.2 Resolve the file path

If `<file.xlsx|file.csv>` is a bare filename → prepend `$SANDBOX/corpus/`.
If it is an absolute path → use as-is.
Verify the file exists and ends in `.xlsx`, `.xlsm`, or `.csv` (case-insensitive).

In `--batch` mode: glob `$SANDBOX/corpus/*.xlsx`, `*.xlsm`, `*.csv` (and uppercase variants).
Process each in turn, sorted by filename. If none found → warn and exit cleanly (not an error).

### 0.3 Resolve the output filename

Determine the next available corpus number:

```
existing = glob("$SANDBOX/corpus/[0-9][0-9][0-9]-*.*")
last_num = max of the leading 3-digit prefix across existing files (default 0)
next_num = last_num + 1   (formatted as %03d)
```

> ⚠️ In `--batch` mode, increment `next_num` for each file processed in sequence.

Derive the slug and extension based on mode:

| Mode | Suffix | Extension | Rationale |
|------|--------|-----------|-----------|
| Hybrid (default) | `-vision` | `.md` | openpyxl tables + Claude vision on images/charts |
| Text (fallback) | `-text` | `.txt` | Markdown tables only — image/chart placeholders |
| CSV | `-text` | `.txt` | Markdown pipe table — no binary content |

- If `--out <slug>` provided → use that slug as-is (suffix already included)
- Otherwise → strip leading `NNN-` prefix and file extension from the input filename,
  then append the mode suffix

Output filename: `$SANDBOX/corpus/<next_num>-<slug>.<ext>`

Example:
```
Input  : corpus/002-devis-isolation.xlsx

Default (hybrid) : corpus/003-devis-isolation-vision.md
text mode        : corpus/003-devis-isolation-text.txt

Input  : corpus/002-elements-structure.csv
CSV mode         : corpus/003-elements-structure-text.txt
```


## Phase 1 — Workbook analysis

### 1.1 Load and inventory the workbook

```python
import openpyxl

wb = openpyxl.load_workbook(xlsx_path, data_only=True)

# Structure Excel:
# wb.sheetnames → ['Feuille1', 'Calculs', 'Récap']
# ws = wb[sheet_name]
# ws.dimensions → 'A1:Z100'  (entire data range as string)
# ws.merged_cells.ranges → list of merged ranges
# ws._images → list of ImageAnchor objects (embedded PNG/JPEG/EMF blobs)
# ws._charts → list of ChartAnchor objects (chart position only — no pixel data)
```

If `--sheet <name>` was provided, verify that sheet name exists in `wb.sheetnames`.
If not found → abort with `⛔ Sheet '<name>' not found. Available: <list>`.

### 1.2 Per-sheet analysis

For each sheet (or the single sheet if `--sheet` was provided):

```python
for sheet_name in (sheets_to_process):
    ws = wb[sheet_name]

    # Row/column count from actual data range
    min_row = ws.min_row or 1
    max_row = ws.max_row or 1
    min_col = ws.min_column or 1
    max_col = ws.max_column or 1
    n_rows  = max_row - min_row + 1
    n_cols  = max_col - min_col + 1

    # Embedded images
    n_images = len(ws._images)

    # Charts (anchor position only — no pixels)
    n_charts = len(ws._charts)

    # Merged cell regions
    n_merged = len(list(ws.merged_cells.ranges))

    print(f"   → Sheet '{sheet_name}': {n_rows} rows × {n_cols} cols, "
          f"{n_images} image(s), {n_charts} chart(s), {n_merged} merged regions",
          file=sys.stderr)
```

Report to the user before generating the script:
```
[chorus-excel] Workbook analysis:
   → 3 sheet(s): Feuille1, Calculs, Récap
   → Sheet 'Feuille1': 45 rows × 8 cols, 2 image(s), 1 chart(s), 3 merged regions
   → Sheet 'Calculs' : 120 rows × 12 cols, 0 image(s), 2 chart(s), 5 merged regions
   → Sheet 'Récap'   : 18 rows × 4 cols, 0 image(s), 0 chart(s), 0 merged regions
   → Mode: hybrid (Claude vision on images/charts)
```

### 1.3 Table detection heuristic

A worksheet may contain data in one of three configurations:

```python
from openpyxl.utils import range_boundaries

def detect_data_blocks(ws):
    """Detect contiguous rectangular data blocks in the worksheet.
    Returns list of (min_col, min_row, max_col, max_row) tuples."""
    # Strategy 1: use ws.tables if named Excel tables are defined
    named_tables = []
    for tbl in ws.tables.values():
        named_tables.append(range_boundaries(tbl.ref))
    if named_tables:
        return named_tables

    # Strategy 2: use ws.dimensions as a single data block
    if ws.dimensions and ws.dimensions not in ('A1:A1', ''):
        return [range_boundaries(ws.dimensions)]

    # Strategy 3: scan min/max from actual non-empty cells
    if ws.min_row and ws.max_row and ws.min_column and ws.max_column:
        return [(ws.min_column, ws.min_row, ws.max_column, ws.max_row)]

    return []   # empty sheet
```

> ⚠️ `openpyxl.load_workbook(path, data_only=True)` returns the **last saved values**
> for formula cells. If the file was never saved after calculation, formula cells
> will return `None` → displayed as `[FORMULA — not evaluated]`.

### 1.4 Merged cells — reconstruction rules

Excel merged cells have one master cell (top-left) that holds the value; all other
cells in the range are "slaves" with `value = None`. The extraction script must:

1. Build a `merged_map: {(row, col): master_value}` for all slave cells
2. When formatting the Markdown table, use the master value for any slave cell
3. Display the merged value **only once** in the first column of the merged range
4. Optionally annotate prominent merged ranges: `[MERGED: A1:C1 — "Titre section"]`


## Phase 1.5 — nohup gate (hybrid mode only)

After Phase 1.2, the skill knows the total count of images + charts across all sheets.
Each image or chart = 1 API call ≈ 30 s average. The IDE has a hard timeout of ~10 minutes.

**Decision rule:**

| Images + charts total (`n_media`) | Estimated time | Action |
|----------------------------------:|---------------:|--------|
| ≤ 15 | ≤ 7.5 min | proceed directly |
| ≥ 16 | > 8 min | **exit(2)** + print `nohup` command |

```
[chorus-excel] ⚠️  18 images/charts detected — estimated time ~9–13 min (threshold: 15).
[chorus-excel]    Run with nohup to avoid a 10-min IDE timeout:
[chorus-excel]    CHORUS_EXCEL_FORCE=1 nohup python3 /path/to/agent/extract-excel-<slug>.py > corpus/<NNN>-<slug>-vision.md.log 2>&1 &
```

The threshold constant `NOHUP_THRESHOLD = 15` is defined at the top of the script.

**Bypass `CHORUS_EXCEL_FORCE=1`:** set this env var to skip the gate unconditionally.

> ⚠️ **instruction:** when executing the script and receiving exit code 2, do **not** retry
> automatically. Set `CHORUS_EXCEL_FORCE=1` and relaunch with `nohup` — pre-approved, no
> confirmation required.


## Phase 2 — Generate the extraction script

Create `$SANDBOX/agent/` if it does not exist.
Write `$SANDBOX/agent/extract-excel-<slug>.py`, then execute it.


### Shared utilities — Text & Hybrid modes

The following functions are used verbatim in both the Text and Hybrid script templates.
Include them in the generated script when either mode is active.

```python
def build_merged_map(ws):
    merged_map = {}
    for merged_range in ws.merged_cells.ranges:
        cells = list(merged_range.cells)
        if not cells:
            continue
        master_row, master_col = cells[0]
        master_cell = ws.cell(row=master_row, column=master_col)
        master_val = master_cell.value if master_cell.value is not None else ""
        for row, col in cells[1:]:
            merged_map[(row, col)] = master_val
    return merged_map


def cell_value(cell, merged_map):
    if cell.value is not None:
        if isinstance(cell.value, str) and cell.value.startswith('='):
            return FORMULA_PLACEHOLDER
        return str(cell.value)
    master = merged_map.get((cell.row, cell.column))
    return str(master) if master is not None else ""


def extract_sheet_to_markdown(ws):
    merged_map = build_merged_map(ws)
    min_row = ws.min_row or 1
    max_row = ws.max_row or 1
    min_col = ws.min_column or 1
    max_col = ws.max_column or 1
    rows = []
    for r in range(min_row, max_row + 1):
        row = [cell_value(ws.cell(row=r, column=c), merged_map)
               for c in range(min_col, max_col + 1)]
        rows.append(row)
    rows = [r for r in rows if any(v.strip() for v in r if v)]
    if not rows:
        return "(empty sheet)"
    def cell_md(v):
        return str(v or "").replace("|", "｜").replace("\n", " ").strip()
    n_cols = max(len(r) for r in rows)
    rows_padded = [r + [''] * (n_cols - len(r)) for r in rows]
    lines = ["| " + " | ".join(cell_md(v) for v in rows_padded[0]) + " |",
             "| " + " | ".join("---" for _ in rows_padded[0]) + " |"]
    for row in rows_padded[1:]:
        lines.append("| " + " | ".join(cell_md(v) for v in row) + " |")
    return "\n".join(lines)


def get_image_position(img_anchor):
    """Return (row, col) of the image anchor top-left (1-based)."""
    anchor = img_anchor.anchor
    if hasattr(anchor, '_from'):
        return (anchor._from.row + 1, anchor._from.col + 1)
    return (0, 0)   # AbsoluteAnchor — insert at top of sheet


def get_chart_position(chart_anchor):
    """Return (row, col) of the chart anchor top-left (1-based)."""
    anchor = chart_anchor.anchor
    if hasattr(anchor, '_from'):
        return (anchor._from.row + 1, anchor._from.col + 1)
    return (0, 0)
```

### Script template — CSV mode (always text, no API key needed)

```python
#!/usr/bin/env python3
"""
chorus-excel extraction script — CSV mode
Generated by chorus-excel skill
Sandbox : <sandbox-name>
Source  : <input-csv-path>
Output  : <output-txt-path>
"""
import sys
import csv
import os

CSV_PATH    = "<input-csv-path>"
OUTPUT_PATH = "<output-txt-path>"

def csv_to_markdown_safe(csv_path):
    """Convert CSV to Markdown pipe table (safe version without list method abuse)."""
    with open(csv_path, newline='', encoding='utf-8-sig') as f:
        reader = csv.reader(f)
        rows = list(reader)
    if not rows:
        return "(empty CSV file)"

    def cell(c):
        return str(c or "").replace("|", "｜").replace("\n", " ").strip()

    n_cols = max(len(r) for r in rows)

    def pad_row(r):
        return r + [''] * max(0, n_cols - len(r))

    header = pad_row(rows[0])
    lines = [
        "| " + " | ".join(cell(c) for c in header) + " |",
        "| " + " | ".join("---" for _ in header) + " |",
    ]
    for row in rows[1:]:
        padded = pad_row(row)
        lines.append("| " + " | ".join(cell(c) for c in padded) + " |")
    return "\n".join(lines)

def main():
    print(f"[chorus-excel] CSV mode — {CSV_PATH}", file=sys.stderr)
    md = csv_to_markdown_safe(CSV_PATH)
    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write(md)
    line_count = md.count('\n') + 1
    print(f"[chorus-excel] ✅ CSV → Markdown ({line_count} lines). Written to {OUTPUT_PATH}",
          file=sys.stderr)

if __name__ == "__main__":
    main()
```

> ⚠️ **Encoding:** `utf-8-sig` handles BOM-prefixed CSV files produced by Excel on Windows.
> ⚠️ **Dependencies**: none beyond Python 3.6+ stdlib.


### Script template — Text mode (XLSX without API key)

Uses `openpyxl` only. No API key, no network. Images and charts produce placeholders.
Output: `<NNN>-<slug>-text.txt`

```python
#!/usr/bin/env python3
"""
chorus-excel extraction script — text mode (no API key)
Generated by chorus-excel skill
Sandbox : <sandbox-name>
Source  : <input-xlsx-path>
Output  : <output-txt-path>
"""
import sys
import os

XLSX_PATH   = "<input-xlsx-path>"
OUTPUT_PATH = "<output-txt-path>"
SHEET_FILTER = None   # set to a sheet name string to process only that sheet

IMAGE_PLACEHOLDER = (
    "[IMAGE — not extracted]\n"
    "[Run chorus-excel with ANTHROPIC_API_KEY set to extract images via hybrid mode]"
)
CHART_PLACEHOLDER = (
    "[CHART — not extracted]\n"
    "[Run chorus-excel with ANTHROPIC_API_KEY set to extract charts via hybrid mode]"
)
FORMULA_PLACEHOLDER = "[FORMULA — not evaluated]"

# → build_merged_map / cell_value / extract_sheet_to_markdown / get_image_position / get_chart_position
#   see "Shared utilities — Text & Hybrid modes" above

def main():
    try:
        import openpyxl
    except ImportError:
        print("⛔ openpyxl not installed. Run: pip install openpyxl", file=sys.stderr)
        sys.exit(1)

    print(f"[chorus-excel] Text mode — {XLSX_PATH}", file=sys.stderr)
    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    sheets = [SHEET_FILTER] if SHEET_FILTER else wb.sheetnames
    parts = []

    for sheet_name in sheets:
        if sheet_name not in wb.sheetnames:
            print(f"[chorus-excel] ⚠️  Sheet '{sheet_name}' not found — skipped", file=sys.stderr)
            continue
        ws = wb[sheet_name]
        n_images = len(ws._images)
        n_charts = len(ws._charts)
        print(f"[chorus-excel] Sheet '{sheet_name}' — "
              f"{ws.max_row or 0} rows × {ws.max_column or 0} cols, "
              f"{n_images} image(s), {n_charts} chart(s)", file=sys.stderr)

        parts.append(f"=== SHEET: {sheet_name} ===")

        # Table
        md = extract_sheet_to_markdown(ws)
        parts.append(md)

        # Image placeholders (with anchor position)
        for i, img in enumerate(ws._images, 1):
            row, col = get_image_position(img)
            parts.append(
                f"\n[IMAGE {i} — anchor: row {row}, col {col}]\n"
                + IMAGE_PLACEHOLDER.replace("[IMAGE", f"[IMAGE {i}")
            )

        # Chart placeholders (with anchor position)
        for i, chart in enumerate(ws._charts, 1):
            row, col = get_chart_position(chart)
            parts.append(
                f"\n[CHART {i} — anchor: row {row}, col {col}]\n"
                + CHART_PLACEHOLDER.replace("[CHART", f"[CHART {i}")
            )

        parts.append(f"=== END SHEET: {sheet_name} ===")

    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write("\n\n".join(parts))
    print(f"[chorus-excel] ✅ Written to {OUTPUT_PATH}", file=sys.stderr)

if __name__ == "__main__":
    main()
```

> ⚠️ **Dependencies**: `pip install openpyxl`
> ⚠️ Images and charts are not extracted in text mode — use hybrid mode with `ANTHROPIC_API_KEY`.


### Script template — Hybrid mode (XLSX with API key)

Best-quality mode for Excel files with embedded images and charts.
`openpyxl` extracts tables and image blobs. Claude vision describes each image/chart.
Output: `<NNN>-<slug>-vision.md`

#### Chart extraction strategies

Excel charts are **not** raw PNG blobs in the XLSX format — they are XML descriptions
(`xl/charts/chart*.xml`) rendered by the spreadsheet engine. Two strategies:

**Strategy A (recommended) — LibreOffice conversion:**
Convert the entire workbook to PDF, render the PDF page(s) containing the chart to PNG,
send to Claude. This produces a faithful visual representation.

**Strategy B (fallback) — Vision placeholder:**
If LibreOffice is not installed, emit a descriptive placeholder with the chart's XML
metadata (title, chart type, series names) extracted from the openpyxl chart object.

```python
#!/usr/bin/env python3
"""
chorus-excel extraction script — hybrid mode (API key required)
Generated by chorus-excel skill
Sandbox : <sandbox-name>
Source  : <input-xlsx-path>
Output  : <output-md-path>
"""
import sys
import os
import base64
import json
import re
import time
import io
import glob
import subprocess
import tempfile
import urllib.request
import urllib.error

XLSX_PATH   = "<input-xlsx-path>"
OUTPUT_PATH = "<output-md-path>"
MAX_RETRIES = 4
API_KEY     = os.environ.get("ANTHROPIC_API_KEY", "")
API_URL     = "https://api.anthropic.com/v1/messages"
SHEET_FILTER = None   # set to a sheet name string to process only that sheet
NOHUP_THRESHOLD = 15

FIGURE_PROMPT = """You are a technical document extraction engine.
Describe this figure extracted from a normative PDF document.

Apply the following rules strictly:

FIGURES AND DIAGRAMS
- Output a block of the form:
    [FIGURE <N> — <title or caption if visible>]
    <Structured description of all visual content:>
    - Labeled dimensions, dimensions with units
    - Named components and their spatial relationships
    - Numerical values visible in or next to the figure
    - Arrows, load paths, connection points, hinge symbols, support symbols
    - Hatching patterns and what material or condition they represent
    - Scale bar if present
    [END FIGURE <N>]
    IDENTIFIERS: ["<id1>", "<id2>", ...]
- If there is no caption visible, assign [FIGURE ?] and describe anyway.
- For IDENTIFIERS: list every alphanumeric code, label, designation or identifier
  visible in the figure (callout tags, part numbers, zone codes, element IDs,
  article references, dimension labels with letters). Use the exact string as printed.
  Exclude purely numeric values (dimensions, measurements), single letters used as
  generic variables, and common stopwords. Output valid JSON array on a single line
  immediately after [END FIGURE <N>]. Output [] if no identifiers found.
- Do not add text outside the [FIGURE] ... [END FIGURE] block and IDENTIFIERS line.
- Use UTF-8. Preserve all special characters (±, ≤, ≥, ×, °, ², ³, …).
"""

CHART_PLACEHOLDER_VISION = (
    "[CHART — LibreOffice required for visual extraction]\n"
    "[Install LibreOffice: sudo apt install libreoffice]\n"
    "[Then rerun chorus-excel to extract chart via vision]"
)

FORMULA_PLACEHOLDER = "[FORMULA — not evaluated]"

# ---------------------------------------------------------------------------
# Image extraction helpers
# ---------------------------------------------------------------------------

def extract_image_png(img_anchor):
    """Extract an openpyxl ImageAnchor blob as PNG bytes.

    openpyxl stores the raw image bytes in img_anchor.image.blob.
    The format can be PNG, JPEG, EMF, WMF, or BMP.
    Pillow normalises all supported formats to PNG.
    EMF/WMF (Windows Metafiles) are not supported by Pillow — returns None.
    """
    try:
        from PIL import Image
    except ImportError:
        print("⛔ Pillow not installed. Run: pip install Pillow", file=sys.stderr)
        sys.exit(1)

    blob = img_anchor.image.blob   # raw bytes
    try:
        img = Image.open(io.BytesIO(blob))
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        return buf.getvalue()
    except Exception:
        # Fallback: if blob starts with PNG magic, return as-is
        if blob[:4] == b'\x89PNG':
            return blob
        return None   # unsupported format (EMF/WMF) — skip

# → get_image_position / get_chart_position — see "Shared utilities — Text & Hybrid modes" above

# ---------------------------------------------------------------------------
# Chart extraction via LibreOffice (Strategy A)
# ---------------------------------------------------------------------------

def chart_to_png_via_libreoffice(xlsx_path, tmpdir):
    """Convert workbook to PDF via LibreOffice, render pages to PNG.

    Returns a list of PNG byte strings, one per rendered page.
    Returns None if LibreOffice is not available.
    """
    # Step 1: convert XLSX to PDF
    result = subprocess.run(
        ['libreoffice', '--headless', '--convert-to', 'pdf', xlsx_path,
         '--outdir', tmpdir],
        capture_output=True, timeout=120
    )
    if result.returncode != 0:
        return None   # LibreOffice not available or conversion failed

    pdf_name = os.path.splitext(os.path.basename(xlsx_path))[0] + '.pdf'
    pdf_path = os.path.join(tmpdir, pdf_name)
    if not os.path.exists(pdf_path):
        return None

    # Step 2: render PDF pages to PNG via pdftoppm
    prefix = os.path.join(tmpdir, 'chart-page')
    result2 = subprocess.run(
        ['pdftoppm', '-r', '150', '-png', pdf_path, prefix],
        capture_output=True
    )
    if result2.returncode != 0:
        return None

    pngs = sorted(glob.glob(prefix + '*.png'))
    if not pngs:
        return None

    pages_png = []
    try:
        from PIL import Image as PILImage
        for p in pngs:
            img = PILImage.open(p)
            buf = io.BytesIO()
            img.save(buf, format='PNG')
            pages_png.append(buf.getvalue())
    except ImportError:
        # Pillow unavailable — read raw PNG bytes
        for p in pngs:
            with open(p, 'rb') as f:
                pages_png.append(f.read())

    return pages_png if pages_png else None

def extract_chart_metadata(chart_obj):
    """Extract chart title and type from the openpyxl chart object for the fallback placeholder."""
    try:
        title = str(chart_obj.title) if hasattr(chart_obj, 'title') and chart_obj.title else "untitled"
        chart_type = type(chart_obj).__name__
        series_names = []
        if hasattr(chart_obj, 'series'):
            for s in chart_obj.series:
                if hasattr(s, 'title') and s.title:
                    series_names.append(str(s.title))
        return title, chart_type, series_names
    except Exception:
        return "untitled", "Chart", []

# ---------------------------------------------------------------------------
# Claude vision — describe a single image or chart crop
# ---------------------------------------------------------------------------

def call_claude_figure(png_bytes, sheet_name, fig_idx):
    """Send a single PNG to Claude and return the [FIGURE] block."""
    b64 = base64.standard_b64encode(png_bytes).decode("utf-8")
    content = [
        {"type": "text",
         "text": f"[Sheet '{sheet_name}', Figure {fig_idx}]\n\n{FIGURE_PROMPT}"},
        {"type": "image",
         "source": {"type": "base64", "media_type": "image/png", "data": b64}},
    ]
    payload = {
        "model": "claude-opus-4-5",
        "max_tokens": 2048,
        "messages": [{"role": "user", "content": content}]
    }
    headers = {
        "x-api-key": API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
    for attempt in range(MAX_RETRIES):
        req = urllib.request.Request(
            API_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read().decode("utf-8"))["content"][0]["text"].strip()
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if e.code in (429, 529) and attempt < MAX_RETRIES - 1:
                wait = 10 * (2 ** attempt)
                print(f"  HTTP {e.code} — retrying in {wait}s ...", file=sys.stderr)
                time.sleep(wait)
            else:
                raise RuntimeError(
                    f"HTTP {e.code} sheet='{sheet_name}' fig={fig_idx}: {body[:300]}")

# → build_merged_map / cell_value / extract_sheet_to_markdown
#   see "Shared utilities — Text & Hybrid modes" above

# ---------------------------------------------------------------------------
# Phase 2.5 — Cross-reference pass (Excel adaptation)
# ---------------------------------------------------------------------------

_XREF_STOPWORDS = {
    "N", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
    "M", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "kN", "mm", "cm", "m", "kg", "kPa", "MPa", "GPa", "kNm",
    "Figure", "Table", "Clause", "Section", "Annex", "NOTE", "Fig",
}
_XREF_MIN_LEN = 2

def build_sheet_texts(wb, sheet_names):
    """Build {sheet_name: [(text, row, col), ...]} for all text cells.

    This is the Excel equivalent of pdfminer's page_texts dict.
    Only string cells with non-empty content are included.
    """
    result = {}
    for sheet_name in sheet_names:
        ws = wb[sheet_name]
        cells = []
        for row in ws.iter_rows():
            for cell in row:
                if cell.value and isinstance(cell.value, str) and cell.value.strip():
                    cells.append((cell.value.strip(), cell.row, cell.column))
        result[sheet_name] = cells
    return result

def parse_identifiers(description: str) -> list:
    """Extract IDENTIFIERS JSON array from a [FIGURE] block. Same as chorus-pdf."""
    ids = []
    m = re.search(r'^IDENTIFIERS:\s*(\[.*?\])\s*$', description, re.MULTILINE)
    if m:
        try:
            raw = json.loads(m.group(1))
            ids = [str(x).strip() for x in raw if str(x).strip()]
        except json.JSONDecodeError:
            pass
    if not ids:
        ids = re.findall(r'\b([A-Za-z][A-Za-z0-9\-_]{1,19})\b', description)
    seen = set()
    result = []
    for ident in ids:
        if ident in _XREF_STOPWORDS or len(ident) < _XREF_MIN_LEN:
            continue
        if ident.lower() in seen:
            continue
        seen.add(ident.lower())
        result.append(ident)
    return result

def find_text_occurrences_excel(identifier: str, sheet_texts: dict) -> list:
    """Search all sheet cells for identifier as a whole word.

    Returns a list of (sheet_name, row, col, snippet) tuples.
    The snippet is ≤ 120 chars centred on the first match.
    """
    pattern = re.compile(r'\b' + re.escape(identifier) + r'\b')
    results = []
    for sheet_name, cells in sheet_texts.items():
        for (text, row, col) in cells:
            m = pattern.search(text)
            if m:
                start = max(0, m.start() - 55)
                end   = min(len(text), m.end() + 55)
                snippet = text[start:end].replace('\n', ' ').strip()
                if start > 0:   snippet = '…' + snippet
                if end < len(text): snippet += '…'
                results.append((sheet_name, row, col, snippet))
    return results

def _fmt_occ_excel(occurrences: list) -> str:
    """Format Excel occurrence list: Sheet 'X' R5C3: ..."""
    if not occurrences:
        return "    (no occurrence found in sheet cells)"
    lines = []
    for sheet_name, row, col, snippet in occurrences:
        lines.append(f"    Sheet '{sheet_name}' R{row}C{col}: {snippet}")
    return '\n'.join(lines)

def xref_pass_excel(all_figure_descs: dict, sheet_texts: dict) -> tuple:
    """Run the full cross-reference pass (Excel adaptation of chorus-pdf xref_pass).

    Parameters
    ----------
    all_figure_descs : {(sheet_name, fig_idx): description_text}
    sheet_texts      : {sheet_name: [(text, row, col), ...]}

    Returns
    -------
    (annotated_descs, xref_index_block)
    """
    annotated    = {}
    global_index = {}   # {identifier: [(sheet_name, fig_idx, occurrences), ...]}

    for (sheet_name, fig_idx), desc in all_figure_descs.items():
        identifiers = parse_identifiers(desc)
        if not identifiers:
            annotated[(sheet_name, fig_idx)] = desc
            continue

        xref_lines = [f"[XREF FIGURE {fig_idx} — sheet '{sheet_name}']"]
        for ident in identifiers:
            occs = find_text_occurrences_excel(ident, sheet_texts)
            xref_lines.append(f"  {ident}:")
            xref_lines.append(_fmt_occ_excel(occs))
            global_index.setdefault(ident, []).append((sheet_name, fig_idx, occs))
        xref_lines.append(f"[END XREF FIGURE {fig_idx}]")

        annotated_desc = re.sub(
            r'(\[END FIGURE[^\]]*\])',
            r'\1\n' + '\n'.join(xref_lines),
            desc,
            count=1
        )
        if annotated_desc == desc:
            annotated_desc = desc + '\n' + '\n'.join(xref_lines)
        annotated[(sheet_name, fig_idx)] = annotated_desc

    # Build global XREF INDEX
    index_lines = [
        "=== XREF INDEX ===",
        "# Cross-reference: identifiers found in figures → cell occurrences",
        "",
    ]
    for ident in sorted(global_index):
        entries = global_index[ident]
        fig_refs    = []
        all_occs    = []
        for sheet_name, fig_idx, occs in entries:
            fig_refs.append(f"Figure {fig_idx} (Sheet '{sheet_name}')")
            all_occs.extend(occs)
        index_lines.append(f"## {ident}")
        index_lines.append(f"   Appears in: {', '.join(fig_refs)}")
        seen_locs = set()
        for sheet_name, row, col, snip in all_occs:
            loc_key = (sheet_name, row, col)
            if loc_key not in seen_locs:
                index_lines.append(
                    f"   Cell occurrence (Sheet '{sheet_name}' R{row}C{col}): {snip}")
                seen_locs.add(loc_key)
        if not all_occs:
            index_lines.append("   Cell occurrence: (none found)")
        index_lines.append("")
    index_lines.append("=== END XREF INDEX ===")

    return annotated, '\n'.join(index_lines)

# ---------------------------------------------------------------------------
# Assembly: one block per sheet
# ---------------------------------------------------------------------------

def assemble_sheet(sheet_name, md_table, figure_descs_ordered):
    """
    Assemble one sheet block: Markdown table followed by figure descriptions.

    figure_descs_ordered: list of (fig_idx, anchor_row, anchor_col, kind, description)
    kind: 'image' or 'chart'
    """
    parts = [f"=== SHEET: {sheet_name} ===", md_table]
    for fig_idx, row, col, kind, desc in figure_descs_ordered:
        kind_label = "IMAGE" if kind == 'image' else "CHART"
        parts.append(f"\n[{kind_label} {fig_idx} — anchor: row {row}, col {col}]")
        parts.append(desc)
    parts.append(f"=== END SHEET: {sheet_name} ===")
    return "\n\n".join(parts)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    try:
        import openpyxl as _openpyxl
    except ImportError:
        print("⛔ openpyxl not installed. Run: pip install openpyxl", file=sys.stderr)
        sys.exit(1)

    if not API_KEY:
        print("⛔ ANTHROPIC_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    print(f"[chorus-excel] Hybrid mode — {XLSX_PATH}", file=sys.stderr)
    wb = _openpyxl.load_workbook(XLSX_PATH, data_only=True)
    sheets = [SHEET_FILTER] if SHEET_FILTER else wb.sheetnames

    # Count total media for nohup gate
    total_images = sum(len(wb[s]._images) for s in sheets if s in wb.sheetnames)
    total_charts = sum(len(wb[s]._charts) for s in sheets if s in wb.sheetnames)
    n_media = total_images + total_charts
    print(f"[chorus-excel]   → {len(sheets)} sheet(s), "
          f"{total_images} image(s), {total_charts} chart(s) = {n_media} media element(s)",
          file=sys.stderr)

    # --- nohup gate ----------------------------------------------------------
    force = os.environ.get("CHORUS_EXCEL_FORCE", "") == "1"
    if n_media > NOHUP_THRESHOLD and not force:
        print(
            f"[chorus-excel] ⚠️  {n_media} images/charts detected — estimated time "
            f"~{n_media * 30 // 60}–{n_media * 45 // 60} min "
            f"(threshold: {NOHUP_THRESHOLD}).\n"
            f"[chorus-excel]    Run with nohup to avoid a 10-min IDE timeout:\n"
            f"[chorus-excel]    CHORUS_EXCEL_FORCE=1 nohup python3 {os.path.abspath(__file__)} "
            f"> {OUTPUT_PATH}.log 2>&1 &",
            file=sys.stderr
        )
        sys.exit(2)   # exit code 2 = "nohup required" (not an error)
    elif n_media > NOHUP_THRESHOLD and force:
        print(
            f"[chorus-excel] ⚠️  {n_media} media — CHORUS_EXCEL_FORCE=1 → proceeding without gate.",
            file=sys.stderr
        )
    # -------------------------------------------------------------------------

    # Try LibreOffice once for chart conversion (Strategy A)
    libreoffice_available = False
    chart_pages_png = None   # list of PNG bytes (one per PDF page)

    all_figure_descs = {}   # {(sheet_name, fig_idx): description_text}
    sheet_parts      = []
    total_figs       = 0

    with tempfile.TemporaryDirectory(prefix="chorus-excel-") as tmpdir:
        if total_charts > 0:
            print("[chorus-excel] Attempting LibreOffice chart extraction ...", file=sys.stderr)
            chart_pages_png = chart_to_png_via_libreoffice(XLSX_PATH, tmpdir)
            if chart_pages_png:
                libreoffice_available = True
                print(f"[chorus-excel]   → LibreOffice: {len(chart_pages_png)} page(s) rendered",
                      file=sys.stderr)
            else:
                print("[chorus-excel]   → LibreOffice not available — chart placeholders will be used",
                      file=sys.stderr)

        for sheet_name in sheets:
            if sheet_name not in wb.sheetnames:
                continue
            ws = wb[sheet_name]
            print(f"[chorus-excel] Sheet '{sheet_name}' ...", file=sys.stderr)

            # Table
            md_table = extract_sheet_to_markdown(ws)

            # Per-sheet figure index (global across images + charts)
            fig_descs_for_sheet = []   # [(fig_idx, row, col, kind, desc), ...]
            sheet_fig_start = total_figs + 1

            # Images
            for img_anchor in ws._images:
                total_figs += 1
                fig_idx = total_figs
                row, col = get_image_position(img_anchor)
                png_bytes = extract_image_png(img_anchor)
                if png_bytes:
                    print(f"[chorus-excel]   Image {fig_idx} (R{row}C{col}) → Claude ...",
                          file=sys.stderr)
                    desc = call_claude_figure(png_bytes, sheet_name, fig_idx)
                    all_figure_descs[(sheet_name, fig_idx)] = desc
                    fig_descs_for_sheet.append((fig_idx, row, col, 'image', desc))
                    print(f"[chorus-excel]     → {len(desc)} chars", file=sys.stderr)
                else:
                    placeholder = (
                        "[IMAGE — unsupported format (EMF/WMF) — not extractable]\n"
                        "[Convert the embedded image to PNG/JPEG in Excel and rerun]"
                    )
                    fig_descs_for_sheet.append((fig_idx, row, col, 'image', placeholder))

            # Charts
            for chart_anchor in ws._charts:
                total_figs += 1
                fig_idx = total_figs
                row, col = get_chart_position(chart_anchor)
                if libreoffice_available and chart_pages_png:
                    # Use the first available rendered page (best-effort)
                    # In a multi-sheet workbook, the chart page index is approximate
                    page_png = chart_pages_png[min(len(chart_pages_png) - 1, 0)]
                    print(f"[chorus-excel]   Chart {fig_idx} (R{row}C{col}) → Claude (via LibreOffice) ...",
                          file=sys.stderr)
                    desc = call_claude_figure(page_png, sheet_name, fig_idx)
                    all_figure_descs[(sheet_name, fig_idx)] = desc
                    fig_descs_for_sheet.append((fig_idx, row, col, 'chart', desc))
                    print(f"[chorus-excel]     → {len(desc)} chars", file=sys.stderr)
                else:
                    # Fallback: include chart metadata as placeholder
                    chart_obj = chart_anchor if hasattr(chart_anchor, 'title') else getattr(chart_anchor, 'chart', chart_anchor)
                    title, ctype, series = extract_chart_metadata(chart_obj)
                    placeholder = (
                        f"[CHART {fig_idx} — anchor: row {row}, col {col}]\n"
                        f"[Chart type: {ctype}]\n"
                        f"[Title: {title}]\n"
                        + (f"[Series: {', '.join(series)}]\n" if series else "")
                        + CHART_PLACEHOLDER_VISION
                    )
                    fig_descs_for_sheet.append((fig_idx, row, col, 'chart', placeholder))

            sheet_parts.append((sheet_name, md_table, fig_descs_for_sheet))

    # --- Phase 2.5 — Cross-reference pass ------------------------------------
    if all_figure_descs:
        print("[chorus-excel] Phase 2.5 — cross-reference pass ...", file=sys.stderr)
        sheet_texts = build_sheet_texts(wb, sheets)
        annotated_descs, xref_index = xref_pass_excel(all_figure_descs, sheet_texts)
        total_xref = sum(len(parse_identifiers(d)) for d in all_figure_descs.values())
        print(f"[chorus-excel]   → {total_xref} identifier(s) cross-referenced",
              file=sys.stderr)
    else:
        annotated_descs = {}
        xref_index = None

    # Merge annotated descriptions back into sheet_parts
    output_parts = []
    for sheet_name, md_table, fig_descs_for_sheet in sheet_parts:
        updated_figs = []
        for (fig_idx, row, col, kind, orig_desc) in fig_descs_for_sheet:
            key = (sheet_name, fig_idx)
            desc = annotated_descs.get(key, orig_desc)
            updated_figs.append((fig_idx, row, col, kind, desc))
        output_parts.append(assemble_sheet(sheet_name, md_table, updated_figs))

    if xref_index:
        output_parts.append(xref_index)

    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write("\n\n".join(output_parts))
    print(f"[chorus-excel] ✅ {len(sheet_parts)} sheet(s), {total_figs} figure(s) — "
          f"Written to {OUTPUT_PATH}", file=sys.stderr)

if __name__ == "__main__":
    main()
```

> ⚠️ **Dependencies**:
> - `pip install openpyxl Pillow` (required)
> - `sudo apt install libreoffice` (optional — chart extraction via Strategy A)
> - `sudo apt install poppler-utils` (optional — required by LibreOffice strategy)
> - `export ANTHROPIC_API_KEY="sk-ant-..."` (required for hybrid mode)
>
> ℹ️ **API calls**: 1 call per embedded image or LibreOffice-rendered chart page.
> Charts without LibreOffice produce a metadata placeholder — no API call.
>
> ℹ️ **Merged cells**: master values are propagated to slave cells automatically.
> The Markdown table shows the master value once in its natural column position.


## Phase 2.5 — Cross-reference pass (hybrid mode only)

After all image and chart descriptions have been obtained from Claude (Phase 2), and
**before** assembling the final Markdown output, the hybrid script runs an automatic
cross-reference pass. This is the Excel adaptation of `chorus-pdf`'s Phase 2.5.

### 2.5.1 — Collect identifiers from figures

Same logic as `chorus-pdf` Phase 2.5.1: parse the `IDENTIFIERS: [...]` JSON line
appended by Claude to each `[FIGURE N]` block. Apply the same `_XREF_STOPWORDS`
filter and `_XREF_MIN_LEN = 2` minimum length threshold.

### 2.5.2 — Search cell occurrences

For each identifier, `find_text_occurrences_excel()` searches `sheet_texts`
(all string cells collected by `build_sheet_texts()`) using a whole-word regex
`\bIDENTIFIER\b`. Returns `(sheet_name, row, col, snippet)` tuples.

> **Difference from chorus-pdf**: the lookup space is worksheet cells (identified by
> `sheet_name` + `R{row}C{col}`) instead of PDF text blocks (identified by `page_num`).

### 2.5.3 — Annotate figure descriptions

A `[XREF FIGURE N]` block is appended immediately after each `[END FIGURE N]` marker:

```
[XREF FIGURE 3 — sheet 'Calculs']
  M-001:
    Sheet 'Feuille1' R12C3: …The member M-001 shall be designed for…
    Sheet 'Calculs' R45C1: …see M-001 in the load table…
  IPE-200:
    (no occurrence found in sheet cells)
[END XREF FIGURE 3]
```

### 2.5.4 — Append global XREF INDEX

After all sheet blocks, a global index is appended at the end of the `-vision.md` file:

```
=== XREF INDEX ===
# Cross-reference: identifiers found in figures → cell occurrences

## M-001
   Appears in: Figure 3 (Sheet 'Calculs'), Figure 7 (Sheet 'Récap')
   Cell occurrence (Sheet 'Feuille1' R12C3): …The member M-001…
   Cell occurrence (Sheet 'Calculs' R45C1): …see M-001 in the…

## IPE-200
   Appears in: Figure 3 (Sheet 'Calculs')
   Cell occurrence: (none found)

=== END XREF INDEX ===
```

### 2.5 — Output format summary

| Section | Location in output | Purpose |
|---|---|---|
| `[XREF FIGURE N]` block | Inline, after each `[END FIGURE N]` | Local annotation — kept with the figure for `chorus-feed` |
| `=== XREF INDEX ===` | End of file | Global map — all identifiers with all cell occurrences |

> ⚠️ **Hybrid mode only** — the XREF pass requires both `sheet_texts` (cell content)
> and Claude figure descriptions. It is not available in text or CSV modes.


## Phase 3 — Execute and validate

### 3.1 Execute the script

```bash
python3 "$SANDBOX/agent/extract-excel-<slug>.py"
```

Capture stderr for progress reporting. Exit code 0 = success. Exit code 2 = nohup required.

### 3.2 Validate the output

```python
import sys, re

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
sheets       = re.findall(r'=== SHEET: .+? ===', text)
figures      = re.findall(r'\[FIGURE', text)
tables_rows  = re.findall(r'^\|', text, re.MULTILINE)
placeholders = text.count('not extracted')
xref_local   = re.findall(r'\[XREF FIGURE', text)
xref_index   = 1 if '=== XREF INDEX ===' in text else 0

print(f"Sheets found     : {len(sheets)}")
print(f"Figures found    : {len(figures)}")
print(f"XREF annotations : {len(xref_local)}  (inline, hybrid mode)")
print(f"XREF INDEX       : {'present' if xref_index else 'absent'}")
print(f"Table rows       : {len(tables_rows)}")
print(f"Placeholders     : {placeholders}")
print(f"Total chars      : {len(text)}")
if len(sheets) == 0:
    print("⚠️  WARNING: no === SHEET === markers — output may be malformed")
if len(text) < 200:
    print("⚠️  WARNING: output is suspiciously short")
if placeholders > 0:
    print(f"ℹ️  {placeholders} element(s) not extracted — set ANTHROPIC_API_KEY and rerun")
```

Run this validation snippet on `$SANDBOX/corpus/<NNN>-<slug>-vision.md` (or `-text.txt`).

### 3.3 Failure handling

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| `openpyxl` ImportError | Missing dependency | `pip install openpyxl` |
| `Pillow` ImportError | Missing dependency (hybrid) | `pip install Pillow` |
| `ANTHROPIC_API_KEY not set` | Missing env var | `export ANTHROPIC_API_KEY="sk-ant-..."` |
| HTTP 400 | Image too large | Check image size — openpyxl may include very large embedded images |
| HTTP 429 / 529 | API rate limit | Retry handled automatically (exponential backoff, up to 4 attempts) |
| Script exit code 2 | nohup required | Set `CHORUS_EXCEL_FORCE=1` and relaunch with `nohup` |
| `ws._images` empty despite visible images | Images are ActiveX/OLE objects | Cannot be extracted via openpyxl — note in output |
| Merged cell values blank | File uses unusual merge encoding | Check `ws.merged_cells.ranges` — may require manual verification |
| Chart placeholder instead of description | LibreOffice not installed | `sudo apt install libreoffice` + `sudo apt install poppler-utils` |
| `ws.max_row` is very large | Excel stores phantom rows | The script skips empty rows — output should be correct |
| EMF/WMF image — skipped | Unsupported format | Re-export the image as PNG in Excel before processing |
| CSV: garbled characters | Wrong encoding | Add `encoding='latin-1'` or `encoding='cp1252'` in the reader |


## Phase 4 — Update sandbox metadata

### 4.1 Update `README.org`

Add a row for the new file in the `Corpus` table:

```org
| <NNN> | corpus/<NNN>-<slug>-text.txt   | openpyxl from <source.xlsx> (text mode)    | <date> |
| <NNN> | corpus/<NNN>-<slug>-vision.md  | openpyxl+vision from <source.xlsx>          | <date> |
| <NNN> | corpus/<NNN>-<slug>-text.txt   | csv.reader from <source.csv>                | <date> |
```

Do **not** remove the original `.xlsx` or `.csv` — keep it in `corpus/` for traceability.

### 4.2 Report to the user

```
✅ chorus-excel completed
   Mode     : hybrid  (or: text | csv)
   Source   : corpus/<source.xlsx>  (<N> sheet(s))
   Output   : corpus/<NNN>-<slug>-vision.md   (or: -text.txt)
   Sheets   : <N>
   Tables   : <N> Markdown pipe tables
   Images   : <N> described via Claude vision  (or: <N> placeholders)
   Charts   : <N> described via LibreOffice+Claude  (or: <N> placeholders)
   XREF     : <N> identifier(s) cross-referenced  [hybrid only]
   Size     : <N> chars

   Next step: chorus-feed <sandbox-name> corpus/<NNN>-<slug>-vision.md
              (or: corpus/<NNN>-<slug>-text.txt)
```


## Integration with chorus-feed

`chorus-excel` is a **pre-processing step**, not a replacement for `chorus-feed`.
It must be run **before** `chorus-feed` when the corpus contains `.xlsx` or `.csv` files,
and **before** `chorus-import-project` when the source project documents are spreadsheets.

Typical workflow:

```
# XLSX with embedded images/charts — hybrid activated automatically if API key set
chorus-excel  <sandbox> corpus/002-devis-isolation.xlsx
→ corpus/003-devis-isolation-vision.md   (hybrid mode)

# XLSX without API key — text mode fallback
chorus-excel  <sandbox> corpus/002-devis-isolation.xlsx
→ corpus/003-devis-isolation-text.txt

# CSV file — always text mode
chorus-excel  <sandbox> corpus/002-elements-structure.csv
→ corpus/003-elements-structure-text.txt

# Process specific sheet only
chorus-excel  <sandbox> corpus/002-devis-isolation.xlsx --sheet Calculs
→ corpus/003-devis-isolation-text.txt   (single-sheet extract)

# Then in all cases:
chorus-feed <sandbox> corpus/003-devis-isolation-vision.md
            (or: corpus/003-devis-isolation-text.txt)

# For project import — preferred over chorus-import-project's built-in handler:
chorus-excel        <sandbox> corpus/source.xlsx
chorus-import-project <sandbox> corpus/<NNN>-source-vision.md
```

### Why `chorus-excel` vs. `chorus-import-project`'s built-in Excel handler

`chorus-import-project`'s built-in Excel handling (Phase 0B) is minimal:
- Tab-separated dump via `openpyxl` (no Markdown table structure)
- No merged cell handling
- No image extraction
- No chart extraction
- No XREF pass

`chorus-excel` provides:
- Full Markdown pipe table with merged cell resolution
- Claude vision on embedded images
- Chart extraction via LibreOffice (with graceful fallback)
- XREF cross-reference pass linking figure identifiers to cell values
- Structured output compatible with `chorus-feed` and `chorus-import-project`


## Dependencies

| Package | Install | Notes |
|---------|---------|-------|
| `openpyxl` | `pip install openpyxl` | XLSX extraction — required |
| `Pillow` | `pip install Pillow` | Image conversion (hybrid mode only) — required for hybrid |
| `LibreOffice` | `sudo apt install libreoffice` | Chart extraction — optional, graceful fallback |
| `pdftoppm` | `sudo apt install poppler-utils` | Chart page rendering — optional, required if LibreOffice used |
| `ANTHROPIC_API_KEY` | `export ANTHROPIC_API_KEY="sk-ant-..."` | Hybrid mode |


## Quick Reference — Naming Conventions

| Artifact | Convention | Example |
|----------|-----------|---------|
| Extraction script | `agent/extract-excel-<slug>.py` | `agent/extract-excel-devis-isolation.py` |
| CSV / text mode output | `corpus/<NNN>-<slug>-text.txt` | `corpus/003-devis-isolation-text.txt` |
| Hybrid mode output | `corpus/<NNN>-<slug>-vision.md` | `corpus/003-devis-isolation-vision.md` |
| Original XLSX/CSV | kept as-is in `corpus/` | `corpus/002-devis-isolation.xlsx` |


## Troubleshooting

**"The output table has blank cells where I expected values"**
→ The cells contain formulas, and the XLSX was saved before calculation, so `data_only=True`
  returns `None`. Open the file in Excel/LibreOffice, save it (which caches calculated values),
  then rerun `chorus-excel`. The script will show `[FORMULA — not evaluated]` for uncached cells.

**"Merged cell values appear in the wrong column"**
→ The `build_merged_map` function maps slave cells to their master value. The master cell
  is always the top-left of the merged range. If the table looks correct in Excel but wrong
  in the Markdown output, check the merge range orientation with:
  `python3 -c "import openpyxl; wb = openpyxl.load_workbook('f.xlsx'); ws = wb.active; print(list(ws.merged_cells.ranges))"`

**"Images exist in the Excel file but `ws._images` is empty"**
→ The images may be ActiveX controls, OLE objects, or SmartArt — openpyxl only exposes
  standard `ImageAnchor` objects. These exotic formats cannot be extracted programmatically.
  Screenshot the images manually and add them as standalone PNG files to `corpus/`.

**"LibreOffice chart extraction produced the wrong chart"**
→ The LibreOffice strategy converts the entire workbook to PDF and uses the first rendered
  page. In multi-sheet workbooks with many charts, the page-to-chart mapping is approximate.
  For precise extraction, use LibreOffice's macro API (out of scope for this skill) or
  export charts as PNG directly from Excel before running `chorus-excel`.

**"Script exited with code 2 — nohup required"**
→ The workbook has ≥ 16 images/charts. Copy the `nohup` command printed to stderr:
  ```bash
  CHORUS_EXCEL_FORCE=1 nohup python3 $SANDBOX/agent/extract-excel-<slug>.py > $SANDBOX/corpus/<NNN>-<slug>-vision.md.log 2>&1 &
  tail -f $SANDBOX/corpus/<NNN>-<slug>-vision.md.log
  ```

**"CSV output has garbled accented characters"**
→ The CSV uses a Windows encoding. Try `encoding='cp1252'` or `encoding='latin-1'`
  in the `csv_to_markdown_safe` function instead of `utf-8-sig`.

**"A formula cell shows `[FORMULA — not evaluated]` instead of its value"**
→ The file was last saved without calculation. In LibreOffice Calc: Tools → Macros →
  Run `ThisComponent.calculate()`, then save. In Excel: press F9 (recalculate), then save.
  Rerun `chorus-excel` after resaving.

**"The XREF INDEX is absent from the output"**
→ The XREF pass only runs in hybrid mode when at least one image or chart was described
  by Claude. If the workbook has no embedded images or charts (pure data tables), the
  XREF pass is skipped — this is expected and correct. The output is still valid for
  `chorus-feed`.
