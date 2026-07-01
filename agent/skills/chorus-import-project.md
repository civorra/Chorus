# Skill — chorus-import-project

> Trigger: `chorus-import-project <sandbox-name> <source…> [--out <fichier.json>] [--batch]`
> Agent: `architect`
>
> `<sandbox-name>` : sandbox containing a KB produced by `chorus-feed`
> `<source…>`      : one or more project sources from the engineer (see modes below)
>                    Accepted formats: PDF, Word (.docx), Excel (.xlsx/.csv),
>                    plain text, table pasted in the chat, directory path
> `--out`          : output JSON filename (merge mode only;
>                    default: `projet-import-<NNN>.json`)
> `--batch`        : force batch mode even if a single source is provided
>
> ### Invocation Modes
>
> | Syntax | Mode | Behavior |
> |---|---|---|
> | `chorus-import-project sb fichier.pdf` | **Single** | 1 source → 1 JSON (original behavior) |
> | `chorus-import-project sb f1.pdf f2.xlsx f3.docx` | **Merge** | N sources → 1 merged JSON (same project, complementary files) |
> | `chorus-import-project sb ./dossier/` | **Batch** | Directory → 1 JSON per file + summary report |
> | `chorus-import-project sb *.pdf --batch` | **Batch** | Explicit glob → 1 JSON per file + summary report |
> | `chorus-import-project sb fichier.pdf --align-review` | **Align-review** | Stops after Phase 3 — produces `align-review-NNN.org` for human validation before JSON |
>
> **Automatic mode detection rule:**
> - 1 non-directory source argument → Single
> - N > 1 source arguments (same or mixed formats) → Merge
> - 1 directory argument or `--batch` flag present → Batch
> - `--align-review` present → alignment review mode (compatible with Single and Merge; incompatible with `--batch`)
>
> **Single responsibility: align the engineer's project terminology with the sandbox
> KB slots and types, then produce a valid project JSON file.**
>
> Prerequisites: `chorus-feed <sandbox-name>` must have been run beforehand (org KB present).
>
> ⚠️ **KB sources to use — strict order:**
> 1. `$SANDBOX/agent/chorus/index.org` → Frame types, pipeline, namespace
> 2. `$SANDBOX/agent/chorus/<slug>.org` → sections `Ontologie`, `Dictionnaire des slots`,
>    `Catalogue des Frames` (mandatory slots, value domains)
> 3. `$SANDBOX/agent/import-report-*.org` existing → previous alignment decisions
>
> ⛔ **Never read** `Helpers.pm`, `Feed.pm`, `Agent/*.pm` to infer slots.
> ⛔ **Never invent** a value absent from the source document — report the gap.

---

## Phase 0 — Source Data Acquisition

### Mode Detection and Source Collection

```
# Batch Mode (directory)
If <source> is a directory:
  files = glob("$source/*.{pdf,docx,xlsx,csv,txt}")
  Sort by name — process each file independently (→ Phase 0B per file)
  Continue to Phase 0-BATCH after collection

# Batch Mode (glob / explicit --batch)
If --batch present or N homogeneous-format sources (N > 1 same extension):
  files = source list
  Sort by name — process each file independently
  Continue to Phase 0-BATCH after collection

# Merge Mode (N sources, mixed formats, without --batch)
If N > 1 sources without --batch:
  Extract each source separately → produce N labelled text blocks
  Merge blocks before Phase 2 (global inventory)
  ⚠️ Warn if two files appear to cover the same elements (potential duplicate ids)

# Single Mode
1 non-directory source, without --batch → original behaviour (Phase 0A/0B below)
```

### Phase 0-BATCH — Batch Processing

For each file `f` in `files`:
1. Extract plain text (Phase 0B below)
2. Run Phases 1–6 **autonomously** for this file
3. Name the outputs: `projet-import-<NNN>.json` and `import-report-<NNN>.org`
   (increment NNN independently for each file)
4. At the end of the batch → produce the **batch summary report** (see Phase 6-BATCH)

> ⚠️ Phase 1 (KB reading) is run **once only** at the start of the batch
> and reused for all files — the terminology reference is shared.

### Phase 0-FUSION — Multi-Source Merge

After individually extracting each source:
1. Concatenate the text blocks, labelling each by source file:
   ```
   === SOURCE: structure.pdf ===
   <texte extrait>

   === SOURCE: isolation.xlsx ===
   <texte extrait>
   ```
2. The inventory (Phase 2) processes the whole as a single source
3. Retain the `_source_fichier` attribute on each JSON element for traceability
4. **Id conflict handling**: if two sources define an element with the same `id`:
   - Include both with suffix `_a` / `_b` on the duplicate
   - Add `_conflit: 1` and `_conflit_source: ["fichier1", "fichier2"]`
   - Report the conflict in the import report

### Case A — Inline source (data pasted in the chat)

The engineer pastes a table excerpt, a list of elements, or a descriptive text directly.
Process the content as-is — proceed directly to Phase 1.

### Case B — Filesystem source (files on disk)

Identify the format and extract plain text **before** any semantic processing.

#### PDF — hybrid extraction (same pipeline as `chorus-pdf --hybrid`)

PDF extraction uses the **same 4-mode pipeline as `chorus-pdf`**:
figures, diagrams, and normative tables are recovered via Claude vision — not just raw text.

> **Why it matters:** project documents (DCE, CCTP, BET notes) often embed structural
> diagrams, specification tables as images, or mixed layouts that `pdftotext` silently drops.
> Hybrid mode preserves this information for the terminology alignment phases.

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

#### Excel / CSV
```bash
# CSV direct
cat "<fichier.csv>"

# Excel → CSV via LibreOffice
libreoffice --headless --convert-to csv "<fichier.xlsx>" --outdir /tmp/
cat /tmp/"<fichier>.csv"

# Excel via Python (si LibreOffice absent)
python3 -c "
import openpyxl
wb = openpyxl.load_workbook('<fichier.xlsx>')
for ws in wb.worksheets:
    for row in ws.iter_rows(values_only=True):
        print('\t'.join(str(c) if c is not None else '' for c in row))
"
```

#### Word (.docx)
```bash
python3 -c "
import docx
doc = docx.Document('<fichier.docx>')
for p in doc.paragraphs: print(p.text)
for t in doc.tables:
    for row in t.rows:
        print('\t'.join(c.text for c in row.cells))
"
```

> ⚠️ If extraction tools are absent → ask the engineer to provide copy-pasted content
> from their application (Case A).
> Never block the workflow over a missing tool — offer the inline alternative.

---

## Phase 1 — Read the KB (canonical terminology)

### 1.0 Sandbox inventory (first tool call — token keepalive)

**Before reading any file**, read the directory tree $SANDBOX/ immediately.

This serves two purposes:
1. Acquires the full sandbox structure early (agents list, rules dirs, existing JSON/report files)
2. Ensures at least one tool call happens before any long reading+thinking cycle,
   keeping the IDE token active from the very start.

Use this inventory to:
- Confirm the list of `<slug>.org` files to read in 1.2
- Know which `rules/<slug>/` directories exist (for the keepalive calls in 1.2)
- Detect any existing `import-report-*.org` files (for 1.3)

### 1.1 Pipeline Index

Read `$SANDBOX/agent/chorus/index.org`:
- Namespace + agent list (slug, pos)
- Global slot dictionary (if present in the index)

### 1.2 Per-agent terminology

For each agent, apply this two-step sequence:

1. **Read** `$SANDBOX/agent/chorus/<slug>.org` and extract:

| KB Section | What we extract |
|---|---|
| `Ontologie` | Domain concepts, synonyms, relationships (e.g. "entrait" = horizontal truss beam) |
| `Catalogue des Frames` | Exact types (`type_element`), mandatory slots per type |
| `Dictionnaire des slots` | Canonical names, value types, units, allowed domains |

2. **Immediately after** (no thinking between the two calls): read the directory tree $SANDBOX/rules/<slug>/
   to list the rule files for this agent.

> **Why the immediate tool call:** Opus extended thinking after reading a dense KB file
> can be long enough to expire the IDE token. Reading the directory tree right after
> each read resets the token TTL and produces a useful rules inventory at no extra cost.

Build an internal **terminology reference**:
```
concept_kb        → type_element / slot_kb       unit_kb     domain
────────────────────────────────────────────────────────────────────
montant porteur   → montant_porteur              —           —
lisse              → lisse_basse / lisse_haute   —           to clarify
classe résistance → classe_bois                 —           C14/C16/C18/C24/C30
épaisseur isolant → epaisseur_mm                mm          positive integer
conductivité λ    → classe_conductivite         —           "031"/"035"/"040"
hauteur libre     → hauteur_libre_m             m           decimal
section           → section_bois                —           "BxH" ex. "45x145"
```

### 1.3 Previous alignment decisions

If `$SANDBOX/agent/import-report-*.org` exists, read the latest report:
- Retrieve previously validated mappings → reapply them without asking again
- Retrieve pending questions → re-raise them if the same terms reappear

---

## Phase 2 — Raw Inventory of Project Elements

### Keepalive checkpoint (token refresh before long thinking phases)

**Before starting the inventory**, if the source is a filesystem file, call:
```bash
wc -l "<fichier-source-extrait>"
```
or, if working from inline/already-extracted text, read the directoy tree $SANDBOX/agent/
to confirm the report directory.

> **Why:** Phases 2, 3 and 4 are pure thinking phases with no tool calls.
> On a complex project (many element types, many ambiguous terms), the combined
> thinking time across these three phases can expire the IDE token before Phase 5
> triggers the next tool call (JSON write). This checkpoint resets the TTL just
> before entering the silent zone.

Scan the source data and produce a **raw inventory**:
an uninterpreted list of what the engineer has provided.

```
Source line / cell              Term identified      Associated values
────────────────────────────────────────────────────────────────────────
"Poteau porteur 45×145 C24"    "poteau porteur"     dim=45×145, classe=C24
"h libre 2,5m, entraxe 40cm"  "h libre"            2.5m / "entraxe"=40cm
"Laine de verre λ035, e=20cm" "laine de verre"     λ=0.035, e=200mm
"panneau OSB 12mm, CE"         "panneau OSB"        ep=12mm, CE=oui
```

> **Rule:** do not map at this stage — inventory first, align later.
> Preserve the original source text in the inventory for traceability.

---

## Phase 3 — Terminology Alignment

### KB Coverage Gauge (pre-alignment check)

**Before starting the term-by-term alignment**, compute a coverage indicator from the
raw inventory (Phase 2) against the KB reference (Phase 1.2):

```
📊 KB Coverage Gauge
   Distinct types detected in inventory : N  (e.g. 8)
   Types recognised in KB               : n / N  (e.g. 5 / 8 = 62%)
   Critical slots covered               : n / total  (e.g. 11 / 17 = 65%)
   KB Aliases section present           : yes / no
```

| Coverage | Level | Action |
|---|---|---|
| ≥ 80% types + ≥ 80% critical slots | 🟢 Good | Proceed directly |
| 60–79% on either axis | 🟡 Moderate | Proceed with a warning — flag `_couverture_kb: moderate` in the JSON `_import` block |
| < 60% on either axis | 🔴 Low | Emit the warning below and ask whether to continue |

**🔴 Low-coverage warning (display before alignment):**

```
⚠️  KB Coverage Gauge — LOW COVERAGE DETECTED
    Types recognised   : n/N (XX%)
    Critical slots     : n/N (XX%)

    The KB may lack aliases for the project's terminology.
    Risk: many terms will receive ❓ (ambiguous) or ⬜ (out-of-scope),
    producing an incomplete or unusable JSON.

    Recommended actions (choose one or both):
      1. Run `chorus-feed --harvest-aliases <previous-import-report.org>`
         if a validated import report exists for this sandbox.
      2. Enrich the KB: add aliases to `$SANDBOX/agent/chorus/<slug>.org`
         under `** Aliases` before re-running this import.

    Continue anyway? [yes / abort]
```

If the engineer confirms `yes`, proceed — but set `"_couverture_kb": "low"` in the
`_import` block and list the unrecognised types under a dedicated section
`* KB coverage gap` in the import report (Phase 6).

> **Batch mode:** compute the gauge once per file, using the shared KB loaded in Phase 1.
> Files with 🔴 coverage are flagged in the batch summary report (Phase 6-BATCH)
> with a `⚠️ low KB coverage` marker in the results table — the batch is not aborted.

---

### Alignment table

This is the core phase. For each term from the raw inventory, cross-reference against
the KB reference (Phase 1.2) and produce an alignment table:

```
Project term                  KB slot / type_element    KB value         Confidence
──────────────────────────────────────────────────────────────────────────────────
"poteau porteur"              type_element              montant_porteur  ✅ certain
"45×145"                      section_bois              "45x145"         ✅ certain
"C24"                         classe_bois               "C24"            ✅ certain
"h libre 2,5m"                hauteur_libre_m           2.5              ✅ certain
"entraxe 40cm"                entraxe_mm                400              ✅ certain (×10)
"laine de verre λ035"         type_element              isolant_laine    ✅ certain
                              classe_conductivite       "035"            ✅ certain
"panneau OSB 12mm"            type_element              panneau_osb      ✅ certain
                              osb_epaisseur_mm          12               ✅ certain
"poteau intérieur cloison"    type_element              montant_non_porteur ⚠️ likely
"panneau contreventement"     type_element              panneau_osb ?    ❓ ambiguous
"traitement cl. 2"            traitement_applique ?     ?                ❓ to clarify
```

### Confidence Levels

| Symbol | Meaning | Action |
|---|---|---|
| ✅ certain | Direct or near-direct match with the KB | Map without asking |
| ⚠️ likely | Logical match but term is not exact | Propose + ask for confirmation |
| ❓ ambiguous | Multiple possible mappings or unknown KB term | Block + ask for clarification |
| ⛔ gap | Mandatory slot absent from the source document | Report — do not invent |
| ⬜ out-of-scope | `type_element` absent from this sandbox's KB | Exclude from JSON — flag `_hors_perimetre: 1` + report |

> **Out-of-scope rule:** an element receives `⬜` if its `type_element` is not recognised
> by **any** `Catalogue des Frames` in the target sandbox. This is non-blocking — the import
> continues. The element is excluded from the output JSON and listed in the
> `Out-of-scope elements` section of the import report.
>
> **Architectural consequence:** a multi-domain project (e.g. structural + thermal) must
> be imported **once per target sandbox** — each import retains only the types that sandbox
> knows. `chorus-import-project` is the partitioning tool; `run.pl` only sees the elements
> that concern it.
>
> ```bash
> # Mixed project → two targeted imports
> chorus-import-project sandbox-structurel ./dossier-projet/ --batch
>     # → JSON containing only montant_porteur, lisse_basse, ...
>     # → elements isolant_laine, membrane_etanche → ⬜ excluded + report
>
> chorus-import-project sandbox-thermique ./dossier-projet/ --batch
>     # → JSON containing only isolant_laine, membrane_etanche, ...
>     # → elements montant_porteur, lisse_basse → ⬜ excluded + report
> ```

### Figure identifiers as matching candidates (hybrid mode)

When the source document was extracted in hybrid mode, each `[FIGURE N]` block ends with
an `IDENTIFIERS: [...]` line listing the labels and codes visible in the figure (callout
tags, part numbers, element IDs).

**These identifiers are first-class matching candidates** for Phase 3:

1. **Cross-reference with KB aliases** — if `chorus-feed` has populated an
   `** Aliases from figures` table in the KB `Ontologie` (built from the XREF INDEX of
   the normative corpus), check whether the identifier appears there. A direct hit gives
   confidence ✅ and maps directly to the corresponding `type_element` or slot value.

2. **Cross-reference with figure description body** — if the identifier is not in the KB
   aliases, search the description text of the same `[FIGURE N]` block for a co-occurring
   corpus term. Example: `IDENTIFIERS: ["P1"]` + description mentions *"Poteau porteur
   45×145 C24"* → candidate `type_element: montant_porteur` at confidence ⚠️.

3. **Cross-reference with surrounding text blocks** — search the raw inventory (Phase 2)
   for text blocks on the same page that mention the identifier alongside a known slot
   value. Example: `P1` appears in a table row *"P1 — 45×145 — C24 — h=2.5m"* on the
   same page → aggregate all slot values from that row under the element `id: P1`.

4. **Preserve identifier as `id`** — when an element is successfully mapped, use the
   figure identifier as the element `id` in the output JSON (preferred over a generated
   ID), since it matches the document's own reference system and enables
   document ↔ JSON traceability.

> **Rule:** figure identifiers that could not be matched to any KB term after steps 1–3
> are listed in the import report under a dedicated section
> `* Unmatched figure identifiers` — they are candidates for a future `chorus-feed --enrich`
> run to extend the KB aliases.

### Unit Transformations

Explicitly document every conversion:

| Source pattern | Transformation | KB Slot |
|---|---|---|
| `2,5m` / `2.5m` / `250cm` | → `2.5` | `hauteur_libre_m` |
| `40cm` / `400mm` / `0,4m` | → `400` | `entraxe_mm` |
| `20cm` / `200mm` | → `200` | `epaisseur_mm` |
| `λ=0,035` / `λ035` / `laine 035` | → `"035"` | `classe_conductivite` |
| `45/145` / `45×145` / `45x145` | → `"45x145"` | `section_bois` |
| `C 24` / `classe C24` / `C24 EN338` | → `"C24"` | `classe_bois` |

### Resolving Ambiguities

For each ❓ term, present the following to the engineer:
```
❓ "panneau contreventement" — multiple interpretations possible:
   1. panneau_osb     (structural OSB panel §3.1)
   2. panneau_fibragglo (bracing panel §3.2)
   Which type matches your document?
```

**Do not proceed until blocking ❓ items are resolved** (ambiguous `type_element` slots).
⚠️ items may be provisionally accepted with a `_a_confirmer: 1` flag.

### --align-review mode — stop here for human validation

If `--align-review` was specified, **stop after Phase 3** and produce an alignment review
file instead of proceeding to Phase 4 / JSON generation:

1. **Write** `$SANDBOX/agent/align-review-<NNN>.org`:

```org
#+TITLE: Alignment review — <source> — <date>
#+STATUS: pending-validation

* KB Coverage Gauge
  Types recognised   : n/N (XX%)
  Critical slots     : n/N (XX%)
  Coverage level     : 🟢 good / 🟡 moderate / 🔴 low

* Full alignment table
  | Project term | KB slot / type_element | KB value | Confidence | Notes |
  |---|---|---|---|---|
  | ...          | ...                    | ...      | ✅/⚠️/❓   | ...   |

* Items requiring engineer decision
  ** Ambiguous (❓) — must be resolved before JSON generation
     | Term | Options | Decision |
     |---|---|---|

  ** Likely (⚠️) — provisionally accepted, confirm or override
     | Term | Proposed mapping | Confirm? |
     |---|---|---|

  ** Out-of-scope (⬜) — will be excluded from JSON
     | Term | Reason | Correct sandbox? |
     |---|---|---|

* Gaps identified at this stage
  | Element id | Missing slot | Mandatory? |
  |---|---|---|

* How to proceed
  1. Review and annotate this file (correct ❓ decisions, confirm/reject ⚠️ items)
  2. Rerun WITHOUT --align-review to produce the JSON:
     chorus-import-project <sandbox> <source>
     The skill will reload this align-review file (Phase 1.3) and apply your decisions.
```

2. **Display** a summary to the engineer:
```
✅ Alignment review produced: $SANDBOX/agent/align-review-NNN.org
   ✅ certain  : N terms
   ⚠️ likely   : N terms (to confirm)
   ❓ ambiguous: N terms (must be resolved)
   ⬜ out-of-scope: N terms
   ⛔ gaps     : N mandatory slots absent

   Next step: review the file, then rerun without --align-review to generate the JSON.
```

3. **Do not** proceed to Phase 4, Phase 5, or Phase 6.
   The JSON is produced only on the subsequent run (without `--align-review`),
   after the engineer has validated the alignment file.

---

## Phase 4 — Identify Gaps

For each element, cross-reference the present slots against the KB `Catalogue des Frames`:

```
Type            Mandatory slot      Present?    Source
──────────────────────────────────────────────────────────
montant_porteur classe_bois         ✅          "C24"
montant_porteur humidite_pct        ⛔ ABSENT   not mentioned
montant_porteur hauteur_libre_m     ✅          "h=2.5m"
```

### Gap Handling

| Gap type | Action |
|---|---|
| Mandatory slot absent | Ask the engineer — do not assume |
| Optional slot absent | Omit from JSON — the pipeline handles it |
| Out-of-domain value (e.g. `classe_bois: "C12"`) | Report — let the engineer correct it |
| Entire element unmappable | Include with `_incomplet: 1` — will be cleanly rejected by Feed |

---

## Phase 5 — Produce the JSON

### Single / Merge Mode — one JSON

Once all ❓ items are resolved and critical gaps are filled:

```json
{
  "projet": "<nom-projet-ingenieur>",
  "description": "Import from <source> — <date> — <N> elements",
  "_import": {
    "source": "<nom-fichier-ou-inline>",
    "sources": ["<f1>", "<f2>"],
    "mode": "unitaire|fusion",
    "date": "<date>",
    "gaps": ["<id>: <slot manquant>", "..."],
    "a_confirmer": ["<id>: <terme ambigu>", "..."],
    "conflits": ["<id>: present in f1 and f2 — duplicate renamed", "..."]
  },
  "elements": [
    {
      "id": "<id-issu-du-document>",
      "type_element": "<type_kb>",
      "<slot_1>": "<valeur>",
      "_source_fichier": "<nom-fichier>",
      "_a_confirmer": 1,
      "_conflit": 1,
      "_conflit_source": ["<f1>", "<f2>"]
    }
  ]
}
```

> **`id` convention**: keep the source document identifier if available
> (e.g. "Poteau P1", "IPE-01"), otherwise generate `<TYPE_ABREV>-<NN>`.
> Document ↔ JSON traceability is the priority.
> In merge mode, `_source_fichier` is always set on each element.

### Batch Mode — one JSON per file

Each file produces its own JSON named `projet-import-<NNN>.json`.
The `_import.mode` field is `"batch"`.
No cross-file merging — each JSON is self-contained and can be piped independently.

---

## Phase 6 — Produce the Import Report

Create `$SANDBOX/agent/import-report-<NNN>.org`:

```org
#+TITLE: Import report — <source> — <date>
#+STATUS: draft

* Source
  File    : <path or "inline">
  Date    : <date>
  Elements extracted: N

* Alignment table
  | Project term | KB slot | KB value | Confidence | Decision |
  |---|---|---|---|---|
  | ...          | ...     | ...      | ✅/⚠️/❓   | ...      |

* Unit transformations applied
  | Source | Transformation | KB slot |
  |---|---|---|

* Gaps identified
  | Element | Missing slot | Action |
  |---|---|---|

* Ambiguities resolved
  | Term | Options | Engineer decision |
  |---|---|---|

* Elements with _a_confirmer
  | id | Reason |
  |---|---|

* Out-of-scope elements (⬜)
  | id | source type_element | Recommended sandbox |
  |---|---|---|

* Unmatched figure identifiers
  Identifiers found in figures but not mapped to any KB slot or type_element.
  Candidates for a future chorus-feed --enrich run to extend KB aliases.
  | Identifier | Figure | Page | Snippets seen | Action |
  |---|---|---|---|---|

* Output file
  <path projet-*.json>
  N elements retained / N complete / N with gaps / N to confirm / N out-of-scope (excluded)
```

> This report is the **alignment decision memory** for this sandbox.
> It is automatically re-read during the next `chorus-import-project` run on the same sandbox.

### Post-import — automatic harvest proposal

After writing the import report, check whether new ✅ alignments were produced that are
**absent from all previous `import-report-*.org`** files in this sandbox:

```
N_new = count of ✅ alignments not present in any prior import-report-*.org
```

If `N_new > 0`, display:

```
💡 Harvest opportunity — N new ✅ alignments detected
   These mappings are not yet in the KB and will need to be re-derived on every future import.
   Run the following to integrate them permanently into the sandbox KB:

     chorus-feed --harvest-aliases $SANDBOX/agent/import-report-NNN.org

   Future imports from this sandbox will resolve these terms at ✅ confidence without re-asking.
   (Skip if the KB is intentionally minimal or the mappings are project-specific.)
```

If `N_new == 0` (all alignments were already known from prior reports), skip silently.

### Phase 6-BATCH — Summary Report (batch mode only)

In addition to the individual reports, create `$SANDBOX/agent/import-batch-<NNN>.org`:

```org
#+TITLE: Batch summary report — <directory or glob> — <date>
#+STATUS: draft

* Parameters
  Source    : <directory or file list>
  Sandbox   : <sandbox-name>
  Files     : N processed / M skipped (unsupported format)
  Date      : <date>

* Results per file
  | File    | JSON produced | Elements | Retained | Gaps | To confirm | Conflicts | Out-of-scope |
  |---|---|---|---|---|---|---|---|
  | f1.pdf  | projet-import-001.json | 34 | 26 | 6 | 2 | 0 | 0 |
  | f2.xlsx | projet-import-002.json | 18 | 15 | 3 | 0 | 0 | 3 |
  | ...     | ...                    | .. | .. | . | . | . | . |

* Totals
  Elements processed  : N
  Retained (in JSON)  : N
  With gaps           : N
  To confirm          : N
  Out-of-scope        : N (excluded from JSON — import in another sandbox)
  Id conflicts        : N (merge mode only — N/A in batch)

* New terms detected
  Terms absent from previous import-report-*.org → to integrate into the KB
  | Source term | File | Proposed alignment | Confidence |
  |---|---|---|---|

* Skipped files
  | File | Reason |
  |---|---|
  | scan-brouillon.pdf | Empty text extraction — re-read or provide inline |

* Suggested next step
  perl $SANDBOX/run.pl <JSON1> <JSON2> ...
  (run the pipeline on each produced JSON)
```

> **New terms**: if a source term was not present in previous reports AND received a
> ✅ safe alignment, it is a candidate for integration into the `Dictionnaire` section
> of the corresponding agent KB (via `chorus-feed` or manual editing of the org file).

---

## Phase 7 — Run the Pipeline (optional)

If the engineer explicitly requests it, follow up with `chorus-check`:

```bash
perl $SANDBOX/run.pl $SANDBOX/<projet-import-NNN.json>
```

If `run.pl` does not yet exist → indicate that `chorus-check` should be run first.

---

## Separation of Responsibilities

| | `chorus-feed` | `chorus-import-project` | `chorus-create-project` | `chorus-check` |
|---|---|---|---|---|
| **Reads** | normative corpus | engineer project docs + org KB | org KB | org KB + YAML |
| **Produces** | KB org, YAML, Helpers.pm | `projet-import-*.json` + `.org` report | `projet-*.json` | Feed.pm, shells, Expert.pm, run.pl |
| **Threshold source** | corpus | org KB only | org KB only | org KB |
| **Gaps** | n/a | reported, never invented | computed from KB | n/a |
| **Never reads** | — | Helpers.pm, Feed.pm | Helpers.pm, Feed.pm | — |

---

## Architectural Principle — sandbox granularity = JSON granularity

> **The granularity of a sandbox defines the granularity of the project JSON intended for it.**

A sandbox covers a coherent normative domain (e.g. structural, thermal, hygrometry).
A multi-domain project produces as many import JSONs as there are target sandboxes.
**`chorus-import-project` is the partitioning tool — not `run.pl`.**

Out-of-scope elements (⬜) are cleanly excluded at import time; `run.pl` and
`Feed.pm` only receive the types they know.

```
dossier-projet/                      ← single source (all domains mixed)
  charpente.pdf
  isolation.xlsx
  bardage.docx

  ↓ chorus-import-project sandbox-structurel ./dossier-projet/ --batch
projet-structurel-001.json           ← montants, lisses, chevrons
                                        # → elements isolant_laine, membrane_etanche → ⬜ excluded + report

  ↓ chorus-import-project sandbox-thermique ./dossier-projet/ --batch
projet-thermique-001.json            ← isolants, membranes
                                        # → elements montant_porteur, lisse_basse → ⬜ excluded + report

  ↓
perl sandbox-structurel/run.pl projet-structurel-001.json → rapport_struct.txt
perl sandbox-thermique/run.pl  projet-thermique-001.json  → rapport_thermo.txt
```

**Consequence for `Feed.pm`** (generated by `chorus-check`):
The template uses `warn + next` instead of `die` on an unknown type, as a safety net
in case a mixed JSON somehow reached `run.pl`. Partitioning remains the responsibility
of `chorus-import-project`.
