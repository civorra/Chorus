#!/usr/bin/env python3
"""
Generate a synthetic, reproducible PDF fixture for chorus-pdf non-regression testing.

Run with the pipx 'pdfplumber' venv interpreter (which has reportlab injected):
  ~/.local/share/pipx/venvs/pdfplumber/bin/python3 generate-chorus-pdf-regression-test.py

Produces: chorus-pdf-regression-test.pdf (5 pages, one case per page):
  1. Bordered table      — real vector lines (nominal pdfplumber detection case)
  2. Borderless table    — whitespace-aligned only, no vector lines (blind spot §1.4d)
  3. Rotated header      — 90°-rotated text, one char per line visually (blind spot §1.4c)
  4. Real formula        — "2128" flattened exponent near keywords (nominal detect_and_tag_formulas() case)
  5. Known false positive — ToC-style line with 3-digit number after "operation" (regression witness for [#K])
"""
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm

OUT = "chorus-pdf-regression-test.pdf"

c = canvas.Canvas(OUT, pagesize=A4)
width, height = A4

# -------------------------------------------------------------------------
# PAGE 1 — Bordered table (real vector lines — nominal case, has_table=True)
# -------------------------------------------------------------------------
c.setFont("Helvetica-Bold", 14)
c.drawString(20 * mm, height - 20 * mm, "Case 1 — Bordered table (vector borders)")

c.setFont("Helvetica", 10)
rows = [
    ["Component", "EAL1", "EAL2", "EAL3"],
    ["ADV_ARC", "1", "1", "1"],
    ["ADV_FSP", "1", "2", "3"],
    ["ADV_TDS", "-", "1", "2"],
]
col_w = 35 * mm
row_h = 10 * mm
x0 = 25 * mm
y0 = height - 40 * mm
n_cols = len(rows[0])
n_rows = len(rows)

# draw cell text
for r, row in enumerate(rows):
    for col, text in enumerate(row):
        cx = x0 + col * col_w + 3 * mm
        cy = y0 - r * row_h - 7 * mm
        c.drawString(cx, cy, text)

# draw vector lines: horizontal
for r in range(n_rows + 1):
    y = y0 - r * row_h
    c.line(x0, y, x0 + n_cols * col_w, y)
# vertical
for col in range(n_cols + 1):
    x = x0 + col * col_w
    c.line(x, y0, x, y0 - n_rows * row_h)

c.showPage()

# -------------------------------------------------------------------------
# PAGE 2 — Borderless table (whitespace-aligned only, NO vector lines)
# -------------------------------------------------------------------------
c.setFont("Helvetica-Bold", 14)
c.drawString(20 * mm, height - 20 * mm, "Case 2 — Borderless table (no vectors)")

c.setFont("Courier", 10)
lines = [
    "Assurance family      EAL1    EAL2    EAL3    EAL4",
    "ADV_ARC                 1       1       1       1",
    "ADV_FSP                 1       2       3       4",
    "ADV_TDS                 -       1       2       3",
    "ADV_IMP                 -       -       -       1",
    "ADV_INT                 -       -       -       -",
    "ALC_CMC                 1       2       3       4",
    "ALC_CMS                 1       2       3       4",
]
y = height - 40 * mm
for ln in lines:
    c.drawString(25 * mm, y, ln)
    y -= 7 * mm
# NOTE: no c.line() calls at all on this page — purely whitespace-aligned text.

c.showPage()

# -------------------------------------------------------------------------
# PAGE 3 — Rotated 90° column header (one char per line visually after extraction)
# -------------------------------------------------------------------------
c.setFont("Helvetica-Bold", 14)
c.drawString(20 * mm, height - 20 * mm, "Case 3 — Rotated 90 degrees column header")

c.setFont("Helvetica", 9)
# Row label + one "X" mark, drawn normally
c.drawString(25 * mm, height - 60 * mm, "ADV_ARC.1")
c.drawString(55 * mm, height - 60 * mm, "X")

# Rotated column header "ADV_FSP.1" — drawn via canvas rotation (one letter
# stacked above the next, reproducing a vertically-stacked single-char column
# as described in chorus-pdf.md §1.4c)
header_text = "ADV_FSP.1"
hx = 70 * mm
hy = height - 45 * mm
c.saveState()
c.translate(hx, hy)
c.rotate(90)
c.setFont("Helvetica", 9)
c.drawString(0, 0, header_text)
c.restoreState()

c.showPage()

# -------------------------------------------------------------------------
# PAGE 4 — Real formula with flattened exponent "2128" near context keywords
# -------------------------------------------------------------------------
c.setFont("Helvetica-Bold", 14)
c.drawString(20 * mm, height - 20 * mm, "Case 4 — Real formula (flattened exponent)")

c.setFont("Helvetica", 11)
text_lines = [
    "The security level of the algorithm is estimated by the number of",
    "operations required for an exhaustive search of the key space.",
    "",
    "An attacker must perform approximately 2128 operations to achieve",
    "a collision, which exceeds the computational complexity bound",
    "acceptable for this security level (bits of entropy: 128).",
]
y = height - 50 * mm
for ln in text_lines:
    c.drawString(25 * mm, y, ln)
    y -= 7 * mm

c.showPage()

# -------------------------------------------------------------------------
# PAGE 5 — Known false positive: ToC-style line, "operation" + 3-digit number
# -------------------------------------------------------------------------
c.setFont("Helvetica-Bold", 14)
c.drawString(20 * mm, height - 20 * mm, "Case 5 — Known false positive (ToC-style)")

c.setFont("Helvetica", 11)
toc_lines = [
    "Table of Contents",
    "",
    "1. Introduction .......................................... 12",
    "2. Security Functional Requirements ..................... 87",
    "3. Cryptographic operation (FCS_COP) .................... 210",
    "4. Trusted path/channel (FTP) ........................... 245",
]
y = height - 50 * mm
for ln in toc_lines:
    c.drawString(25 * mm, y, ln)
    y -= 7 * mm

c.showPage()

c.save()
print(f"Generated {OUT}")
