#!/usr/bin/env python3
"""
org2html.py — Convert an Org-mode file to a standalone styled HTML file.

Usage:
    python3 org2html.py <input.org> <output.html>

Handles:
    #+TITLE / #+SANDBOX / #+CONTEXT / #+DATE header keywords
    * ** *** **** headings  (→ h2 h3 h4 h5)
    #+BEGIN_SRC … #+END_SRC    code blocks
    #+BEGIN_QUOTE … #+END_QUOTE   blockquotes
    #+BEGIN_EXAMPLE … #+END_EXAMPLE  verbatim blocks
    | pipe | tables |  with |---|---| separator
    - / + unordered list items
    N. ordered list items
    ~inline code~  =verbatim=  *bold*  /italic/

No external dependencies — standard library only.
Designed to be visually consistent with md2html.py (same base CSS).
"""

import sys
import re
import html as _html

# ── CSS ───────────────────────────────────────────────────────────────────
CSS = """
body      { font-family: 'DejaVu Sans', Arial, sans-serif; font-size: 15px;
            line-height: 1.6; max-width: 960px; margin: 2em auto;
            padding: 0 1.5em; color: #222; }
h1        { font-size: 26px; border-bottom: 2px solid #333; padding-bottom: 6px;
            margin-bottom: 4px; }
h2        { font-size: 20px; border-bottom: 1px solid #999; padding-bottom: 4px;
            margin-top: 32px; }
h3        { font-size: 17px; margin-top: 24px; color: #333; }
h4        { font-size: 14px; margin-top: 18px; color: #444;
            padding-left: 10px; border-left: 3px solid #ccc; }
h5        { font-size: 13px; margin-top: 14px; color: #555; }
p         { margin: 8px 0; }
table     { border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 14px; }
th, td    { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
th        { background-color: #eee; font-weight: 600; }
code      { font-family: 'DejaVu Sans Mono', monospace; font-size: 13px;
            background: #f4f4f4; padding: 1px 4px; border-radius: 3px; color: #c0392b; }
pre       { background: #f8f8f8; border: 1px solid #ddd; border-radius: 6px;
            padding: 10px 14px; overflow-x: auto; font-size: 12px;
            font-family: 'DejaVu Sans Mono', monospace; }
pre code  { background: none; padding: 0; color: #444; font-size: 12px; }
pre.org-example { border-style: dashed; background: #fafafa; }
blockquote { border-left: 3px solid #888; margin: 10px 0; padding: 4px 14px;
             color: #555; background: #f8f8f8; border-radius: 0 4px 4px 0; }
ul, ol    { padding-left: 22px; margin: 8px 0; }
li        { margin: 3px 0; }
.org-meta { font-family: 'DejaVu Sans Mono', monospace; font-size: 12px; color: #666;
            background: #f5f5f5; border: 1px solid #e0e0e0; border-radius: 5px;
            padding: 5px 14px; margin: 4px 0 20px;
            display: flex; flex-wrap: wrap; gap: 4px 10px; }
"""

# ── Inline markup ─────────────────────────────────────────────────────────

def _esc(s):
    return _html.escape(s)

def _inline(s):
    """Apply org-mode inline markup to an already-html-escaped string."""
    r = _esc(s)
    # ~code~ and =verbatim=
    r = re.sub(r'~([^~\n]{1,100})~', r'<code>\1</code>', r)
    r = re.sub(r'=([^=\n]{1,100})=', r'<code>\1</code>', r)
    # *bold* — requires word boundary on both sides
    r = re.sub(r'(^|[\s(])\*([^*\n]{1,120})\*(?=[\s),.]|$)',
               r'\1<strong>\2</strong>', r, flags=re.MULTILINE)
    # /italic/
    r = re.sub(r'(^|[\s(])\/([^/\n]{1,80})\/(?=[\s),.]|$)',
               r'\1<em>\2</em>', r, flags=re.MULTILINE)
    return r

# ── Table ─────────────────────────────────────────────────────────────────

def _is_sep(line):
    """True for an org table separator row like |---|---|  or |--+--|"""
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

    heads = [l for l in lines[:sep_i]    if not _is_sep(l)]
    body  = [l for l in lines[sep_i+1:]  if not _is_sep(l)]
    return ('<table>'
            + '<thead>' + ''.join(row(l, 'th') for l in heads) + '</thead>'
            + '<tbody>' + ''.join(row(l, 'td') for l in body)  + '</tbody>'
            + '</table>')

# ── Main renderer ─────────────────────────────────────────────────────────

def render(src):
    """Convert org-mode source text to an HTML body fragment."""
    lines = src.split('\n')
    out   = []
    i     = 0

    # Collect #+KEYWORD: metadata at the top of the file
    meta = {}
    while i < len(lines) and re.match(r'^#\+\w', lines[i]):
        m = re.match(r'^#\+(\w+):\s*(.*)', lines[i])
        if m and not re.match(r'^(BEGIN|END)_', m.group(1), re.I):
            meta[m.group(1).upper()] = m.group(2).strip()
        i += 1

    # Title
    if 'TITLE' in meta:
        out.append(f'<h1>{_esc(meta["TITLE"])}</h1>')

    # Metadata bar
    bits = []
    if 'DATE'    in meta: bits.append(f'📅 {_esc(meta["DATE"])}')
    if 'SANDBOX' in meta: bits.append(f'🗂 {_esc(meta["SANDBOX"])}')
    if 'CONTEXT' in meta: bits.append(f'🏢 {_esc(meta["CONTEXT"])}')
    if bits:
        out.append('<div class="org-meta">'
                   + '&emsp;·&emsp;'.join(bits)
                   + '</div>')

    # Body — process line by line
    para = []

    def flush():
        txt = '\n'.join(para).strip()
        if txt:
            out.append(f'<p>{_inline(txt)}</p>')
        para.clear()

    while i < len(lines):
        line = lines[i]

        # Skip stray #+KEY: lines in body (not BEGIN/END)
        if re.match(r'^#\+\w+:', line) and not re.match(r'^#\+(BEGIN|END)_', line, re.I):
            i += 1
            continue

        # #+BEGIN_xxx … #+END_xxx blocks
        bm = re.match(r'^#\+BEGIN_(\w+)', line, re.I)
        if bm:
            flush()
            kind  = bm.group(1).upper()
            block = []
            i += 1
            while i < len(lines) and not re.match(r'^#\+END_', lines[i], re.I):
                block.append(lines[i])
                i += 1
            i += 1  # consume #+END_xxx
            raw = '\n'.join(block).strip('\n')
            if   kind == 'SRC':
                out.append(f'<pre><code>{_esc(raw)}</code></pre>')
            elif kind == 'QUOTE':
                out.append(f'<blockquote>{_inline(raw)}</blockquote>')
            else:  # EXAMPLE, VERSE, …
                out.append(f'<pre class="org-example">{_esc(raw)}</pre>')
            continue

        # * Headings  (level 1 → h2, level 2 → h3, …, capped at h5)
        hm = re.match(r'^(\*+) +(.*)', line)
        if hm:
            flush()
            lvl = min(len(hm.group(1)) + 1, 5)
            out.append(f'<h{lvl}>{_inline(hm.group(2))}</h{lvl}>')
            i += 1
            continue

        # Pipe tables
        if re.match(r'^\s*\|', line):
            flush()
            t = []
            while i < len(lines) and re.match(r'^\s*\|', lines[i]):
                t.append(lines[i])
                i += 1
            out.append(_table(t))
            continue

        # - / + unordered list
        if re.match(r'^[ \t]*[-+] ', line):
            flush()
            items = []
            while i < len(lines) and re.match(r'^[ \t]*[-+] ', lines[i]):
                items.append(re.sub(r'^[ \t]*[-+] ', '', lines[i]))
                i += 1
            out.append('<ul>'
                       + ''.join(f'<li>{_inline(t)}</li>' for t in items)
                       + '</ul>')
            continue

        # N. ordered list
        if re.match(r'^[ \t]*\d+\. ', line):
            flush()
            items = []
            while i < len(lines) and re.match(r'^[ \t]*\d+\. ', lines[i]):
                items.append(re.sub(r'^[ \t]*\d+\. ', '', lines[i]))
                i += 1
            out.append('<ol>'
                       + ''.join(f'<li>{_inline(t)}</li>' for t in items)
                       + '</ol>')
            continue

        # Blank line → flush accumulated paragraph
        if not line.strip():
            flush()
            i += 1
            continue

        # Regular text line — accumulate into paragraph
        para.append(line)
        i += 1

    flush()
    return '\n'.join(out)

# ── Entry point ───────────────────────────────────────────────────────────

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 org2html.py <input.org> <output.html>", file=sys.stderr)
        sys.exit(1)

    org_path, html_path = sys.argv[1], sys.argv[2]
    with open(org_path, encoding='utf-8') as f:
        text = f.read()

    title    = org_path.rsplit('/', 1)[-1]
    html_body = render(text)
    page = f"""<!DOCTYPE html>
<html lang="fr">
<head><meta charset="utf-8"><title>{_esc(title)}</title>
<style>{CSS}</style>
</head>
<body>{html_body}</body>
</html>"""

    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(page)
    print(f"OK -> {html_path}")

if __name__ == "__main__":
    main()
