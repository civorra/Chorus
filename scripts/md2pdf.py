#!/usr/bin/env python3
"""
md2pdf.py — Convert a Markdown file to PDF (tables, fenced code supported).

Usage:
    python3 md2pdf.py <input.md> <output.pdf>

Dependencies (not part of the system Python — install in a dedicated venv):
    python3 -m venv /path/to/venv
    /path/to/venv/bin/pip install markdown weasyprint

Used by chorus-check.md (--explain / --summary options) to produce PDF
copies of the generated Markdown reports, alongside chorus-pdf/chorus-word's
own PDF exports.
"""
import sys
import markdown
from weasyprint import HTML

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 md2pdf.py <input.md> <output.pdf>", file=sys.stderr)
        sys.exit(1)

    md_path, pdf_path = sys.argv[1], sys.argv[2]
    with open(md_path, encoding='utf-8') as f:
        text = f.read()

    html_body = markdown.markdown(text, extensions=['tables', 'fenced_code'])
    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
@page {{ margin: 1cm 1cm 2cm 1cm; }}
body {{ font-family: DejaVu Sans, sans-serif; font-size: 11px; line-height: 1.4; margin: 0; }}
h1 {{ font-size: 18px; border-bottom: 2px solid #333; padding-bottom: 4px; }}
h2 {{ font-size: 15px; border-bottom: 1px solid #999; padding-bottom: 2px; margin-top: 20px; }}
h3 {{ font-size: 13px; margin-top: 16px; color: #333; }}
table {{ border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 10px; }}
th, td {{ border: 1px solid #ccc; padding: 4px 6px; text-align: left; }}
th {{ background-color: #eee; }}
code {{ background-color: #f4f4f4; padding: 1px 3px; }}
hr {{ border: none; border-top: 1px solid #ccc; margin: 16px 0; }}
</style></head><body>{html_body}</body></html>"""

    HTML(string=html, base_url='.').write_pdf(pdf_path)
    print(f"OK -> {pdf_path}")

if __name__ == "__main__":
    main()
