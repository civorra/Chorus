#!/usr/bin/env python3
"""
chorus-pdf extraction script — text mode (default, no ANTHROPIC_API_KEY)
Generated per the chorus-pdf skill "Script template — Text mode".
Sandbox : t/fixtures (regression test fixture, not a real sandbox)
Source  : t/fixtures/chorus-pdf-regression-test.pdf  (resolved via __file__)
Output  : t/fixtures/chorus-pdf-regression-test-text.md  (resolved via __file__)
"""

import sys
import os

# --- pdfplumber interpreter bootstrap ---
try:
    import pdfplumber as _chk; del _chk
except ImportError:
    _pipx_py = os.path.expanduser("~/.local/share/pipx/venvs/pdfplumber/bin/python3")
    if os.path.exists(_pipx_py) and sys.executable != _pipx_py:
        os.execv(_pipx_py, [_pipx_py] + sys.argv)

def _log_environment():
    import importlib.metadata as _ilmd
    parts = []
    for pkg in ("pdfminer.six", "pdfplumber"):
        try:
            parts.append(f"{pkg}=={_ilmd.version(pkg)}")
        except _ilmd.PackageNotFoundError:
            parts.append(f"{pkg}==<not installed>")
    print(f"[chorus-pdf] Environment: {', '.join(parts)} (interpreter: {sys.executable})",
          file=sys.stderr)

_log_environment()

import pathlib as _pathlib
_HERE = _pathlib.Path(__file__).parent.resolve()
PDF_PATH    = str(_HERE / "chorus-pdf-regression-test.pdf")
OUTPUT_PATH = str(_HERE / "chorus-pdf-regression-test-text.md")

FIGURE_PLACEHOLDER = (
    "[FIGURE — not extracted]\n"
    "[Run chorus-pdf with --hybrid, --auto or --images to extract figures via LLM vision]"
)


def analyse_pages(pdf_path):
    try:
        from pdfminer.high_level import extract_pages
        from pdfminer.layout import LAParams, LTTextBox, LTFigure, LTCurve
    except ImportError:
        print("⛔ pdfminer.six not installed. Run: pip install pdfminer.six", file=sys.stderr)
        sys.exit(1)
    laparams = LAParams(
        line_overlap=0.5, char_margin=2.0, line_margin=0.5,
        word_margin=0.1, boxes_flow=0.5, detect_vertical=False, all_texts=False
    )
    result = {}
    for page_num, layout in enumerate(extract_pages(pdf_path, laparams=laparams), 1):
        texts, figures, curves = [], [], []
        for el in layout:
            if isinstance(el, LTTextBox):
                t = el.get_text().strip()
                if t:
                    texts.append((t, (el.y0 + el.y1) / 2, el.x0, el.x1))
            elif isinstance(el, LTFigure):
                figures.append((el.x0, el.y0, el.x1, el.y1))
            elif isinstance(el, LTCurve):
                curves.append(el)

        h_lines = [c for c in curves if (c.y1 - c.y0) < 3 and (c.x1 - c.x0) > 50]
        v_lines = [c for c in curves if (c.x1 - c.x0) < 3 and (c.y1 - c.y0) > 30]

        _has_table = False
        if len(h_lines) >= 2 and len(v_lines) >= 2:
            for base in h_lines:
                aligned = [h for h in h_lines
                           if abs(h.x0 - base.x0) <= 10 and abs(h.x1 - base.x1) <= 10]
                if len(aligned) >= 2:
                    aligned_sorted = sorted(aligned, key=lambda h: h.y0)
                    min_spacing = min(aligned_sorted[i+1].y0 - aligned_sorted[i].y1
                                     for i in range(len(aligned_sorted) - 1))
                    if min_spacing >= 3:
                        h_x_span = (min(h.x0 for h in aligned), max(h.x1 for h in aligned))
                        v_crossing = [v for v in v_lines
                                     if h_x_span[0] - 5 <= (v.x0 + v.x1) / 2 <= h_x_span[1] + 5]
                        if len(v_crossing) >= 2:
                            _has_table = True
                            break

        result[page_num] = {
            'texts':     texts,
            'figures':   figures,
            'height':    layout.height,
            'has_table': _has_table,
        }
    return result


def detect_table_columns(page):
    edges   = page.edges
    v_edges = [e for e in edges if e['orientation'] == 'v' and e['height'] > 30]
    h_edges = [e for e in edges if e['orientation'] == 'h' and e['width']  > 50]

    if len(h_edges) < 2 or len(v_edges) < 1:
        return None

    xs = sorted(set(e['x0'] for e in v_edges))
    clustered = []
    for x in xs:
        if not clustered or x - clustered[-1] > 3:
            clustered.append(x)

    widest = max(h_edges, key=lambda e: e['width'])
    all_xs = sorted(set([widest['x0']] + clustered + [widest['x1']]))

    return all_xs if len(all_xs) >= 2 else None


def extract_tables_from_page(page):
    col_xs = detect_table_columns(page)

    def cell(c):
        return str(c or "").replace("\n", " ").replace("|", "｜").strip()

    def quality_check(rows):
        if not rows or not any(any(c for c in row) for row in rows):
            return False

        total_cells = sum(len(row) for row in rows)
        empty_cells = sum(1 for row in rows for c in row if not str(c or "").strip())

        if len(rows[0]) == 1:
            long_texts = sum(1 for row in rows for c in row
                            if c and len(str(c).strip()) > 100)
            if total_cells > 0 and long_texts / total_cells > 0.30:
                return False

        if total_cells > 0 and empty_cells / total_cells > 0.55:
            return False

        non_empty_cells = [str(c or "").strip() for row in rows for c in row
                           if str(c or "").strip()]
        if non_empty_cells:
            fragments = sum(1 for t in non_empty_cells
                            if len(t) < 20 and t and t[0].islower())
            if fragments / len(non_empty_cells) > 0.30:
                return False

        return True

    tables_out = []
    try:
        if col_xs:
            settings = {
                "vertical_strategy": "explicit",
                "explicit_vertical_lines": col_xs,
                "horizontal_strategy": "lines",
                "snap_tolerance": 3,
            }
        else:
            settings = {}
        found_tables = page.find_tables(table_settings=settings) if settings else page.find_tables()
        for t in found_tables:
            rows = t.extract()
            if not quality_check(rows):
                continue
            header = rows[0]
            md_lines = ["| " + " | ".join(cell(c) for c in header) + " |"]
            md_lines.append("| " + " | ".join(["---"] * len(header)) + " |")
            for row in rows[1:]:
                md_lines.append("| " + " | ".join(cell(c) for c in row) + " |")
            md = "\n".join(md_lines)
            tables_out.append((t.bbox, md))
    except Exception as e:
        print(f"[chorus-pdf] ⚠️ table extraction failed on a page: {e}", file=sys.stderr)

    return tables_out


def detect_and_tag_formulas(text):
    import re

    MATH_SYMBOLS = re.compile(r'[≥≤⊕√∑∏²³ℓλσ±×÷≈≠∈∉⊂⊃∀∃∞]')
    FUNC_NOTATION = re.compile(r'\b[A-Zℓλσ][A-Za-z0-9]{0,4}\([^()]{1,40},[^()]{0,40}\)')
    EXPONENT_CONTEXT = re.compile(
        r'(?i)\b(bits?|calculs?|op[ée]rations?|complexit[ée]s?|collisions?|operations?|complexity)\b'
    )
    EXPONENT_PATTERN = re.compile(r'\b2\d{2,3}\b')

    def tag_line(line):
        tags = []

        if FUNC_NOTATION.search(line):
            tags.append("functional notation")
        if MATH_SYMBOLS.search(line):
            tags.append("math symbol")
        if EXPONENT_PATTERN.search(line) and EXPONENT_CONTEXT.search(line):
            tags.append("ambiguous exponent")

        if not tags:
            return line

        latex_hint = ""
        m = re.search(r'(\w)([²³])', line)
        if m:
            base, exp = m.group(1), m.group(2)
            power = {"²": "2", "³": "3"}[exp]
            latex_hint = f" — best-effort LaTeX: {base}^{power}"

        reason = ", ".join(tags)
        return f"{line}\n[FORMULA: pattern detected ({reason}){latex_hint} — verify against source]"

    return "\n".join(tag_line(line) for line in text.split("\n"))


def main():
    try:
        import pdfplumber as pdfplumber_mod
        HAS_PDFPLUMBER = True
    except ImportError:
        HAS_PDFPLUMBER = False
        print("[chorus-pdf] ⚠️  pdfplumber not available — vector tables will not be reconstructed",
              file=sys.stderr)

    print(f"[chorus-pdf] Text mode — {PDF_PATH}", file=sys.stderr)
    page_data = analyse_pages(PDF_PATH)
    plumber_pdf = pdfplumber_mod.open(PDF_PATH) if HAS_PDFPLUMBER else None

    parts = []
    parts.append(f"# ORIGINAL: {PDF_PATH}")
    fig_pages   = 0
    total_tables = 0

    for page_num in sorted(page_data):
        pdata = page_data[page_num]
        blocks, has_figure, has_table, page_height = \
            pdata['texts'], bool(pdata['figures']), pdata['has_table'], pdata['height']
        elements = []

        table_bboxes = []
        if plumber_pdf and has_table:
            table_entries = extract_tables_from_page(plumber_pdf.pages[page_num - 1])
            for (tx0, t_top, tx1, t_bottom), md in table_entries:
                y_min = page_height - t_bottom
                y_max = page_height - t_top
                y_c   = (y_min + y_max) / 2
                table_bboxes.append((tx0, y_min, tx1, y_max))
                elements.append((y_c, md))
                total_tables += 1

        for (text, y_center, x0, x1) in blocks:
            x_center = (x0 + x1) / 2
            in_table = any(
                tb_x0 - 5 <= x_center <= tb_x1 + 5 and tb_y_min <= y_center <= tb_y_max
                for (tb_x0, tb_y_min, tb_x1, tb_y_max) in table_bboxes
            )
            if in_table:
                continue
            elements.append((y_center, text))

        if has_figure:
            elements.append((0, FIGURE_PLACEHOLDER))
            fig_pages += 1

        elements.sort(key=lambda e: e[0], reverse=True)
        body = "\n\n".join(c for (_, c) in elements)
        parts.append(f"=== PAGE {page_num} ===\n{body}\n=== END PAGE {page_num} ===")

    if plumber_pdf:
        plumber_pdf.close()

    if HAS_PDFPLUMBER and total_tables:
        print(f"[chorus-pdf] Table reconstruction: pdfplumber active ({total_tables} table(s) reconstructed)",
              file=sys.stderr)
    elif not HAS_PDFPLUMBER:
        print("[chorus-pdf] ⚠️  Table reconstruction skipped: pdfplumber unavailable — "
              "tables flattened to plain text (fallback, degraded output)",
              file=sys.stderr)

    final_text = "\n\n".join(parts)
    final_text = detect_and_tag_formulas(final_text)
    n_formulas = final_text.count("[FORMULA:")

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write(final_text)

    if n_formulas:
        print(f"[chorus-pdf]    {n_formulas} formula pattern(s) tagged [FORMULA: ...] — see § Formula strategy",
              file=sys.stderr)

    print(f"[chorus-pdf] ✅ {len(page_data)} pages extracted, {total_tables} table(s)", file=sys.stderr)
    if fig_pages:
        print(f"[chorus-pdf]    {fig_pages} page(s) contain figures — use --hybrid or --auto to extract them",
              file=sys.stderr)
    print(f"[chorus-pdf] Written to {OUTPUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
