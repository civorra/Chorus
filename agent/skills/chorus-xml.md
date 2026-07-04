# Skill — chorus-xml

> Trigger: `chorus-xml <sandbox-name> <file.xml|.html|.htm> [--out <slug>] [--batch] [--strip-boilerplate|--no-strip-boilerplate]`
> Agent: `architect`
>
> `<sandbox-name>`: name of the sandbox directory under `$SANDBOXES/`
> `<file.xml|.html|.htm>`: path to the XML or HTML document — absolute, or relative to `$SANDBOX/corpus/`
> `--out <slug>`: override the output filename stem (default: derived from input filename)
> `--batch`: process all `*.xml`, `*.html`, `*.htm` files found in `$SANDBOX/corpus/`
> `--strip-boilerplate` / `--no-strip-boilerplate`: force boilerplate removal on/off
>              (default: **on** when mode = HTML, **off** when mode = XML)
>
> **Single responsibility: produce an enriched Markdown file from an XML or HTML document.**
> Extracts text, tables, lists and embedded images while preserving document structure
> and reading order via the native DOM tree. One skill covers both formats because HTML
> is itself a tag tree (SGML/XML-derived) — only the parser and the boilerplate-cleaning
> phase differ between the two modes.
>
> Output format is always **Markdown** (`.md`), regardless of API availability.
> The suffix distinguishes the image treatment:
> - Hybrid mode (default when API key available): `corpus/<NNN>-<slug>-vision.md` — DOM text + Claude vision on images
> - Text mode (fallback — no API key): `corpus/<NNN>-<slug>-content.md` — DOM text + image placeholders
>
> This skill must be run **before** `chorus-import-project` when the corpus contains
> `.xml`/`.html`/`.htm` files. `chorus-feed` then takes the output file as its corpus input.

---

## ⛔ Strict sandbox isolation

Never read any KB, YAML, or artifact from a sandbox other than `<sandbox-name>`.
This skill operates exclusively on the `corpus/` directory of the target sandbox.

---

## ⛔ XXE — mandatory security guard

**XML parsing must never resolve external entities or fetch remote DTDs/schemas.**
A malicious or malformed XML file could otherwise cause the extraction script to read
arbitrary local files or make unwanted network calls (XXE — XML External Entity attack).

Every parser instantiation in this skill **must** disable entity resolution and network
access:

```python
from lxml import etree

parser = etree.XMLParser(
    resolve_entities=False,   # never expand external entities
    no_network=True,          # never fetch remote DTD/schema over network
    dtd_validation=False,     # never validate against (possibly remote) DTD
    load_dtd=False,           # never load the DTD at all
    huge_tree=False,          # guard against decompression-bomb style huge documents
)
```

For HTML (via BeautifulSoup + lxml backend), the same underlying `lxml.etree` parser
settings apply — BeautifulSoup's `"lxml"` and `"lxml-xml"` builders both honor a parser
instance created with `resolve_entities=False`.

> ⛔ This guard is **not optional** and must appear unmodified in every generated
> extraction script (text mode and hybrid mode).

---

## Overview

HTML and XML documents share the same underlying representation — a tree of nested
tagged elements — but differ in intent:

- **HTML**: rendering-oriented, mixed with navigational/decorative boilerplate
  (menus, scripts, ads, cookie banners) that must be stripped before extraction.
- **XML**: data-oriented, typically a clean structured export (legal text, technical
  documentation, DITA/DocBook exports, XML-based normative annexes) with little to no
  boilerplate — content should be extracted as-is.

This skill provides two extraction modes, auto-detected from the file, combined with
two API-availability modes (text / hybrid) identical in spirit to `chorus-word`.

### Format mode (auto-detected in Phase 0.0)

| Signal | Format mode |
|---|---|
| Extension `.html` / `.htm` | HTML |
| Extension `.xml` | XML |
| Content sniff: starts with `<!DOCTYPE html` or contains `<html` root tag | HTML (overrides `.xml` extension) |
| Content sniff: has `<?xml version=` declaration and no `<html>` root | XML |

### API mode (auto-detected in Phase 0.1, same logic as chorus-word)

| Mode | Flag | Engine | API key | Images | Tables | Output |
|------|------|--------|---------|--------|--------|--------|
| **Hybrid** (**default**) | *(none — auto-detected)* | DOM text + Claude vision on images | ✅ `ANTHROPIC_API_KEY` | ✅ described | ✅ Markdown pipe | `<NNN>-<slug>-vision.md` |
| **Text** (fallback) | *(none — no API key)* | DOM parsing only | ❌ not required | `[IMAGE — not extracted]` placeholder | ✅ Markdown pipe | `<NNN>-<slug>-content.md` |

---

## Phase 0.0 — Auto-detect format mode (HTML vs XML)

```python
def detect_format_mode(path):
    """Return 'html' or 'xml' based on extension + content sniff."""
    ext = path.suffix.lower()
    with open(path, encoding="utf-8", errors="replace") as f:
        head = f.read(2048).lstrip()

    looks_like_html = (
        head.lower().startswith("<!doctype html")
        or "<html" in head.lower()[:500]
    )
    if ext in (".html", ".htm") or looks_like_html:
        return "html"
    return "xml"
```

Print the detected mode to stderr:
```
[chorus-xml] Format detected: html   (source: extension .html)
[chorus-xml] Format detected: xml    (source: <?xml version= declaration, no <html> root)
```

---

## Phase 0.1 — Auto-detect API mode (no explicit flag)

Identical logic to `chorus-word` Phase 0.0:

1. Check `ANTHROPIC_API_KEY` presence — absent → text mode, skip probe.
2. If present, probe Claude with a minimal 1-token request (`claude-haiku-4-5`).
3. Decision table:

| `ANTHROPIC_API_KEY` | Probe result | Mode activated |
|---|---|---|
| absent | — | text |
| present | ✅ valid | **hybrid** |
| present | ❌ invalid (401/403) | text |
| present | ❌ unreachable | text |
| present | ⚠️ throttled (429/529) | **hybrid** |

Reuse the exact `probe_claude()` function from `chorus-word.md` Phase 0.0.2 verbatim.

---

## Phase 0.2 — Resolve inputs

### 0.2.1 Resolve the sandbox path

```
SANDBOX = $SANDBOXES/<sandbox-name>
```

Verify that `$SANDBOX/corpus/` exists. If not, abort with:
```
⛔ Sandbox '<sandbox-name>' does not exist or has no corpus/ directory.
   Create corpus/ manually or run chorus-feed first to initialize the sandbox.
```

### 0.2.2 Resolve the source path

If `<file>` is a bare filename → prepend `$SANDBOX/corpus/`.
If it is an absolute path → use as-is.
Verify the file exists and ends in `.xml`, `.html`, or `.htm` (case-insensitive).

In `--batch` mode: glob `$SANDBOX/corpus/*.xml`, `*.html`, `*.htm` (and uppercase
variants). Process each in turn.
If none found → warn and exit cleanly (not an error).

### 0.2.3 Resolve the boilerplate-stripping default

```
if --strip-boilerplate given        → strip = True
elif --no-strip-boilerplate given   → strip = False
elif format_mode == "html"          → strip = True   (default)
else                                 → strip = False   (default — XML is data, not chrome)
```

### 0.2.4 Resolve the output filename

Same numbering convention as `chorus-word`:

```
existing = glob("$SANDBOX/corpus/[0-9][0-9][0-9]-*.*")
next_num = max(leading 3-digit prefix, default 0) + 1
```

Output is always **Markdown** (`.md`). The suffix distinguishes the image treatment:

| Mode | Suffix | Extension |
|------|--------|-----------|
| Hybrid (default) | `-vision` | `.md` |
| Text (fallback) | `-content` | `.md` |

Example:
```
Input   : corpus/002-norme-nf-en-338.xml

Hybrid  : corpus/003-norme-nf-en-338-vision.md
Text    : corpus/003-norme-nf-en-338-content.md
```

Both formats are valid inputs for `chorus-feed`.

---

## Phase 1 — Document analysis

### 1.1 Parse and count elements

**HTML** (BeautifulSoup, `lxml` backend, XXE guard applied to the underlying parser):

```python
from bs4 import BeautifulSoup
from lxml import etree

def safe_lxml_parser():
    return etree.XMLParser(
        resolve_entities=False, no_network=True,
        dtd_validation=False, load_dtd=False, huge_tree=False,
    )

with open(html_path, encoding="utf-8", errors="replace") as f:
    raw = f.read()
soup = BeautifulSoup(raw, "lxml")   # BeautifulSoup's lxml builder inherits libxml2 safe defaults
```

**XML** (`lxml.etree`, explicit safe parser):

```python
from lxml import etree

parser = safe_lxml_parser()
tree = etree.parse(str(xml_path), parser)
root = tree.getroot()
```

### 1.2 Boilerplate stripping (HTML, when `strip = True`)

Remove before extraction:

```python
BOILERPLATE_TAGS = ["script", "style", "nav", "header", "footer", "aside", "noscript"]
BOILERPLATE_CLASS_PATTERN = re.compile(
    r"cookie|banner|advert|sidebar|menu|popup|modal", re.IGNORECASE
)

for tag in soup(BOILERPLATE_TAGS):
    tag.decompose()

for el in soup.find_all(class_=True):
    classes = " ".join(el.get("class", []))
    if BOILERPLATE_CLASS_PATTERN.search(classes):
        el.decompose()

for comment in soup.find_all(string=lambda s: isinstance(s, Comment)):
    comment.extract()
```

### 1.3 Reading order via the DOM tree

**The order of elements in the DOM is the canonical reading order** for both HTML
and XML — no Y-coordinate sorting needed (unlike PDF). Walk the tree depth-first,
in document order, exactly as `chorus-word` walks `doc.element.body`.

```python
def iter_block_items_html(soup):
    """Yield (kind, obj) in DOM order for HTML.

    Yields:
      ('heading', (level: int, text: str))
      ('para',    text: str)
      ('list',    (ordered: bool, items: list[str]))
      ('table',   <table> tag)
      ('image',   <img> tag)
      ('link',    (text: str, href: str))          # inline, informational only
    """
    BLOCK_TAGS = {"h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "table", "img"}
    for el in soup.find_all(BLOCK_TAGS, recursive=True):
        # skip nested duplicates (e.g. <p> inside <table> already handled by table walk)
        if el.find_parent("table") and el.name != "table":
            continue
        if el.name in ("h1", "h2", "h3", "h4", "h5", "h6"):
            level = int(el.name[1])
            yield ("heading", (level, el.get_text(strip=True)))
        elif el.name == "p":
            text = el.get_text(strip=True)
            if text:
                yield ("para", text)
        elif el.name in ("ul", "ol"):
            items = [li.get_text(strip=True) for li in el.find_all("li", recursive=False)]
            if items:
                yield ("list", (el.name == "ol", items))
        elif el.name == "table":
            yield ("table", el)
        elif el.name == "img":
            yield ("image", el)
```

```python
def iter_block_items_xml(root):
    """Generic fallback walk for XML without a recognized schema.

    Depth becomes Markdown heading level. Any element with direct text content
    (ignoring whitespace-only) yields a text block. Tables are not assumed —
    XML has no universal <table> semantics; a generic element named
    'table'/'tbl'/'informaltable' (case-insensitive, common in DocBook/DITA)
    is treated as tabular if it contains 'row'/'tr' children — otherwise
    every leaf-with-text is emitted as a paragraph.

    Yields:
      ('heading', (level: int, text: str))
      ('para',    text: str)
      ('attr',    (tag: str, attrs: dict))          # informational — id/title/xml:lang
    """
    TABLE_LIKE = {"table", "tbl", "informaltable"}
    ROW_LIKE   = {"row", "tr"}
    CELL_LIKE  = {"entry", "td", "th", "cell"}

    def walk(el, depth):
        tag = etree.QName(el).localname.lower()
        text = (el.text or "").strip()

        significant_attrs = {k: v for k, v in el.attrib.items()
                              if etree.QName(k).localname in ("id", "title", "lang")}
        if significant_attrs:
            yield ("attr", (tag, significant_attrs))

        if tag in TABLE_LIKE:
            rows = [r for r in el if etree.QName(r).localname.lower() in ROW_LIKE]
            if rows:
                yield ("table_xml", (tag, rows))
                return  # do not recurse further into a handled table

        if text:
            # depth 0-1 → treat as heading if short and no child elements; else paragraph
            if len(el) == 0 and len(text) < 120 and depth <= 3:
                yield ("heading", (min(depth + 1, 6), text))
            else:
                yield ("para", text)

        for child in el:
            yield from walk(child, depth + 1)

    yield from walk(root, 0)
```

> ⚠️ **No schema-specific support in this version.** DocBook (`<sect1>`, `<title>`,
> `<para>`), DITA (`<topic>`, `<title>`, `<p>`) and similar schemas are handled correctly
> *incidentally* by the generic fallback (their tag names happen to carry text
> naturally), but there is no dedicated schema-aware branch. If a specific normative
> XML schema needs first-class support (custom table semantics, cross-reference
> resolution, specialized metadata), extend `iter_block_items_xml` in a later revision.

### 1.4 Tables → Markdown

**HTML tables**: reuse the `chorus-word` merged-cell deduplication logic, adapted to
`<td>`/`<th>` and `colspan`/`rowspan` attributes:

```python
def html_table_to_markdown(table_tag):
    rows = table_tag.find_all("tr", recursive=True)
    grid = []
    for tr in rows:
        cells = tr.find_all(["td", "th"], recursive=False)
        row_cells = []
        for cell in cells:
            text = cell.get_text(strip=True)
            colspan = int(cell.get("colspan", 1))
            row_cells.extend([text] + [""] * (colspan - 1))  # naive colspan fill
        if row_cells:
            grid.append(row_cells)
    if not grid:
        return ""
    n_cols = max(len(r) for r in grid)
    grid = [r + [""] * (n_cols - len(r)) for r in grid]

    def cell_md(c):
        return str(c or "").replace("\n", " ").replace("|", "｜").strip()

    lines = [
        "| " + " | ".join(cell_md(c) for c in grid[0]) + " |",
        "| " + " | ".join("---" for _ in grid[0]) + " |",
    ]
    for row in grid[1:]:
        lines.append("| " + " | ".join(cell_md(c) for c in row) + " |")
    return "\n".join(lines)
```

**XML generic tables** (`table_like` rows collected in 1.3): same grid-building
approach, iterating `ROW_LIKE`/`CELL_LIKE` children instead of `tr`/`td`.

> ⚠️ **`rowspan`/`colspan` are filled naively** (value repeated/blanked, not merged
> like `chorus-word`'s `_tc` identity tracking — HTML tables don't expose a stable
> cell-identity object the way DOCX does). Acceptable for normative tables (typically
> simple grids); flag visually garbled tables to the user for manual review (see
> Troubleshooting).

### 1.5 Images

**HTML**: `<img src="...">` — three cases:
1. `src="data:image/...;base64,..."` → decode inline, no network/filesystem access needed.
2. `src="relative/or/absolute/local/path"` → resolve relative to the source file's
   directory; read from local filesystem only. **Never fetch remote URLs** (no
   `http://`/`https://` `src` is ever downloaded — treat as `[IMAGE — remote, not extracted]`).
3. `src` missing/broken → placeholder.

**XML**: no universal image convention — skip image handling for generic XML (v1).
If a schema-specific image element is encountered (e.g. DITA `<image href=...>`),
it falls through to a `[IMAGE — not extracted: unsupported XML schema]` placeholder.

---

## Phase 1.5 — nohup gate (hybrid mode only)

Identical mechanism to `chorus-word` Phase 1.5. After counting images in Phase 1.1/1.5,
apply the same threshold:

| Images detected (`n_images`) | Action |
|---:|---|
| ≤ 15 | proceed directly |
| ≥ 16 | **exit(2)** + print `nohup` command |

```
[chorus-xml]   → 22 image(s) detected — estimated time ~11–16 min (threshold: 15).
[chorus-xml] ⚠️  Run with nohup to avoid a 10-min IDE timeout:
[chorus-xml]    CHORUS_XML_FORCE=1 nohup python3 /path/to/agent/extract-xml-<slug>.py > corpus/<NNN>-<slug>-vision.md.log 2>&1 &
```

Bypass with `CHORUS_XML_FORCE=1`. Exit code 2 = "nohup required", not an error.
The agent must set `CHORUS_XML_FORCE=1` and relaunch with `nohup` — pre-approved,
no confirmation required.

---

## Phase 2 — Generate the extraction script

Create `$SANDBOX/agent/` if it does not exist.
Write `$SANDBOX/agent/extract-xml-<slug>.py`, then execute it.

Reuse the `FIGURE_PROMPT` constant verbatim from `chorus-word.md` Phase 2 for hybrid
image description.

### Script structure (both text and hybrid modes)

The generated script must:

1. Apply the XXE-safe parser configuration (mandatory, see guard above).
2. Detect format mode (HTML/XML) per Phase 0.0 logic — hardcoded at generation time
   from the resolved input, no need to re-detect at runtime.
3. Apply boilerplate stripping per the resolved `strip` flag (HTML only).
4. Walk the DOM in document order (`iter_block_items_html` or `iter_block_items_xml`).
5. **Always convert to Markdown format**:
   - Headings → `#`, `##`, …
   - Tables → Markdown pipe tables
   - Lists → `-`/`1.` Markdown lists
6. **Image treatment depends on API mode**:
   - **Text mode**: images → `[IMAGE — not extracted]` placeholder
   - **Hybrid mode**: images → Claude vision description via `FIGURE_PROMPT`, followed
     by the same Phase 2.5 cross-reference pass as `chorus-word` (identifiers in figures
     ↔ text occurrences), reusing `parse_identifiers()`, `find_text_occurrences()`,
     `xref_pass()` verbatim — with `block_texts` built from the `("para", ...)` /
     `("heading", ...)` yields instead of DOCX paragraphs.
7. Write output to `<NNN>-<slug>-content.md` (text) or `<NNN>-<slug>-vision.md` (hybrid).

> ℹ️ **Implementation note**: rather than duplicating the full ~400-line hybrid script
> from `chorus-word.md` here, the extraction script generated for `chorus-xml` **imports
> the shared Claude-vision helpers** (`convert_to_png`, `call_claude_image`, `xref_pass`,
> `parse_identifiers`, `find_text_occurrences`, `check_nohup_gate`) by copying them
> verbatim into the generated script (same approach as `chorus-word` — each generated
> script is self-contained, no shared runtime dependency). Only the DOM-walking layer
> (`iter_block_items_html` / `iter_block_items_xml`, `html_table_to_markdown`,
> boilerplate stripping) is specific to `chorus-xml`.

### IMAGE_PLACEHOLDER (text mode)

```python
IMAGE_PLACEHOLDER = (
    "[IMAGE — not extracted]\n"
    "[Run chorus-xml with ANTHROPIC_API_KEY set to extract images via hybrid mode]"
)
REMOTE_IMAGE_PLACEHOLDER = "[IMAGE — remote URL, not fetched (no network access)]"
```

---

## Phase 3 — Execute and validate

### 3.1 Execute the script

```bash
python3 "$SANDBOX/agent/extract-xml-<slug>.py"
```

Capture stderr for progress reporting. Exit code 0 = success. Exit code 2 = nohup required.

### 3.2 Validate the output

```bash
python3 - "$SANDBOX/corpus/<NNN>-<slug>-content.md" <<'EOF'
import sys, re

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
headings      = re.findall(r'^#+\s', text, re.MULTILINE)
tables        = re.findall(r'^\|', text, re.MULTILINE)
figures       = re.findall(r'\[FIGURE', text)
image_placeholders = text.count('[IMAGE')
xref_index    = 1 if '=== XREF INDEX ===' in text else 0

print(f"Headings         : {len(headings)}")
print(f"Table rows       : {len(tables)}")
print(f"Figures found    : {len(figures)}")
print(f"Image placeholders : {image_placeholders}")
print(f"XREF INDEX       : {'present' if xref_index else 'absent'}")
print(f"Total chars      : {len(text)}")
if len(text) < 200:
    print("⚠️  WARNING: output is suspiciously short")
if image_placeholders > 0:
    print(f"ℹ️  {image_placeholders} image(s) not extracted — set ANTHROPIC_API_KEY for hybrid mode")
EOF
```

Report the sanity check results to the user before proceeding.

### 3.3 Failure handling

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| `bs4`/`lxml` ImportError | Missing dependency | `pip install beautifulsoup4 lxml` |
| `Pillow` ImportError | Missing dependency (hybrid) | `pip install Pillow` |
| `ANTHROPIC_API_KEY not set` | Missing env var (hybrid) | `export ANTHROPIC_API_KEY="sk-ant-..."` |
| Output mostly boilerplate (menus/nav text) | `--strip-boilerplate` not applied or page uses non-standard chrome markup | Retry with `--strip-boilerplate`, or inspect classes manually and extend `BOILERPLATE_CLASS_PATTERN` |
| Tables garbled / columns misaligned | Nested `colspan`/`rowspan` not fully resolved (naive fill) | Inspect source table manually; consider simplifying via a pre-pass (e.g. `pandas.read_html`) if the table is critical |
| XML fallback produces flat wall of paragraphs, no headings | Schema has no short/leaf-text elements matching the heading heuristic | Acceptable for v1 (generic fallback) — manually re-tag section boundaries in the output if needed |
| `XMLSyntaxError` | Malformed XML | Validate the file: `xmllint --noout <file.xml>` |
| Local image not found | Relative `src` path broken | Verify the image file exists relative to the source document's directory |
| Remote image not fetched | By design — no network access | Download the image manually into `corpus/` and reference it locally if needed |
| Script exited with code 2 | ≥ 16 images detected | Run via nohup with `CHORUS_XML_FORCE=1` (see Phase 1.5) |

---

## Phase 4 — Update sandbox metadata

### 4.1 Update `README.org`

```org
| <NNN> | corpus/<NNN>-<slug>-content.md  | DOM extraction (html) from <source.html>          | <date> |
| <NNN> | corpus/<NNN>-<slug>-vision.md   | hybrid(DOM+Claude vision) from <source.xml>       | <date> |
```

Do **not** remove the row for the original XML/HTML file or any prior file.

### 4.2 Report to the user

```
✅ chorus-xml completed
   Format      : html  (or: xml)
   API mode    : text  (or: hybrid — Claude vision on images)
   Boilerplate : yes (or: no)
   Source      : corpus/<source.html>
   Output      : corpus/<NNN>-<slug>-content.md   (or: -vision.md)
   Headings    : <N>
   Tables      : <N>
   Images      : <N> described (hybrid) / <N> placeholders (text)
   XREF        : <N> identifier(s) cross-referenced [hybrid only]
   Size        : <N> chars
   
   ✅ Both formats are ready for chorus-feed:
      chorus-feed <sandbox-name> corpus/<NNN>-<slug>-content.md
      chorus-feed <sandbox-name> corpus/<NNN>-<slug>-vision.md
```

---

## Integration with chorus-feed

`chorus-xml` is a **pre-processing step**, not a replacement for `chorus-feed`.

```
# No API key → text mode, but always Markdown
chorus-xml <sandbox> corpus/002-norme-publiee.html
→ corpus/003-norme-publiee-content.md

# API key available → hybrid mode, Markdown with images
chorus-xml <sandbox> corpus/002-norme-publiee.html
→ corpus/003-norme-publiee-vision.md

# Batch: process all XML/HTML files in corpus/
chorus-xml <sandbox> --batch
→ corpus/003-norme-publiee-vision.md
→ corpus/004-annexe-technique-content.md
→ ...

# Both formats are valid for chorus-feed
chorus-feed <sandbox> corpus/003-norme-publiee-content.md
chorus-feed <sandbox> corpus/003-norme-publiee-vision.md
```

---

## Dependencies

| Package | Install | Mode |
|---------|---------|------|
| `beautifulsoup4` | `pip install beautifulsoup4` | HTML (mandatory) |
| `lxml` | `pip install lxml` | Both (mandatory — HTML backend + XML parser) |
| `Pillow` | `pip install Pillow` | Hybrid (image conversion, local/base64 images) |
| `ANTHROPIC_API_KEY` | `export ANTHROPIC_API_KEY="sk-ant-..."` | Hybrid |

> ℹ️ No external binary is required. Both `lxml` and `beautifulsoup4` are pure
> Python-wheel installs (lxml ships prebuilt libxml2/libxslt binaries on PyPI).

---

## Quick Reference — Naming Conventions

| Artifact | Convention | Example |
|----------|-----------|---------|
| Extraction script | `agent/extract-xml-<slug>.py` | `agent/extract-xml-norme-nf-en-338.py` |
| Text mode output | `corpus/<NNN>-<slug>-content.md` | `corpus/003-norme-nf-en-338-content.md` |
| Hybrid output | `corpus/<NNN>-<slug>-vision.md` | `corpus/003-norme-nf-en-338-vision.md` |
| Original XML/HTML | kept as-is in `corpus/` | `corpus/002-norme-nf-en-338.xml` |

---

## Troubleshooting

**"Output is full of menu links and cookie banner text"**
→ Boilerplate stripping was not applied or missed a non-standard container. Re-run
  with `--strip-boilerplate` explicitly, or inspect the page's `class`/`id` attributes
  and extend `BOILERPLATE_CLASS_PATTERN` in the generated script.

**"XML fallback output has almost no heading structure"**
→ Expected for schemas without short leaf-text elements near the root (v1 has no
  schema-specific support — see Phase 1.3 note). The content is still extracted in
  document order; only the heading-level inference is approximate. Manually annotate
  section boundaries in the output before `chorus-feed` if precise structure matters.

**"`XMLSyntaxError: Extra content at the end of the document"`**
→ The file contains multiple root-level fragments or is actually HTML with a `.xml`
  extension. Re-run and let format auto-detection reclassify it (or rename to `.html`).

**"Table columns misaligned after conversion"**
→ Nested `colspan`/`rowspan` are filled naively (unlike `chorus-word`'s stable cell
  identity tracking — HTML/XML tables expose no equivalent). For simple normative
  tables this is rarely an issue; for complex nested tables, review the Markdown
  output manually and correct before `chorus-feed`.

**"Local image referenced by the HTML is not found"**
→ The `src` path is resolved relative to the source file's own directory. If the image
  lives elsewhere (e.g. a separate `assets/` folder copied incompletely), copy the
  missing asset next to the source document, or pass an absolute path if adapting the
  script manually.
