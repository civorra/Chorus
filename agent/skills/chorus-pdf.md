# Skill — chorus-pdf

## ⚡ Sub-skills index (ENG-042) — load in this order after Phase 0.0 mode detection

> `chorus-pdf.md` is now `chorus-pdf-core.md` — always loaded first.
> Mode-specific sub-skills are loaded via `eca__read_file` after Phase 1.

| Mode | Sub-skills to load (in order) |
|---|---|
| **text** (default, no API key) | `chorus-pdf-_shared-text-hybrid.md` → `chorus-pdf-text.md` |
| **`--hybrid`** | `chorus-pdf-_shared-text-hybrid.md` + Phase 1.5 in `chorus-pdf-hybrid.md` → `chorus-pdf-hybrid.md` |
| **`--auto`** | `chorus-pdf-_shared-auto-images.md` → `chorus-pdf-auto.md` |
| **`--images`** | `chorus-pdf-_shared-auto-images.md` → `chorus-pdf-images.md` |

> `call_claude_with_retry()` is defined in this file (Phase 2 intro) — available to all modes.
> Load this file first, then the mode sub-skill(s).

## ⛔ Strict sandbox isolation

Never read any KB, YAML, or artifact from a sandbox other than `<sandbox-name>`.
This skill operates exclusively on the `corpus/` directory of the target sandbox.

## Overview

Standard PDF-to-text tools (`pdftotext`, `pdf2txt.py`) extract only typographic text.
They silently drop structural diagrams, normative tables rendered as images, multi-column
layouts, and figure annotations. This skill provides three extraction modes of increasing
capability:

### Four extraction modes

| Mode | Flag | Engine | API key | Figures | Tables (vector) | Output |
|------|------|--------|---------|---------|-----------------|--------|
| **Auto** (**default**) | *(none — auto-detected)* | `pdfminer` on text pages + vision LLM on figure pages | ✅ `ANTHROPIC_API_KEY` | ✅ described (targeted) | ⚠️ not reconstructed | `<slug>-vision.md` |
| **Hybrid** | `--hybrid` | `pdfminer` for text on ALL pages + Claude vision on cropped figures only | ✅ `ANTHROPIC_API_KEY` | ✅ described (precise crop) | ✅ `pdfplumber` — Markdown pipe table | `<slug>-vision.md` |
| **Text** (fallback) | *(none — no API key)* | `pdfminer.six` | ❌ not required | `[FIGURE — not extracted]` placeholder | ✅ `pdfplumber` — Markdown pipe table | `<slug>-text.md` |
| **Images** | `--images` | `pdftoppm` 150 DPI + vision LLM on all pages | ✅ `ANTHROPIC_API_KEY` | ✅ described (exhaustive) | ⚠️ not reconstructed | `<slug>-vision.md` |

**Choosing a mode:**

```
No flag provided
  → Phase 0.0 auto-detects ANTHROPIC_API_KEY and probes Claude
  → if key valid   : --auto activated automatically  ← DEFAULT
  → if key absent or invalid : text mode (fallback)

API key available, document has mixed pages (text + embedded figures)
  → (default — auto activated automatically)

API key available, document requires maximum fidelity on figures (precise crop per LTFigure)
  → --hybrid   ← higher quality on figure-dense normative standards (DTU, EC5, NF EN…)

API key available, document is mostly diagrams or scanned
  → --images

No API key available
  → (default text mode — forced fallback)
```

> **`--auto` is the default mode** when an API key is available — uses `pypdf` page
> classification to send only pages with embedded images to Claude vision, avoiding
> false positives from decorative vector elements (`LTFigure`) detected by pdfminer.
> Use `--hybrid` when maximum figure fidelity is required (precise bbox crop per figure).

> ⛔ **Known blind spot — rotated-header matrix tables** (cross-reference /
> dependency matrices with column headers printed one character per line,
> rotated 90°): silently flattened into unreadable text by **all** modes
> (no mode is immune — the failure is in `pdfminer`/`pdfplumber` layout
> analysis, upstream of the mode-specific rendering). See § 1.4c for
> detection heuristic, `pdftotext -layout` fallback, and manual verification
> method. Always independently verify any table containing "X"/"-" marks
> mixed inline with a run of column-header-like tokens.

> ⛔ **Known blind spot — borderless (whitespace-only) tables — the majority
> case on cleanly-typeset modern standards** (CC:2022, ISO-style documents):
> the `has_table` heuristic (§1.4b) only fires on tables with drawn vector
> borders (`LTCurve` H/V lines). Tables aligned purely by whitespace, with
> no drawn cell lines, are **never detected** — they silently fall through
> to plain text extraction and are flattened into a long sequence of
> single-line paragraphs (no `|` pipe syntax at all), with **no warning in
> the extraction log** (the log only reports pages where `has_table` fired).
> This is more common, and more silent, than the rotated-header case above.
> See §1.4d for detection heuristic and fallback. **Always run the §1.4g
> checklist** on every table-bearing page after generation — do not rely on
> the extraction log's table count as a completeness signal.

> ⛔ **Known blind spot — mis-split header cells** (`pdfplumber` column
> detection places a boundary mid-word inside a merged header cell) and
> **unstitched multi-page tables** (each page processed independently, no
> automatic continuation): both pass `quality_check()` silently since
> neither triggers the existing empty-cell/fragment filters. See §1.4e and
> §1.4f. Manual review of header rows and page-boundary row counts is
> required — these are not filterable defects at generation time with the
> current `quality_check()` heuristics.

> It combines pdfminer precision on text (exact characters, no OCR risk) with
> Claude vision on cropped figures only (smaller payload, lower cost, no text
> re-interpretation). On pages with both text and figures, text fidelity is
> maximised and API calls are minimised to the figure bounding boxes.

## Phase 0.0 — Auto-detect mode (no explicit flag)

This phase runs **only when neither `--auto`, `--hybrid` nor `--images` was provided**.
Its goal: activate `--hybrid` automatically if Claude is available.

### 0.0.1 Check API key presence

```python
# Résolution de la clé — 3 sources dans l'ordre de priorité :
#   1. Variable d'env ANTHROPIC_API_KEY (hôte via claude-python, ou API-key mode)
#   2. Secret Docker  /run/secrets/anthropic_api_key  (container chorus-web)
#   3. Fichier hôte   ~/.config/anthropic/api_key     (dev local)
import os
from pathlib import Path

API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
if not API_KEY:
    for _kf in ["/run/secrets/anthropic_api_key",
                str(Path.home() / ".config/anthropic/api_key")]:
        if Path(_kf).exists():
            API_KEY = Path(_kf).read_text().strip()
            if API_KEY:
                break

if not API_KEY:
    # No key found anywhere → stay in text mode, skip probe
    mode = "text"
    print("[chorus-pdf] No ANTHROPIC_API_KEY — text mode.", file=sys.stderr)
```

If a key is present → proceed to 0.0.2.

### 0.0.2 Probe Claude availability

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

### 0.0.3 Decision table

| `ANTHROPIC_API_KEY` | Probe result | Mode activated | Message |
|---|---|---|---|
| absent | — | text | `No ANTHROPIC_API_KEY — text mode.` |
| present | ✅ valid | **auto** | `ANTHROPIC_API_KEY detected — Claude available ✅ — auto mode activated.` |
| present | ❌ invalid (401/403) | text | `ANTHROPIC_API_KEY set but key is invalid (HTTP 4xx) — falling back to text mode.` |
| present | ❌ unreachable | text | `Claude unreachable (network error) — falling back to text mode.` |
| present | ⚠️ throttled (429/529) | **auto** | `ANTHROPIC_API_KEY detected — Claude available (throttled) ✅ — auto mode activated.` |

Print the selected mode to stderr before proceeding to Phase 0.1.

> ⚠️ **Explicit flags always take precedence.**
> `--auto`, `--hybrid` and `--images` bypass Phase 0.0 (no mode negotiation), but each
> performs its own **pre-flight key check at module level** — absence → `sys.exit(1)` immediately,
> presence → `_probe_claude()` validates the key before any PDF processing starts.
> Phase 0.0 is only entered when the user provides no mode flag.

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

### 0.2 Resolve the PDF path

If `<file.pdf>` is a bare filename → prepend `$SANDBOX/corpus/`.
If it is an absolute path → use as-is.
If it is a relative path → resolve against `$SANDBOX/`.
Verify the file exists and ends in `.pdf` (case-insensitive).

In `--batch` mode: glob `$SANDBOX/corpus/*.pdf` (and `*.PDF`). Process each in turn.
If no PDF found → warn and exit cleanly (not an error).

#### ⛔ Guard — PDF outside `corpus/` → automatic import-context mode

After resolving the PDF path, check whether it falls under `$SANDBOX/corpus/`:

```
if resolved_pdf_path does NOT start with $SANDBOX/corpus/:
    → automatically activate --output-dir mode (Phase 0.3b)
       output_dir = dirname(resolved_pdf_path)
    → Phase 4.1 README.org update is SKIPPED ([skip-readme-update] implicit)
    → print: "[chorus-pdf] PDF outside corpus/ — import-context mode activated automatically.
              Output dir: <output_dir>. README.org will NOT be updated."
```

**Rationale:** a PDF located in `workspace/`, an absolute path outside the sandbox,
or any path not under `corpus/` is by definition a project document, not normative
corpus. Sending its output to `corpus/` and updating README.org would corrupt the
corpus numbering sequence and misclassify the document as normative source material.
This guard makes the distinction deterministic and unambiguous — the operator never
needs to remember to pass `--output-dir` for a project document.

### 0.3 Resolve the output filename

Two modes depending on whether `--output-dir <path>` is provided:

#### 0.3a — Standalone mode (default, no `--output-dir`)

Output goes to `$SANDBOX/corpus/` with a sequential NNN prefix:

```
existing = glob("$SANDBOX/corpus/[0-9][0-9][0-9]-*.*")
last_num = max of the leading 3-digit prefix across existing files (default 0)
next_num = last_num + 1   (formatted as %03d)
```

> ⚠️ In `--batch` mode, increment `next_num` for each PDF processed in sequence.

Output filename: `$SANDBOX/corpus/<next_num>-<slug>.<ext>`

Example:
```
Input   : corpus/002-uk-approved-doc-a-2013.pdf
Default : corpus/003-uk-approved-doc-a-2013-text.md
--auto  : corpus/003-uk-approved-doc-a-2013-vision.md
--images: corpus/003-uk-approved-doc-a-2013-vision.md
```

#### 0.3b — Import context mode (`--output-dir <path>` provided)

Used when `chorus-pdf` is invoked by `chorus-import-project` to convert a project
document. The caller passes the target directory explicitly (e.g.
`workspace/<client>/sources/`). In this mode:

- **No NNN prefix** — the output file is named `<slug>.<ext>` directly (project
  documents are not corpus entries and must not pollute the `corpus/` numbering sequence)
- **No README.org update** — Phase 4.1 is skipped entirely (the caller handles
  the import report itself)
- Output directory is created if it does not exist

Output filename: `<--output-dir>/<slug>.<ext>`

Example:
```
Input        : workspace/Mairie-Acme/sources/import-17935/plan.pdf
--output-dir : workspace/Mairie-Acme/sources/
Output       : workspace/Mairie-Acme/sources/plan-text.md
```

> ⚠️ `--output-dir` and `--batch` are mutually exclusive — abort with an error if
> both are provided.

#### 0.3c — Derive slug and extension (both modes)

Derive the slug and extension based on mode:

| Mode | Suffix | Extension | Rationale |
|------|--------|-----------|-----------|
| Hybrid (default) | `-vision` | `.md` | pdfminer text + cropped figure vision — default when API key present |
| Text (fallback) | `-text` | `.md` | pdfminer text + Markdown pipe tables when `pdfplumber` available; plain text fallback otherwise |
| Auto (`--auto`) | `-vision` | `.md` | Contains Markdown tables and `[FIGURE]` blocks |
| Images (`--images`) | `-vision` | `.md` | Contains Markdown tables and `[FIGURE]` blocks |

- If `--out <slug>` provided → use that slug as-is (suffix already included)
- Otherwise → strip leading `NNN-` prefix and `.pdf` extension from the input filename,
  then append the mode suffix

## Phase 1 — PDF assessment

### 1.1 Count pages

```bash
python3 -c "
import sys
try:
    import pypdf
    r = pypdf.PdfReader(sys.argv[1])
    print(len(r.pages))
except Exception as e:
    print('ERROR:', e, file=sys.stderr)
    sys.exit(1)
" "<path/to/file.pdf>"
```

Fallback if `pypdf` unavailable:
```bash
pdfinfo "<path/to/file.pdf>" | grep "^Pages:" | awk '{print $2}'
```

### 1.2 Page classification (--auto mode only)

For `--auto`, each page is classified **before** generating the script,
using `pypdf` to inspect the page content.

→ Implementation: see `classify_pages()` in the Auto mode script template.

Report the classification to the user before generating the script:
```
[chorus-pdf] Page classification:
   → 38 text-only pages  (pdfminer — no API call)
   → 16 pages with figures (vision LLM — 4 chunks × 4 pages)
```

### 1.3 Chunk sizes

| Mode | Chunk size | Rationale |
|------|-----------|-----------|
| Text (default) | N/A — single pass | pdfminer processes the whole file at once |
| Auto (`--auto`) | 5 vision pages per call | only figure pages are chunked |
| Hybrid (`--hybrid`) | 1 figure crop per call | each `LTFigure` bbox sent individually |
| Images (`--images`) | 5 pages per call | all pages, one PNG each (~500 KB) |

### 1.4 Figure detection for `--hybrid` mode

For `--hybrid`, figure bounding boxes are detected via `pdfminer` layout analysis.
Each `LTFigure` element exposes its `(x0, y0, x1, y1)` coordinates in PDF space.

### 1.4b Vector table detection (all modes)

Many normative PDFs (EU directives, JOUE publications, regulatory annexes) encode their
tables as **vectors** (`LTCurve` elements — thin lines forming cell borders), not as
`LTFigure` or embedded images. Standard pdfminer text extraction silently discards the
table structure and dumps cell contents in Y-order, mixing columns.

**Detection heuristic** — applied during `analyse_pages` on every page:
≥3 H-lines (`LTCurve`, width > 50) sharing a **consistent horizontal span** (same x0 ±10pt AND same x1 ±10pt) + ≥1 V-line (`LTCurve`, height > 30) whose X center falls within that span → `has_table = True`.
This avoids false positives on flowcharts, whose H-segments have varying widths and scattered positions.
→ Implementation: see `analyse_pages()` in "Shared utilities — Text & Hybrid modes" (Phase 2).

Store `has_table` in the `analyse_pages` result so that the assembly phase knows
which pages require `pdfplumber` table reconstruction.

**Reconstruction with `pdfplumber`:**

When `has_table` is `True`, use `pdfplumber` to reconstruct the table as a Markdown
pipe table. The key insight is that pdfplumber's automatic column detection often fails
on PDF files with doubled/hairline lines (linewidth ≈ 0). Use `'vertical_strategy':
'explicit'` with column x-coordinates derived from the V-edges detected above.

→ Implementation: see `detect_table_columns()` / `extract_tables_from_page()` in the script templates below.

**Coordinate system — pdfplumber `top` → pdfminer `y_center`:**

pdfplumber uses origin=top-left (`top` increases downward); pdfminer uses
origin=bottom-left (`y` increases upward).

→ Implementation: see `pdfplumber_top_to_pdfminer_y()` in the script templates below.

**Deduplication:** after inserting a table block at its Y-position, suppress all
`LTTextBox` elements whose `y_center` falls within the table's vertical range —
they are already represented by the Markdown table.

**Layout analysis loop** — extracts text blocks and figure bboxes per page, with
`has_table` detection embedded.

→ Implementation: see `analyse_pages()` in "Shared utilities — Text & Hybrid modes" (Phase 2).

**Coordinate conversion — PDF space → PNG pixels:**

PDF coordinates have their origin at the **bottom-left**; PNG pixels have theirs at
the **top-left**.

→ Implementation: see `pdf_bbox_to_png_crop()` in the Hybrid mode script template.

**Reading order reconstruction:**

After mixing text blocks and `[FIGURE N]` placeholders, sort all elements by their
`y_center` in **descending** order (top of page = highest PDF y-coordinate).

→ Implementation: see `assemble_page()` in the Hybrid mode script template.

**Dependency:** `pdfplumber` — installed in the pipx venv at
`~/.local/share/pipx/venvs/pdfplumber/bin/python3` if not available system-wide.
The script must detect the correct interpreter or fall back gracefully.

### 1.4c Rotated-header table detection — `pdftotext -layout` fallback

**⛔ Known failure mode:** normative standards frequently include **cross-reference /
dependency matrices** whose column headers are printed **rotated 90°** (one character
per line, e.g. a column header `ADV_FSP.1` rendered as a vertical stack `A`/`D`/`V`/`_`/
`F`/`S`/`P`/`.`/`1`). `pdfminer`'s `LTTextBox` grouping and `pdfplumber`'s
`find_tables()` both assume horizontal reading order — they silently **flatten** this
layout into a single incoherent line of text (row label + first data mark + all column
headers concatenated), with no error, no warning, and no `quality_check()` rejection
(the flattened output does not match any of Filters 0-3, since it exits as an
`LTTextBox` never routed through `extract_tables_from_page()` at all — `has_table`
detection via H/V-line curves may not fire either, if the matrix uses hairline
borders instead of the H+V curve pattern of § 1.4b).

**Symptom in the generated `.md` file:** a single line mixing a row label, one or two
"X"/"-" marks, and a run of column header tokens with no visual separation, e.g.:
```
ADV_ARC.1   X  ADV_FSP.1   ADV_FSP.2   ADV_FSP.3   ADV_FSP.4   ADV_FSP.5   ADV_FSP.6 ...
```
This is **not** a garbled/corrupt PDF — the underlying content is fully recoverable
(see verification method below) — it is a **structural blind spot** in the current
`analyse_pages()` / `extract_tables_from_page()` pipeline.

**Detection heuristic — applied during `analyse_pages` on every page:**

A page is flagged `rotated_header_suspect = True` when pdfminer reports ≥ 6
`LTChar` (or single-character `LTTextLineHorizontal`) elements that are:
- vertically stacked (each char's `y0`/`y1` adjacent to the next, same `x0` ±2pt), AND
- collectively spell a token matching the corpus's own component-id pattern
  (`[A-Z]+_[A-Z]+\.\d+`, e.g. `ADV_FSP.1`) when read top-to-bottom.

```python
def detect_rotated_headers(layout, page_num):
    """Detect vertically-stacked single-character columns spelling out
    component-id-like tokens (e.g. rotated 'ADV_FSP.1' column headers).
    Returns True if the page likely contains a rotated-header matrix table.
    """
    import re
    from pdfminer.layout import LTChar, LTTextLineHorizontal

    chars = []
    for el in layout:
        if isinstance(el, LTTextLineHorizontal) and len(el.get_text().strip()) <= 2:
            chars.append((el.get_text().strip(), el.x0, el.y0, el.y1))

    # Cluster by x0 (same column) — chars sharing x0 ±2pt stacked in Y
    from collections import defaultdict
    columns = defaultdict(list)
    for text, x0, y0, y1 in chars:
        key = round(x0 / 2) * 2   # snap to 2pt buckets
        columns[key].append((text, y0, y1))

    id_pattern = re.compile(r'^[A-Z]+_[A-Z]+\.\d+$')
    for x0, entries in columns.items():
        if len(entries) < 6:
            continue
        entries.sort(key=lambda e: -e[1])   # top-to-bottom (descending y)
        spelled = ''.join(t for t, _, _ in entries)
        if id_pattern.match(spelled.replace(' ', '')):
            return True
    return False
```

Store `rotated_header_suspect` in the `analyse_pages()` per-page result dict
(alongside `has_table`), so downstream assembly can trigger the fallback.

**Fallback — `pdftotext -layout` reconstruction:**

When `rotated_header_suspect` is `True` for a page, **do not** attempt to reconstruct
the table via `pdfplumber`/`pdfminer` — both preserve the same broken reading order.
Instead, shell out to `pdftotext -layout`, which uses Poppler's own layout-preserving
text extraction (character-position-aware, handles rotated/pivoted headers correctly
because it lays out the *page's absolute X/Y grid* rather than grouping text runs):

```python
def extract_page_via_pdftotext_layout(pdf_path, page_num):
    """Fallback extraction for pages with rotated-header matrix tables.
    Returns the raw -layout text for the page, or None on failure.
    """
    import subprocess
    result = subprocess.run(
        ["pdftotext", "-f", str(page_num), "-l", str(page_num), "-layout", pdf_path, "-"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    return result.stdout
```

Insert the raw `pdftotext -layout` output for that page as a fenced block, clearly
labelled, instead of the (broken) reconstructed Markdown table:

```
[MATRIX TABLE — extracted via pdftotext -layout (rotated column headers detected)]
<raw -layout text, monospace-aligned>
[END MATRIX TABLE]
```

> ⚠️ **Do not attempt to convert this into a Markdown pipe table automatically.**
> `pdftotext -layout` preserves alignment via whitespace positioning only — reliably
> readable by a human or by a downstream LLM pass, but converting it losslessly into
> `| col | col |` syntax requires column-boundary inference that is exactly the failure
> mode being avoided here. Downstream tools (`chorus-feed`) must read the monospace
> block as-is and may ask a human to confirm the row/column mapping before codifying
> it into rules — never auto-derive `dependencies` arrays from this block without
> explicit confirmation.

**Verification method (manual, for auditing an already-generated `.md`):**

If a suspicious flattened line is spotted in a generated `-vision.md` or `-text.md`
file (row label immediately followed by marks and a run-on of column tokens), verify
independently **before** trusting or rejecting the content:

```bash
pdftotext -f <page> -l <page> -layout <source.pdf> - | less
```

- If `pdftotext -layout` produces a clean, aligned grid → the PDF source is fine;
  the extraction pipeline (`chorus-pdf`) failed on this page — apply the fallback above.
- If `pdftotext -layout` **also** produces garbled output → the PDF itself has a
  genuine rendering problem (non-standard font encoding, requires OCR) — escalate,
  do not attempt automated reconstruction.

> **This check adds zero API cost** — `pdftotext` is a local, offline tool
> (part of `poppler-utils`, already a hard dependency of this skill).

### 1.4d Borderless (whitespace-only) tables — undetected by `has_table` — flattened to a vertical list

**⛔ Known failure mode, distinct from §1.4c:** many modern normative standards
(CC:2022 Parts 2/3/5, ISO-style documents, and similar "clean" typesetting) render
tables **without any drawn cell borders** — columns are aligned purely by
whitespace positioning (visible in `pdftotext -layout`), with no `LTCurve` H/V
lines at all. The `has_table` heuristic (§1.4b) requires ≥2 aligned H-lines +
≥2 V-lines — it **never fires** on this table style, so `pdfplumber` is never
invoked and the page falls through to plain `LTTextBox` extraction.

**Symptom in the generated `.md` file:** every cell of a real multi-column
table appears as its own paragraph/line, in Y-order, with **no `|` pipe
syntax at all** — e.g. a 6×7 EAL summary matrix (component vs. assurance
level) becomes ~200 consecutive single-line blocks:
```
Assurance class

Assurance components by evaluation assurance level

Assurance family

EAL1

EAL2
...
ADV_ARC

1

1
```
This is **not** a garbled/corrupt PDF and **not** the rotated-header case
(§1.4c) — the underlying table has a completely ordinary horizontal layout;
it is simply undetectable by the vector-line heuristic because no vectors
exist in the source PDF.

**Detection heuristic — applied during `analyse_pages` on every page:**

A page is flagged `borderless_table_suspect = True` when `has_table` is
`False` (no vector lines found) **and** the page's `LTTextBox` elements show
a numeric-density pattern consistent with a data matrix:

```python
import re as _re

# Pattern d'annonce textuelle explicite d'un tableau (ENG-043 — détection duale)
_TABLEAU_ANNONCE = _re.compile(
    r'tableau\s+ci[- ]dessous|tableau\s+suivant|tableau\s+ci[- ]après'
    r'|le\s+tableau\s+(?:suivant\s+)?(?:indique|récapitule|présente|montre'
    r'|répertorie|ci[- ]dessous)',
    _re.IGNORECASE
)

def detect_borderless_table(texts, page_width, page_text=""):
    """Detect a likely borderless (whitespace-aligned) table — dual heuristic.

    Two independent signals combined with OR (ENG-043):

    Signal 1 — explicit text announcement:
        "Le tableau ci-dessous indique…", "le tableau suivant récapitule…", etc.
        Covers text-content tables (long cell values) that the X-band heuristic
        misses (validated on sandbox 03b pages 28, 29, 31, 36, 38).

    Signal 2 — X-band numeric density (original §1.4d heuristic):
        Many short text blocks (≤3 chars) clustering into repeating X-bands.
        Covers numeric/code matrices without textual announcement (page 24).

    Returns (bool, reason_str) — reason is "text_announcement" | "x_band_numeric"
    | None.
    """
    # Signal 1 — text announcement
    if page_text and _TABLEAU_ANNONCE.search(page_text):
        return True, "text_announcement"

    # Signal 2 — X-band numeric density
    if not texts:
        return False, None
    short_blocks = [(t, x0, x1) for (t, y, x0, x1) in texts if len(t.strip()) <= 3]
    if len(short_blocks) < 15:
        return False, None
    from collections import defaultdict
    bands = defaultdict(int)
    for _, x0, _ in short_blocks:
        bands[round(x0 / 15) * 15] += 1
    repeated_bands = [b for b, count in bands.items() if count >= 5]
    if len(repeated_bands) >= 3:
        return True, "x_band_numeric"
    return False, None
```

> ⚠️ **Signature modifiée (ENG-043)** : la fonction retourne désormais `(bool, reason)`
> au lieu de `bool`. Mettre à jour tous les appels dans `analyse_pages()` :
> `borderless_table_suspect, borderless_reason = detect_borderless_table(texts, page_width, page_text)`

Store `borderless_table_suspect` and `borderless_reason` in the `analyse_pages()` per-page result
dict, alongside `has_table` and `rotated_header_suspect`.

**Fallback — `pdftotext -layout` reconstruction (same principle as §1.4c):**

When `borderless_table_suspect` is `True`, do not rely on the flattened
`LTTextBox` dump. Use the same `extract_page_via_pdftotext_layout()` helper
already defined in §1.4c to pull the whitespace-aligned grid for that page,
and insert it as a fenced block:

```
[MATRIX TABLE — extracted via pdftotext -layout (no vector borders detected)]
<raw -layout text, monospace-aligned>
[END MATRIX TABLE]
```

> ⚠️ Same rule as §1.4c applies: **do not** auto-convert this monospace block
> into a Markdown pipe table inside the generation script. Column boundaries
> in a borderless table are only reliable via manual/LLM-assisted column
> inference — a downstream pass (human review, or a `chorus-feed` pre-check)
> must confirm row/column mapping before any rule references specific cells.
> Unlike §1.4c (rare, cross-reference matrices only), this failure mode is
> the **majority case** for cleanly-typeset modern standards — expect it on
> most non-legacy PDFs with numeric summary tables (e.g. an EAL/CAP/PPA/STA
> catalogue, a dependency matrix without drawn cell lines).

**Verification method — identical to §1.4c:**

```bash
pdftotext -f <page> -l <page> -layout <source.pdf> - | less
```

If the layout output is clean and aligned, the failure is in the extraction
pipeline (apply the fallback above); if it is also garbled, escalate as a
genuine PDF rendering problem — do not attempt automated reconstruction.

### 1.4e Header cell split mid-word — `quality_check()` blind spot — ✅ mitigated

**⛔ Known failure mode:** even when `has_table` correctly fires and
`pdfplumber` successfully reconstructs a table, the **column-boundary
detection** (`detect_table_columns()`, explicit V-edge clustering at 3pt)
can place a boundary **in the middle of a word** when a header cell spans
multiple logical columns (e.g. "Assurance components by protection profile
assurance package" merged across 2 columns in the source). The result is a
header row where the phrase is split character-run by character-run:
```
| Assurance components by p pack | rotation profile assurance age |
```
A second, related symptom (observed in practice on FIPS 186-5 Table A.1/A.2):
a **trailing prose-pollution row** — `pdfplumber` occasionally captures the
start of the next paragraph (unrelated running text below the table's visual
boundary) as a spurious extra row, mostly empty cells plus one long
multi-word fragment.

**Why `quality_check()` does not catch this:** the four existing filters
(§ "Shared utilities") reject tables based on empty-cell ratio, short
lowercase fragments, or single-column long-text — none of them test for
*"a word straddling a cell boundary"* or *"a trailing row that is actually
unrelated prose"*. Neither symptom pushes the overall empty/fragment ratios
past any threshold, so the table passes quality control despite being
unreliable.

**✅ Mitigation implemented — `detect_and_fix_header_split()`:** (see
`format_table()` in "Shared utilities — Text & Hybrid modes") applied to
every table before it is written to the output `.md`:

- **Trailing prose-pollution row** → removed automatically. A row is
  considered pollution when all but one cell are empty and the remaining
  cell is a long (>60 char), multi-word (>6 words) fragment unrelated to
  the table's own short tabular values — never legitimate data, always a
  mis-captured next-paragraph fragment.
- **Mid-word header split** → **not auto-merged** (risk of inventing a
  wrong reconstruction is higher than the cost of a flagged review) — but
  no longer silently passed through either. A visible banner is prepended
  to the table in the generated `.md`:
  ```
  [TABLE QUALITY WARNING — §1.4e mis-split header cells / prose-pollution check — see chorus-pdf.md Known failure modes]
    - Row 1, cells 2-3 look mid-word split (§1.4e symptom 1): "Max. of len(p" | ") + len(q2) 2" — NOT auto-merged (verify against source before trusting this header).
  [END TABLE QUALITY WARNING]
  ```
  This turns a previously **undetectable** blind spot into an **explicit,
  human-reviewable signal** directly in the output — consistent with the
  `[FIGURE — not extracted]` / `[FORMULA: ...]` placeholder convention
  already used elsewhere in this skill. `chorus-markdown` (if invoked in
  post-processing) can also be extended to scan for this exact banner
  string as an additional fidelity check.

**Practical mitigation — manual correction still required for the header
itself:** this mechanism detects and flags, it does not reconstruct the
correct header wording — that still requires cross-checking against
`pdftotext -layout` (§1.4c method) and manually rewriting the header row.
Always visually scan the **header row(s)** of every table carrying a
`[TABLE QUALITY WARNING]` banner during the manual audit pass (§1.4g)
before trusting it in `chorus-feed`.

### 1.4f Multi-page table continuity — no automatic stitching

**⛔ Known limitation:** neither the vector-detection path (§1.4b) nor the
borderless fallback (§1.4d) currently stitches a table that spans a page
break into a single continuous Markdown table. Each page is processed
independently by `analyse_pages()` / `assemble_page()`, so a table split
across pages N and N+1 produces two separate fragments — sometimes with a
repeated header row on the continuation page, sometimes with none.

**Recommended practice:** when manually auditing a generated `.md` (§1.4c/
§1.4d method), check whether a table's row count on the last page matches
the source's expected total (cross-check against `pdftotext -layout` output
spanning both pages). If a table is split, merge the fragments manually and
insert an explicit marker at the point of continuation:

```
[TABLE CONTINUED — <table title/number> — merged into single table above, see note]
```

This is a manual/human-review step, not an automated one — automatic
stitching would require reliably detecting "same table resumes" across a
page-break event, which is out of scope for the current `analyse_pages()`
per-page architecture.

### 1.4g Practical checklist — auditing a generated `.md` for table integrity

Given that §1.4c, §1.4d and §1.4f are still **manual-verification**
failure modes (no fully automated fix exists for them), apply this
checklist to **every** table-bearing page of a newly generated `.md`, not
only to pages that "look suspicious" at first glance — borderless tables
(§1.4d) in particular produce no visually obvious warning sign in the raw
log output (`chorus-pdf` only reports pages where `has_table` fired,
silently omitting pages with undetected borderless tables). §1.4e is now
**semi-automated** (detection + explicit in-file warning banner — see
below) but still requires a human to confirm/rewrite the flagged header.

1. Search the generated `.md` for every `Table \d+` / `Tableau \d+` heading
   in the corpus's own numbering scheme.
2. For each, confirm the surrounding text renders as a proper `| ... | ... |`
   Markdown table — not a flat sequence of single-line paragraphs (§1.4d
   symptom).
3. Search the generated `.md` for `[TABLE QUALITY WARNING` banners (§1.4e)
   — each one flags a table whose header row is suspected mid-word split.
   Cross-check against `pdftotext -layout` and rewrite the header manually;
   do not trust the flagged header as-is. Tables **without** this banner
   still deserve a quick visual header check (the heuristic is
   conservative, not exhaustive).
4. Check whether the table's last row on a page looks truncated (fewer
   columns filled than expected, or the very next page continues with more
   rows of the same shape) — if so, apply the §1.4f merge/continuation
   marker.
5. For any doubt, cross-check against `pdftotext -f <page> -l <page>
   -layout <source.pdf>` — never trust the flattened extraction over the
   verified source layout.

> **Cost note:** this checklist is manual and does not require any API
> call — `pdftotext` is local/offline. On a large corpus (dozens of tables),
> budget this as an explicit post-extraction review pass before handing the
> `.md` to `chorus-feed`, not as an afterthought.

## Table strategy — confidence thresholds for vision fallback

The blind spots above (§1.4b–§1.4g) are **not duplicated here** — this
section only adds explicit, actionable confidence thresholds for when a
page should automatically trigger the `--hybrid`/`--auto` vision fallback
instead of relying on the text-mode heuristics alone.

**Trigger rule:** when `has_table` (§1.4b) is `False` **and**
`borderless_table_suspect` (§1.4d) is also `False` on a page whose text
contains a heading matching `Table \d+`/`Tableau \d+`, this is a **silent
gap** — none of the current heuristics fired, yet the source explicitly
announces a table. This is exactly the audit [#J] § T3 finding (table-count
log is not a reliable completeness signal): a page can contain a real
table that trips neither the vector-line detector nor the borderless-table
density heuristic (e.g. a very small 2×2 table, or one using an unusual
layout).

| Signal combination on a `Table N`/`Tableau N` page | Confidence table was captured | Recommended action |
|---|---|---|
| `has_table = True` (vector lines found) | High | Keep text-mode `pdfplumber` reconstruction, apply §1.4g checklist |
| `borderless_table_suspect = True` (§1.4d) | Medium | Apply §1.4d `pdftotext -layout` fallback, flag for manual column-mapping review |
| `rotated_header_suspect = True` (§1.4c) | Medium | Apply §1.4c `pdftotext -layout` fallback, do not auto-convert to pipe syntax |
| **Neither signal fires, but a `Table N`/`Tableau N` heading is present** | **Low (silent gap)** | **Re-run this specific page with `--hybrid`/`--auto` as a targeted vision fallback** — do not trust the text-mode output for this page alone |
| No `Table N`/`Tableau N` heading nearby, no signal fires | N/A — no table expected | No action |

**Implementation note:** this is a per-page decision, not a whole-document
one — re-running the entire PDF in `--hybrid` mode to recover a handful of
missed pages is wasteful. When the "silent gap" row applies, the practical
workaround today (no automated single-page re-dispatch exists yet in the
generated script) is to note the page number during the §1.4g audit pass
and manually invoke `chorus-pdf <sandbox> <file.pdf> --hybrid` once, then
splice the recovered page(s) into the text-mode output — or, if the
document is small enough, accept the cost of a full `--hybrid` re-run.
Automating per-page re-dispatch is a natural follow-up but is not
implemented in the current script templates (Phase 2).

## Formula strategy

Motivated directly by audit `[#J]` findings F1/F2/F3 (see
`todo-history/TODO.org` § `[#J]` and `chorus-markdown.md` § "Known failure
patterns"): unlike figures, mathematical formulas were never flagged in
text mode prior to this section — they silently blend into the prose flow,
with no equivalent of `[FIGURE — not extracted]` to signal a risk zone.

**Detection patterns** (implemented in `detect_and_tag_formulas()`, see
"Shared utilities — Text & Hybrid modes", and invoked in the Text-mode
script template just before the output file is written):

| Pattern | Example | Audit finding |
|---|---|---|
| Unicode math symbols | `≥ ≤ ⊕ √ ∑ ∏ ² ³ ℓ λ σ ± × ÷ ≈` | F2 (symbols preserved but formula context lost) |
| Functional notation | `XH(M, ℓ)`, `f(x, y)` | F2 — formula split mid-block by `pdfminer` layout grouping |
| Ambiguous flattened exponent | `2128` (= `2^128`), `2h/2` (= `2^(h/2)`) — only flagged near keywords `bits`/`calculs`/`opérations`/`complexité`/`collision` | F1 — visually indistinguishable from a plain integer |

**Transcription:** best-effort only, and only for the single unambiguous
case of a Unicode superscript digit directly following an identifier
(`A²` → `A^2`). Every other detected pattern receives a bare
`[FORMULA: pattern detected (<reason>) — verify against source]`
placeholder immediately after the flagged line — never an invented LaTeX
transcription for a pattern that cannot be resolved reliably (false
transcription is worse than no transcription for a normative/security
threshold).

**Placeholder convention** — mirrors `[FIGURE — not extracted]`:

```
2128 opérations.
[FORMULA: pattern detected (ambiguous exponent) — verify against source]
```

**Why this is best-effort, not exhaustive:** the regex context keywords
(§ table above) are deliberately narrow to limit false positives on years
or identifiers (e.g. a document revision "2024" must not be tagged) — per
audit [#J], a purely syntactic check ("does this look like `2` + digits?")
is not enough; a contextual keyword check is required to "aim right
without too many false positives". Expect occasional misses on formulas
phrased without any of the listed keywords nearby — this is a detection
aid for a human/`chorus-markdown` review pass, not a guarantee of complete
recall.

**Relationship to `chorus-markdown`:** `chorus-markdown` §2.5 checks for
the **presence** of `[FORMULA: ...]` placeholders in the output (previously
only `ℹ️`-level/informational because `chorus-pdf` never emitted this
placeholder — see `chorus-markdown.md` § "Known failure patterns"). With
this section shipped, that control can be escalated from informational to
a real `⚠️`/`❌` severity in a future `chorus-markdown` revision, since the
placeholder now actually exists to be checked.


> **Phase 1.5** (nohup gate, hybrid only) → see `chorus-pdf-hybrid.md`

## Phase 2 — Generate the extraction script

Create `$SANDBOX/agent/` if it does not exist.
writes `$SANDBOX/agent/extract-pdf-<slug>.py`, then executes it

> ⚠️ **Mandatory post-generation step:** once the script completes and the
> `.md` file is written, run the §1.4g audit checklist on **every** page
> containing a `Table`/`Tableau` heading in the corpus's own numbering —
> not only pages flagged suspicious by eye. The extraction log's reported
> table count (`has_table` hits) is **not** a reliable completeness signal:
> borderless tables (§1.4d) produce zero log signal while still being
> silently flattened. Treat this checklist as part of the extraction task
> itself, not an optional follow-up.

### Phase 2b — `CHORUS:no_auto_rules` auto-annotation (mandatory post-generation step)

After the `.md` file is written and the §1.4g checklist is complete, scan
the generated `.md` for section headings that match known **doctrinal patterns**
and insert a `<!-- CHORUS:no_auto_rules — <reason> -->` marker immediately after
each matching heading.

This marker is read by `chorus-corpus-scoping` Phase 2 Step 1 to bypass keyword
scoring and immediately classify the section as `OUT-OF-SCOPE` or `CONTEXT-ONLY`,
without any operator domain knowledge required.

#### Doctrinal patterns to auto-detect (case-insensitive, partial match)

| Pattern in heading | Inserted marker reason |
|---|---|
| `foreword`, `avant-propos` | `informative foreword — no codifiable requirement` |
| `introduction` (if first section before any normative §) | `introductory section — context only` |
| `scope`, `domaine d'application` | `scope definition — context only, no rule generated` |
| `normative references`, `références normatives` | `external reference list — no rule generated` |
| `terms and definitions`, `termes et définitions` | `definitions — fed to thesaurus, no rule generated` |
| `symbols`, `abbreviated terms`, `abréviations` | `terminology — fed to thesaurus, no rule generated` |
| `bibliography`, `bibliographie` | `informative bibliography — no codifiable requirement` |
| `annex` / `annexe` followed by `(informative)` | `informative annex — no codifiable requirement` |
| `index` (standalone last section) | `document index — no codifiable requirement` |

> ⚠️ **Do NOT auto-annotate** sections whose heading contains `(normative)` or
> whose heading matches a domain-specific identifier pattern (e.g. `ADV_`, `ATE_`,
> `§3.`, article numbers) — even if they also contain introductory prose.
> These sections must go through the normal keyword scoring in Phase 2.

#### Auto-annotation implementation (added to the extraction script)

After the main `parts` list is assembled and written, perform a second pass
on the output file:

```python
import re

DOCTRINAL_PATTERNS = [
    (r'(?i)^#+\s*(foreword|avant.propos)', 'informative foreword — no codifiable requirement'),
    (r'(?i)^#+\s*(introduction)\b(?!.*normative)', 'introductory section — context only'),
    (r'(?i)^#+\s*(scope|domaine d.application)\b', 'scope definition — context only, no rule generated'),
    (r'(?i)^#+\s*(normative references|références normatives)', 'external reference list — no rule generated'),
    (r'(?i)^#+\s*(terms and definitions|termes et définitions)', 'definitions — fed to thesaurus, no rule generated'),
    (r'(?i)^#+\s*(symbols|abbreviat|abréviat)', 'terminology — fed to thesaurus, no rule generated'),
    (r'(?i)^#+\s*(bibliography|bibliographie)', 'informative bibliography — no codifiable requirement'),
    (r'(?i)^#+\s*annex[e]?\b.*\(informative\)', 'informative annex — no codifiable requirement'),
    (r'(?i)^#+\s*index\s*$', 'document index — no codifiable requirement'),
]

with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
result = []
i = 0
annotated = 0
while i < len(lines):
    line = lines[i]
    matched = False
    for pattern, reason in DOCTRINAL_PATTERNS:
        if re.match(pattern, line):
            result.append(line)
            result.append(f'<!-- CHORUS:no_auto_rules — {reason} -->')
            annotated += 1
            matched = True
            break
    if not matched:
        result.append(line)
    i += 1

with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
    f.write('\n'.join(result))

if annotated:
    print(f"[chorus-pdf] Phase 2b — {annotated} section(s) auto-annotated CHORUS:no_auto_rules",
          file=sys.stderr)
```

Print summary: `[chorus-pdf] Phase 2b — N section(s) auto-annotated as no_auto_rules`
If N = 0: `[chorus-pdf] Phase 2b — no doctrinal sections detected (manual annotation may be needed)`

### Phase 2 — Mode dispatch

> **Load `call_claude_with_retry()` (below) first, then the mode sub-skill:**

def call_claude_with_retry(payload, headers, label, timeout=300):
    """Execute a Claude API call with exponential backoff (MAX_RETRIES attempts).
    Returns the text content of Claude's first response block.
    Raises RuntimeError on non-retryable errors.

    Retryable conditions:
      - HTTP 429 / 529 (rate-limit / overload)
      - urllib.error.URLError (network-level: timeout, connection reset, DNS)
    Non-retryable: all other HTTP errors (4xx/5xx except 429/529).
    """
    for attempt in range(MAX_RETRIES):
        req = urllib.request.Request(
            API_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))["content"][0]["text"]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if e.code in (429, 529) and attempt < MAX_RETRIES - 1:
                wait = 10 * (2 ** attempt)
                print(f"  HTTP {e.code} — retrying in {wait}s ...", file=sys.stderr)
                time.sleep(wait)
            else:
                raise RuntimeError(f"HTTP {e.code} on {label}: {body[:500]}")
        except urllib.error.URLError as e:
            # Network-level error (timeout, connection reset, DNS failure…)
            # Always retryable — transient infrastructure issue.
            if attempt < MAX_RETRIES - 1:
                wait = 10 * (2 ** attempt)
                print(f"  URLError ({e.reason}) on {label} — retrying in {wait}s ...",
                      file=sys.stderr)
                time.sleep(wait)
            else:
                raise RuntimeError(f"URLError on {label} after {MAX_RETRIES} attempts: {e.reason}")
```


### Phase 2 — Mode-specific sub-skills

After loading `call_claude_with_retry` above, load the mode sub-skill(s):

**Text mode (default):**
```
eca__read_file("$ENGINE/agent/skills/chorus-pdf-_shared-text-hybrid.md")
eca__read_file("$ENGINE/agent/skills/chorus-pdf-text.md")
```

**Hybrid mode (`--hybrid`):**
```
eca__read_file("$ENGINE/agent/skills/chorus-pdf-_shared-text-hybrid.md")
eca__read_file("$ENGINE/agent/skills/chorus-pdf-hybrid.md")
```
> Phase 1.5 (nohup gate) is in `chorus-pdf-hybrid.md` — execute it before the script template.

**Auto mode (`--auto`):**
```
eca__read_file("$ENGINE/agent/skills/chorus-pdf-_shared-auto-images.md")
eca__read_file("$ENGINE/agent/skills/chorus-pdf-auto.md")
```

**Images mode (`--images`):**
```
eca__read_file("$ENGINE/agent/skills/chorus-pdf-_shared-auto-images.md")
eca__read_file("$ENGINE/agent/skills/chorus-pdf-images.md")
```

> After mode sub-skill loaded → proceed to Phase 3 (Execute and validate).

## Phase 3 — Execute and validate

### 3.1 Execute the script

```bash
claude-python "$SANDBOX/agent/extract-pdf-<slug>.py"
```

> `claude-python` est le wrapper qui injecte `ANTHROPIC_API_KEY` **uniquement** pour les
> scripts de conversion (`extract-pdf-*`), que l'on soit sur l'hôte ou dans le container
> Docker (`/usr/local/bin/claude-python`). Sans lui, `probe_claude()` retourne `False` et
> le mode text est sélectionné même si la clé est disponible.

Capture stderr for progress reporting. Exit code 0 = success.

### 3.2 Validate the output

```bash
python3 - "$SANDBOX/corpus/<NNN>-<slug>-vision.md" <<'EOF'
import sys, re

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
pages        = re.findall(r'=== PAGE \d+ ===', text)
figures      = re.findall(r'\[FIGURE', text)
tables       = re.findall(r'^\|', text, re.MULTILINE)
placeholders = text.count('not extracted')
xref_local   = re.findall(r'\[XREF FIGURE', text)
xref_index   = 1 if '=== XREF INDEX ===' in text else 0

print(f"Pages found      : {len(pages)}")
print(f"Figures found    : {len(figures)}")
print(f"XREF annotations : {len(xref_local)}  (inline, hybrid mode)")
print(f"XREF INDEX       : {'present' if xref_index else 'absent'}")
print(f"Table rows       : {len(tables)}")
print(f"Placeholders     : {placeholders}")
print(f"Total chars      : {len(text)}")
if len(pages) == 0:
    print("⚠️  WARNING: no === PAGE === markers — output may be malformed")
if len(text) < 500:
    print("⚠️  WARNING: output is suspiciously short")
if placeholders > 0:
    print(f"ℹ️  {placeholders} figure(s) not extracted — run with --auto to extract them")
if len(figures) > 0 and len(xref_local) == 0:
    print("ℹ️  Figures found but no XREF annotations — check IDENTIFIERS: lines in figure descriptions")
EOF
```

Report the sanity check results to the user before proceeding.

### 3.3 Failure handling

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| `pdfminer.six` ImportError | Missing dependency | `pip install pdfminer.six` |
| `pypdf` ImportError | Missing dependency | `pip install pypdf` |
| `Pillow` ImportError | Missing dependency (`--hybrid`) | `pip install Pillow` |
| `pdftoppm` not found | `poppler-utils` absent | `sudo apt install poppler-utils` |
| `ANTHROPIC_API_KEY not set` | Missing env var | `export ANTHROPIC_API_KEY="sk-ant-..."` |
| HTTP 400 | PDF chunk too large | Reduce `CHUNK_SIZE` to 3 |
| HTTP 429 / 529 | API rate limit / overload | Retry handled automatically (exponential backoff) |
| No PNG files rendered | Password-protected PDF | Decrypt first: `qpdf --decrypt in.pdf out.pdf` |
| Output < 500 chars | Extraction returned nothing | Check API key validity; verify PDF is not encrypted |
| Figures described but values wrong | Dense diagram | Increase `DPI = 200` in script header; keep `CHUNK_SIZE = 3` |
| Text mode: garbled multi-column | pdfminer layout | Normal on very complex layouts — use `--auto` instead |
| Auto mode: page miscategorised | `pypdf` image detection | Force individual pages to vision by adjusting text threshold in `classify_pages` |
| Auto mode: `chorus-markdown` §2.2 ❌ "malformed table" — separator-first | Claude vision generates table without header row (`\|---\|` as first line, col count ≠ data rows) | Run `pdftotext -layout -f <page> -l <page> <pdf>` to get real column count; regenerate separator with that count. See § "Auto mode — separator-first table fix" below. |

### Auto mode — separator-first table fix

**⛔ Known blind spot — `--auto` mode only:** Claude vision occasionally generates
Markdown tables **without a header row**, starting directly with a separator line
(`| --- | --- | ... |`) whose column count does not match the data rows below it.

**Symptom in `chorus-markdown` §2.2:** `❌ N malformed table(s)` where the detection
uses `block[0]` as reference — if `block[0]` is a separator with M cols and data rows
have N≠M cols, the table is flagged.

**Why it happens:** Claude infers table structure visually from the PDF page image.
When the header row is visually merged, rotated, or ambiguous, Claude may omit it and
start directly with a separator, then produce data rows with the correct (larger) column
count.

**Fix procedure:**
1. Identify the affected page(s) from the `chorus-markdown` report.
2. Run `pdftotext -layout -f <page> -l <page> <pdf> -` → count columns in the source.
3. The data rows' column count is the correct target (they reflect what Claude extracted).
4. Regenerate the separator with the target count:
   ```python
   target = Counter(r.count('|') - 1 for r in data_rows).most_common(1)[0][0]
   new_sep = '| ' + ' | '.join(['---'] * target) + ' |'
   ```
5. Re-run `chorus-markdown` to confirm ✅.

> ⚠️ **This defect is specific to `--auto` mode** — in `--hybrid` mode, tables are
> reconstructed by pdfplumber from vector lines, which always produces a proper
> header + separator structure. If separator-first tables are frequent in a document,
> consider switching to `--hybrid`.

## Cross-tool comparison — standard triage procedure for suspect pages

> This procedure was applied ad hoc during audit `[#J]` to resolve a disputed
> extraction result; it is now documented here as a **standard method**, not a
> one-off gesture, and should be invoked systematically whenever a page is
> flagged suspect — not only during a formal audit.

**When to invoke it:**

- Any page `chorus-markdown` reports as `⚠️` or `❌` (§2.2 table-count
  mismatch, §2.3 borderless flattening, §2.4 rotated-header pattern, §2.6
  length-ratio outlier, §2.7 encoding residue) — before concluding the defect
  is in the source PDF itself.
- Any page where a human reviewer manually doubts the fidelity of the
  `chorus-pdf` text-mode output (garbled columns, missing table, suspicious
  formula rendering), even outside a formal `chorus-markdown` run.

**Exact command:**

```bash
pdftotext -layout -f <page> -l <page> <pdf> -
```

- `-layout` preserves the visual column/row structure as best `poppler-utils`
  can infer it from the PDF's glyph positions — a **completely independent**
  layout engine from `pdfminer`/`pdfplumber` (different codebase, different
  heuristics, no shared library).
- `-f <page> -l <page>` restricts extraction to the single suspect page
  (1-indexed, matches the page numbering already used in `chorus-markdown`
  reports and in this skill's own page-by-page logs).
- `-` sends output to stdout for immediate inspection (pipe to `less`, or
  redirect to a scratch file for diffing against the corresponding section of
  `<output.md>`).
- Fully offline, no API call, no network dependency — safe to run at any time,
  including when `ANTHROPIC_API_KEY` is absent.

**How to interpret the result:**

- **If `pdftotext -layout` renders a coherent, readable structure** (e.g. a
  table with aligned columns, a formula with its exponent correctly
  positioned) **that `pdfminer`/`pdfplumber` failed to reconstruct** — this is
  a **strong signal that the defect originates in the layout-analysis
  heuristic** (`pdfminer`'s block segmentation, `pdfplumber`'s vector-line
  detection, or `chorus-markdown`'s own suspicious-zone heuristics), **not in
  the PDF's actual content or encoding**. In this case: do not treat the
  source PDF as corrupt; instead, consider it a known blind spot of the
  current extraction pipeline (cf. findings T1/T2 below) and document it as
  such rather than re-attempting extraction with the same tool.
- **If `pdftotext -layout` is equally garbled or produces the same gap**
  (e.g. the same borderless table collapses into unseparated characters in
  both outputs) — this points instead to a genuine property of the source
  PDF (e.g. no embedded structure to recover, a scanned/rasterised page, or a
  font encoding issue) that no text-layer tool can resolve; vision-mode
  (`--hybrid`/`--auto`/`--images`) extraction should be considered instead of
  further text-mode tuning.
- **Reference precedent — audit `[#J]` findings T1/T2:** both the
  borderless-table flattening (T1) and the rotated-header collapse (T2)
  blind spots documented in this skill (§1.4c/§1.4d) were confirmed using
  exactly this procedure — `pdftotext -layout` on the suspect page recovered
  a legible (if imperfect) table structure that `pdfminer`'s line-by-line
  text blocks had silently flattened, confirming the defect was in
  `pdfminer`'s layout heuristic rather than in the PDF's own content. This is
  the canonical worked example to follow when applying the procedure to a
  new suspect page.

> See also `chorus-markdown.md` §2.3/§2.4, which references this procedure
> directly as the recommended triage step for any `⚠️`/`❌` row it reports.

## Phase 3.5 — ⛔ Vérification de fidélité (`chorus-markdown`) — OBLIGATOIRE

> ⛔ **Cette phase est NON OPTIONNELLE et s'applique sans exception :**
> invocation directe par l'utilisateur, lancement depuis la webapp, skill
> appelant (`chorus-import-project` auto-conversion, etc.) — **peu importe
> le contexte, `chorus-markdown` DOIT être lancé immédiatement après la fin
> du script d'extraction, avant de passer à Phase 4.**
>
> Ne jamais retourner le contrôle à l'utilisateur sans avoir exécuté cette étape.
>
> **Pourquoi :** les défauts d'extraction (tableaux aplatis, tableaux manquants,
> artefacts d'encodage) ne sont PAS visibles dans les logs du script de Phase 3 —
> ils ne se manifestent que sur le `.md` produit, comparé à la source.
> `chorus-markdown` est le seul filet de sécurité indépendant entre l'extraction
> et `chorus-feed` / `chorus-import-project`. Son omission invalide la chaîne de
> contrôle qualité.

Immédiatement après la fin du script d'extraction, lancer :

```
chorus-markdown <sandbox> <source.pdf> <output.md> --report
```

Exemples selon contexte :
```bash
# Sortie standard (corpus/)
chorus-markdown 01-PMR corpus/003-doc.pdf corpus/003-doc-vision.md --report

# Sortie dans workspace/ (--output-dir ou appel import)
chorus-markdown 01-PMR workspace/Leclerc/sources/PC39.pdf workspace/Leclerc/PC39-vision.md --report
```

**Règles d'application :**

- `--report` est **toujours inclus** — il produit
  `workspace/reports/markdown-check-<slug>.md` avec le détail des anomalies.
- La vérification est **non-bloquante par défaut** (exit 0 même avec `❌`) —
  elle ne stoppe pas le flux sauf si `--strict` est explicitement ajouté.
- En mode `--batch` : lancer `chorus-markdown` sur **chaque** fichier produit
  dans la boucle, pas seulement sur le dernier.
- En mode `--output-dir` (invoqué par `chorus-import-project`) : le rapport
  est écrit dans `<output-dir>/../reports/` si `workspace/reports/` n'existe
  pas encore — `chorus-markdown` crée le dossier automatiquement.

**Seuil de ratio mots spécifique au mode — trois cas :**

| Mode | Seuil normal | Explication |
|---|---|---|
| `--hybrid` | ≤ **1.80** | pdfminer texte + descriptions Claude vision séparées par figure → mots ajoutés |
| `--auto` pages mixtes | ≤ **1.80** | même logique : pages vision apportent des descriptions supplémentaires |
| `--auto` all-pages vision | ≤ **1.50** | Claude reconstruit le texte depuis les images — pas de descriptions de figures *en plus* du texte, ratio proche de 1.0 ; léger surplus lié à la reformulation Claude |

Si le ratio dépasse 1.30 mais reste dans la plage normale du mode utilisé, signaler explicitement à l'utilisateur :
> `ℹ️  Ratio mots 1.62 — normal en mode hybrid/auto (descriptions vision Claude incluses)`
> `ℹ️  Ratio mots 1.34 — normal en mode auto all-pages (Claude reconstruit le texte depuis les images)`
Ne pas traiter ces cas comme un ❌.

**Le résultat de `chorus-markdown` est intégré au rapport final Phase 4.2.**

## Phase 4 — Update sandbox metadata

### 4.1 Update `README.org`

> ⛔ **`[skip-readme-update]` guard:** if this skill was invoked automatically by
> `chorus-import-project`'s auto-conversion mechanism (see `chorus-import-project.md`
> § Auto-conversion algorithm), **skip this entire step** — do not touch `README.org`
> at all. The caller records the converted file itself, under its own
> `* Imported project documents (not corpus — chorus-import-project artefacts)`
> section, never under `* Corpus`. A converted project document is never normative
> corpus, even though it lands in the same `corpus/` output directory.
> (Precedent: a converted project document was wrongly listed in `* Corpus`
> after an auto-invoked `chorus-word` call ran this step unconditionally.)
>
> Proceed with the row-add below **only** when invoked directly by the user
> (or by any other caller that does not pass `[skip-readme-update]`) to feed
> normative corpus material.

Add a row for the new file in the `Corpus` table:

```org
| <NNN> | corpus/<NNN>-<slug>-text.md    | pdfminer from <source-pdf>                    | <date> |
| <NNN> | corpus/<NNN>-<slug>-vision.md  | hybrid(pdfminer+cropped vision) from <source> | <date> |
| <NNN> | corpus/<NNN>-<slug>-vision.md  | auto(pdfminer+vision) from <source>           | <date> |
| <NNN> | corpus/<NNN>-<slug>-vision.md  | vision(LLM) from <source-pdf>                 | <date> |
```

(use the row matching the mode used)

Do **not** remove the row for the original PDF or any prior file — all versions are
kept for traceability.

### 4.2 Report to the user

```
✅ chorus-pdf completed
   Mode     : text  (or: auto — 38 text / 16 vision  |  images — 150 DPI)
   Source   : corpus/<source.pdf>  (<N> pages)
   Output   : corpus/<NNN>-<slug>-text.md    (or: -vision.md)
   Pages    : <N>
   Figures  : <N> blocks extracted  (or: <N> placeholders — use --hybrid or --auto to extract)
   XREF     : <N> identifier(s) cross-referenced across <N> figure(s)  [hybrid only]
   Table rows: <N>
   Size     : <N> chars

   chorus-markdown : ✅ toutes les vérifications passent
                  (ou) ⚠️  N avertissement(s) — voir workspace/reports/markdown-check-<slug>.md
                  (ou) ❌  N contrôle(s) échoué(s) — voir workspace/reports/markdown-check-<slug>.md

   Next step: chorus-feed <sandbox-name> corpus/<NNN>-<slug>-text.md
              (or: corpus/<NNN>-<slug>-vision.md)
```

## Integration with chorus-feed

`chorus-pdf` is a **pre-processing step**, not a replacement for `chorus-feed`.
Typical workflow:

```
# No flag — hybrid activated automatically if API key present (DEFAULT)
chorus-pdf  <sandbox> corpus/002-uk-approved-doc-a-2013.pdf
→ corpus/003-uk-approved-doc-a-2013-vision.md   (hybrid mode)

# No API key — text mode fallback
chorus-pdf  <sandbox> corpus/002-uk-approved-doc-a-2013.pdf
→ corpus/003-uk-approved-doc-a-2013-text.md

# API key available — text-dominant document, faster
chorus-pdf  <sandbox> corpus/002-uk-approved-doc-a-2013.pdf --auto
→ corpus/003-uk-approved-doc-a-2013-vision.md

# Mostly diagrams or scanned PDF
chorus-pdf  <sandbox> corpus/002-uk-approved-doc-a-2013.pdf --images
→ corpus/003-uk-approved-doc-a-2013-vision.md

# Then in all cases:
chorus-feed <sandbox> corpus/003-uk-approved-doc-a-2013-text.md
            (or: corpus/003-uk-approved-doc-a-2013-vision.md)
```

If a `.txt` from `pdftotext` already exists alongside the PDF, prefer the `-text.md`
(text mode) or `-vision.md` (hybrid/auto/images) for `chorus-feed`.
The `pdftotext` output can be kept for diff/audit purposes.

### Post-processing — fidelity check (`chorus-markdown`)

> ⛔ **Cette section a été remplacée par Phase 3.5 — OBLIGATOIRE.**
> `chorus-markdown` n'est plus une étape optionnelle de "post-processing" :
> elle fait partie du flux principal et doit être exécutée **avant** Phase 4,
> immédiatement après la fin du script d'extraction.
>
> → Voir **§ Phase 3.5** pour les instructions complètes, les règles batch,
>   et la note sur le seuil de ratio mots pour le mode hybrid (≤ 1.80 attendu).

## Quick Reference — Naming Conventions

| Artifact | Convention | Example |
|----------|-----------|---------|
| Extraction script | `agent/extract-pdf-<slug>.py` | `agent/extract-pdf-uk-approved-doc-a.py` |
| Text mode output | `corpus/<NNN>-<slug>-text.md` | `corpus/003-uk-approved-doc-a-2013-text.md` |
| Auto/Hybrid/Images output | `corpus/<NNN>-<slug>-vision.md` | `corpus/003-uk-approved-doc-a-2013-vision.md` |
| Original PDF | kept as-is in `corpus/` | `corpus/002-uk-approved-doc-a-2013.pdf` |

## Troubleshooting

**"The output in text mode is identical to what pdftotext produced"**
→ Both tools read the same embedded text layer. The gain from pdfminer is the layout
  ordering (multi-column), not the character content. For richer extraction, use `--auto`.

**"Text mode output has garbled column order"**
→ `pdfminer` uses `boxes_flow=0.5` which handles most two-column layouts. For unusual
  layouts (three columns, overlapping regions), `--auto` or `--images` will be more
  reliable since Claude reconstructs column order visually.

**"Figures are described but values seem invented"**
→ LLMs can hallucinate values in dense technical diagrams. Always cross-check critical
  normative values against the original PDF. Mark uncertain values with
  `# TODO: verify against PDF §<N>` in `Helpers.pm`.

**"Auto mode: a text page was sent to vision unnecessarily"**
→ The threshold `len(text.strip()) > 50` in `classify_pages` may be too low for sparse
  pages (cover pages, blank pages, page numbers only). Increase to `> 200` if needed.

**"Chunk boundaries cut through a table"**
→ The fragment is prefixed `[TABLE CONTINUED — ...]`. `chorus-feed` treats both
  fragments as separate text blocks — rarely an issue for KB extraction.

**"Too slow — 54-page PDF with --auto takes a long time"**
→ Only the vision pages hit the API. If 16/54 pages have figures: 4 chunks × ~30s = ~2 min.
  The text pages (pdfminer) complete in seconds. Total: ~2–3 minutes for a 54-page standard.

**"Script exited with code 2 — nohup required"**
→ The layout analysis detected ≥ 16 figures. The script aborted before any API call.
  Copy the `nohup` command printed to stderr and run it in a terminal:
  ```bash
  CHORUS_PDF_FORCE=1 nohup claude-python $SANDBOX/agent/extract-pdf-<slug>.py > $SANDBOX/corpus/<NNN>-<slug>-vision.md.log 2>&1 &
  tail -f $SANDBOX/corpus/<NNN>-<slug>-vision.md.log
  ```
  The threshold `NOHUP_THRESHOLD = 15` can be raised in the script header if your
  API responses are consistently faster (< 20s/call on average).

**"I want higher quality on specific diagram pages"**
→ Increase `DPI = 200` in the script header. Keep `CHUNK_SIZE = 3` at 200 DPI
  (PNG ≈ 900 KB/page → 3 pages ≈ 2.7 MB payload).
