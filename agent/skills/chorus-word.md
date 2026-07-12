# Skill — chorus-word

> Trigger: `chorus-word <sandbox-name> <file.docx> [--out <slug>] [--batch]`
> Agent: `architect`
>
> `<sandbox-name>`: name of the sandbox directory under `$SANDBOXES/`
> `<file.docx>`: path to the Word document — absolute, or relative to `$SANDBOX/corpus/`
> `--out <slug>`: override the output filename stem (default: derived from input filename)
> `--batch`: process all `*.docx` files found in `$SANDBOX/corpus/`
>
> **Single responsibility: produce an enriched text file from a Word document (.docx).**
> Extracts text, tables, images, headers, and footers that naive conversion tools silently
> discard or mangle. Preserves document structure and reading order via the native XML tree.
>
> Output format depends on mode:
> - Hybrid mode (default when API key available): `corpus/<NNN>-<slug>-vision.md` — python-docx text + Claude vision on images
> - Text mode (fallback — no API key): `corpus/<NNN>-<slug>-text.txt` — plain text, python-docx only
>
> This skill must be run **before** `chorus-import-project` when the corpus contains `.docx` files.
> `chorus-feed` then takes the output file as its corpus input.


## ⛔ Strict sandbox isolation

Never read any KB, YAML, or artifact from a sandbox other than `<sandbox-name>`.
This skill operates exclusively on the `corpus/` directory of the target sandbox.


## Overview

Standard Word-to-text converters (`docx2txt`, `python-docx` naive extraction) extract
only the raw paragraph text in declaration order. They silently drop:
- Inline images and embedded figures (logos, diagrams, charts)
- Table structure (merged cells, multi-row headers)
- Reading order (interleaving of paragraphs, tables and images as in the rendered document)
- Headers and footers (section metadata, normative information)

This skill provides two extraction modes:

### Two extraction modes

| Mode | Flag | Engine | API key | Images | Tables | Output |
|------|------|--------|---------|--------|--------|--------|
| **Hybrid** (**default**) | *(none — auto-detected)* | python-docx text + Claude vision on images | ✅ `ANTHROPIC_API_KEY` | ✅ described | ✅ Markdown pipe | `<NNN>-<slug>-vision.md` |
| **Text** (fallback) | *(none — no API key)* | python-docx only | ❌ not required | `[IMAGE — not extracted]` placeholder | ✅ Markdown pipe | `<NNN>-<slug>-text.txt` |

**Choosing a mode:**

```
No flag provided
  → Phase 0.0 auto-detects ANTHROPIC_API_KEY and probes Claude
  → if key valid   : hybrid activated automatically  ← DEFAULT
  → if key absent or invalid : text mode (fallback)

API key absent
  → text mode (fallback) — python-docx only
```

> **`hybrid` is the recommended mode** for technical Word documents (CCTP, DCE, BET notes,
> normative annexes) when an API key is available. It combines python-docx precision on
> text (exact characters, no OCR risk) with Claude vision on embedded images only
> (smaller payload, lower cost). Tables are always reconstructed as Markdown pipe tables
> via python-docx in both modes.


## Phase 0.0 — Auto-detect mode (no explicit flag)

This phase runs **always** (there are no explicit mode flags for chorus-word).
Its goal: activate `hybrid` automatically if Claude is available.

### 0.0.1 Check API key presence

```python
API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
if not API_KEY:
    # No key → stay in text mode, skip probe
    mode = "text"
    print("[chorus-word] No ANTHROPIC_API_KEY — text mode.", file=sys.stderr)
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
| present | ✅ valid | **hybrid** | `ANTHROPIC_API_KEY detected — Claude available ✅ — hybrid mode activated.` |
| present | ❌ invalid (401/403) | text | `ANTHROPIC_API_KEY set but key is invalid (HTTP 4xx) — falling back to text mode.` |
| present | ❌ unreachable | text | `Claude unreachable (network error) — falling back to text mode.` |
| present | ⚠️ throttled (429/529) | **hybrid** | `ANTHROPIC_API_KEY detected — Claude available (throttled) ✅ — hybrid mode activated.` |

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

### 0.2 Resolve the DOCX path

If `<file.docx>` is a bare filename → prepend `$SANDBOX/corpus/`.
If it is an absolute path → use as-is.
Verify the file exists and ends in `.docx` (case-insensitive).

In `--batch` mode: glob `$SANDBOX/corpus/*.docx` (and `*.DOCX`). Process each in turn.
If no DOCX found → warn and exit cleanly (not an error).

### 0.3 Resolve the output filename

Determine the next available corpus number:

```
existing = glob("$SANDBOX/corpus/[0-9][0-9][0-9]-*.*")
last_num = max of the leading 3-digit prefix across existing files (default 0)
next_num = last_num + 1   (formatted as %03d)
```

> ⚠️ In `--batch` mode, increment `next_num` for each DOCX processed in sequence.

Derive the slug and extension based on mode:

| Mode | Suffix | Extension | Rationale |
|------|--------|-----------|-----------|
| Hybrid (default) | `-vision` | `.md` | python-docx text + Claude vision on images — default when API key present |
| Text (fallback) | `-text` | `.txt` | Plain text only — no Markdown syntax produced |

- If `--out <slug>` provided → use that slug as-is (suffix already included)
- Otherwise → strip leading `NNN-` prefix and `.docx` extension from the input filename,
  then append the mode suffix

Output filename: `$SANDBOX/corpus/<next_num>-<slug>.<ext>`

Example:
```
Input   : corpus/002-cctp-structure.docx

Hybrid  : corpus/003-cctp-structure-vision.md
Text    : corpus/003-cctp-structure-text.txt
```


## Phase 1 — Document analysis

### 1.1 Open the document and count blocks

Use `python-docx` to open the document and count its elements:

```python
import docx

doc = docx.Document(docx_path)

# Count elements via the XML body (authoritative — respects reading order)
n_paras  = 0
n_tables = 0
n_images = 0

from docx.oxml.ns import qn

for child in doc.element.body:
    tag = child.tag.split('}')[-1]
    if tag == 'p':
        blips = child.findall('.//' + qn('a:blip'))
        if blips:
            n_images += len(blips)
        else:
            para = docx.text.paragraph.Paragraph(child, doc)
            if para.text.strip():
                n_paras += 1
    elif tag == 'tbl':
        n_tables += 1
```

Report to stderr:
```
[chorus-word] Document analysis:
   → N paragraphs / M tables / K images
   → Mode: hybrid (Claude vision on images) / text (no API key)
```

### 1.2 Reading order via the XML body

**The order of elements in a DOCX is the XML order of `doc.element.body`** — this is
the canonical reading order for Word documents. Unlike PDFs (which require Y-coordinate
sorting), Word documents have a fully sequential DOM: paragraphs, tables and images
appear in the order the author placed them.

```python
from docx.oxml.ns import qn

def iter_block_items(doc):
    """Yield (kind, obj) in document order.

    Yields:
      ('para',  (text: str, style: str))   — non-empty text paragraph
      ('table', Table)                      — python-docx Table object
      ('image', (img_idx: int, blob: bytes)) — inline image bytes (PNG/JPEG/EMF)
    """
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
                        img_part = doc.part.rels[rId].target_part
                        img_counter[0] += 1
                        yield ('image', (img_counter[0], img_part.blob))
            else:
                text = para.text.strip()
                if text:
                    style = para.style.name if para.style else ''
                    yield ('para', (text, style))
        elif tag == 'tbl':
            tbl = docx.table.Table(child, doc)
            yield ('table', tbl)
```

> ⚠️ **No Y-sort required.** Unlike the PDF pipeline (which sorts elements by
> `y_center` descending), the Word pipeline simply iterates the XML body in order.
> The reading order is guaranteed by the document format itself.


## Phase 1.5 — nohup gate (hybrid mode only)

After counting the images in Phase 1.1, the script knows the **exact number of API
calls** required. Each image = 1 API call ≈ 30 s average. The IDE has a hard timeout
of ~10 minutes.

**Decision rule — applied inside the generated script:**

| Images detected (`n_images`) | Estimated time | Action |
|-----------------------------:|---------------:|--------|
| ≤ 15 | ≤ 7.5 min | proceed directly |
| ≥ 16 | > 8 min | **exit(2)** + print `nohup` command |

```
[chorus-word]   → 22 image(s) detected — estimated time ~11–16 min (threshold: 15).
[chorus-word] ⚠️  Run with nohup to avoid a 10-min IDE timeout:
[chorus-word]    CHORUS_WORD_FORCE=1 nohup python3 /path/to/agent/extract-word-<slug>.py > corpus/<NNN>-<slug>-vision.md.log 2>&1 &
```

Exit code **2** = "nohup required" (not an error). Exit code 0 = successful completion.

**Bypass `CHORUS_WORD_FORCE=1`:** when launched via `nohup`, set `CHORUS_WORD_FORCE=1`
to skip the gate and proceed unconditionally.

> ⚠️ **instruction:** when executing the script and receiving exit code 2, the agent must
> **not** retry automatically. Instead, it must set `CHORUS_WORD_FORCE=1` and relaunch
> with `nohup` — **launch the nohup command** (pre-approved, no confirmation required).


## Phase 2 — Generate the extraction script

Create `$SANDBOX/agent/` if it does not exist.
Write `$SANDBOX/agent/extract-word-<slug>.py`, then execute it.

### Figure description prompt (used verbatim in hybrid script)

```
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
```


### Shared utilities — Text & Hybrid modes

The following functions are used verbatim in both the Text and Hybrid script templates.
Include them in the generated script when either mode is active.

```python
def cell_text(cell):
    """Concatenate all paragraph text in a cell, stripping whitespace."""
    return " ".join(p.text.strip() for p in cell.paragraphs if p.text.strip())


def table_to_markdown(tbl):
    """Convert a python-docx Table to a Markdown pipe table.
    Handles merged cells by tracking unique _tc XML elements per row.
    """
    if not tbl.rows:
        return ""
    seen_cells = set()
    deduped = []
    for row in tbl.rows:
        row_cells = []
        for cell in row.cells:
            cell_id = id(cell._tc)
            if cell_id not in seen_cells:
                seen_cells.add(cell_id)
                row_cells.append(cell_text(cell))
        if row_cells:
            deduped.append(row_cells)
    if not deduped or not deduped[0]:
        return ""
    n_cols = max(len(r) for r in deduped)
    rows_padded = [r + [''] * (n_cols - len(r)) for r in deduped]
    def cell_md(c):
        return str(c or "").replace("\n", " ").replace("|", "｜").strip()
    lines = ["| " + " | ".join(cell_md(c) for c in rows_padded[0]) + " |",
             "| " + " | ".join("---" for _ in rows_padded[0]) + " |"]
    for row in rows_padded[1:]:
        lines.append("| " + " | ".join(cell_md(c) for c in row) + " |")
    return "\n".join(lines)


def iter_block_items(doc):
    """Yield (kind, obj) in XML body order (= reading order for DOCX).
    Yields: ('para', (text, style)) | ('table', Table) | ('image', (idx, blob))
    """
    from docx.oxml.ns import qn
    import docx.text.paragraph as _dp
    body = doc.element.body
    img_counter = [0]
    for child in body:
        tag = child.tag.split('}')[-1]
        if tag == 'p':
            para = _dp.Paragraph(child, doc)
            blips = child.findall('.//' + qn('a:blip'))
            if blips:
                for blip in blips:
                    rId = blip.get(qn('r:embed'))
                    if rId and rId in doc.part.rels:
                        img_part = doc.part.rels[rId].target_part
                        img_counter[0] += 1
                        yield ('image', (img_counter[0], img_part.blob))
            else:
                text = para.text.strip()
                if text:
                    style = para.style.name if para.style else ''
                    yield ('para', (text, style))
        elif tag == 'tbl':
            import docx as _docx
            tbl = _docx.table.Table(child, doc)
            yield ('table', tbl)
```

### Script template — Text mode (no API key or Claude unavailable)

Uses `python-docx` only. No API key, no network. Images produce a placeholder.
Tables are reconstructed as Markdown pipe tables.
Output: `<NNN>-<slug>-text.txt`

```python
#!/usr/bin/env python3
"""
chorus-word extraction script — text mode
Generated by chorus-word skill
Sandbox : <sandbox-name>
Source  : <input-docx-path>
Output  : <output-txt-path>   (e.g. corpus/003-cctp-structure-text.txt)
"""

import sys
import os

DOCX_PATH   = "<input-docx-path>"
OUTPUT_PATH = "<output-txt-path>"

IMAGE_PLACEHOLDER = (
    "[IMAGE — not extracted]\n"
    "[Run chorus-word with ANTHROPIC_API_KEY set to extract images via hybrid mode]"
)

# → cell_text / table_to_markdown / iter_block_items
#   see "Shared utilities — Text & Hybrid modes" above

def main():
    try:
        import docx
    except ImportError:
        print("⛔ python-docx not installed. Run: pip install python-docx", file=sys.stderr)
        sys.exit(1)

    print(f"[chorus-word] Text mode — {DOCX_PATH}", file=sys.stderr)
    doc = docx.Document(DOCX_PATH)

    # --- Headers and footers (informational) ---
    header_lines = []
    footer_lines = []
    for section in doc.sections:
        for p in section.header.paragraphs:
            t = p.text.strip()
            if t:
                header_lines.append(t)
        for p in section.footer.paragraphs:
            t = p.text.strip()
            if t:
                footer_lines.append(t)
    if header_lines:
        print(f"[chorus-word] Header: {' | '.join(header_lines)}", file=sys.stderr)
    if footer_lines:
        print(f"[chorus-word] Footer: {' | '.join(footer_lines)}", file=sys.stderr)

    elements = []
    n_paras = 0
    n_tables = 0
    n_images = 0

    for kind, obj in iter_block_items(doc):
        if kind == 'para':
            text, style = obj
            elements.append(text)
            n_paras += 1
        elif kind == 'table':
            md = table_to_markdown(obj)
            if md:
                elements.append(md)
                n_tables += 1
        elif kind == 'image':
            idx, blob = obj
            elements.append(IMAGE_PLACEHOLDER)
            n_images += 1

    # Optional: prepend header/footer info
    preamble = []
    if header_lines:
        preamble.append("[HEADER: " + " | ".join(header_lines) + "]")
    if footer_lines:
        preamble.append("[FOOTER: " + " | ".join(footer_lines) + "]")

    output_parts = preamble + elements
    output = "\n\n".join(output_parts)

    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write(output)

    print(f"[chorus-word] ✅ {n_paras} paragraph(s), {n_tables} table(s), "
          f"{n_images} image(s) — written to {OUTPUT_PATH}", file=sys.stderr)
    if n_images:
        print(f"[chorus-word]    {n_images} image(s) not extracted — "
              f"set ANTHROPIC_API_KEY to enable hybrid mode", file=sys.stderr)

if __name__ == "__main__":
    main()
```

> ⚠️ **Dependencies**: `pip install python-docx`


### Script template — Hybrid mode (default when API key present)

Uses `python-docx` for text and tables. Embedded images are sent to Claude vision
with `FIGURE_PROMPT`. Images that cannot be decoded to PNG (EMF/WMF metafiles) are
skipped with a warning. The cross-reference pass (Phase 2.5) runs after all images
have been described.
Output: `<NNN>-<slug>-vision.md`

```python
#!/usr/bin/env python3
"""
chorus-word extraction script — hybrid mode
Generated by chorus-word skill
Sandbox : <sandbox-name>
Source  : <input-docx-path>
Output  : <output-md-path>   (e.g. corpus/003-cctp-structure-vision.md)
Images  : <total-images>
"""

import sys
import base64
import json
import re
import time
import os
import io

DOCX_PATH   = "<input-docx-path>"
OUTPUT_PATH = "<output-md-path>"
MAX_RETRIES = 4
API_KEY     = os.environ.get("ANTHROPIC_API_KEY", "")
API_URL     = "https://api.anthropic.com/v1/messages"

FIGURE_PROMPT = """<verbatim — see "Figure description prompt" above in Phase 2>"""

# ---------------------------------------------------------------------------
# nohup gate
# ---------------------------------------------------------------------------

NOHUP_THRESHOLD = 15

def check_nohup_gate(n_images):
    """Exit with code 2 if image count exceeds threshold (unless CHORUS_WORD_FORCE=1)."""
    force = os.environ.get("CHORUS_WORD_FORCE", "") == "1"
    if n_images > NOHUP_THRESHOLD and not force:
        est_min = n_images * 30 // 60
        est_max = n_images * 45 // 60
        print(
            f"[chorus-word]   → {n_images} image(s) detected — "
            f"estimated time ~{est_min}–{est_max} min "
            f"(threshold: {NOHUP_THRESHOLD}).\n"
            f"[chorus-word] ⚠️  Run with nohup to avoid a 10-min IDE timeout:\n"
            f"[chorus-word]    CHORUS_WORD_FORCE=1 nohup python3 {os.path.abspath(__file__)} "
            f"> {OUTPUT_PATH}.log 2>&1 &",
            file=sys.stderr
        )
        sys.exit(2)
    elif n_images > NOHUP_THRESHOLD and force:
        print(
            f"[chorus-word] ⚠️  {n_images} images — CHORUS_WORD_FORCE=1 → proceeding without gate.",
            file=sys.stderr
        )

# → cell_text / table_to_markdown / iter_block_items
#   see "Shared utilities — Text & Hybrid modes" above

# ---------------------------------------------------------------------------
# Image conversion — blob → PNG bytes via Pillow
# ---------------------------------------------------------------------------

def convert_to_png(blob):
    """Convert an image blob to PNG bytes via Pillow.

    Handles: JPEG, PNG, BMP, GIF, TIFF.
    EMF/WMF metafiles are not supported by Pillow — returns None (image skipped).
    """
    try:
        from PIL import Image
    except ImportError:
        print("⛔ Pillow not installed. Run: pip install Pillow", file=sys.stderr)
        sys.exit(1)

    # EMF magic: 0x01000000 little-endian
    if len(blob) >= 4 and blob[:4] == b'\x01\x00\x00\x00':
        return None   # EMF — not supported by Pillow
    # WMF magic: 0xD7CD (or 0x01 0x00 for Placeable WMF)
    if len(blob) >= 2 and blob[:2] in (b'\xd7\xcd', b'\x01\x00'):
        return None   # WMF — not supported by Pillow

    try:
        img = Image.open(io.BytesIO(blob))
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        return buf.getvalue()
    except Exception:
        # Already PNG?
        if len(blob) >= 8 and blob[:8] == b'\x89PNG\r\n\x1a\n':
            return blob
        return None

# ---------------------------------------------------------------------------
# Claude vision — describe a single image
# ---------------------------------------------------------------------------

def call_claude_image(png_bytes, doc_name, img_idx):
    """Send a single image to Claude and return the [FIGURE] block.

    Same retry logic as chorus-pdf call_claude_figure (exponential backoff
    on 429/529, hard failure on other HTTP errors).
    """
    b64 = base64.standard_b64encode(png_bytes).decode("utf-8")
    content = [
        {
            "type": "text",
            "text": f"[Document: {doc_name}, Image {img_idx}]\n\n{FIGURE_PROMPT}"
        },
        {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": b64
            }
        },
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
    import urllib.request
    import urllib.error
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
                    f"HTTP {e.code} image {img_idx}: {body[:300]}"
                )

# ---------------------------------------------------------------------------
# Phase 2.5 — Cross-reference pass
# ---------------------------------------------------------------------------

# Identifiers to ignore even if they match the extraction pattern:
# single letters used as generic variables, unit abbreviations, and
# common structural-engineering stopwords.
_XREF_STOPWORDS = {
    "N", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
    "M", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "kN", "mm", "cm", "m", "kg", "kPa", "MPa", "GPa", "kNm",
    "Figure", "Table", "Clause", "Section", "Annex", "NOTE", "Fig",
}

# Minimum length for an identifier to be considered (avoids noise like "a1")
_XREF_MIN_LEN = 2

def parse_identifiers(description):
    """Extract the IDENTIFIERS JSON array from a [FIGURE] description block.

    Returns a de-duplicated, filtered list of identifier strings.
    Falls back to regex extraction if the JSON line is absent or malformed.
    """
    ids = []

    # 1. Try the structured IDENTIFIERS: [...] line
    m = re.search(r'^IDENTIFIERS:\s*(\[.*?\])\s*$', description, re.MULTILINE)
    if m:
        try:
            raw = json.loads(m.group(1))
            ids = [str(x).strip() for x in raw if str(x).strip()]
        except json.JSONDecodeError:
            pass

    # 2. Fallback: scan the description for plausible identifiers
    #    Pattern: 2+ chars, at least one letter, mix of letters/digits/hyphens
    if not ids:
        ids = re.findall(r'\b([A-Za-z][A-Za-z0-9\-_]{1,19})\b', description)

    # 3. Filter
    seen = set()
    result = []
    for ident in ids:
        if ident in _XREF_STOPWORDS:
            continue
        if len(ident) < _XREF_MIN_LEN:
            continue
        if ident.lower() in seen:
            continue
        seen.add(ident.lower())
        result.append(ident)

    return result

def find_text_occurrences(identifier, block_texts):
    """Search all text blocks for occurrences of *identifier* as a whole word.

    Parameters
    ----------
    block_texts : {block_idx: [(text_content, block_idx), ...]}
        All paragraph text blocks indexed by block position.

    Returns a list of (block_idx, snippet) tuples, one per matching text block.
    The snippet is ≤ 120 chars centred on the first match in the block.
    """
    pattern = re.compile(r'\b' + re.escape(identifier) + r'\b')
    results = []
    for block_idx in sorted(block_texts):
        for entry in block_texts[block_idx]:
            block_text = entry[0]
            m = pattern.search(block_text)
            if m:
                start = max(0, m.start() - 55)
                end   = min(len(block_text), m.end() + 55)
                snippet = block_text[start:end].replace('\n', ' ').strip()
                if start > 0:
                    snippet = '…' + snippet
                if end < len(block_text):
                    snippet = snippet + '…'
                results.append((block_idx, snippet))
    return results

def _fmt_occ(occurrences):
    """Format occurrence list as a compact multi-line string for the XREF block."""
    if not occurrences:
        return "    (no occurrence found in text)"
    lines = []
    for block_idx, snippet in occurrences:
        lines.append(f"    § {block_idx}: {snippet}")
    return '\n'.join(lines)

def xref_pass(all_image_descs, block_texts):
    """Run the full cross-reference pass.

    Parameters
    ----------
    all_image_descs : {img_idx: description_text}
        All figure descriptions keyed by image index.
    block_texts : {block_idx: [(text_content, block_idx)]}
        All paragraph text blocks from the document body.

    Returns
    -------
    (annotated_descs, xref_index_block)

    annotated_descs  : same keys, descriptions now include a [XREF FIGURE N]
                       annotation appended after [END FIGURE N]
    xref_index_block : string — the global === XREF INDEX === section
    """
    annotated = {}
    # Global index: {identifier: [(img_idx, occurrences), ...]}
    global_index = {}

    for img_idx, desc in all_image_descs.items():
        identifiers = parse_identifiers(desc)
        if not identifiers:
            annotated[img_idx] = desc
            continue

        xref_lines = [f"[XREF FIGURE {img_idx}]"]
        for ident in identifiers:
            occs = find_text_occurrences(ident, block_texts)
            xref_lines.append(f"  {ident}:")
            xref_lines.append(_fmt_occ(occs))
            global_index.setdefault(ident, []).append((img_idx, occs))
        xref_lines.append(f"[END XREF FIGURE {img_idx}]")

        # Append the XREF annotation to the description, after [END FIGURE …]
        annotated_desc = re.sub(
            r'(\[END FIGURE[^\]]*\])',
            r'\1\n' + '\n'.join(xref_lines),
            desc,
            count=1
        )
        # If [END FIGURE] marker is absent (malformed), just append
        if annotated_desc == desc:
            annotated_desc = desc + '\n' + '\n'.join(xref_lines)
        annotated[img_idx] = annotated_desc

    # Build the global XREF INDEX block
    index_lines = [
        "=== XREF INDEX ===",
        "# Cross-reference: identifiers found in figures → text occurrences",
        "",
    ]
    for ident in sorted(global_index):
        entries = global_index[ident]
        all_occs_flat = []
        fig_refs = []
        for img_idx, occs in entries:
            fig_refs.append(f"Figure {img_idx}")
            all_occs_flat.extend(occs)
        index_lines.append(f"## {ident}")
        index_lines.append(f"   Appears in: {', '.join(fig_refs)}")
        if all_occs_flat:
            seen_blocks = set()
            for blk, snip in all_occs_flat:
                if blk not in seen_blocks:
                    index_lines.append(f"   Text occurrence (§ {blk}): {snip}")
                    seen_blocks.add(blk)
        else:
            index_lines.append("   Text occurrence: (none found)")
        index_lines.append("")
    index_lines.append("=== END XREF INDEX ===")

    return annotated, '\n'.join(index_lines)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    try:
        import docx
    except ImportError:
        print("⛔ python-docx not installed. Run: pip install python-docx", file=sys.stderr)
        sys.exit(1)

    if not API_KEY:
        print("⛔ ANTHROPIC_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    doc_name = os.path.basename(DOCX_PATH)
    print(f"[chorus-word] Hybrid mode — {DOCX_PATH}", file=sys.stderr)
    doc = docx.Document(DOCX_PATH)

    # --- Phase 1.1 — count elements ---
    n_paras = 0
    n_tables = 0
    n_images = 0
    from docx.oxml.ns import qn as _qn
    for child in doc.element.body:
        tag = child.tag.split('}')[-1]
        if tag == 'p':
            blips = child.findall('.//' + _qn('a:blip'))
            if blips:
                n_images += len(blips)
            else:
                import docx.text.paragraph as _dp
                para = _dp.Paragraph(child, doc)
                if para.text.strip():
                    n_paras += 1
        elif tag == 'tbl':
            n_tables += 1

    print(f"[chorus-word] Document analysis:", file=sys.stderr)
    print(f"[chorus-word]    → {n_paras} paragraph(s) / {n_tables} table(s) / {n_images} image(s)",
          file=sys.stderr)
    print(f"[chorus-word]    → Mode: hybrid (Claude vision on images)", file=sys.stderr)

    # --- Phase 1.5 — nohup gate ---
    check_nohup_gate(n_images)

    # --- Headers and footers (informational) ---
    header_lines = []
    footer_lines = []
    for section in doc.sections:
        for p in section.header.paragraphs:
            t = p.text.strip()
            if t:
                header_lines.append(t)
        for p in section.footer.paragraphs:
            t = p.text.strip()
            if t:
                footer_lines.append(t)

    # --- Phase 2 — iterate document body ---
    # Collect: ordered elements list + block_texts for XREF + image descs
    ordered_elements = []   # list of ('text', content) | ('table', md) | ('image', img_idx)
    block_texts = {}        # {block_idx: [(text, block_idx)]}  — for XREF search
    all_image_descs = {}    # {img_idx: description_text}
    block_idx = 0

    for kind, obj in iter_block_items(doc):
        if kind == 'para':
            text, style = obj
            ordered_elements.append(('text', text))
            block_texts.setdefault(block_idx, []).append((text, block_idx))
            block_idx += 1
        elif kind == 'table':
            md = table_to_markdown(obj)
            if md:
                ordered_elements.append(('table', md))
        elif kind == 'image':
            img_idx, blob = obj
            ordered_elements.append(('image', img_idx))

    # --- Phase 2 — Claude vision on all images ---
    image_positions = [i for i, (k, _) in enumerate(ordered_elements) if k == 'image']
    if image_positions:
        print(f"[chorus-word] Processing {len(image_positions)} image(s) via Claude ...",
              file=sys.stderr)
        for pos in image_positions:
            _, img_idx = ordered_elements[pos]
            # Retrieve blob: re-iterate to get the blob for this idx
            # (blobs were not stored above to avoid memory duplication — re-extract)
            blob = None
            idx_counter = 0
            from docx.oxml.ns import qn as _qn2
            for child in doc.element.body:
                tag = child.tag.split('}')[-1]
                if tag == 'p':
                    blips = child.findall('.//' + _qn2('a:blip'))
                    if blips:
                        for blip in blips:
                            rId = blip.get(_qn2('r:embed'))
                            if rId and rId in doc.part.rels:
                                idx_counter += 1
                                if idx_counter == img_idx:
                                    blob = doc.part.rels[rId].target_part.blob
                                    break
                    if blob:
                        break
            if blob is None:
                print(f"[chorus-word]   image {img_idx} — blob not found (skipped)",
                      file=sys.stderr)
                all_image_descs[img_idx] = (
                    f"[FIGURE {img_idx} — not extracted: blob not found]"
                )
                continue

            png_bytes = convert_to_png(blob)
            if png_bytes is None:
                print(f"[chorus-word]   image {img_idx} — unsupported format (EMF/WMF, skipped)",
                      file=sys.stderr)
                all_image_descs[img_idx] = (
                    f"[FIGURE {img_idx} — not extracted: unsupported format (EMF/WMF)]\n"
                    f"IDENTIFIERS: []"
                )
                continue

            print(f"[chorus-word]   image {img_idx} ({len(png_bytes)//1024} KB) → Claude ...",
                  file=sys.stderr)
            desc = call_claude_image(png_bytes, doc_name, img_idx)
            all_image_descs[img_idx] = desc
            print(f"[chorus-word]     → {len(desc)} chars", file=sys.stderr)

    # --- Phase 2.5 — Cross-reference pass ---
    if all_image_descs:
        print("[chorus-word] Phase 2.5 — cross-reference pass ...", file=sys.stderr)
        annotated_descs, xref_index = xref_pass(all_image_descs, block_texts)
        total_xref = sum(len(parse_identifiers(d)) for d in all_image_descs.values())
        print(f"[chorus-word]   → {total_xref} identifier(s) cross-referenced", file=sys.stderr)
    else:
        annotated_descs = {}
        xref_index = None

    # --- Assemble output ---
    parts = []
    if header_lines:
        parts.append("[HEADER: " + " | ".join(header_lines) + "]")
    if footer_lines:
        parts.append("[FOOTER: " + " | ".join(footer_lines) + "]")

    for kind, content in ordered_elements:
        if kind == 'text':
            parts.append(content)
        elif kind == 'table':
            parts.append(content)
        elif kind == 'image':
            img_idx = content
            desc = annotated_descs.get(img_idx, f"[FIGURE {img_idx} — description unavailable]")
            parts.append(desc)

    if xref_index:
        parts.append(xref_index)

    output = "\n\n".join(parts)
    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write(output)

    print(
        f"[chorus-word] ✅ {n_paras} paragraph(s), {n_tables} table(s), "
        f"{len(all_image_descs)} image(s) — written to {OUTPUT_PATH}",
        file=sys.stderr
    )

if __name__ == "__main__":
    main()
```

> ⚠️ **Dependencies**: `pip install python-docx Pillow`
>
> ⚠️ **API key**: `export ANTHROPIC_API_KEY="sk-ant-..."`
>
> ℹ️ **API calls**: 1 call per embedded image — maximally targeted. A 30-page
> Word document with 6 images = 6 API calls, regardless of page count.
>
> ℹ️ **EMF/WMF images**: Windows metafile format (common in older Word documents)
> is not supported by Pillow. These images are skipped with a warning. Convert the
> document to DOCX with a modern Word version to re-embed images as PNG/JPEG.


## Phase 2.5 — Cross-reference pass (hybrid mode only)

After all image descriptions have been obtained from Claude (Phase 2), and **before**
assembling the final Markdown output, the hybrid script runs an automatic cross-reference
pass at no extra API cost. This pass links identifiers visible in images to their
occurrences in the surrounding paragraph text.

The mechanism is identical to `chorus-pdf` Phase 2.5, adapted for Word:

- `page_texts` → `block_texts` (paragraph text blocks indexed by sequential block position)
- `page_num` / `p.N` → `block_idx` / `§ N`
- There is no page-level segmentation — the document is treated as a single linear sequence

### 2.5.1 — Collect identifiers from figures

For each `[FIGURE N]` block, parse the `IDENTIFIERS: [...]` JSON line appended by
Claude. Filtering rules (see `parse_identifiers()`):
- Remove entries in `_XREF_STOPWORDS`
- Remove entries shorter than `_XREF_MIN_LEN = 2`
- De-duplicate case-insensitively
- Fallback regex if `IDENTIFIERS:` line is absent or malformed

### 2.5.2 — Search text occurrences

`find_text_occurrences()` searches all `block_texts` using `\bIDENTIFIER\b`.
For each matching block, a ≤ 120-char snippet centred on the match is recorded
along with its block index (§ N).

### 2.5.3 — Annotate figure descriptions

A `[XREF FIGURE N]` block is appended immediately after each `[END FIGURE N]` marker:

```
[XREF FIGURE 3]
  M-001:
    § 14: …The member M-001 shall be designed for…
    § 27: …see M-001 in the elevation detail…
  Z-A2:
    (no occurrence found in text)
[END XREF FIGURE 3]
```

### 2.5.4 — Append global XREF INDEX

After all content blocks, a global index is appended at the end of the `-vision.md` file:

```
=== XREF INDEX ===
# Cross-reference: identifiers found in figures → text occurrences

## M-001
   Appears in: Figure 3
   Text occurrence (§ 14): …The member M-001 shall be designed for…
   Text occurrence (§ 22): …load path through M-001 and M-002…

## Z-A2
   Appears in: Figure 3
   Text occurrence: (none found)

=== END XREF INDEX ===
```

### 2.5 — Output format summary

| Section | Location in output | Purpose |
|---|---|---|
| `[XREF FIGURE N]` block | Inline, after each `[END FIGURE N]` | Local annotation — kept with the figure for `chorus-feed` |
| `=== XREF INDEX ===` | End of file | Global map — all identifiers with all occurrences |

> ⚠️ **Hybrid mode only** — the cross-reference pass requires both the paragraph text
> blocks and the Claude image descriptions to be available simultaneously.


## Phase 3 — Execute and validate

### 3.1 Execute the script

```bash
python3 "$SANDBOX/agent/extract-word-<slug>.py"
```

Capture stderr for progress reporting. Exit code 0 = success. Exit code 2 = nohup required.

### 3.2 Validate the output

```bash
python3 - "$SANDBOX/corpus/<NNN>-<slug>-vision.md" <<'EOF'
import sys, re

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
figures      = re.findall(r'\[FIGURE', text)
tables       = re.findall(r'^\|', text, re.MULTILINE)
placeholders = text.count('not extracted')
xref_local   = re.findall(r'\[XREF FIGURE', text)
xref_index   = 1 if '=== XREF INDEX ===' in text else 0
headers      = re.findall(r'\[HEADER:', text)
footers      = re.findall(r'\[FOOTER:', text)

print(f"Figures found    : {len(figures)}")
print(f"XREF annotations : {len(xref_local)}  (inline, hybrid mode)")
print(f"XREF INDEX       : {'present' if xref_index else 'absent'}")
print(f"Table rows       : {len(tables)}")
print(f"Placeholders     : {placeholders}")
print(f"Header blocks    : {len(headers)}")
print(f"Footer blocks    : {len(footers)}")
print(f"Total chars      : {len(text)}")
if len(text) < 200:
    print("⚠️  WARNING: output is suspiciously short")
if placeholders > 0:
    print(f"ℹ️  {placeholders} image(s) not extracted — check ANTHROPIC_API_KEY for hybrid mode")
if len(figures) > 0 and len(xref_local) == 0:
    print("ℹ️  Figures found but no XREF annotations — check IDENTIFIERS: lines in figure descriptions")
EOF
```

Report the sanity check results to the user before proceeding.

### 3.3 Failure handling

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| `python-docx` ImportError | Missing dependency | `pip install python-docx` |
| `Pillow` ImportError | Missing dependency (hybrid) | `pip install Pillow` |
| `ANTHROPIC_API_KEY not set` | Missing env var | `export ANTHROPIC_API_KEY="sk-ant-..."` |
| HTTP 429 / 529 | API rate limit / overload | Retry handled automatically (exponential backoff) |
| EMF/WMF images skipped | Old Word document format | Re-save the DOCX with a modern Word version |
| Output < 200 chars | DOCX is empty or encrypted | Check the file is a valid .docx (unzip it manually to inspect) |
| Tables appear garbled | Merged cells not deduplicated | Check `table_to_markdown` — increase deduplication tolerance |
| Images described but values wrong | Small/complex diagram | No DPI control for Word images — check source image resolution in the DOCX |
| `blob not found` warning | Image relationship broken | The DOCX has a dangling rId — re-save the document from Word |
| Script exited with code 2 | ≥ 16 images detected | Run via nohup with `CHORUS_WORD_FORCE=1` (see Phase 1.5) |


## Phase 4 — Update sandbox metadata

### 4.1 Update `README.org`

Add a row for the new file in the `Corpus` table:

```org
| <NNN> | corpus/<NNN>-<slug>-text.txt    | python-docx from <source.docx>                   | <date> |
| <NNN> | corpus/<NNN>-<slug>-vision.md   | hybrid(python-docx+Claude vision) from <source>  | <date> |
```

Do **not** remove the row for the original DOCX or any prior file — all versions are
kept for traceability.

### 4.2 Report to the user

```
✅ chorus-word completed
   Mode     : text  (or: hybrid — Claude vision on images)
   Source   : corpus/<source.docx>
   Output   : corpus/<NNN>-<slug>-text.txt   (or: -vision.md)
   Paragraphs: <N>
   Tables   : <N>
   Images   : <N> described (hybrid)  /  <N> placeholders (text)
   XREF     : <N> identifier(s) cross-referenced across <N> figure(s)  [hybrid only]
   Size     : <N> chars

   Next step: chorus-feed <sandbox-name> corpus/<NNN>-<slug>-text.txt
              (or: corpus/<NNN>-<slug>-vision.md)
```


## Integration with chorus-feed

`chorus-word` is a **pre-processing step**, not a replacement for `chorus-feed`.
Typical workflow:

```
# No API key — text mode fallback
chorus-word  <sandbox> corpus/002-cctp-structure.docx
→ corpus/003-cctp-structure-text.txt

# API key available — hybrid mode activated automatically
chorus-word  <sandbox> corpus/002-cctp-structure.docx
→ corpus/003-cctp-structure-vision.md

# Batch: process all DOCX files in corpus/
chorus-word  <sandbox> --batch
→ corpus/003-cctp-structure-vision.md
→ corpus/004-note-de-calcul-vision.md
→ ...

# Then in all cases:
chorus-feed <sandbox> corpus/003-cctp-structure-text.txt
            (or: corpus/003-cctp-structure-vision.md)
```


## Dependencies

| Package | Install | Mode |
|---------|---------|------|
| `python-docx` | `pip install python-docx` | Both (mandatory) |
| `Pillow` | `pip install Pillow` | Hybrid (image conversion) |
| `ANTHROPIC_API_KEY` | `export ANTHROPIC_API_KEY="sk-ant-..."` | Hybrid |

> ℹ️ No external binary is required (`pdftoppm` is not needed for Word documents).
> `python-docx` reads the DOCX XML directly without any native dependency.


## Quick Reference — Naming Conventions

| Artifact | Convention | Example |
|----------|-----------|---------|
| Extraction script | `agent/extract-word-<slug>.py` | `agent/extract-word-cctp-structure.py` |
| Text mode output | `corpus/<NNN>-<slug>-text.txt` | `corpus/003-cctp-structure-text.txt` |
| Hybrid output | `corpus/<NNN>-<slug>-vision.md` | `corpus/003-cctp-structure-vision.md` |
| Original DOCX | kept as-is in `corpus/` | `corpus/002-cctp-structure.docx` |


## Troubleshooting

**"Tables appear as garbled text or duplicated columns"**
→ The document likely uses horizontally merged cells. `table_to_markdown` handles
  this via unique `_tc` element tracking. If the issue persists, inspect the DOCX
  XML: `unzip doc.docx word/document.xml -d /tmp/docx && xmllint --format /tmp/docx/word/document.xml | grep '<w:tc'`

**"Images are skipped as EMF/WMF"**
→ Very common in Word documents generated by older versions of Office or LibreOffice.
  Open the document in Microsoft Word 365 or LibreOffice Writer, then `File > Save As…`
  (same format) to let the application re-embed images as modern PNG/JPEG.

**"The output is identical to a simple `python-docx` text dump"**
→ If no images are present and all tables are simple, the output is indeed equivalent
  to naive extraction. The value of chorus-word shows when images or merged-cell tables
  are present. For text-only Word documents, the result is correct and complete.

**"No images extracted even though the document visually has figures"**
→ Some images are in text boxes (`<w:txbxContent>`) or drawing canvases (`<wps:wsp>`)
  rather than inline shapes. The current `iter_block_items` covers inline blip references.
  Check with: `unzip doc.docx word/document.xml -d /tmp && grep -c 'a:blip' /tmp/word/document.xml`
  If count is 0 but images exist visually, they may be linked (not embedded) or in
  a drawing layer. Use `--batch` after converting to PDF via LibreOffice as a fallback.

**"Script exited with code 2 — nohup required"**
→ The document has ≥ 16 embedded images. The script aborted before any API call.
  Copy the `nohup` command printed to stderr and run it in a terminal:
  ```bash
  CHORUS_WORD_FORCE=1 nohup python3 $SANDBOX/agent/extract-word-<slug>.py \
    > $SANDBOX/corpus/<NNN>-<slug>-vision.md.log 2>&1 &
  tail -f $SANDBOX/corpus/<NNN>-<slug>-vision.md.log
  ```

**"XREF annotations are present but XREF INDEX is empty"**
→ All identifiers extracted from figures were filtered by `_XREF_STOPWORDS` or
  `_XREF_MIN_LEN`. Inspect the `IDENTIFIERS: [...]` lines in the raw output. If the
  identifiers are valid, add them to a project-specific whitelist by removing them from
  `_XREF_STOPWORDS` in the generated script.

**"Hybrid mode is slow on a document with many small icons"**
→ Icons and decorative bullets are often embedded as tiny PNG images and consume one
  API call each. Add a size filter in `iter_block_items` to skip images smaller than
  a threshold (e.g., < 5 KB):
  ```python
  if img_part.blob and len(img_part.blob) > 5000:
      yield ('image', (img_counter[0], img_part.blob))
  ```
  Adjust the threshold based on the document's icon sizes.
