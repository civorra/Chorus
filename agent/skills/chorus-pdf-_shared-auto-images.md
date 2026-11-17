> **Sub-skill of `chorus-pdf` — shared utilities for Auto & Images modes (ENG-042)**
> Loaded via `eca__read_file` from `chorus-pdf-core.md` for `--auto` and `--images`.

---

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


### Shared utility — Auto & Images modes

> ⚠️ **`pdftoppm` required** (Auto & Images): `sudo apt install poppler-utils`
> ⚠️ **API key** (Auto & Images): `export ANTHROPIC_API_KEY="sk-ant-..."`

```python
def image_to_b64(path):
    with open(path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")
```

