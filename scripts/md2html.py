#!/usr/bin/env python3
"""
md2html.py — Convert a Markdown file to a standalone styled HTML file.

Usage:
    python3 md2html.py <input.md> <output.html>

Reuses the exact same CSS styling as md2pdf.py so the HTML and PDF versions
of a report are visually consistent.
"""
import sys
import markdown

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 md2html.py <input.md> <output.html>", file=sys.stderr)
        sys.exit(1)

    md_path, html_path = sys.argv[1], sys.argv[2]
    with open(md_path, encoding='utf-8') as f:
        text = f.read()

    html_body = markdown.markdown(text, extensions=['tables', 'fenced_code'])
    title = md_path.rsplit('/', 1)[-1]
    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{title}</title>
<style>
body {{ font-family: 'DejaVu Sans', Arial, sans-serif; font-size: 15px; line-height: 1.5;
        max-width: 960px; margin: 2em auto; padding: 0 1.5em; color: #222; }}
h1 {{ font-size: 26px; border-bottom: 2px solid #333; padding-bottom: 6px; }}
h2 {{ font-size: 20px; border-bottom: 1px solid #999; padding-bottom: 4px; margin-top: 32px; }}
h3 {{ font-size: 17px; margin-top: 24px; color: #333; }}
table {{ border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 14px; }}
th, td {{ border: 1px solid #ccc; padding: 6px 10px; text-align: left; }}
th {{ background-color: #eee; }}
code {{ background-color: #f4f4f4; padding: 1px 4px; border-radius: 3px; }}
hr {{ border: none; border-top: 1px solid #ccc; margin: 24px 0; }}
blockquote {{ border-left: 3px solid #ccc; margin-left: 0; padding-left: 1em; color: #555; }}
</style></head><body>{html_body}</body></html>"""

    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f"OK -> {html_path}")

if __name__ == "__main__":
    main()
