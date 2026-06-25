# Skill — chorus-pdf

> Trigger: `chorus-pdf <sandbox-name> <file.pdf> [--out <slug>] [--auto] [--images] [--batch]`
> Agent: `architect`
>
> `<sandbox-name>`: name of the sandbox directory under `$CHORUS/sandboxes/`
> `<file.pdf>`: path to the PDF — absolute, or relative to `$SANDBOX/corpus/`
> `--out <slug>`: override the output filename stem (default: derived from input filename)
> `--auto`: smart mode — pdfminer on text-only pages, vision LLM on pages with figures
> `--images`: full vision mode — all pages processed by vision LLM via `pdftoppm` + Anthropic
> `--batch`: process all `*.pdf` files found in `$SANDBOX/corpus/`
>
> **Single responsibility: produce an enriched text file from a PDF.**
> Extracts text, tables, figures, diagrams, and technical annotations that `pdftotext`
> and similar tools silently discard.
>
> Output format depends on mode:
> - Text mode (default): `corpus/<NNN>-<slug>-text.txt` — plain text, pdfminer only
> - Auto / Images mode: `corpus/<NNN>-<slug>-vision.md` — Markdown with tables and figure blocks
>
> This skill must be run **before** `chorus-feed` when the corpus contains PDFs.
> `chorus-feed` then takes the output file as its corpus input.

---

## ⛔ Strict sandbox isolation

Never read any KB, YAML, or artifact from a sandbox other than `<sandbox-name>`.
This skill operates exclusively on the `corpus/` directory of the target sandbox.

---

## Overview

Standard PDF-to-text tools (`pdftotext`, `pdf2txt.py`) extract only typographic text.
They silently drop structural diagrams, normative tables rendered as images, multi-column
layouts, and figure annotations. This skill provides three extraction modes of increasing
capability:

### Three extraction modes

| Mode | Flag | Engine | API key | Figures | Output |
|------|------|--------|---------|---------|--------|
| **Text** (default) | *(none)* | `pdfminer.six` | ❌ not required | `[FIGURE — not extracted]` placeholder | `<slug>-text.txt` |
| **Auto** | `--auto` | `pdfminer` on text pages + vision LLM on figure pages | ✅ `ANTHROPIC_API_KEY` | ✅ described (targeted) | `<slug>-vision.md` |
| **Images** | `--images` | `pdftoppm` 150 DPI + vision LLM on all pages | ✅ `ANTHROPIC_API_KEY` | ✅ described (exhaustive) | `<slug>-vision.md` |

**Choosing a mode:**

```
No API key available, quick extraction needed
  → (default text mode)

API key available, mixed document (mostly text + some diagrams)
  → --auto   ← recommended for most technical standards

API key available, document is mostly diagrams or scanned
  → --images
```

> **`--auto` is the recommended mode** for building/structural standards
> (Approved Document A, DTU, EC5, NF EN…) when an API key is available.
> It combines pdfminer precision on text with vision accuracy on figures,
> and minimises API calls to pages that actually need them.

---

## Phase 0 — Resolve inputs

### 0.1 Resolve the sandbox path

```
SANDBOX = $CHORUS/sandboxes/<sandbox-name>
```

Verify that `$SANDBOX/corpus/` exists. If not, abort with:
```
⛔ Sandbox '<sandbox-name>' does not exist or has no corpus/ directory.
   Create corpus/ manually or run chorus-feed first to initialize the sandbox.
```

### 0.2 Resolve the PDF path

If `<file.pdf>` is a bare filename → prepend `$SANDBOX/corpus/`.
If it is an absolute path → use as-is.
Verify the file exists and ends in `.pdf` (case-insensitive).

In `--batch` mode: glob `$SANDBOX/corpus/*.pdf` (and `*.PDF`). Process each in turn.
If no PDF found → warn and exit cleanly (not an error).

### 0.3 Resolve the output filename

Determine the next available corpus number:

```
existing = glob("$SANDBOX/corpus/[0-9][0-9][0-9]-*.*")
last_num = max of the leading 3-digit prefix across existing files (default 0)
next_num = last_num + 1   (formatted as %03d)
```

> ⚠️ In `--batch` mode, increment `next_num` for each PDF processed in sequence.

Derive the slug and extension based on mode:

| Mode | Suffix | Extension | Rationale |
|------|--------|-----------|-----------|
| Text (default) | `-text` | `.txt` | Plain text only — no Markdown syntax produced |
| Auto (`--auto`) | `-vision` | `.md` | Contains Markdown tables and `[FIGURE]` blocks |
| Images (`--images`) | `-vision` | `.md` | Contains Markdown tables and `[FIGURE]` blocks |

- If `--out <slug>` provided → use that slug as-is (suffix already included)
- Otherwise → strip leading `NNN-` prefix and `.pdf` extension from the input filename,
  then append the mode suffix

Output filename: `$SANDBOX/corpus/<next_num>-<slug>.<ext>`

Example:
```
Input  : corpus/002-uk-approved-doc-a-2013.pdf

Default : corpus/003-uk-approved-doc-a-2013-text.txt
--auto  : corpus/003-uk-approved-doc-a-2013-vision.md
--images: corpus/003-uk-approved-doc-a-2013-vision.md
```

---

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
using `pypdf` to inspect the page content:

```python
import pypdf
reader = pypdf.PdfReader(pdf_path)
for i, page in enumerate(reader.pages, 1):
    text      = page.extract_text() or ""
    has_image = len(page.images) > 0
    has_text  = len(text.strip()) > 50   # threshold: ignore near-empty pages

    if has_image or not has_text:
        category = 'vision'   # → pdftoppm + Claude
    else:
        category = 'text'     # → pdfminer
```

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
| Images (`--images`) | 5 pages per call | all pages, one PNG each (~500 KB) |

---

## Phase 2 — Generate the extraction script

ECA writes `$SANDBOX/eca/extract-pdf-<slug>.py` via `eca__write_file`, then executes it.
Create `$SANDBOX/eca/` if it does not exist.

### Vision extraction prompt (used verbatim in `--auto` and `--images` scripts)

```
You are a technical document extraction engine.
Your task is to produce a complete, faithful plain-text reconstruction of this PDF page.

Apply the following rules strictly:

TEXT
- Extract all text in reading order (top to bottom, left to right).
- For multi-column layouts: extract column 1 fully, then column 2. Insert a blank line between columns.
- Preserve section numbers, article numbers, and clause references exactly as printed.
- Preserve all footnote markers and footnote text (append footnotes at end of page output).
- Do not summarize, paraphrase, or omit any text.

TABLES
- Reconstruct every table in Markdown format (pipe syntax).
- Preserve all column headers, row labels, units, and footnote references inside the table.
- If a table spans multiple pages: output the fragment visible on this page; prefix it with
  [TABLE CONTINUED — <table title or number>] if this is a continuation.

FIGURES AND DIAGRAMS
- For every figure, diagram, or illustration: output a block of the form:
    [FIGURE <N> — <title or caption>]
    <Structured description of all visual content:>
    - Labeled dimensions, dimensions with units
    - Named components and their spatial relationships
    - Numerical values visible in or next to the figure
    - Arrows, load paths, connection points, hinge symbols, support symbols
    - Hatching patterns and what material or condition they represent
    - Scale bar if present
    [END FIGURE <N>]
- If there is no figure number or caption in the PDF, assign [FIGURE ?] and describe anyway.

EQUATIONS AND FORMULAS
- Render every equation in linearized form (e.g., σ = F / A).
- Preserve all variable names, subscripts, and units as printed.

HEADERS AND FOOTERS
- If a page has a running header or footer containing normative information (standard number,
  edition date, section title): include it once at the top of the page output as:
    [HEADER: <content>]
- Omit purely decorative headers/footers (page number alone, logo only).

OUTPUT FORMAT
- Begin each page with: === PAGE <N> ===
- End each page with: === END PAGE <N> ===
- Separate pages with a single blank line.
- Use UTF-8. Preserve all special characters (±, ≤, ≥, ×, °, ², ³, φ, σ, …).
- Do not add commentary outside the === PAGE === markers.
```

---

### Script template — Text mode (default, no flag)

Uses `pdfminer.six` only. No API key, no network. Figures produce a placeholder.
Output: `<NNN>-<slug>-text.txt`

```python
#!/usr/bin/env python3
"""
chorus-pdf extraction script — text mode (default)
Generated by ECA chorus-pdf skill
Sandbox : <sandbox-name>
Source  : <input-pdf-path>
Output  : <output-txt-path>   (e.g. corpus/003-uk-approved-doc-a-2013-text.txt)
"""

import sys
import os

PDF_PATH    = "<input-pdf-path>"
OUTPUT_PATH = "<output-txt-path>"

FIGURE_PLACEHOLDER = (
    "[FIGURE — not extracted]\n"
    "[Run chorus-pdf with --auto or --images to extract figures via LLM vision]"
)


def extract_pages(pdf_path):
    try:
        from pdfminer.high_level import extract_pages as pm_extract
        from pdfminer.layout import LAParams, LTTextBox, LTFigure
    except ImportError:
        print("⛔ pdfminer.six not installed. Run: pip install pdfminer.six", file=sys.stderr)
        sys.exit(1)

    # boxes_flow=0.5 : balanced horizontal/vertical ordering — handles multi-column well
    laparams = LAParams(
        line_overlap=0.5,
        char_margin=2.0,
        line_margin=0.5,
        word_margin=0.1,
        boxes_flow=0.5,
        detect_vertical=False,
        all_texts=False
    )

    pages = []
    for page_num, page_layout in enumerate(pm_extract(pdf_path, laparams=laparams), 1):
        blocks = []
        has_figure = False
        for element in page_layout:
            if isinstance(element, LTTextBox):
                t = element.get_text().strip()
                if t:
                    blocks.append(t)
            elif isinstance(element, LTFigure):
                has_figure = True

        text = "\n".join(blocks)
        if has_figure:
            text += f"\n\n{FIGURE_PLACEHOLDER}"

        pages.append((page_num, text))

    return pages


def main():
    print(f"[chorus-pdf] Text mode — {PDF_PATH}", file=sys.stderr)
    pages = extract_pages(PDF_PATH)

    parts = []
    for page_num, text in pages:
        parts.append(
            f"=== PAGE {page_num} ===\n{text}\n=== END PAGE {page_num} ==="
        )

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write("\n\n".join(parts))

    fig_pages = sum(1 for _, t in pages if "FIGURE — not extracted" in t)
    print(f"[chorus-pdf] ✅ {len(pages)} pages extracted", file=sys.stderr)
    if fig_pages:
        print(f"[chorus-pdf]    {fig_pages} page(s) contain figures — use --auto to extract them",
              file=sys.stderr)
    print(f"[chorus-pdf] Written to {OUTPUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
```

> ⚠️ **Dependency**: `pip install pdfminer.six`

---

### Script template — Auto mode (`--auto`)

Classifies pages first. Text-only pages use `pdfminer`. Pages with figures use
`pdftoppm` + Claude vision. Only figure pages consume API tokens.
Output: `<NNN>-<slug>-vision.md`

```python
#!/usr/bin/env python3
"""
chorus-pdf extraction script — auto mode (--auto)
Generated by ECA chorus-pdf skill
Sandbox : <sandbox-name>
Source  : <input-pdf-path>
Output  : <output-md-path>    (e.g. corpus/003-uk-approved-doc-a-2013-vision.md)
Pages   : <total-pages>  (<N-text> text, <N-vision> vision)
"""

import sys
import base64
import json
import glob
import re
import time
import tempfile
import subprocess
import urllib.request
import urllib.error
import os

PDF_PATH    = "<input-pdf-path>"
OUTPUT_PATH = "<output-txt-path>"
CHUNK_SIZE  = 5
DPI         = 150
MAX_RETRIES = 4
API_KEY     = os.environ.get("ANTHROPIC_API_KEY", "")
API_URL     = "https://api.anthropic.com/v1/messages"

PROMPT = """<verbatim vision extraction prompt — see Phase 2>"""


# ---------------------------------------------------------------------------
# Page classification
# ---------------------------------------------------------------------------

def classify_pages(pdf_path):
    """Return {page_num: 'text'|'vision'} for all pages."""
    try:
        import pypdf
    except ImportError:
        print("⛔ pypdf not installed. Run: pip install pypdf", file=sys.stderr)
        sys.exit(1)

    reader = pypdf.PdfReader(pdf_path)
    result = {}
    for i, page in enumerate(reader.pages, 1):
        text      = page.extract_text() or ""
        has_image = len(page.images) > 0
        has_text  = len(text.strip()) > 50
        result[i] = 'vision' if (has_image or not has_text) else 'text'
    return result


# ---------------------------------------------------------------------------
# Text extraction — pdfminer
# ---------------------------------------------------------------------------

def extract_text_page(pdf_path, page_num):
    """Extract text from a single page using pdfminer."""
    try:
        from pdfminer.high_level import extract_pages
        from pdfminer.layout import LAParams, LTTextBox
    except ImportError:
        print("⛔ pdfminer.six not installed. Run: pip install pdfminer.six", file=sys.stderr)
        sys.exit(1)

    laparams = LAParams(boxes_flow=0.5, char_margin=2.0)
    blocks = []
    for pnum, layout in enumerate(extract_pages(pdf_path, laparams=laparams), 1):
        if pnum == page_num:
            for el in layout:
                if isinstance(el, LTTextBox):
                    t = el.get_text().strip()
                    if t:
                        blocks.append(t)
            break
    return "\n".join(blocks)


# ---------------------------------------------------------------------------
# Vision extraction — pdftoppm + Claude
# ---------------------------------------------------------------------------

def render_page(pdf_path, page_num, tmpdir):
    """Render a single PDF page to PNG via pdftoppm."""
    prefix = os.path.join(tmpdir, f"p{page_num:04d}")
    result = subprocess.run(
        ["pdftoppm", "-r", str(DPI), "-png",
         "-f", str(page_num), "-l", str(page_num),
         pdf_path, prefix],
        capture_output=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"pdftoppm failed on page {page_num}:\n{result.stderr.decode()}")
    files = sorted(glob.glob(prefix + "*.png"))
    if not files:
        raise RuntimeError(f"No PNG produced for page {page_num}")
    return files[0]


def image_to_b64(path):
    with open(path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")


def call_claude(pages_with_pngs):
    """Send a chunk of (page_num, png_path) pairs to Claude vision.
    Returns the raw text response."""
    content = []
    for page_num, path in pages_with_pngs:
        content.append({
            "type": "text",
            "text": f"[Processing page {page_num}]\n\n{PROMPT}"
        })
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": image_to_b64(path)
            }
        })

    payload = {
        "model": "claude-opus-4-5",
        "max_tokens": 8192,
        "messages": [{"role": "user", "content": content}]
    }
    headers = {
        "x-api-key": API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
    label = f"{pages_with_pngs[0][0]}-{pages_with_pngs[-1][0]}"
    for attempt in range(MAX_RETRIES):
        req = urllib.request.Request(
            API_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                return json.loads(resp.read().decode("utf-8"))["content"][0]["text"]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if e.code in (429, 529) and attempt < MAX_RETRIES - 1:
                wait = 10 * (2 ** attempt)
                print(f"  HTTP {e.code} — retrying in {wait}s ...", file=sys.stderr)
                time.sleep(wait)
            else:
                raise RuntimeError(f"HTTP {e.code} on pages {label}: {body[:500]}")


def split_page_markers(text, expected_pages):
    """Parse Claude's response into {page_num: page_block}.
    Falls back gracefully if markers are absent."""
    result = {}
    matches = list(re.finditer(
        r'(=== PAGE (\d+) ===.*?=== END PAGE \d+ ===)', text, re.DOTALL
    ))
    if matches:
        for m in matches:
            pnum = int(m.group(2))
            result[pnum] = m.group(1)
    else:
        # No markers — assign full response to first page
        result[expected_pages[0]] = (
            f"=== PAGE {expected_pages[0]} ===\n{text.strip()}\n"
            f"=== END PAGE {expected_pages[0]} ==="
        )
    # Fill any missing pages with a warning block
    for p in expected_pages:
        if p not in result:
            result[p] = (
                f"=== PAGE {p} ===\n"
                f"[WARNING: page {p} not found in Claude response]\n"
                f"=== END PAGE {p} ==="
            )
    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if not API_KEY:
        print("⛔ ANTHROPIC_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    print("[chorus-pdf] Auto mode — classifying pages ...", file=sys.stderr)
    classification = classify_pages(PDF_PATH)
    text_pages   = sorted(p for p, t in classification.items() if t == 'text')
    vision_pages = sorted(p for p, t in classification.items() if t == 'vision')
    total = len(classification)
    print(f"[chorus-pdf]   → {len(text_pages)}/{total} text-only pages  (pdfminer)", file=sys.stderr)
    print(f"[chorus-pdf]   → {len(vision_pages)}/{total} pages with figures (vision LLM)", file=sys.stderr)

    results = {}

    # --- Text pages ---
    if text_pages:
        print("[chorus-pdf] Extracting text pages ...", file=sys.stderr)
        for pnum in text_pages:
            text = extract_text_page(PDF_PATH, pnum)
            results[pnum] = (
                f"=== PAGE {pnum} ===\n{text}\n=== END PAGE {pnum} ==="
            )

    # --- Vision pages ---
    if vision_pages:
        chunks = [
            vision_pages[i:i+CHUNK_SIZE]
            for i in range(0, len(vision_pages), CHUNK_SIZE)
        ]
        print(f"[chorus-pdf] Processing vision pages — {len(chunks)} chunk(s) ...", file=sys.stderr)
        with tempfile.TemporaryDirectory(prefix="chorus-pdf-") as tmpdir:
            for cidx, chunk in enumerate(chunks, 1):
                label = f"{chunk[0]}-{chunk[-1]}"
                print(f"[chorus-pdf] Vision chunk {cidx}/{len(chunks)} (pages {label}) ...",
                      file=sys.stderr)
                pages_with_pngs = [
                    (pnum, render_page(PDF_PATH, pnum, tmpdir))
                    for pnum in chunk
                ]
                response = call_claude(pages_with_pngs)
                parsed   = split_page_markers(response, chunk)
                results.update(parsed)
                print(f"[chorus-pdf]   → {sum(len(t) for t in parsed.values())} chars",
                      file=sys.stderr)

    # --- Assemble in page order ---
    parts = [results[p] for p in sorted(results)]
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write("\n\n".join(parts))
    print(f"[chorus-pdf] ✅ Written to {OUTPUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
```

> ⚠️ **Dependencies**: `pip install pdfminer.six pypdf`
>
> ⚠️ **`pdftoppm` required**: `sudo apt install poppler-utils`
>
> ⚠️ **API key**: `export ANTHROPIC_API_KEY="sk-ant-..."`

---

### Script template — Images mode (`--images`)

All pages rendered to PNG at 150 DPI via `pdftoppm`, submitted to Claude vision.
Use when the document is mostly diagrams or scanned.
Output: `<NNN>-<slug>-vision.md`

```python
#!/usr/bin/env python3
"""
chorus-pdf extraction script — images mode (--images)
Generated by ECA chorus-pdf skill
Sandbox : <sandbox-name>
Source  : <input-pdf-path>
Output  : <output-md-path>    (e.g. corpus/003-uk-approved-doc-a-2013-vision.md)
Pages   : <total-pages>
DPI     : 150
"""

import sys
import base64
import json
import glob
import re
import time
import tempfile
import subprocess
import urllib.request
import urllib.error
import os

PDF_PATH    = "<input-pdf-path>"
OUTPUT_PATH = "<output-txt-path>"
CHUNK_SIZE  = 5
DPI         = 150
MAX_RETRIES = 4
API_KEY     = os.environ.get("ANTHROPIC_API_KEY", "")
API_URL     = "https://api.anthropic.com/v1/messages"

PROMPT = """<verbatim vision extraction prompt — see Phase 2>"""


def render_pages(pdf_path, tmpdir):
    """Render all PDF pages to PNG files using pdftoppm."""
    prefix = os.path.join(tmpdir, "page")
    result = subprocess.run(
        ["pdftoppm", "-r", str(DPI), "-png", pdf_path, prefix],
        capture_output=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"pdftoppm failed:\n{result.stderr.decode()}")
    pages = sorted(glob.glob(os.path.join(tmpdir, "page-*.png")))
    if not pages:
        pages = sorted(glob.glob(os.path.join(tmpdir, "page.*.png")))
    if not pages:
        raise RuntimeError("pdftoppm produced no PNG files — is the PDF password-protected?")
    return pages


def image_to_b64(path):
    with open(path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")


def call_claude(page_paths, page_offset):
    """Send a chunk of page PNGs to Claude vision."""
    content = []
    for i, path in enumerate(page_paths):
        page_num = page_offset + i + 1
        content.append({
            "type": "text",
            "text": f"[Processing page {page_num}]\n\n{PROMPT}"
        })
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": image_to_b64(path)
            }
        })

    payload = {
        "model": "claude-opus-4-5",
        "max_tokens": 8192,
        "messages": [{"role": "user", "content": content}]
    }
    headers = {
        "x-api-key": API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
    label = f"{page_offset+1}-{page_offset+len(page_paths)}"
    for attempt in range(MAX_RETRIES):
        req = urllib.request.Request(
            API_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                return json.loads(resp.read().decode("utf-8"))["content"][0]["text"]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if e.code in (429, 529) and attempt < MAX_RETRIES - 1:
                wait = 10 * (2 ** attempt)
                print(f"  HTTP {e.code} — retrying in {wait}s ...", file=sys.stderr)
                time.sleep(wait)
            else:
                raise RuntimeError(f"HTTP {e.code} on pages {label}: {body[:500]}")


def main():
    if not API_KEY:
        print("⛔ ANTHROPIC_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    r = subprocess.run(["pdftoppm", "--help"], capture_output=True)
    if r.returncode not in (0, 99):
        print("⛔ pdftoppm not found. Install: sudo apt install poppler-utils", file=sys.stderr)
        sys.exit(1)

    with tempfile.TemporaryDirectory(prefix="chorus-pdf-") as tmpdir:
        print(f"[chorus-pdf] Rendering pages at {DPI} DPI ...", file=sys.stderr)
        pages  = render_pages(PDF_PATH, tmpdir)
        total  = len(pages)
        chunks = [pages[i:i+CHUNK_SIZE] for i in range(0, total, CHUNK_SIZE)]
        print(f"[chorus-pdf] {total} pages → {len(chunks)} chunk(s) of {CHUNK_SIZE}",
              file=sys.stderr)

        all_text = []
        for idx, chunk in enumerate(chunks):
            start = idx * CHUNK_SIZE
            label = f"{start+1}-{start+len(chunk)}"
            print(f"[chorus-pdf] Chunk {idx+1}/{len(chunks)} (pages {label}) ...",
                  file=sys.stderr)
            text = call_claude(chunk, start)
            all_text.append(text)
            print(f"[chorus-pdf]   → {len(text)} chars", file=sys.stderr)

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write("\n\n".join(all_text))
    print(f"[chorus-pdf] ✅ Written to {OUTPUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
```

> ⚠️ **Dependencies**: `pip install pypdf`
>
> ⚠️ **`pdftoppm` required**: `sudo apt install poppler-utils`
>
> ⚠️ **API key**: `export ANTHROPIC_API_KEY="sk-ant-..."`

---

## Phase 3 — Execute and validate

### 3.1 Execute the script

```bash
python3 "$SANDBOX/eca/extract-pdf-<slug>.py"
```

Capture stderr for progress reporting. Exit code 0 = success.

### 3.2 Validate the output

```bash
python3 - "$SANDBOX/corpus/<NNN>-<slug>-vision.txt" <<'EOF'
import sys, re

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
pages   = re.findall(r'=== PAGE \d+ ===', text)
figures = re.findall(r'\[FIGURE', text)
tables  = re.findall(r'^\|', text, re.MULTILINE)
placeholders = text.count('not extracted')

print(f"Pages found      : {len(pages)}")
print(f"Figures found    : {len(figures)}")
print(f"Table rows       : {len(tables)}")
print(f"Placeholders     : {placeholders}")
print(f"Total chars      : {len(text)}")
if len(pages) == 0:
    print("⚠️  WARNING: no === PAGE === markers — output may be malformed")
if len(text) < 500:
    print("⚠️  WARNING: output is suspiciously short")
if placeholders > 0:
    print(f"ℹ️  {placeholders} figure(s) not extracted — run with --auto to extract them")
EOF
```

Report the sanity check results to the user before proceeding.

### 3.3 Failure handling

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| `pdfminer.six` ImportError | Missing dependency | `pip install pdfminer.six` |
| `pypdf` ImportError | Missing dependency | `pip install pypdf` |
| `pdftoppm` not found | `poppler-utils` absent | `sudo apt install poppler-utils` |
| `ANTHROPIC_API_KEY not set` | Missing env var | `export ANTHROPIC_API_KEY="sk-ant-..."` |
| HTTP 400 | PDF chunk too large | Reduce `CHUNK_SIZE` to 3 |
| HTTP 429 / 529 | API rate limit / overload | Retry handled automatically (exponential backoff) |
| No PNG files rendered | Password-protected PDF | Decrypt first: `qpdf --decrypt in.pdf out.pdf` |
| Output < 500 chars | Extraction returned nothing | Check API key validity; verify PDF is not encrypted |
| Figures described but values wrong | Dense diagram | Increase `DPI = 200` in script header; keep `CHUNK_SIZE = 3` |
| Text mode: garbled multi-column | pdfminer layout | Normal on very complex layouts — use `--auto` instead |
| Auto mode: page miscategorised | `pypdf` image detection | Force individual pages to vision by adjusting text threshold in `classify_pages` |

---

## Phase 4 — Update sandbox metadata

### 4.1 Update `README.org`

Add a row for the new file in the `Corpus` table:

```org
| <NNN> | corpus/<NNN>-<slug>-text.txt   | pdfminer from <source-pdf>          | <date> |
| <NNN> | corpus/<NNN>-<slug>-vision.md  | auto(pdfminer+vision) from <source> | <date> |
| <NNN> | corpus/<NNN>-<slug>-vision.md  | vision(LLM) from <source-pdf>       | <date> |
```

(use the row matching the mode used)

Do **not** remove the row for the original PDF or any prior file — all versions are
kept for traceability.

### 4.2 Report to the user

```
✅ chorus-pdf completed
   Mode     : text  (or: auto — 38 text / 16 vision  |  images — 150 DPI)
   Source   : corpus/<source.pdf>  (<N> pages)
   Output   : corpus/<NNN>-<slug>-text.txt   (or: -vision.md)
   Pages    : <N>
   Figures  : <N> blocks extracted  (or: <N> placeholders — use --auto to extract)
   Table rows: <N>
   Size     : <N> chars

   Next step: chorus-feed <sandbox-name> corpus/<NNN>-<slug>-text.txt
              (or: corpus/<NNN>-<slug>-vision.md)
```

---

## Integration with chorus-feed

`chorus-pdf` is a **pre-processing step**, not a replacement for `chorus-feed`.
Typical workflow:

```
# No API key — extract text only (figures get placeholders)
chorus-pdf  <sandbox> corpus/002-uk-approved-doc-a-2013.pdf
→ corpus/003-uk-approved-doc-a-2013-text.txt

# API key available — recommended for technical standards
chorus-pdf  <sandbox> corpus/002-uk-approved-doc-a-2013.pdf --auto
→ corpus/003-uk-approved-doc-a-2013-vision.md

# Mostly diagrams or scanned PDF
chorus-pdf  <sandbox> corpus/002-uk-approved-doc-a-2013.pdf --images
→ corpus/003-uk-approved-doc-a-2013-vision.md

# Then in all cases:
chorus-feed <sandbox> corpus/003-uk-approved-doc-a-2013-text.txt
            (or: corpus/003-uk-approved-doc-a-2013-vision.md)
```

If a `.txt` from `pdftotext` already exists alongside the PDF, prefer the `-text.txt`
(text mode) or `-vision.md` (auto/images) for `chorus-feed`.
The `pdftotext` output can be kept for diff/audit purposes.

---

## Quick Reference — Naming Conventions

| Artifact | Convention | Example |
|----------|-----------|---------|
| Extraction script | `eca/extract-pdf-<slug>.py` | `eca/extract-pdf-uk-approved-doc-a.py` |
| Text mode output | `corpus/<NNN>-<slug>-text.txt` | `corpus/003-uk-approved-doc-a-2013-text.txt` |
| Auto/Images output | `corpus/<NNN>-<slug>-vision.md` | `corpus/003-uk-approved-doc-a-2013-vision.md` |
| Original PDF | kept as-is in `corpus/` | `corpus/002-uk-approved-doc-a-2013.pdf` |

---

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

**"I want higher quality on specific diagram pages"**
→ Increase `DPI = 200` in the script header. Keep `CHUNK_SIZE = 3` at 200 DPI
  (PNG ≈ 900 KB/page → 3 pages ≈ 2.7 MB payload).
