#!/usr/bin/env python3
"""
org2pdf.py — Convert an Org-mode file to PDF.

Usage:
    python3 org2pdf.py <input.org> <output.pdf>

Dependencies (same venv as md2pdf.py):
    pip install weasyprint

Handles the same org-mode constructs as org2html.py.
CSS is tuned for print (compact fonts, @page margins),
consistent with md2pdf.py.
"""

import sys
import re
import html as _html
from weasyprint import HTML

# ── CSS (print-optimised, consistent with md2pdf.py) ─────────────────────
CSS = """
@page   { margin: 1cm 1cm 2cm 1cm; }
body    { font-family: DejaVu Sans, sans-serif; font-size: 11px;
          line-height: 1.4; margin: 0; color: #222; }
h1      { font-size: 18px; border-bottom: 2px solid #333; padding-bottom: 4px;
          margin-bottom: 3px; }
h2      { font-size: 15px; border-bottom: 1px solid #999; padding-bottom: 2px;
          margin-top: 20px; }
h3      { font-size: 13px; margin-top: 16px; color: #333; }
h4      { font-size: 12px; margin-top: 12px; color: #444;
          padding-left: 8px; border-left: 2px solid #ccc; }
h5      { font-size: 11px; margin-top: 10px; color: #555; }
p       { margin: 6px 0; }
table   { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 10px; }
th, td  { border: 1px solid #ccc; padding: 4px 6px; text-align: left; }
th      { background-color: #eee; font-weight: 600; }
code    { font-family: DejaVu Sans Mono, monospace; font-size: 9.5px;
          background: #f4f4f4; padding: 1px 3px; }
pre     { background: #f8f8f8; border: 1px solid #ddd; border-radius: 4px;
          padding: 6px 10px; font-size: 9px;
          font-family: DejaVu Sans Mono, monospace; white-space: pre-wrap; }
pre code { background: none; padding: 0; font-size: 9px; }
pre.org-example { border-style: dashed; }
blockquote { border-left: 3px solid #888; margin: 8px 0; padding: 3px 10px;
             color: #555; background: #f8f8f8; }
ul, ol  { padding-left: 18px; margin: 6px 0; }
li      { margin: 2px 0; }
.org-meta { font-family: DejaVu Sans Mono, monospace; font-size: 9px; color: #666;
            background: #f5f5f5; border: 1px solid #e0e0e0;
            padding: 3px 10px; margin: 3px 0 14px; }
"""

# ── Inline markup ─────────────────────────────────────────────────────────

def _esc(s):
    return _html.escape(s)

def _inline(s):
    r = _esc(s)
    r = re.sub(r'~([^~\n]{1,100})~', r'<code>\1</code>', r)
    r = re.sub(r'=([^=\n]{1,100})=', r'<code>\1</code>', r)
    r = re.sub(r'(^|[\s(])\*([^*\n]{1,120})\*(?=[\s),.]|$)',
               r'\1<strong>\2</strong>', r, flags=re.MULTILINE)
    r = re.sub(r'(^|[\s(])\/([^/\n]{1,80})\/(?=[\s),.]|$)',
               r'\1<em>\2</em>', r, flags=re.MULTILINE)
    return r

# ── Table ─────────────────────────────────────────────────────────────────

def _is_sep(line):
    return (bool(re.match(r'^\s*\|[-+| \t]+\|\s*$', line))
            and not re.search(r'[^|\-+ \t]', line))

def _table(lines):
    def row(line, tag):
        cells = [c.strip() for c in line.split('|')[1:-1]]
        return '<tr>' + ''.join(f'<{tag}>{_inline(c)}</{tag}>' for c in cells) + '</tr>'

    sep_i = next((i for i, l in enumerate(lines) if _is_sep(l)), -1)
    if sep_i < 1:
        data = [l for l in lines if not _is_sep(l)]
        return '<table>' + ''.join(row(l, 'td') for l in data) + '</table>'

    heads = [l for l in lines[:sep_i]   if not _is_sep(l)]
    body  = [l for l in lines[sep_i+1:] if not _is_sep(l)]
    return ('<table>'
            + '<thead>' + ''.join(row(l, 'th') for l in heads) + '</thead>'
            + '<tbody>' + ''.join(row(l, 'td') for l in body)  + '</tbody>'
            + '</table>')

# ── Main renderer ─────────────────────────────────────────────────────────

def render(src):
    lines = src.split('\n')
    out   = []
    i     = 0

    meta = {}
    while i < len(lines) and re.match(r'^#\+\w', lines[i]):
        m = re.match(r'^#\+(\w+):\s*(.*)', lines[i])
        if m and not re.match(r'^(BEGIN|END)_', m.group(1), re.I):
            meta[m.group(1).upper()] = m.group(2).strip()
        i += 1

    if 'TITLE' in meta:
        out.append(f'<h1>{_esc(meta["TITLE"])}</h1>')
    bits = []
    if 'DATE'    in meta: bits.append(f'📅 {_esc(meta["DATE"])}')
    if 'SANDBOX' in meta: bits.append(f'🗂 {_esc(meta["SANDBOX"])}')
    if 'CONTEXT' in meta: bits.append(f'🏢 {_esc(meta["CONTEXT"])}')
    if bits:
        out.append('<div class="org-meta">'
                   + '&emsp;·&emsp;'.join(bits)
                   + '</div>')

    para = []

    def flush():
        txt = '\n'.join(para).strip()
        if txt:
            out.append(f'<p>{_inline(txt)}</p>')
        para.clear()

    while i < len(lines):
        line = lines[i]

        if re.match(r'^#\+\w+:', line) and not re.match(r'^#\+(BEGIN|END)_', line, re.I):
            i += 1; continue

        bm = re.match(r'^#\+BEGIN_(\w+)', line, re.I)
        if bm:
            flush()
            kind  = bm.group(1).upper()
            block = []
            i += 1
            while i < len(lines) and not re.match(r'^#\+END_', lines[i], re.I):
                block.append(lines[i]); i += 1
            i += 1
            raw = '\n'.join(block).strip('\n')
            if   kind == 'SRC':   out.append(f'<pre><code>{_esc(raw)}</code></pre>')
            elif kind == 'QUOTE': out.append(f'<blockquote>{_inline(raw)}</blockquote>')
            else:                 out.append(f'<pre class="org-example">{_esc(raw)}</pre>')
            continue

        hm = re.match(r'^(\*+) +(.*)', line)
        if hm:
            flush()
            lvl = min(len(hm.group(1)) + 1, 5)
            out.append(f'<h{lvl}>{_inline(hm.group(2))}</h{lvl}>')
            i += 1; continue

        if re.match(r'^\s*\|', line):
            flush()
            t = []
            while i < len(lines) and re.match(r'^\s*\|', lines[i]):
                t.append(lines[i]); i += 1
            out.append(_table(t))
            continue

        if re.match(r'^[ \t]*[-+] ', line):
            flush()
            items = []
            while i < len(lines) and re.match(r'^[ \t]*[-+] ', lines[i]):
                items.append(re.sub(r'^[ \t]*[-+] ', '', lines[i])); i += 1
            out.append('<ul>' + ''.join(f'<li>{_inline(t)}</li>' for t in items) + '</ul>')
            continue

        if re.match(r'^[ \t]*\d+\. ', line):
            flush()
            items = []
            while i < len(lines) and re.match(r'^[ \t]*\d+\. ', lines[i]):
                items.append(re.sub(r'^[ \t]*\d+\. ', '', lines[i])); i += 1
            out.append('<ol>' + ''.join(f'<li>{_inline(t)}</li>' for t in items) + '</ol>')
            continue

        if not line.strip():
            flush(); i += 1; continue

        para.append(line)
        i += 1

    flush()
    return '\n'.join(out)

# ── Entry point ───────────────────────────────────────────────────────────

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 org2pdf.py <input.org> <output.pdf>", file=sys.stderr)
        sys.exit(1)

    org_path, pdf_path = sys.argv[1], sys.argv[2]
    with open(org_path, encoding='utf-8') as f:
        text = f.read()

    html_body = render(text)
    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>{CSS}</style>
</head><body>{html_body}</body></html>"""

    HTML(string=html, base_url='.').write_pdf(pdf_path)
    print(f"OK -> {pdf_path}")

if __name__ == "__main__":
    main()
