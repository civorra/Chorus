# Skill — chorus-import-project

> Trigger: `chorus-import-project <sandbox-name> <source…> [--out <fichier.json>] [--batch] [--context <label>]`
> Agent: `code`
> ⚠️ Downgraded from `architect` to `code` (claude-sonnet-4-6 / medium) — extended thinking
> (variant: large) interacts poorly with the intra-phase keepalive protocol: the model may
> batch all thinking before emitting tool calls, nullifying the TTL resets.
> Standard thinking (`code`) iterates more tightly with tool calls → keepalive writes fire
> reliably every 50 elements (Phase 2) and every 20 terms (Phase 3).
>
> `<sandbox-name>` : sandbox containing a KB produced by `chorus-feed`
> `<source…>`      : one or more project sources from the engineer (see modes below)
>                    Accepted formats: **PDF, Word (.docx), Excel (.xlsx/.csv), XML/HTML,
>                    plain text, table pasted in the chat, or directory path**.
>                    Document files (PDF/DOCX/XLSX/CSV/XML/HTML) are automatically converted
>                    to plain text before semantic processing.
> `--out`          : output JSON filename (merge mode only; overrides the default
>                    location entirely — see "Output JSON location", Phase 5).
>                    Default when absent: `project-import-<NNN>.json`, written under
>                    `$WORKSPACE/<client>/` if this import's Scope resolves to a
>                    non-global client, or `$SANDBOX/agent/` otherwise.
> `--batch`        : force batch mode even if a single source is provided
> `--context <label>` : declares the terminology scope for this import (e.g. a client
>                    name, a project family, a business domain). Optional — manual
>                    override only. If absent, the scope is auto-derived from the
>                    source path (`$SANDBOX/$WORKSPACE/<client>/sources/...` → scope =
>                    `<client>`) or defaults to `global` otherwise (same behaviour as
>                    before this flag existed). See "Scope derivation" (Phase 1.2b)
>                    for the full three-step cascade — this addresses multi-project/
>                    multi-client sandboxes where the same term can legitimately mean
>                    different things depending on context.
>
> ### Invocation Modes
>
> | Syntax | Mode | Behavior |
> |---|---|---|
> | `chorus-import-project sb fichier.pdf` | **Single** | 1 source → 1 JSON (original behavior) |
> | `chorus-import-project sb f1.pdf f2.xlsx f3.docx` | **Merge** | N sources → 1 merged JSON (same project, complementary files) |
> | `chorus-import-project sb ./dossier/` | **Batch** | Directory → 1 JSON per file + summary report |
> | `chorus-import-project sb *.pdf --batch` | **Batch** | Explicit glob → 1 JSON per file + summary report |
> | `chorus-import-project sb fichier.pdf --align-review` | **Align-review** | Stops after Phase 3 — produces `align-review-NNN.org` for human validation before JSON |
>
> **Automatic mode detection rule:**
> - 1 non-directory source argument → Single
> - N > 1 source arguments (same or mixed formats) → Merge
> - 1 directory argument or `--batch` flag present → Batch
> - `--align-review` present → alignment review mode (compatible with Single and Merge; incompatible with `--batch`)
>
> **Single responsibility: align the engineer's project terminology with the sandbox
> KB slots and types, then produce a valid project JSON file.**
>
> Prerequisites: `chorus-feed <sandbox-name>` must have been run beforehand (org KB present).
>
> ⚠️ **KB sources to use — strict order:**
> 1. `$SANDBOX/agent/chorus/index.org` → Frame types, pipeline, namespace
> 2. `$SANDBOX/agent/chorus/<slug>.org` → sections `Ontologie`, `Dictionnaire des slots`,
>    `Catalogue des Frames` (mandatory slots, value domains)
> 3. `$WORKSPACE/import-report-*.org` existing → previous alignment decisions
>    (`$WORKSPACE` = `$SANDBOX/workspace/`, created if absent)
>
> ⛔ **Never read** `Helpers.pm`, `Feed.pm`, `Agent/*.pm` to infer slots.
> ⛔ **Never invent** a value absent from the source document — report the gap.


## Phase -0.1 — Sandbox-local extension discovery (optional)

> **Purpose:** allow a sandbox to plug in source-format-specific pre-fill logic
> (e.g. a CBOM/OID registry, a domain-specific unit-conversion table) **without
> touching this generic skill**. This core skill stays domain-agnostic — any
> sandbox-specific knowledge lives in the sandbox itself, never here.

**Before Phase 0**, check whether `$SANDBOX/skills/` exists and contains one or
more files matching `chorus-*-import.md`.

```
extensions = glob("$SANDBOX/skills/chorus-*-import.md")
```

- **No match** → proceed directly to Phase 0. No behavior change (this is the
  case for every sandbox that has no such extension — the default, unchanged path).
- **One or more matches** → read each matching file. Each extension file
  documents:
  - which source format(s) it targets (e.g. CBOM/CycloneDX JSON),
  - a pre-fill data table or reference file it provides (e.g. an OID → KB-slot
    mapping),
  - at which phase of the standard pipeline (0/2/3) its data should be
    consulted, and how (first-class candidate vs. fallback — same spirit as
    `xref_map` in the PDF/Excel/Word pipelines).
  Apply the extension's instructions **in addition to**, never instead of, the
  standard phases below — an extension only pre-fills candidate values; the
  standard Phase 3 alignment table, gap detection (Phase 4), and `_a_confirmer`
  flagging rules still apply unchanged on top of it.
- **Ambiguous match (source format not covered by any extension)** → ignore
  extensions silently, proceed with the standard pipeline.
- **Multiple matches** → apply all applicable extensions, in the ordering each
  extension file itself declares (an extension may state a dependency on
  another extension's output — e.g. "runs after a source-format extension has
  resolved `famille_probleme_math`/size slots"). If no ordering is declared by
  any of them, apply source-format extensions (those tied to a specific file
  format, e.g. CBOM/CycloneDX) before format-agnostic enrichment extensions
  (those operating on already-resolved slots, e.g. a size→security-strength
  proxy table). Never let two extensions silently overwrite the same slot for
  the same element without surfacing the conflict — if both would set the same
  slot with different values, flag the element `_a_confirmer: 1` and report
  both candidate values.

> ⛔ This skill (`chorus-import-project.md`) never hardcodes any sandbox-specific
> registry, mapping, or vocabulary. If you find yourself about to add a
> domain-specific table here (OID lists, unit tables, etc.) — stop: it belongs
> in `$SANDBOX/skills/chorus-<domain>-import.md` instead.


## Phase 0 — Source Data Acquisition

### Format Detection & Auto-conversion

**Before mode detection**, check each source file's extension (case-insensitive).
`chorus-import-project` accepts **plain text, inline data, and directories by default**.
**However**, if a document format requiring preprocessing is detected, the corresponding
conversion skill is invoked **automatically** and the extracted output replaces the input
for subsequent phases.

| Extension | Format | Auto-conversion skill | Output file(s) |
|---|---|---|---|
| `.pdf` | PDF | `chorus-pdf <sandbox> <file> --auto` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.docx` | Word | `chorus-word <sandbox> <file>` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.xlsx` / `.csv` | Spreadsheet | `chorus-excel <sandbox> <file>` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.xml` / `.html` / `.htm` | XML/HTML | `chorus-xml <sandbox> <file>` | `<NNN>-<slug>-content.md` or `-vision.md` |
| `.txt` / `.md` / inline | Plain/Markdown | *(none)* | Use as-is |

**Auto-conversion algorithm:**

> ⚠️ **`README.org` ownership — do NOT let the invoked conversion skill touch `* Corpus`.**
> `chorus-word`/`chorus-pdf`/`chorus-excel`/`chorus-xml` each have their own Phase 4.1
> ("Update `README.org`") which unconditionally appends a row to the `* Corpus` table.
> That table is reserved for **normative texts that fed `chorus-feed`** — a project
> document routed through `chorus-import-project` is never normative corpus, even
> though it physically lands in `corpus/` (shared conversion output directory) and even
> though the same conversion skill is reused. Silently letting the invoked skill run its
> own Phase 4.1 here would misclassify the file as corpus (see incident: sandbox
> `07c-cyber-sec-CC-PART1-INTRO+FUNCTIONAL+ASSURANCE`, file
> `005-SIMUL-ID-PKI-ADV-FSP2-fiche-vision.md` wrongly listed in `* Corpus` after an
> auto-invoked `chorus-word` call).
>
> **Rule:** when invoking a conversion skill from this algorithm, instruct it explicitly
> to **skip its own Phase 4.1** (pass this instruction as part of the call context —
> e.g. "invoked by chorus-import-project — do not update README.org § Corpus, the
> caller will record this file itself"). `chorus-import-project` performs the
> `README.org` update itself, under the dedicated section described in Step 4 below —
> never under `* Corpus`.

```
For each source in <source…>:
  If source is a directory:
    # Preserve directory mode — will be expanded later
    Add to sources list as-is
  Else if source ends in .pdf, .docx, .xlsx, .csv, .xml, .html, .htm:
    # Invoke conversion skill — instruct it to skip its own README.org Phase 4.1
    # (this algorithm records the file itself, see Step 4 below)
    ext = source file extension
    if ext == .pdf:
      Call: chorus-pdf <sandbox> <source> --auto   [skip-readme-update]
    elif ext == .docx:
      Call: chorus-word <sandbox> <source>          [skip-readme-update]
    elif ext in (.xlsx, .csv):
      Call: chorus-excel <sandbox> <source>         [skip-readme-update]
    elif ext in (.xml, .html, .htm):
      Call: chorus-xml <sandbox> <source>           [skip-readme-update]

    Wait for skill to complete (expected exit code 0)

    # Auto-detect converted file
    candidates = glob(<sandbox>/corpus/[0-9][0-9][0-9]-*-{text,content,vision}.{txt,md})
    converted_path = max(candidates, key=mtime)  # newest file

    # Replace source with converted file for subsequent phases
    source = converted_path
    Print: "[import] Auto-converted <original.ext> → <converted_path>"

    # Step 4 — Record the converted file under the dedicated section
    # (NOT under * Corpus — see warning above). Done once per source, here,
    # regardless of Single/Merge/Batch mode. The produced project-import-*.json
    # name is not yet known at this point in Single/Merge mode — write it as
    # "(pending)" and patch the row in Phase 6 once the output filename is final.
    Ensure $SANDBOX/README.org contains a
      "* Imported project documents (not corpus — chorus-import-project artefacts)"
      heading (create it, with the explanatory preamble below, if absent):
        "⚠️ These files are not normative corpus — they never fed chorus-feed and
         never influenced the KB, YAML rules, or Helper catalogues. They are
         project-side documents aligned against the existing KB terminology by
         chorus-import-project. Kept in corpus/ only because that is where the
         conversion skills write their Markdown output — physical location, not
         classification."
    Append a row:
      | <NNN> | <converted_path> | <original source description> | <produced project-import-*.json, or "(pending)"> | <date> |

  Else:
    # Plain .txt, .md, or inline content — use as-is
    source remains unchanged
```

**Example scenarios:**

```bash
# Single PDF — auto-converted
chorus-import-project test-05-RGPD corpus/002-norme.pdf
→ [auto] Detected .pdf — calling chorus-pdf test-05-RGPD corpus/002-norme.pdf --auto
→ [auto] Conversion complete → corpus/003-norme-vision.md
→ [import] Using converted corpus/003-norme-vision.md
→ [Phase 1] Reading KB...

# Merge mode: mixed formats — each auto-converted separately
chorus-import-project test-05-RGPD dctp.docx isolations.xlsx norms.txt
→ [auto] dctp.docx → corpus/004-dctp-vision.md (via chorus-word)
→ [auto] isolations.xlsx → corpus/005-isolations-text.txt (via chorus-excel)
→ [auto] norms.txt → use as-is
→ [merge] Merging 3 sources...

# Batch mode: directory with mixed formats
chorus-import-project test-05-RGPD ./sources/
→ [auto] Processing sources/norme.pdf → corpus/006-norme-vision.md
→ [auto] Processing sources/dossier.docx → corpus/007-dossier-vision.md
→ [batch] Generating project-import-001.json, project-import-002.json...
```

After format detection and auto-conversion (if any), proceed to Mode Detection.

### Mode Detection and Source Collection

```
# Batch Mode (directory)
If <source> is a directory:
  files = glob("$source/*.{pdf,docx,xlsx,csv,txt}")
  Sort by name — process each file independently (→ Phase 0B per file)
  Continue to Phase 0-BATCH after collection

# Batch Mode (glob / explicit --batch)
If --batch present or N homogeneous-format sources (N > 1 same extension):
  files = source list
  Sort by name — process each file independently
  Continue to Phase 0-BATCH after collection

# Merge Mode (N sources, mixed formats, without --batch)
If N > 1 sources without --batch:
  Extract each source separately → produce N labelled text blocks
  Merge blocks before Phase 2 (global inventory)
  ⚠️ Warn if two files appear to cover the same elements (potential duplicate ids)

# Single Mode
1 non-directory source, without --batch → original behaviour (Phase 0A/0B below)
```

### Phase 0-BATCH — Batch Processing

For each file `f` in `files`:
1. Extract plain text (Phase 0B below)
2. Run Phases 1–6 **autonomously** for this file
3. Name the outputs: `project-import-<NNN>.json` (location per "Output JSON location",
   Phase 5 — `$SANDBOX/agent/` for Scope=global, or `$SANDBOX/workspace/<client>/` if
   the batch's source directory matched the `<client>/sources/` convention) and
   `import-report-<NNN>.org` (in `$WORKSPACE`, i.e. `$SANDBOX/workspace/reports/`,
   or `$SANDBOX/workspace/<client>/reports/` if the batch's source directory matched
   the `<client>/sources/` convention — see "Scope derivation", Phase 1.2b — created
   if absent) — increment NNN independently for each file
4. At the end of the batch → produce the **batch summary report** (see Phase 6-BATCH)

> ⚠️ Phase 1 (KB reading) is run **once only** at the start of the batch
> and reused for all files — the terminology reference is shared.

### Phase 0-FUSION — Multi-Source Merge

After individually extracting each source:
1. Concatenate the text blocks, labelling each by source file:
   ```
   === SOURCE: structure.pdf ===
   <texte extrait>

   === SOURCE: isolation.xlsx ===
   <texte extrait>
   ```
2. The inventory (Phase 2) processes the whole as a single source
3. Retain the `_source_fichier` attribute on each JSON element for traceability
4. **Id conflict handling**: if two sources define an element with the same `id`:
   - Include both with suffix `_a` / `_b` on the duplicate
   - Add `_conflit: 1` and `_conflit_source: ["fichier1", "fichier2"]`
   - Report the conflict in the import report

### Case A — Inline source (data pasted in the chat)

The engineer pastes a table excerpt, a list of elements, or a descriptive text directly.
Process the content as-is — proceed directly to Phase 1.

### Case B — Filesystem source (files on disk)

Identify the format and extract plain text **before** any semantic processing.

#### PDF — hybrid extraction (same pipeline as `chorus-pdf --hybrid`)

PDF extraction uses the **same 4-mode pipeline as `chorus-pdf`**:
figures, diagrams, and normative tables are recovered via Claude vision — not just raw text.

> **Why it matters:** project documents (DCE, CCTP, BET notes) often embed structural
> diagrams, specification tables as images, or mixed layouts that `pdftotext` silently drops.
> Hybrid mode preserves this information for the terminology alignment phases.

##### Step 0 — Auto-detect mode (no explicit flag)

```python
import os, json, urllib.request, urllib.error

def probe_claude(api_key):
    payload = {"model": "claude-haiku-4-5", "max_tokens": 1,
               "messages": [{"role": "user", "content": "ping"}]}
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
               "content-type": "application/json"}
    try:
        req = urllib.request.Request("https://api.anthropic.com/v1/messages",
            data=json.dumps(payload).encode(), headers=headers, method="POST")
        urllib.request.urlopen(req, timeout=10)
        return True
    except urllib.error.HTTPError as e:
        return e.code in (429, 529)   # throttled but valid
    except Exception:
        return False

api_key = os.environ.get("ANTHROPIC_API_KEY", "")
if api_key and probe_claude(api_key):
    pdf_mode = "hybrid"    # default — pdfminer text + Claude vision on figures
    print("[import] ANTHROPIC_API_KEY detected — hybrid mode activated.", flush=True)
else:
    pdf_mode = "text"      # fallback — pdfminer only
    print("[import] No API key or Claude unreachable — text mode (fallback).", flush=True)
```

| `ANTHROPIC_API_KEY` | Probe | Mode |
|---|---|---|
| absent | — | **text** (pdfminer only) |
| present, valid | ✅ | **hybrid** (pdfminer + Claude vision on figures) |
| present, invalid | ❌ 401/403 | **text** |
| present, throttled | ⚠️ 429/529 | **hybrid** |

##### Step 1 — Layout analysis (pdfminer)

```python
from pdfminer.high_level import extract_pages
from pdfminer.layout import LAParams, LTTextBox, LTFigure

laparams = LAParams(boxes_flow=0.5, char_margin=2.0)
page_data = {}   # {page_num: {'texts': [(text, y_center)], 'figures': [(x0,y0,x1,y1)], 'height': float}}

for page_num, layout in enumerate(extract_pages(pdf_path, laparams=laparams), 1):
    texts, figures = [], []
    for el in layout:
        if isinstance(el, LTTextBox):
            t = el.get_text().strip()
            if t:
                texts.append((t, (el.y0 + el.y1) / 2))
        elif isinstance(el, LTFigure):
            figures.append((el.x0, el.y0, el.x1, el.y1))
    page_data[page_num] = {'texts': texts, 'figures': figures, 'height': layout.height}
```

##### Step 2 — Hybrid mode: crop figures and call Claude

Only if `pdf_mode == "hybrid"` **and** figures were detected.

```python
import base64, io, subprocess, tempfile
from PIL import Image

DPI = 150

def pdf_bbox_to_png_crop(x0, y0, x1, y1, page_height, dpi=DPI):
    scale = dpi / 72.0
    margin = int(4 * scale)
    return (
        max(0, int(x0 * scale) - margin),
        max(0, int((page_height - y1) * scale) - margin),
        int(x1 * scale) + margin,
        int((page_height - y0) * scale) + margin,
    )

FIGURE_PROMPT = """You are a technical document extraction engine.
Describe this figure extracted from an engineering project document.
Output a block of the form:
  [FIGURE <N> — <title or caption if visible>]
  <Structured description: labeled dimensions, named components, numerical values,
   spatial relationships, units, arrows, hatching, scale bar if present>
  [END FIGURE <N>]
  IDENTIFIERS: ["<id1>", "<id2>", ...]
If no caption is visible, assign [FIGURE ?]. Do not add text outside the
[FIGURE] ... [END FIGURE] block and IDENTIFIERS line.
For IDENTIFIERS: list every alphanumeric code, label, designation or identifier
visible in the figure (callout tags, part numbers, element IDs, zone codes,
article references). Use the exact string as printed. Exclude purely numeric
values (dimensions, measurements), single generic letters, and common stopwords.
Output a valid JSON array on a single line immediately after [END FIGURE <N>].
Output [] if no identifiers found.
Use UTF-8. Preserve special characters (±, ≤, ≥, ×, °, ², ³…)."""

def call_claude_figure(png_bytes, page_num, fig_idx, api_key):
    import json as _json, urllib.request as _req, urllib.error as _err, time
    b64 = base64.standard_b64encode(png_bytes).decode()
    payload = {
        "model": "claude-opus-4-5", "max_tokens": 2048,
        "messages": [{"role": "user", "content": [
            {"type": "text",  "text": f"[Page {page_num}, Figure {fig_idx}]\n\n{FIGURE_PROMPT}"},
            {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": b64}},
        ]}]
    }
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
               "content-type": "application/json"}
    for attempt in range(4):
        r = _req.Request("https://api.anthropic.com/v1/messages",
            data=_json.dumps(payload).encode(), headers=headers, method="POST")
        try:
            with _req.urlopen(r, timeout=120) as resp:
                return _json.loads(resp.read())["content"][0]["text"].strip()
        except _err.HTTPError as e:
            if e.code in (429, 529) and attempt < 3:
                time.sleep(10 * (2 ** attempt)); continue
            raise

# all_figure_descs accumulates figure descriptions across ALL pages before assembly
all_figure_descs = {}   # {(page_num, fig_idx): description_text}

with tempfile.TemporaryDirectory(prefix="chorus-import-pdf-") as tmpdir:
    for page_num, pdata in sorted(page_data.items()):
        if pdf_mode == "hybrid" and pdata['figures']:
            prefix = os.path.join(tmpdir, f"p{page_num:04d}")
            subprocess.run(
                ["pdftoppm", "-r", str(DPI), "-png",
                 "-f", str(page_num), "-l", str(page_num), pdf_path, prefix],
                check=True, capture_output=True)
            import glob as _glob
            png_files = sorted(_glob.glob(prefix + "*.png"))
            img = Image.open(png_files[0])
            for fig_idx, bbox in enumerate(pdata['figures'], 1):
                crop_box = pdf_bbox_to_png_crop(*bbox, pdata['height'])
                w, h = img.size
                crop_box = (min(crop_box[0],w), min(crop_box[1],h),
                            min(crop_box[2],w), min(crop_box[3],h))
                buf = io.BytesIO()
                img.crop(crop_box).save(buf, format="PNG")
                all_figure_descs[(page_num, fig_idx)] = call_claude_figure(
                    buf.getvalue(), page_num, fig_idx, api_key)
# → all_figure_descs collected — proceed to Step 2.5 before assembling pages
```

##### Step 2.5 — Cross-reference pass (hybrid mode only)

Same logic as `chorus-pdf --hybrid` Phase 2.5 — runs **after** all figure descriptions
are collected, **before** page assembly. No additional API calls.

```python
import re as _re

_XREF_STOPWORDS = {
    "N", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
    "M", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "kN", "mm", "cm", "m", "kg", "kPa", "MPa", "GPa", "kNm",
    "Figure", "Table", "Clause", "Section", "Annex", "NOTE", "Fig",
}
_XREF_MIN_LEN = 2

def _parse_identifiers(description):
    ids = []
    m = _re.search(r'^IDENTIFIERS:\s*(\[.*?\])\s*$', description, _re.MULTILINE)
    if m:
        try:
            import json as _j
            ids = [str(x).strip() for x in _j.loads(m.group(1)) if str(x).strip()]
        except Exception:
            pass
    if not ids:
        ids = _re.findall(r'\b([A-Za-z][A-Za-z0-9\-_]{1,19})\b', description)
    seen, result = set(), []
    for ident in ids:
        if ident in _XREF_STOPWORDS or len(ident) < _XREF_MIN_LEN:
            continue
        if ident.lower() not in seen:
            seen.add(ident.lower())
            result.append(ident)
    return result

def _find_text_occurrences(identifier, page_data):
    pattern = _re.compile(r'\b' + _re.escape(identifier) + r'\b')
    results = []
    for page_num in sorted(page_data):
        for (block_text, _y) in page_data[page_num]['texts']:
            hit = pattern.search(block_text)
            if hit:
                s = max(0, hit.start() - 55)
                e = min(len(block_text), hit.end() + 55)
                snip = block_text[s:e].replace('\n', ' ').strip()
                if s > 0:   snip = '…' + snip
                if e < len(block_text): snip += '…'
                results.append((page_num, snip))
    return results

def _xref_pass(all_figure_descs, page_data):
    """Returns (annotated_descs, xref_index_block, xref_map).

    xref_map : {identifier: [(page_num, fig_idx, occurrences), ...]}
    Used directly by Phase 3 terminology alignment as first-class matching candidates.
    """
    annotated, global_index = {}, {}

    for (page_num, fig_idx), desc in all_figure_descs.items():
        identifiers = _parse_identifiers(desc)
        if not identifiers:
            annotated[(page_num, fig_idx)] = desc
            continue

        xref_lines = [f"[XREF FIGURE {fig_idx} — page {page_num}]"]
        for ident in identifiers:
            occs = _find_text_occurrences(ident, page_data)
            xref_lines.append(f"  {ident}:")
            if occs:
                for p, snip in occs:
                    xref_lines.append(f"    p.{p}: {snip}")
            else:
                xref_lines.append("    (no occurrence found in text)")
            global_index.setdefault(ident, []).append((page_num, fig_idx, occs))
        xref_lines.append(f"[END XREF FIGURE {fig_idx}]")

        # Append annotation after [END FIGURE …]
        annotated_desc = _re.sub(
            r'(\[END FIGURE[^\]]*\])',
            r'\1\n' + '\n'.join(xref_lines),
            desc, count=1
        )
        if annotated_desc == desc:
            annotated_desc = desc + '\n' + '\n'.join(xref_lines)
        annotated[(page_num, fig_idx)] = annotated_desc

    # Build XREF INDEX block
    lines = ["=== XREF INDEX ===",
             "# Cross-reference: figure identifiers → text occurrences", ""]
    for ident in sorted(global_index):
        entries = global_index[ident]
        fig_refs = [f"Figure {fi} (p.{pn})" for pn, fi, _ in entries]
        all_occs = [(p, s) for _, _, occs in entries for p, s in occs]
        lines.append(f"## {ident}")
        lines.append(f"   Appears in: {', '.join(fig_refs)}")
        seen_p = set()
        for p, snip in all_occs:
            if p not in seen_p:
                lines.append(f"   Text occurrence (p.{p}): {snip}")
                seen_p.add(p)
        if not all_occs:
            lines.append("   Text occurrence: (none found)")
        lines.append("")
    lines.append("=== END XREF INDEX ===")

    return annotated, '\n'.join(lines), global_index

# --- Run the cross-reference pass (hybrid only) ---
if pdf_mode == "hybrid" and all_figure_descs:
    annotated_descs, xref_index_block, xref_map = _xref_pass(all_figure_descs, page_data)
else:
    annotated_descs = all_figure_descs
    xref_index_block = ""
    xref_map = {}
# xref_map is passed to Phase 3 as first-class matching candidates
```

> **`xref_map`** is the key output for Phase 3: it maps each figure identifier to the
> text snippets where it co-occurs with corpus terms.
> Phase 3 consults `xref_map` at step 1 (KB aliases) and step 2 (figure body)
> before falling back to generic text search.

##### Step 3 — Assemble pages in reading order (top→bottom)

```python
def assemble_page(page_num, pdata, figure_descriptions):
    elements = []
    for text, y in pdata['texts']:
        elements.append((y, 'text', text))
    for fig_idx, (x0, y0, x1, y1) in enumerate(pdata['figures'], 1):
        desc = figure_descriptions.get(fig_idx,
               f"[FIGURE {fig_idx} — not extracted (text mode)]")
        elements.append(((y0+y1)/2, 'figure', desc))
    elements.sort(key=lambda e: e[0], reverse=True)   # highest Y first
    body = "\n\n".join(content for (_, _, content) in elements)
    return f"=== PAGE {page_num} ===\n{body}\n=== END PAGE {page_num} ==="

# Build per-page figure_descriptions from annotated_descs
per_page_figs = {}
for (page_num, fig_idx), desc in annotated_descs.items():
    per_page_figs.setdefault(page_num, {})[fig_idx] = desc

pages_output = []
for page_num in sorted(page_data):
    pages_output.append(assemble_page(page_num, page_data[page_num],
                                      per_page_figs.get(page_num, {})))

# Append XREF INDEX at end (hybrid only — empty string otherwise)
if xref_index_block:
    pages_output.append(xref_index_block)

extracted_text = "\n\n".join(pages_output)
# extracted_text is the final source passed to Phase 2 (raw inventory)
# xref_map is passed separately to Phase 3 (terminology alignment)
```

##### Step 4 — nohup gate (hybrid only)

If the layout analysis detects **> 15 figures** (≈ > 7.5 min at ~30 s/call):
- Print a `nohup` command and **stop** (do not proceed)
- When relaunched with `CHORUS_PDF_FORCE=1 nohup python3 <script>` → proceed unconditionally

```
[import-pdf] ⚠️  18 figures detected — estimated time ~9–13 min (threshold: 15).
[import-pdf]    Run with nohup to avoid a 10-min IDE timeout:
[import-pdf]    CHORUS_PDF_FORCE=1 nohup python3 <script.py> > <output.md>.log 2>&1 &
```

> ⚠️ **If the extraction script exits with code 2** (nohup required):
> ECA must **not** retry automatically. It must set `CHORUS_PDF_FORCE=1`
> and relaunch with `nohup` — pre-approved, no confirmation required.

##### Dependencies

| Package | Install |
|---------|---------|
| `pdfminer.six` | `pip install pdfminer.six` |
| `Pillow` | `pip install Pillow` (hybrid mode only) |
| `pdftoppm` | `sudo apt install poppler-utils` (hybrid mode only) |
| `ANTHROPIC_API_KEY` | `export ANTHROPIC_API_KEY="sk-ant-..."` (hybrid mode only) |

##### Text-mode fallback (no API key)

When `pdf_mode == "text"`, figures produce a placeholder instead of a Claude description:

```
[FIGURE — not extracted]
[Run chorus-import-project with ANTHROPIC_API_KEY set to extract figures via hybrid mode]
```

The rest of the extraction (text blocks, reading order) is identical.

> ⛔ **Figure-heavy domains — critical warning**
>
> When `pdf_mode == "text"` is active **and** the layout analysis detected ≥ 5 figures,
> emit a prominent warning **before proceeding**:
>
> ```
> [import-pdf] ⛔  Text mode active — N figures not extracted.
>              In figure-heavy domains (BTP/Construction, Medical Devices/MDR),
>              plans, assembly diagrams and specification tables embedded as images
>              typically contain the constituent element identifiers (P1, P2, IPE-01,
>              component tags, MDR annex references…).
>              Phase 3 will be blind to these elements → JSON likely incomplete.
>              Strongly recommended: set ANTHROPIC_API_KEY and rerun to activate hybrid mode.
>              Continue in text-only mode? [yes / abort]
> ```
>
> If the engineer confirms `yes`, proceed — but add `"_extraction_warning": "text-mode: N figures not extracted"` in the `_import` block of the output JSON.
> In batch mode, emit the warning once per file that triggers the threshold.

#### Excel / CSV — full-quality pipeline (same depth as PDF)

Excel and CSV extraction uses the **same architecture as `chorus-pdf`**: tables are
reconstructed as Markdown pipe tables with merged-cell handling, embedded images and
charts are sent to Claude vision (hybrid mode), and the XREF pass links figure
identifiers back to cell values across all sheets.

> **Why it matters:** project spreadsheets (BET quantity surveys, thermal calculation
> tables, compliance matrices) embed images and charts alongside tabular data.
> A naive `openpyxl` dump loses merged cells, images, and chart content entirely.

##### Format detection

```python
import os
ext = os.path.splitext(source_path)[1].lower()
if ext == '.csv':
    excel_mode = 'csv'    # always text — no images
elif ext in ('.xlsx', '.xlsm', '.ods'):
    excel_mode = 'excel'  # hybrid or text depending on API key
else:
    excel_mode = 'fallback'  # libreoffice convert → csv
```

##### Step 0 — Auto-detect mode (Excel only — identical to PDF pipeline)

Same `probe_claude()` probe as PDF Step 0. Three-branch result:
`extraction_mode = "hybrid"` (xlsx + valid key) / `"csv"` (csv format, unconditionally) / `"text"` (fallback).
Print prefix: `[import-excel]`.

##### Step 1 — CSV extraction

```python
import csv

def csv_to_markdown(csv_path):
    with open(csv_path, newline='', encoding='utf-8-sig') as f:
        rows = list(csv.reader(f))
    if not rows:
        return ""
    def cell(c):
        return str(c or "").replace("|", "｜").strip()
    n_cols = max(len(r) for r in rows)
    rows_padded = [r + [''] * (n_cols - len(r)) for r in rows]
    lines = ["| " + " | ".join(cell(c) for c in rows_padded[0]) + " |",
             "| " + " | ".join("---" for _ in rows_padded[0]) + " |"]
    for row in rows_padded[1:]:
        lines.append("| " + " | ".join(cell(c) for c in row) + " |")
    return "\n".join(lines)

extracted_text = csv_to_markdown(source_path)
# → proceed to Phase 2 (no xref_map for CSV)
xref_map = {}
```

##### Step 1 — XLSX extraction (text mode and hybrid mode)

```python
import openpyxl

def build_merged_map(ws):
    """Map (row, col) → master_value for all merged cell slaves."""
    merged_map = {}
    for merged_range in ws.merged_cells.ranges:
        cells = list(merged_range.cells)
        if not cells:
            continue
        master_row, master_col = cells[0]
        master_val = ws.cell(row=master_row, column=master_col).value
        master_str = str(master_val) if master_val is not None else ""
        for row, col in cells[1:]:
            merged_map[(row, col)] = master_str
    return merged_map

def cell_value(cell, merged_map):
    if cell.value is not None:
        return str(cell.value)
    return merged_map.get((cell.row, cell.column), "")

def sheet_to_markdown(ws):
    """Convert one worksheet to a Markdown pipe table, handling merged cells."""
    merged_map = build_merged_map(ws)
    rows_out = []
    for row in ws.iter_rows():
        cells_out = [cell_value(c, merged_map).replace("|", "｜").replace("\n", " ").strip()
                     for c in row]
        rows_out.append(cells_out)
    # Skip fully empty rows
    rows_out = [r for r in rows_out if any(c for c in r)]
    if not rows_out:
        return "(empty sheet)"
    n_cols = max(len(r) for r in rows_out)
    rows_padded = [r + [''] * (n_cols - len(r)) for r in rows_out]
    lines = ["| " + " | ".join(rows_padded[0]) + " |",
             "| " + " | ".join("---" for _ in rows_padded[0]) + " |"]
    for row in rows_padded[1:]:
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)

wb = openpyxl.load_workbook(source_path, data_only=True)
sheet_parts = []
all_image_entries = []    # [(sheet_name, img_idx, png_bytes)]
all_chart_entries = []    # [(sheet_name, chart_idx, png_bytes_or_None)]

for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    sheet_parts.append(f"=== SHEET: {sheet_name} ===")
    sheet_parts.append(sheet_to_markdown(ws))
    # Collect embedded images
    for i, img_anchor in enumerate(ws._images, 1):
        png = convert_blob_to_png(img_anchor.image.blob)  # Pillow conversion
        all_image_entries.append((sheet_name, i, png))
        if extraction_mode == "text":
            sheet_parts.append(
                f"\n[IMAGE {i} — not extracted]\n"
                "[Run with ANTHROPIC_API_KEY to extract images via hybrid mode]")
    # Collect charts
    for i, chart_anchor in enumerate(ws._charts, 1):
        if extraction_mode == "hybrid":
            png = chart_to_png_via_libreoffice(source_path, chart_anchor, tmpdir)
            all_chart_entries.append((sheet_name, i, png))
        else:
            sheet_parts.append(
                f"\n[CHART {i} — not extracted]\n"
                "[Run with ANTHROPIC_API_KEY + LibreOffice to extract charts via hybrid mode]")
    sheet_parts.append(f"=== END SHEET: {sheet_name} ===")
```

##### Step 2 — Hybrid mode: Claude vision on images and charts

Only if `extraction_mode == "hybrid"` and images/charts were detected.

```python
from PIL import Image
import io, base64, json, urllib.request, time

def convert_blob_to_png(blob):
    """Convert image blob (PNG/JPEG/EMF) to PNG bytes via Pillow."""
    try:
        img = Image.open(io.BytesIO(blob))
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        return buf.getvalue()
    except Exception:
        return blob if blob[:4] == b'\x89PNG' else None

# call_claude_figure: same function as chorus-pdf hybrid (FIGURE_PROMPT, claude-opus-4-5, retry)
all_figure_descs = {}   # {(sheet_name, img_idx): description_text}

for sheet_name, img_idx, png_bytes in all_image_entries:
    if png_bytes:
        desc = call_claude_figure(png_bytes, sheet_name, img_idx, api_key)
        all_figure_descs[(sheet_name, img_idx)] = desc

for sheet_name, chart_idx, png_bytes in all_chart_entries:
    if png_bytes:
        desc = call_claude_figure(png_bytes, sheet_name, chart_idx + 1000, api_key)
        all_figure_descs[(sheet_name, chart_idx + 1000)] = desc
```

##### Step 2.5 — Cross-reference pass (hybrid mode only)

The XREF pass links figure identifiers to cell values across all sheets — the same
mechanism as `chorus-pdf` Phase 2.5, adapted for a grid coordinate system.

```python
def build_sheet_texts(wb):
    """Build {sheet_name: [(text, row, col), ...]} for all non-empty text cells."""
    result = {}
    for sheet_name in wb.sheetnames:
        ws = wb[sheet_name]
        cells = []
        merged_map = build_merged_map(ws)
        for row in ws.iter_rows():
            for cell in row:
                val = cell_value(cell, merged_map)
                if val.strip():
                    cells.append((val.strip(), cell.row, cell.column))
        result[sheet_name] = cells
    return result

def find_text_occurrences_excel(identifier, sheet_texts):
    import re
    pattern = re.compile(r'\b' + re.escape(identifier) + r'\b')
    results = []
    for sheet_name, cells in sheet_texts.items():
        for (text, row, col) in cells:
            m = pattern.search(text)
            if m:
                s = max(0, m.start() - 55); e = min(len(text), m.end() + 55)
                snippet = text[s:e].replace('\n', ' ').strip()
                if s > 0: snippet = '…' + snippet
                if e < len(text): snippet += '…'
                results.append((f"Sheet '{sheet_name}' R{row}C{col}", snippet))
    return results

if extraction_mode == "hybrid" and all_figure_descs:
    sheet_texts = build_sheet_texts(wb)
    annotated_descs, xref_index_block, xref_map = _xref_pass_excel(
        all_figure_descs, sheet_texts, find_text_occurrences_excel)
else:
    annotated_descs = all_figure_descs
    xref_index_block = ""
    xref_map = {}
# xref_map passed to Phase 3 as first-class matching candidates (same as PDF pipeline)
```

##### Step 3 — Assemble final output

Inject figure descriptions at their anchor position within each sheet block, then
append the XREF INDEX at the end.

```python
extracted_text = "\n\n".join(sheet_parts)
if xref_index_block:
    extracted_text += "\n\n" + xref_index_block
```

##### nohup gate (hybrid mode — Excel)

If the workbook contains **≥ 15 images + charts** combined → exit(2) + nohup command.
`CHORUS_EXCEL_FORCE=1` to bypass, identical to `chorus-pdf` nohup gate.

##### Dependencies

| Package | Install | Notes |
|---------|---------|-------|
| `openpyxl` | `pip install openpyxl` | XLSX extraction |
| `Pillow` | `pip install Pillow` | Image conversion (hybrid mode) |
| `LibreOffice` | `sudo apt install libreoffice` | Chart extraction (optional — graceful fallback) |
| `pdftoppm` | `sudo apt install poppler-utils` | Chart page rendering (optional) |

> ⛔ **If extraction tools are absent** → warn and offer Case A (inline paste).
> Never block the workflow over a missing optional tool.


#### Word (.docx) — full-quality pipeline (same depth as PDF)

Word extraction uses the **same architecture as `chorus-pdf`**: the native XML body
order is preserved for correct reading order, tables are reconstructed as Markdown
pipe tables with merged-cell handling, embedded images are sent to Claude vision
(hybrid mode), and the XREF pass links figure identifiers to paragraph text.

> **Why it matters:** project CCTP, BET reports, and specification documents routinely
> embed structural diagrams, assembly drawings, and specification tables as images.
> A naive `python-docx` paragraph dump loses all images and flattens table structure.

##### Step 0 — Auto-detect mode (identical to PDF pipeline)

Same `probe_claude()` probe as PDF Step 0. Result: `word_mode = "hybrid"` or `"text"`. Print prefix: `[import-word]`.

##### Step 1 — Document traversal via XML body order

```python
import docx
from docx.oxml.ns import qn

def iter_block_items(doc):
    """Yield (kind, obj) in document XML order — preserves reading order."""
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
                        img_counter[0] += 1
                        yield ('image', (img_counter[0], doc.part.rels[rId].target_part.blob))
            else:
                text = para.text.strip()
                if text:
                    yield ('para', (text, para.style.name if para.style else ''))
        elif tag == 'tbl':
            yield ('table', docx.table.Table(child, doc))

def table_to_markdown(tbl):
    """Convert python-docx Table to Markdown pipe, deduplicating merged cells."""
    seen, rows_out = set(), []
    for row in tbl.rows:
        row_cells = []
        for cell in row.cells:
            cid = id(cell._tc)
            if cid not in seen:
                seen.add(cid)
                row_cells.append(
                    " ".join(p.text.strip() for p in cell.paragraphs if p.text.strip()))
        rows_out.append(row_cells)
    if not rows_out or not rows_out[0]:
        return ""
    n_cols = max(len(r) for r in rows_out)
    rows_padded = [r + [''] * (n_cols - len(r)) for r in rows_out]
    def cell_md(c): return str(c or "").replace("|", "｜").replace("\n", " ").strip()
    lines = ["| " + " | ".join(cell_md(c) for c in rows_padded[0]) + " |",
             "| " + " | ".join("---" for _ in rows_padded[0]) + " |"]
    for row in rows_padded[1:]:
        lines.append("| " + " | ".join(cell_md(c) for c in row) + " |")
    return "\n".join(lines)
```

##### Step 2 — Hybrid mode: Claude vision on embedded images

```python
from PIL import Image
import io

def convert_to_png(blob):
    """Convert image blob (PNG/JPEG/EMF/WMF) to PNG bytes via Pillow."""
    try:
        img = Image.open(io.BytesIO(blob))
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        return buf.getvalue()
    except Exception:
        return blob if blob[:4] == b'\x89PNG' else None  # EMF/WMF → skip

doc = docx.Document(source_path)
block_texts = []       # [(text, block_idx)] — for XREF pass
all_figure_descs = {}  # {(doc_name, img_idx): description_text}
elements = []          # [(kind, content)] — in XML order

for kind, obj in iter_block_items(doc):
    if kind == 'para':
        text, style = obj
        block_idx = len(block_texts)
        block_texts.append((text, block_idx))
        elements.append(('text', text))
    elif kind == 'table':
        md = table_to_markdown(obj)
        if md:
            elements.append(('table', md))
    elif kind == 'image':
        img_idx, blob = obj
        png_bytes = convert_to_png(blob)
        if word_mode == "hybrid" and png_bytes:
            desc = call_claude_figure(png_bytes, "word-doc", img_idx, api_key)
            all_figure_descs[("word-doc", img_idx)] = desc
            elements.append(('figure', desc))
        else:
            elements.append(('image',
                "[IMAGE — not extracted]\n"
                "[Run with ANTHROPIC_API_KEY to extract images via hybrid mode]"))
```

##### Step 2.5 — Cross-reference pass (hybrid mode only)

The XREF pass links figure identifiers to paragraph text blocks — identical to
`chorus-pdf` Phase 2.5, adapted for a block-index coordinate system.

```python
def build_word_block_texts(block_texts):
    """Adapt block_texts for find_text_occurrences: {0: [(text, block_idx), ...]}"""
    return {0: [(text, block_idx) for (text, block_idx) in block_texts]}

def find_text_occurrences_word(identifier, block_texts):
    import re
    pattern = re.compile(r'\b' + re.escape(identifier) + r'\b')
    results = []
    for (text, block_idx) in block_texts:
        m = pattern.search(text)
        if m:
            s = max(0, m.start() - 55); e = min(len(text), m.end() + 55)
            snippet = text[s:e].replace('\n', ' ').strip()
            if s > 0: snippet = '…' + snippet
            if e < len(text): snippet += '…'
            results.append((f"bloc {block_idx}", snippet))
    return results

if word_mode == "hybrid" and all_figure_descs:
    annotated_descs, xref_index_block, xref_map = _xref_pass_word(
        all_figure_descs, block_texts, find_text_occurrences_word)
else:
    annotated_descs = all_figure_descs
    xref_index_block = ""
    xref_map = {}
# xref_map passed to Phase 3 as first-class matching candidates (same as PDF pipeline)
```

##### Step 3 — Assemble final output

XML order is the reading order — no Y-sort required. Append XREF INDEX at end.

```python
output_parts = [content for (_, content) in elements]
if xref_index_block:
    output_parts.append(xref_index_block)
extracted_text = "\n\n".join(output_parts)
```

##### nohup gate (hybrid mode — Word)

If the document contains **≥ 15 embedded images** → exit(2) + nohup command.
`CHORUS_WORD_FORCE=1` to bypass, identical to `chorus-pdf` nohup gate.

##### Figure-heavy domains warning (text mode)

When `word_mode == "text"` **and** ≥ 5 images detected, emit the same prominent
warning as the PDF pipeline — Phase 3 will be blind to image content.

##### Dependencies

| Package | Install | Notes |
|---------|---------|-------|
| `python-docx` | `pip install python-docx` | DOCX extraction |
| `Pillow` | `pip install Pillow` | Image conversion (hybrid mode) |

> ⛔ **If extraction tools are absent** → warn and offer Case A (inline paste).
> Never block the workflow over a missing optional tool.


#### Other formats — LibreOffice universal fallback

For formats not natively handled (`.doc`, `.odt`, `.pptx`, `.ods`, `.rtf`):

```bash
libreoffice --headless --convert-to pdf "<fichier>" --outdir /tmp/
# → produces /tmp/<basename>.pdf → feed to PDF hybrid pipeline above
```

If LibreOffice is absent → ask the engineer to provide copy-pasted content (Case A).
Never block the workflow over a missing tool — offer the inline alternative.


## Phase 1 — Read the KB (canonical terminology)

### 1.0 Sandbox inventory (first tool call — token keepalive)

**Before reading any file**, read the directory tree $SANDBOX/ immediately.

This serves two purposes:
1. Acquires the full sandbox structure early (agents list, rules dirs, existing JSON/report files)
2. Ensures at least one tool call happens before any long reading+thinking cycle,
   keeping the IDE token active from the very start.

Use this inventory to:
- Confirm the list of `<slug>.org` files to read in 1.2
- Know which `rules/<slug>/` directories exist (for the keepalive calls in 1.2)
- Detect the sandbox thesaurus: **new sharded layout**
  `$SANDBOX/agent/thesaurus/global.org` (+ `$SANDBOX/agent/thesaurus/<client>.org` if
  scoped shards exist) **or legacy monolithic** `$SANDBOX/agent/thesaurus.org` (for
  1.2b — highest priority source; see "Thesaurus storage layout" for the detection
  and one-way migration rule)
- Detect any existing `import-report-*.org` files (for 1.3 — secondary memory)

### 1.1 Pipeline Index

Read `$SANDBOX/agent/chorus/index.org`:
- Namespace + agent list (slug, pos)
- Global slot dictionary (if present in the index)

### 1.2 Per-agent terminology

For each agent, apply this two-step sequence:

1. **Read** `$SANDBOX/agent/chorus/<slug>.org` and extract:

| KB Section | What we extract |
|---|---|
| `Ontologie` | Domain concepts, synonyms, relationships (e.g. "entrait" = horizontal truss beam) |
| `Catalogue des Frames` | Exact types (`type_element`), mandatory slots per type |
| `Dictionnaire des slots` | Canonical names, value types, units, allowed domains |
| `Dictionnaire des slots` — `Derived:` annotation | Slots computed at runtime via `_NEEDED` — **not required** in project JSON |
| `Dictionnaire des slots` — `Frame ref` / `→` annotation | Inter-frame link slots — Phase 3.5 processes them; `*_ref` fields are optional |
| `Dictionnaire des slots` — `Triggers X on Y (_AFTER)` annotation | Forward propagation — informational only; no impact on JSON content |

2. **Immediately after** (no thinking between the two calls): read the directory tree $SANDBOX/rules/<slug>/
   to list the rule files for this agent.

> **Why the immediate tool call:** Opus extended thinking after reading a dense KB file
> can be long enough to expire the IDE token. Reading the directory tree right after
> each read resets the token TTL and produces a useful rules inventory at no extra cost.

Build an internal **terminology reference**:
```
concept_kb        → type_element / slot_kb       unit_kb     domain          flags
───────────────────────────────────────────────────────────────────────────────────
montant porteur   → montant_porteur              —           —               —
lisse              → lisse_basse / lisse_haute   —           to clarify      —
classe résistance → classe_bois                 —           C14/C16/C18/C24 —
épaisseur isolant → epaisseur_mm                mm          positive int    —
conductivité λ    → classe_conductivite         —           "031"/"035"     —
hauteur libre     → hauteur_libre_m             m           decimal         —
section           → section_bois                —           "BxH"           —
épaisseur totale  → epaisseur_totale_mm         mm          positive int    DERIVED (_NEEDED)
```

> **`DERIVED` flag:** slots annotated `Derived:` in the KB org are computed at
> runtime by a `_NEEDED` coderef in Feed.pm.  Mark them with a `DERIVED` flag in
> the internal reference so Phase 4 never reports their absence as a gap.
> A `DERIVED` slot that IS present in the project file takes precedence over the
> computed value — include it in the JSON normally.

> **`type_element` — canonical name guard:** while reading the KB, verify that
> the element type slot is named **`type_element`** in the `Dictionnaire des slots`
> of each `<slug>.org`. Then, immediately after reading the directory tree of
> `$SANDBOX/rules/<slug>/`, read one representative `.yml` file and verify that its
> `FIND`/`CHERCHER` block uses `attribut: type_element` (not `element_type`, `type`,
> `kind`, or any variant).
> If a mismatch is found → **stop and report** before producing any JSON:
> ```
> ⛔ Slot name mismatch detected:
>    KB org uses '<found_org_name>' / YAML uses 'attribut: <found_yaml_name>'
>    The import JSON would use "type_element" → all elements silently invisible to the pipeline.
>    Fix: rename to `type_element` in the KB org (Slot dictionary), all YAML rules,
>    and any existing project JSON files before proceeding.
>    (See chorus-feed.md § Naming Conventions and chorus-engine-yaml.md § YAML Rules checklist)
> ```

### 1.2b Sandbox thesaurus (highest priority source)

If a sandbox thesaurus exists (sharded layout `$SANDBOX/agent/thesaurus/*.org`, or
legacy monolithic `$SANDBOX/agent/thesaurus.org` — see "Thesaurus storage layout"
below), **read the relevant shard(s) immediately after Phase 1.2**, before any
import-report.

The thesaurus is the **canonical project-terminology memory** for this sandbox. It is
separated from the normative KB (`<slug>.org`) and from import reports: it stores
project-specific synonyms validated by the engineer across all previous imports.

**Priority rule:**
```
thesaurus (1.2b)  >  import-report-*.org (1.3)  >  KB aliases (1.2)
```

A mapping present in the thesaurus is applied **at ✅ confidence without asking the
engineer again**, regardless of what the KB or previous import-reports say.

#### Thesaurus storage layout — sharded by Scope

The thesaurus is stored as **one `.org` file per Scope**, under
`$SANDBOX/agent/thesaurus/`, rather than a single monolithic file:

```
$SANDBOX/agent/thesaurus/global.org           ← Scope = global (always present once
                                                 the sandbox has at least one ✅ mapping)
$SANDBOX/agent/thesaurus/<client-alpha>.org   ← Scope = client-alpha (created on demand,
$SANDBOX/agent/thesaurus/<client-beta>.org      one shard per distinct non-global Scope
                                                 ever used — see "Scope derivation")
```

**Why sharding, not a single file:** on a multi-client sandbox, a lookup for an import
scoped to `client-alpha` only ever needs `global.org` + `client-alpha.org` — it never
needs to read `client-beta.org`, `client-gamma.org`, etc. Reading cost per import
becomes proportional to **one Scope's volume**, not the sandbox's total accumulated
volume across every client ever imported. This directly addresses the read-cost
concern in the original refactor analysis (large sandboxes, hundreds of imports).

**Which shard(s) to read for a given import**, with `C` = this import's Scope
(resolved per "Scope derivation" below):
```
Always read: $SANDBOX/agent/thesaurus/global.org (if present)
If C != "global": also read $SANDBOX/agent/thesaurus/<C>.org (if present)
Never read any other <other-client>.org shard.
```
If neither file exists yet → no thesaurus hit is possible, proceed to Phase 1.3/KB
lookup as if no thesaurus existed (same as today's "thesaurus.org absent" case).

**`* Pending`, `* Out-of-scope`, and `* Conflicts` tables** (see "Thesaurus format"
below) live **only in `global.org`**, never duplicated per shard — these tables are
not Scope-partitioned data (a `* Conflicts` row already carries its own `Scope` column
for the rare case of a same-scope mismatch; `* Pending`/`* Out-of-scope` are inherently
sandbox-wide bookkeeping, not per-client data worth sharding). Only the two `* Aliases`
tables are actually split across shards.

**Each shard file's own header:**
```org
#+TITLE: Project terminology thesaurus — sandbox <name> — shard: global|<client>
#+UPDATED: <date>
#+LAST_HARVEST: never          ← global.org only (see below)
#+DESCRIPTION: Validated project-term → KB-slot mappings for this sandbox, Scope=<shard>.
               Maintained automatically by chorus-import-project. Part of a sharded
               thesaurus — see agent/thesaurus/global.org for Pending/Out-of-scope/Conflicts.
```
`#+LAST_HARVEST:` is meaningful only in `global.org` — `chorus-feed --harvest-aliases`
only ever promotes `Scope=global` rows (see `chorus-feed.md § Phase C1 — Scope guard`),
so only `global.org` is ever purged/touched by a harvest. Client shards never carry
this header.

#### Legacy monolithic `thesaurus.org` — detection and one-way migration

Sandboxes created before this sharding convention may still have a single
`$SANDBOX/agent/thesaurus.org` file (no `thesaurus/` subfolder). Detection order:

```
1. $SANDBOX/agent/thesaurus/ directory exists → sharded layout, use it (ignore any
   leftover $SANDBOX/agent/thesaurus.org — should not coexist; if it does, warn and
   treat the sharded layout as authoritative, do not merge automatically)
2. $SANDBOX/agent/thesaurus/ absent, $SANDBOX/agent/thesaurus.org exists → legacy
   monolithic sandbox. Read it as-is for this import (fully backward compatible: all
   Scope resolution, dedup, and conflict logic below works identically on a single
   file — sharding is a storage optimisation, not a change to the logic).
   Then, **once this import completes successfully** (Phase 6), perform a one-way
   migration: split thesaurus.org into agent/thesaurus/global.org (+ one shard per
   distinct non-global Scope found in its Aliases rows), moving `* Pending`,
   `* Out-of-scope`, and `* Conflicts` into global.org unchanged. Delete the original
   thesaurus.org only after all shards are written and verified (row count in shards
   == row count in the original file). Report the migration to the engineer:
   ```
   📦 Legacy thesaurus.org migrated to sharded layout:
      agent/thesaurus/global.org        (N aliases, Pending/Out-of-scope/Conflicts)
      agent/thesaurus/client-alpha.org  (N aliases)
      Original agent/thesaurus.org removed.
   ```
3. Neither exists → no thesaurus yet, proceed to "Thesaurus creation" (first import).
```

> ⚠️ Migration is **one-way and one-time** — never re-split an already-sharded
> thesaurus, never reconstruct a monolithic file from shards. If both a `thesaurus/`
> folder and a `thesaurus.org` file exist simultaneously (should not normally happen),
> treat it as a corruption signal: stop, report both, and let the engineer decide
> manually rather than guessing which is authoritative.

#### Thesaurus format

**`agent/thesaurus/global.org`** (always the first shard consulted; holds every
sandbox-wide bookkeeping table):

```org
#+TITLE: Project terminology thesaurus — sandbox <name> — shard: global
#+UPDATED: <date>
#+LAST_HARVEST: never
#+DESCRIPTION: Validated project-term → KB-slot mappings for this sandbox, Scope=global.
               Maintained automatically by chorus-import-project. Part of a sharded
               thesaurus — see agent/thesaurus/<client>.org for other Scopes.
               Do NOT edit KB org files to add project aliases — use this file instead.
               #+LAST_HARVEST is set by `chorus-feed --harvest-aliases` (never edit manually).

* Aliases — type_element
  Project terms validated as mapping to a specific KB type_element, Scope=global.
  Applied at ✅ confidence on every future import without asking again — unless the
  KB has changed since validation (see "KB hash tracking & revalidation" below).

  | Project term             | KB type_element       | Confidence   | Source import     | KB hash @ validation | Scope   |
  |---|---|---|---|---|---|
  | panneau contreventement  | panneau_osb           | ✅ confirmed | import-report-001 | a1b2c3d4              | global  |
  | poteau intérieur cloison | montant_non_porteur   | ✅ confirmed | import-report-001 | a1b2c3d4              | global  |

* Aliases — slot values
  Project value expressions validated as mapping to a specific KB slot + value, Scope=global.
  Applied at ✅ confidence on every future import without asking again — unless the
  KB has changed since validation (see "KB hash tracking & revalidation" below).

  | Project term  | KB slot             | KB value | Confidence   | Source import     | KB hash @ validation | Scope   |
  |---|---|---|---|---|---|---|
  | classe 2      | traitement_applique | "cl2"    | ✅ confirmed | import-report-002 | a1b2c3d4              | global  |
  | laine 032     | classe_conductivite | "032"    | ✅ confirmed | import-report-002 | b5e6f7a8              | global  |

* Pending — to confirm on next import
  Terms provisionally mapped (⚠️) in a previous import, not yet confirmed by the engineer.
  Re-raised on next import if the same term appears — engineer decision upgrades to ✅ or rejects.
  Sandbox-wide (not sharded — lives only in global.org, regardless of which Scope the
  term will eventually resolve to once confirmed).

  | Project term   | Proposed KB mapping            | Flag              | Source import     |
  |---|---|---|---|
  | isolant soufflé | type_element: isolant_vrac ?  | ⚠️ _a_confirmer  | import-report-003 |

* Out-of-scope terms (⬜)
  Terms explicitly identified as outside this sandbox's KB scope.
  Silently excluded on future imports — not re-raised to the engineer.
  Sandbox-wide (not sharded — lives only in global.org).

  | Project term  | Reason                      | Recommended sandbox  | Last seen         |
  |---|---|---|---|
  | bardage zinc  | hors périmètre sandbox-structurel | sandbox-bardage | import-report-001 |

* Conflicts (⚠️ CONFLICT — blocking, requires engineer arbitration)
  A term already resolved to one mapping **at a given Scope** in a prior import,
  re-encountered with a **different** mapping **at that same Scope** in a later import.
  Cross-scope differences (e.g. `client-alpha` vs. `client-beta`) are **not** conflicts
  — see "Thesaurus scoping by context" above; they are two independent, correctly
  scoped rows, living in their respective shards. A true Conflict only arises when
  both the term AND the Scope match but the target mapping differs (legitimate
  homonymy within the same scope — a rarer, genuinely ambiguous case). Never
  auto-resolved, never silently overwritten — see "Deduplication rule" below. Must be
  arbitrated before the conflicting term is applied again.
  Sandbox-wide (not sharded — lives only in global.org, even for a same-scope conflict
  detected on a client shard: the Scope column already identifies which shard is
  affected, no need to duplicate the table per shard).

  | Project term | Scope   | Existing mapping                        | New mapping                              | First seen         | Conflict raised in | Status            |
  |---|---|---|---|---|---|---|
  | poteau        | global  | montant_porteur (import-report-012)     | montant_non_porteur (import-report-340)  | import-report-012  | import-report-340  | ⚠️ to arbitrate  |
```

**`agent/thesaurus/client-alpha.org`** (an example client shard — only the two
`* Aliases` tables, same columns, same Scope value repeated on every row for clarity
even though it is implied by the filename):

```org
#+TITLE: Project terminology thesaurus — sandbox <name> — shard: client-alpha
#+UPDATED: <date>
#+DESCRIPTION: Validated project-term → KB-slot mappings for this sandbox, Scope=client-alpha.
               Maintained automatically by chorus-import-project. Part of a sharded
               thesaurus — see agent/thesaurus/global.org for Pending/Out-of-scope/Conflicts.
               Do NOT edit KB org files to add project aliases — use this file instead.

* Aliases — type_element
  Project terms validated as mapping to a specific KB type_element, Scope=client-alpha.

  | Project term | KB type_element  | Confidence   | Source import     | KB hash @ validation | Scope        |
  |---|---|---|---|---|---|
  | poteau        | montant_porteur | ✅ confirmed | import-report-012 | c3d4e5f6              | client-alpha |

* Aliases — slot values
  Project value expressions validated as mapping to a specific KB slot + value, Scope=client-alpha.

  | Project term | KB slot | KB value | Confidence | Source import | KB hash @ validation | Scope |
  |---|---|---|---|---|---|---|
```

#### KB hash tracking & revalidation

Every `* Aliases` row records the **`.kb-hash`** in effect at the moment the mapping was
validated (`KB hash @ validation` column). This is a **read-only comparison mechanism**
— it never triggers a `.kb-hash` write or invalidation from `chorus-import-project`
itself (only `chorus-feed --enrich` / `--harvest-aliases` write `.kb-hash`, since only
they modify `<slug>.org` files).

**Why:** a `✅ confirmed` mapping is validated against a specific state of the KB (a
given slot definition, a given `type_element` semantics). If the KB is later enriched
or a `type_element`'s meaning/scope changes (`chorus-feed --enrich`), an old thesaurus
mapping could silently keep pointing at a slot that no longer means what it meant when
validated — applied at ✅ confidence forever, with no signal that anything changed.

**Mechanism:**
1. **At validation time** (Phase 3, "Immediate thesaurus update after each resolution"):
   read `$SANDBOX/agent/.kb-hash` (if present) and record its first 8 hex chars in the
   `KB hash @ validation` column of the new/updated Aliases row. If `.kb-hash` is absent
   (KB predates hash tracking, or infra never generated for this sandbox), record `—`
   and skip step 2 below for that row until a hash becomes available.
2. **At lookup time** (Phase 3, "How the thesaurus is used", steps 1–2 below): before
   applying a thesaurus hit at ✅ confidence, compare the row's `KB hash @ validation`
   to the **current** `$SANDBOX/agent/.kb-hash`:
   - **Identical** (or row has `—`) → apply normally, as today.
   - **Different** → the KB changed since this mapping was validated. Do **not** apply
     silently — downgrade the hit to `⚠️ à reconfirmer` and re-raise to the engineer:
     ```
     ⚠️ KB changed since validation — term "poteau" was mapped to montant_porteur
        when the KB hash was a1b2c3d4 (import-report-012). The KB has since changed
        (current hash: f9e8d7c6). Confirm this mapping is still correct, or update it.
        a) Still correct — reconfirm (updates KB hash @ validation to current)
        b) No longer correct — provide the new mapping
     ```
     On (a): update the row's `KB hash @ validation` to the current hash, keep
     `✅ confirmed`, keep the original `Source import`. On (b): treat as a normal
     ❓/⚠️ resolution (Phase 3, "Resolving Ambiguities") and write the corrected mapping.
3. This check is a simple string comparison of two hash values already on disk — no
   extra KB read, no extra hashing pass. Negligible cost per import.

> ⚠️ **Never** infer a `.kb-hash` value or write to `.kb-hash` from within
> `chorus-import-project` — reading it is the only allowed operation. If `.kb-hash`
> is absent for a sandbox that clearly has a generated KB (e.g. `chorus-check` was
> run before), treat all rows as `—` (no comparison) rather than guessing a value.

#### Thesaurus scoping by context

On a multi-project / multi-client sandbox (e.g. a production compliance portal
importing hundreds of projects across different clients or domains), the **same
project term can legitimately mean different things** depending on context (homonymy,
not error — cf. "poteau" → `montant_porteur` for one client's convention vs.
`montant_non_porteur` for another's). A single flat namespace per sandbox forces every
such case through the `* Conflicts` mechanism (Phase 3 Deduplication rule) even when
both mappings are permanently valid side by side — which is correct the first time,
but becomes noisy if the same two clients keep re-triggering the same "conflict" on
every import.

**Every `* Aliases` row carries a `Scope` column:**
- `global` — the mapping is considered valid across the whole sandbox, regardless of
  which import/context it came from. This is the **default** for any import whose
  context resolves to `global` (see "Scope derivation" below) — preserves current
  behaviour exactly for sandboxes that never use client-scoped folders or `--context`.
- `<context-label>` — the mapping is valid **only** within imports declared under that
  same context label.

#### Scope derivation — where does the label actually come from

The Scope used for a given import (`C` in the lookup/dedup rules below) is resolved by
this **strict, three-step cascade** — evaluated in order, first match wins:

```
1. --context <label> passed explicitly on the command line
   → C = <label> (highest priority — manual override always wins)

2. Otherwise, if every source file for this import lives under
   $SANDBOX/$WORKSPACE/<X>/sources/  (see AGENTS.md § "$WORKSPACE/<client>/ convention")
   → C = <X>  (the immediate folder name under $WORKSPACE, one level above `sources/`)
   Reports for this import are then written to $SANDBOX/$WORKSPACE/<X>/reports/
   instead of the flat $SANDBOX/$WORKSPACE/reports/.

3. Otherwise (source is inline content, a single loose file, a directory that is not
   a `<X>/sources/` folder, or sources span more than one <X>)
   → C = "global"  (current/default behaviour, unchanged)
```

**Step 2 is intentionally strict** — it only triggers for the exact
`$WORKSPACE/<client>/sources/` structure, never for an arbitrary directory path passed
as `<source>`. A `Batch Mode` import on `./some-folder/` that is *not* nested under
`$WORKSPACE/<client>/sources/` always resolves to `global` (step 3) — directory-name
scoping is deliberately **not** inferred from arbitrary paths, only from this one
documented convention, to keep the rule predictable and avoid accidental scoping from
an unrelated folder name.

> **Extra content under `<client>/` is irrelevant to this detection rule.** Only the
> presence of `<client>/sources/` (and, once written, `<client>/reports/`) matters —
> see `AGENTS.md § "$WORKSPACE/<client>/ convention" → Conformance rule`. A client
> folder may also contain arbitrary other files/subfolders (produced project JSON,
> reference fixtures, scratch data, etc.) — these have no effect on Scope derivation
> and are never inspected, categorised, or flagged by this skill.

**Mixed-context batch guard:** if a Batch/Merge import's source files are spread
across *more than one* `<X>/sources/` folder in the same invocation (e.g. the engineer
passed `--batch` over a glob spanning two clients) → **stop and report**, do not guess:
```
⛔ Sources span multiple client contexts (client-alpha/sources/, client-beta/sources/)
   in a single import run — Scope cannot be derived unambiguously.
   Run one import per client folder, or pass --context explicitly to force a single Scope.
```

**Lookup resolution order for a term T under context C** (C resolved as above):
```
1. Look for a row matching (T, Scope = C)              → exact context match, apply ✅
2. If not found, look for a row matching (T, Scope = global) → global fallback, apply ✅
3. If neither found → proceed with standard KB lookup (Phase 3 standard flow)
```
A scoped row (`Scope = C`) **never** answers a lookup made under a different context
`C' ≠ C` (except the `global` fallback in step 2, which flows the other way: a
`global` row always answers any context). This is the key difference from a flat
namespace: two clients can validate two different mappings for "poteau" and **both
stay permanently active**, side by side, without ever touching `* Conflicts` — as
long as each was resolved to its own distinct Scope (via `--context` or auto-derived
from `$WORKSPACE/<client>/sources/`).

**When does this become a real Conflict (Phase 3 Deduplication rule) instead?**
Only when the **same term at the same Scope** (both `global`, or both the identical
context label) gets two different mappings. Cross-context collisions
(`client-alpha` vs. `client-beta`) are **not** conflicts — they are simply two
independent, correctly scoped rows. The Deduplication rule (Phase 3, "Immediate
thesaurus update") must compare `(term, Scope)` as the dedup key, not `term` alone.

**Promoting a scoped mapping to `global`:** if the same `(term → mapping)` pair is
independently validated under two or more different context labels with an
**identical** target mapping (not a conflict — same meaning recurring across
contexts), the engineer may explicitly promote it to `Scope = global` on the next
occurrence, merging the redundant scoped rows into one. This is never automatic —
propose it, do not perform it silently:
```
💡 "classe 2" was independently validated identically under 3 different contexts
   (client-alpha, client-beta, client-gamma) — same mapping (traitement_applique="cl2")
   each time. Promote to Scope = global to stop tracking it per-context? (y/n)
```

**No scoping in effect at all (default sandbox usage):** if `--context` is never used
and no import is ever run from a `$WORKSPACE/<client>/sources/` folder, every row is
`global`, lookup step 1 never applies (no non-global scope exists), behaviour is
byte-for-byte identical to a sandbox that never adopts scoping. This mechanism is
purely additive.

#### How the thesaurus is used in Phase 3

When building the alignment table (Phase 3), **check the thesaurus first** for every
term in the raw inventory. In practice this means: for steps 1–2 (Aliases), only the
two shards already loaded in memory (`global.org` + `<C>.org` if `C != global`, per
"Thesaurus storage layout" above) are consulted — never a shard for a different
client. Steps 0/3/4 (Conflicts/Out-of-scope/Pending) always look in `global.org` only,
since those tables are never sharded.

```
For each project term T, with C = current import's Scope (resolved per "Scope derivation" above):
  0. Look up T in global.org → Conflicts (Scope = C or global) : hit (unresolved) → block,
                                                        re-raise ⚠️ CONFLICT to engineer
  1. Look up T in <C>.org → Aliases type_element, then in global.org → Aliases type_element
     (fallback) : hit → check KB hash (see "KB hash tracking & revalidation" above);
       identical → apply ✅, skip KB lookup; different → downgrade to ⚠️ à reconfirmer
  2. Look up T in <C>.org → Aliases slot values, then in global.org → Aliases slot values
     (fallback) : hit → same KB hash check as step 1
  3. Look up T in global.org → Out-of-scope        : hit → mark ⬜, skip KB lookup
  4. Look up T in global.org → Pending              : hit → re-raise ⚠️ to engineer
  5. Not in thesaurus (neither <C>.org nor global.org) → proceed with KB lookup (Phase 3 standard flow)
```
(When `C = global`, steps 1–2 simply read `global.org` once — there is no separate
`<C>.org` to consult, no behaviour change from a non-sharded lookup.)

> **Scope resolution order (steps 1–2):** an exact match on the current import's
> context `C` (its own shard) always wins over a `global` row for the same term —
> check the `<C>.org` shard first, fall back to `global.org` only if no `C`-scoped row
> exists there. See "Thesaurus scoping by context" above for the full rationale and
> the promotion-to-global mechanism.

> **Rule:** a thesaurus hit at step 1–3 is **final** — do not re-ask the engineer,
> do not consult the KB, do not propose alternatives. The engineer already decided.
> **Exception:** steps 1–2 are final only if the KB hash check passes (see above) —
> a stale mapping following a KB change is never applied silently.
>
> A thesaurus hit at step 4 (Pending) re-raises the question exactly once. If the
> engineer confirms → move the entry to Aliases (in the shard matching the current
> import's Scope `C`) and record ✅. If rejected → move to Out-of-scope (global.org)
> and record ⬜.
>
> A thesaurus hit at step 0 (Conflicts, unresolved) **blocks** — never apply either
> mapping automatically. Present both candidate mappings to the engineer for
> arbitration (see "Conflict resolution" below). An unresolved conflict for a term
> takes priority over any other thesaurus section for that same term.

#### Thesaurus initialisation

If neither `$SANDBOX/agent/thesaurus/` nor a legacy `$SANDBOX/agent/thesaurus.org`
exists yet, the sharded layout is created automatically at the end of the first import
that produces at least one ✅ or ⚠️ alignment (Phase 6 — see below): `global.org` is
always created first; a `<C>.org` shard is created only if that import's Scope `C` is
not `global`. No manual creation is required.


### 1.3 Previous alignment decisions

If `$WORKSPACE/import-report-*.org` exists (`$WORKSPACE` = `$SANDBOX/workspace/`),
read the **latest report** as a secondary memory source — complementary to the
thesaurus, not a substitute.

- Retrieve mappings not yet promoted to the thesaurus → reapply without asking
- Retrieve pending questions not yet in thesaurus → re-raise if the same terms reappear
- **Skip any entry already covered by thesaurus.org** (1.2b takes priority)


## Phase 2 — Raw Inventory of Project Elements

### Keepalive — block-based inventory (intra-phase token refresh)

**Before starting the inventory**, if the source is a filesystem file, call:
```bash
wc -l "<fichier-source-extrait>"
```
or, if working from inline/already-extracted text, read the directory tree `$SANDBOX/agent/`
to confirm the report directory.

Use the line count to estimate the number of elements (`N_est ≈ lines / 8`).

#### Block-based inventory protocol

> **Why blocks instead of a single silent pass:**
> Phases 2, 3 and 4 were previously pure thinking phases with no tool calls.
> On a large source (hundreds of elements, dense terminology), the combined thinking
> time could exceed the IDE token TTL before Phase 5 writes the first file.
> The fix is simple: **write a partial file every 50 elements** — each `eca__write_file`
> call resets the token TTL without splitting the document or losing context.
> The entire source is read in one pass; only the *writes* are batched.

```
BLOCK_SIZE = 50   # elements per partial write

block_num  = 1
inventory  = []   # accumulates ALL elements across all blocks

For each element E identified in the source (full sequential scan):
  Append E to inventory

  If len(inventory) % BLOCK_SIZE == 0:
    # Keepalive write — resets IDE token TTL
    Write eca__write_file:
      path    : $SANDBOX/agent/.import-inventory-<NNN>-blk<block_num>.org
      content : partial inventory (last BLOCK_SIZE elements)
    block_num += 1
    Print: "[Phase 2] Inventory block <block_num-1> written — <len(inventory)> elements so far"

# After full scan — write consolidated inventory (used by Phase 3)
Write eca__write_file:
  path    : $SANDBOX/agent/.import-inventory-<NNN>.org
  content : full inventory (all elements, all blocks)
Print: "[Phase 2] Complete inventory written — <len(inventory)> elements total"
```

**Format of each inventory entry (org):**

```org
** Element <seq>
   :PROPERTIES:
   :source_line: <original text from document>
   :END:
   - term_raw    :: <term as found>
   - values_raw  :: <associated raw values>
   - page_or_loc :: <page N / sheet S / block B>
```

> **Rule:** do not map at this stage — inventory first, align later.
> Preserve the original source text in the inventory for traceability.
> The `.import-inventory-<NNN>.org` file is the single source of truth for Phase 3.
> Partial block files (`.import-inventory-<NNN>-blk*.org`) are transient — kept until
> Phase 6 cleanup.

Scan the source data and produce a **raw inventory**:
an uninterpreted list of what the engineer has provided.

```
Source line / cell              Term identified      Associated values
────────────────────────────────────────────────────────────────────────
"Poteau porteur 45×145 C24"    "poteau porteur"     dim=45×145, classe=C24
"h libre 2,5m, entraxe 40cm"  "h libre"            2.5m / "entraxe"=40cm
"Laine de verre λ035, e=20cm" "laine de verre"     λ=0.035, e=200mm
"panneau OSB 12mm, CE"         "panneau OSB"        ep=12mm, CE=oui
```

> **Rule:** do not map at this stage — inventory first, align later.
> Preserve the original source text in the inventory for traceability.


## Phase 3 — Terminology Alignment

### KB Coverage Gauge (pre-alignment check)

**Before starting the term-by-term alignment**, compute a coverage indicator from the
raw inventory (Phase 2) against the KB reference (Phase 1.2):

```
📊 KB Coverage Gauge
   Distinct types detected in inventory : N  (e.g. 8)
   Types recognised in KB               : n / N  (e.g. 5 / 8 = 62%)
   Critical slots covered               : n / total  (e.g. 11 / 17 = 65%)
   KB Aliases section present           : yes / no
```

| Coverage | Level | Action |
|---|---|---|
| ≥ 80% types + ≥ 80% critical slots | 🟢 Good | Proceed directly |
| 60–79% on either axis | 🟡 Moderate | Proceed with a warning — flag `_couverture_kb: moderate` in the JSON `_import` block |
| < 60% on either axis | 🔴 Low | Emit the warning below and ask whether to continue |

**🔴 Low-coverage warning (display before alignment):**

```
⚠️  KB Coverage Gauge — LOW COVERAGE DETECTED
    Types recognised   : n/N (XX%)
    Critical slots     : n/N (XX%)

    The KB may lack aliases for the project's terminology.
    Risk: many terms will receive ❓ (ambiguous) or ⬜ (out-of-scope),
    producing an incomplete or unusable JSON.

    Recommended actions (choose one or both):
      1. Run `chorus-feed --harvest-aliases <previous-import-report.org>`
         if a validated import report exists for this sandbox.
      2. Enrich the KB: add aliases to `$SANDBOX/agent/chorus/<slug>.org`
         under `** Aliases` before re-running this import.

    Continue anyway? [yes / abort]
```

If the engineer confirms `yes`, proceed — but set `"_couverture_kb": "low"` in the
`_import` block and list the unrecognised types under a dedicated section
`* KB coverage gap` in the import report (Phase 6).

> **Batch mode:** compute the gauge once per file, using the shared KB loaded in Phase 1.
> Files with 🔴 coverage are flagged in the batch summary report (Phase 6-BATCH)
> with a `⚠️ low KB coverage` marker in the results table — the batch is not aborted.


### Alignment table

#### Block-based alignment protocol (intra-phase keepalive)

> **Why blocks:** the alignment phase processes every distinct term from the inventory
> against the KB reference. On a large project this can take 10–20 minutes of thinking
> with no tool call — enough to expire the IDE token.
> The fix: **read the consolidated inventory file written by Phase 2** (one tool call =
> keepalive), then **write a partial alignment file every 20 terms** — each write resets
> the token TTL. Full context (KB + inventory) is preserved throughout; only the *writes*
> are batched.

```
# Step 0 — reload inventory from disk (keepalive + single source of truth)
Read eca__read_file:
  path: $SANDBOX/agent/.import-inventory-<NNN>.org
terms = all distinct terms extracted from the inventory
Print: "[Phase 3] Inventory loaded — <len(terms)> distinct terms to align"

BLOCK_SIZE = 20   # terms per partial write

block_num  = 1
alignment  = []   # accumulates ALL aligned terms across all blocks

For each term T in terms (full sequential alignment):
  Align T against KB reference (Phase 1.2) → produce alignment row
  Append row to alignment

  If len(alignment) % BLOCK_SIZE == 0:
    # Keepalive write — resets IDE token TTL
    Write eca__write_file:
      path    : $SANDBOX/agent/.import-alignment-<NNN>-blk<block_num>.org
      content : partial alignment table (last BLOCK_SIZE rows)
    block_num += 1
    Print: "[Phase 3] Alignment block <block_num-1> written — <len(alignment)> terms done"

# After all terms — write consolidated alignment (used by Phase 4 and Phase 5)
Write eca__write_file:
  path    : $SANDBOX/agent/.import-alignment-<NNN>.org
  content : full alignment table (all terms)
Print: "[Phase 3] Complete alignment written — <len(alignment)> terms total"
```

> **Context integrity guarantee:** the full KB reference (Phase 1.2) and the full
> inventory (all elements) remain in the agent's context window throughout.
> Only the *output writes* are split into blocks — the alignment reasoning always
> sees the complete picture. No information is lost, no cross-element context is broken.

> **Partial block files** (`.import-alignment-<NNN>-blk*.org`) are transient.
> The **consolidated file** (`.import-alignment-<NNN>.org`) is the single source of
> truth for Phases 4 and 5. Both are cleaned up at the end of Phase 6.

---

This is the core phase. For each term from the raw inventory, cross-reference against
the KB reference (Phase 1.2) and produce an alignment table:

```
Project term                  KB slot / type_element    KB value         Confidence
──────────────────────────────────────────────────────────────────────────────────
"poteau porteur"              type_element              montant_porteur  ✅ certain
"45×145"                      section_bois              "45x145"         ✅ certain
"C24"                         classe_bois               "C24"            ✅ certain
"h libre 2,5m"                hauteur_libre_m           2.5              ✅ certain
"entraxe 40cm"                entraxe_mm                400              ✅ certain (×10)
"laine de verre λ035"         type_element              isolant_laine    ✅ certain
                              classe_conductivite       "035"            ✅ certain
"panneau OSB 12mm"            type_element              panneau_osb      ✅ certain
                              osb_epaisseur_mm          12               ✅ certain
"poteau intérieur cloison"    type_element              montant_non_porteur ⚠️ likely
"panneau contreventement"     type_element              panneau_osb ?    ❓ ambiguous
"traitement cl. 2"            traitement_applique ?     ?                ❓ to clarify
```

### Confidence Levels

| Symbol | Meaning | Action |
|---|---|---|
| ✅ certain | Direct or near-direct match with the KB | Map without asking |
| ⚠️ likely | Logical match but term is not exact | Propose + ask for confirmation |
| ❓ ambiguous | Multiple possible mappings or unknown KB term | Block + ask for clarification |
| ⛔ gap | Mandatory slot absent from the source document | Report — do not invent |
| ⬜ out-of-scope | `type_element` absent from this sandbox's KB | Exclude from JSON — flag `_hors_perimetre: 1` + report |

> **Out-of-scope rule:** an element receives `⬜` if its `type_element` is not recognised
> by **any** `Catalogue des Frames` in the target sandbox. This is non-blocking — the import
> continues. The element is excluded from the output JSON and listed in the
> `Out-of-scope elements` section of the import report.
>
> **Architectural consequence:** a multi-domain project (e.g. structural + thermal) must
> be imported **once per target sandbox** — each import retains only the types that sandbox
> knows. `chorus-import-project` is the partitioning tool; `run.pl` only sees the elements
> that concern it.
>
> ```bash
> # Mixed project → two targeted imports
> chorus-import-project sandbox-structurel ./dossier-project/ --batch
>     # → JSON containing only montant_porteur, lisse_basse, ...
>     # → elements isolant_laine, membrane_etanche → ⬜ excluded + report
>
> chorus-import-project sandbox-thermique ./dossier-project/ --batch
>     # → JSON containing only isolant_laine, membrane_etanche, ...
>     # → elements montant_porteur, lisse_basse → ⬜ excluded + report
> ```

### Figure identifiers as matching candidates (hybrid mode)

When the source document was extracted in hybrid mode, each `[FIGURE N]` block ends with
an `IDENTIFIERS: [...]` line listing the labels and codes visible in the figure (callout
tags, part numbers, element IDs).

**These identifiers are first-class matching candidates** for Phase 3:

1. **Cross-reference with KB aliases** — if `chorus-feed` has populated an
   `** Aliases from figures` table in the KB `Ontologie` (built from the XREF INDEX of
   the normative corpus), check whether the identifier appears there. A direct hit gives
   confidence ✅ and maps directly to the corresponding `type_element` or slot value.

2. **Cross-reference with figure description body** — if the identifier is not in the KB
   aliases, search the description text of the same `[FIGURE N]` block for a co-occurring
   corpus term. Example: `IDENTIFIERS: ["P1"]` + description mentions *"Poteau porteur
   45×145 C24"* → candidate `type_element: montant_porteur` at confidence ⚠️.

3. **Cross-reference with surrounding text blocks** — search the raw inventory (Phase 2)
   for text blocks on the same page that mention the identifier alongside a known slot
   value. Example: `P1` appears in a table row *"P1 — 45×145 — C24 — h=2.5m"* on the
   same page → aggregate all slot values from that row under the element `id: P1`.

4. **Preserve identifier as `id`** — when an element is successfully mapped, use the
   figure identifier as the element `id` in the output JSON (preferred over a generated
   ID), since it matches the document's own reference system and enables
   document ↔ JSON traceability.

> **Rule:** figure identifiers that could not be matched to any KB term after steps 1–3
> are listed in the import report under a dedicated section
> `* Unmatched figure identifiers` — they are candidates for a future `chorus-feed --enrich`
> run to extend the KB aliases.

### Unit Transformations

Explicitly document every conversion:

| Source pattern | Transformation | KB Slot |
|---|---|---|
| `2,5m` / `2.5m` / `250cm` | → `2.5` | `hauteur_libre_m` |
| `40cm` / `400mm` / `0,4m` | → `400` | `entraxe_mm` |
| `20cm` / `200mm` | → `200` | `epaisseur_mm` |
| `λ=0,035` / `λ035` / `laine 035` | → `"035"` | `classe_conductivite` |
| `45/145` / `45×145` / `45x145` | → `"45x145"` | `section_bois` |
| `C 24` / `classe C24` / `C24 EN338` | → `"C24"` | `classe_bois` |

### Resolving Ambiguities

For each ❓ term, present the following to the engineer:
```
❓ "panneau contreventement" — multiple interpretations possible:
   1. panneau_osb     (structural OSB panel §3.1)
   2. panneau_fibragglo (bracing panel §3.2)
   Which type matches your document?
```

**Do not proceed until blocking ❓ items are resolved** (ambiguous `type_element` slots).
⚠️ items may be provisionally accepted with a `_a_confirmer: 1` flag.

### Immediate thesaurus update after each resolution

**After each engineer decision** (❓ resolved or ⚠️ confirmed/rejected), write the
result **immediately** — do not wait for Phase 6 — into the shard matching the current
import's Scope `C`:
- `* Aliases` writes go to `$SANDBOX/agent/thesaurus/<C>.org` (or `global.org` if `C = global`)
- `* Pending`, `* Out-of-scope`, `* Conflicts` writes always go to `$SANDBOX/agent/thesaurus/global.org`
  regardless of `C` (these tables are never sharded — see "Thesaurus storage layout")

This ensures the thesaurus is always up to date, even if the session is interrupted
before Phase 6 completes.

#### Mapping resolution → thesaurus section

| Engineer decision | Thesaurus action |
|---|---|
| ❓ resolved → ✅ (type_element chosen) | Append to `* Aliases — type_element` in the shard for the current import's Scope (`<C>.org`, or `global.org` if `C = global`) — **unless a row with the same `(term, Scope)` already has a different mapping (checked against that same shard) → append to `* Conflicts` in `global.org` instead (see Deduplication rule below)** |
| ❓ resolved → ✅ (slot value chosen) | Append to `* Aliases — slot values` in the shard for the current Scope — **same conflict check as above** |
| ⚠️ confirmed → ✅ | Move from `* Pending` (in `global.org`) to `* Aliases` in the shard for the current Scope — **same conflict check as above** |
| ⚠️ rejected → ⬜ | Move from `* Pending` to `* Out-of-scope terms` (both in `global.org`) |
| ❓ unresolvable → ⬜ (engineer: "exclude") | Append to `* Out-of-scope terms` (`global.org`) |
| New ⚠️ (first time seen) | Append to `* Pending` (`global.org`) |
| Term already in `* Conflicts` at the current Scope (unresolved), re-encountered | Do not touch any `* Aliases` shard — re-raise for arbitration (see "Conflict resolution") |

#### Write format per section

**Alias confirmed (type_element):**
```org
| <project term> | <KB type_element> | ✅ confirmed | import-report-<NNN> | <kb_hash8 or —> | <Scope: global or context-label> |
```

**Alias confirmed (slot value):**
```org
| <project term> | <KB slot> | <KB value> | ✅ confirmed | import-report-<NNN> | <kb_hash8 or —> | <Scope: global or context-label> |
```

**New pending entry:**
```org
| <project term> | type_element: <proposed> ? | ⚠️ _a_confirmer | import-report-<NNN> |
```

**Out-of-scope:**
```org
| <project term> | <reason> | <recommended sandbox or "unknown"> | import-report-<NNN> |
```

**Conflict (mapping mismatch at the same Scope — never a duplicate write to `* Aliases`):**
```org
| <project term> | <Scope: global or context-label> | <existing mapping> (<existing source import>) | <new mapping> (<new source import>) | <first seen import> | <conflict raised in import> | ⚠️ to arbitrate |
```

#### Thesaurus creation (first import)

If `$SANDBOX/agent/thesaurus/` does not yet exist (and no legacy `thesaurus.org`
either — see "Legacy monolithic thesaurus.org" above) → create
`agent/thesaurus/global.org` using the global shard format defined above (Thesaurus
format), with `* Aliases — type_element`, `* Aliases — slot values`, `* Pending`,
`* Out-of-scope terms`, and `* Conflicts` all empty (headers only, no example rows).
If the current import's Scope `C` is not `global`, also create `agent/thesaurus/<C>.org`
using the client-shard format (only the two `* Aliases` tables). Then append the first
resolved entry under the appropriate section/shard.

> ⚠️ **Deduplication rule:** before appending any entry, check whether the pair
> `(project term, Scope)` already exists in the target shard's `* Aliases —
> type_element` or `* Aliases — slot values` — where `Scope` is the current import's
> context (resolved per "Scope derivation" above). In practice this means checking
> only the shard(s) already loaded for this import (`<C>.org` and/or `global.org` —
> never a shard for a different client, since a different-Scope row cannot exist in
> a shard that was never read for this import).
>
> - **If a row with the same `(term, Scope)` exists and its mapping is identical** to
>   the new one → **update** the existing row (confidence, source import) in place,
>   in its own shard, rather than inserting a duplicate. This is the only case where
>   a silent update is correct.
> - **If a row with the same `(term, Scope)` exists and its mapping differs** from the
>   new one → this is a **mapping conflict**, not a duplicate. **Never overwrite the
>   existing row.** Instead:
>   1. Leave the existing `Aliases` row untouched (in its shard).
>   2. Append a new row to `* Conflicts` **in `global.org`** with both mappings, their
>      respective source imports, the shared Scope, and status `⚠️ to arbitrate`.
>   3. Do **not** apply either mapping automatically on this or future imports at this
>      Scope until the conflict is arbitrated (see Phase 3 lookup step 0 and "Conflict
>      resolution" below).
> - **If the term exists only at a *different* Scope** (e.g. new row would go in
>   `client-beta.org`, but an existing row for the same term lives in
>   `client-alpha.org`, or in `global.org`) → **this is not a conflict.** Simply append
>   the new row as an independent entry in its own shard — both stay permanently
>   active side by side, in different files (see "Thesaurus scoping by context"). Note
>   that under sharding, this case is even less likely to be noticed accidentally,
>   since the two rows never even appear in the same file.
>
> This mirrors the existing **Id conflict handling** (multi-source import, § 1 above):
> conflicting evidence **at the same scope** is never silently merged — it is surfaced
> as an explicit, engineer-arbitrated conflict record. Evidence at *different* scopes
> is not conflicting evidence at all — it is deliberately parallel, valid knowledge,
> now additionally isolated by file boundary.

#### Conflict resolution (engineer arbitration)

When a term in `* Conflicts` is encountered again in a new import (or when the engineer
explicitly revisits the thesaurus), present it for arbitration:

```
⚠️ CONFLICT — term "poteau" has two validated mappings at the same Scope (global):
   1. montant_porteur      (validated in import-report-012)
   2. montant_non_porteur  (validated in import-report-340)
   This may be legitimate homonymy (same word, different meaning depending on context)
   rather than an error. How should this import's occurrence of "poteau" be resolved?
   a) Apply mapping 1 (montant_porteur) — this occurrence only
   b) Apply mapping 2 (montant_non_porteur) — this occurrence only
   c) One of the two mappings is wrong — correct it permanently (specify which)
   d) Both are legitimate but depend on context — rescope them: assign mapping 1 to a
      new context label (e.g. "client-x") and mapping 2 to another (e.g. "client-y").
      Future imports must pass --context <label> to resolve "poteau" without asking
      again; imports without --context keep hitting this conflict at global Scope
      unless one of the two rescoped rows is also duplicated as `global`.
```

- **(a) or (b)** — this occurrence only: apply the chosen mapping to the current import's
  element, but **leave the `* Conflicts` entry open** (status stays `⚠️ to arbitrate`) —
  the ambiguity remains for future imports.
- **(c)** — permanent correction: update the `* Aliases` row with the corrected mapping,
  remove the row from `* Conflicts` (status `✅ resolved`), and record which of the two
  prior imports is now considered to have been mis-mapped.
- **(d)** — rescope: split the single `global`-Scope conflict into two distinct
  `* Aliases` rows, each with its own context label as `Scope` (per "Thesaurus scoping
  by context" above). Remove the row from `* Conflicts` (status `✅ resolved — rescoped`).
  Going forward, only imports run without `--context` (or with a third, unrelated
  context) would ever re-trigger ambiguity for this term — and only if a `global` row
  is also added later for it.
- Never resolve a `* Conflicts` entry by silently picking one side without engineer input.

### --align-review mode — stop here for human validation

If `--align-review` was specified, **stop after Phase 3** and produce an alignment review
file instead of proceeding to Phase 4 / JSON generation:

1. **Write** `$WORKSPACE/align-review-<NNN>.org` (`$WORKSPACE` =
   `$SANDBOX/workspace/`, created if absent):

```org
#+TITLE: Alignment review — <source> — <date>
#+STATUS: pending-validation

* KB Coverage Gauge
  Types recognised   : n/N (XX%)
  Critical slots     : n/N (XX%)
  Coverage level     : 🟢 good / 🟡 moderate / 🔴 low

* Full alignment table
  | Project term | KB slot / type_element | KB value | Confidence | Notes |
  |---|---|---|---|---|
  | ...          | ...                    | ...      | ✅/⚠️/❓   | ...   |

* Items requiring engineer decision
  ** Ambiguous (❓) — must be resolved before JSON generation
     | Term | Options | Decision |
     |---|---|---|

  ** Likely (⚠️) — provisionally accepted, confirm or override
     | Term | Proposed mapping | Confirm? |
     |---|---|---|

  ** Out-of-scope (⬜) — will be excluded from JSON
     | Term | Reason | Correct sandbox? |
     |---|---|---|

* Gaps identified at this stage
  | Element id | Missing slot | Mandatory? |
  |---|---|---|

* How to proceed
  1. Review and annotate this file (correct ❓ decisions, confirm/reject ⚠️ items)
  2. Rerun WITHOUT --align-review to produce the JSON:
     chorus-import-project <sandbox> <source>
     The skill will reload this align-review file (Phase 1.3) and apply your decisions.
```

2. **Display** a summary to the engineer:
```
✅ Alignment review produced: $WORKSPACE/align-review-NNN.org
   ✅ certain  : N terms
   ⚠️ likely   : N terms (to confirm)
   ❓ ambiguous: N terms (must be resolved)
   ⬜ out-of-scope: N terms
   ⛔ gaps     : N mandatory slots absent

   Next step: review the file, then rerun without --align-review to generate the JSON.
```

3. **Do not** proceed to Phase 4, Phase 5, or Phase 6.
   The JSON is produced only on the subsequent run (without `--align-review`),
   after the engineer has validated the alignment file.


## Phase 3.5 — Inter-Element Relationship Detection

> **Prerequisite:** Phase 3 complete — `.import-alignment-<NNN>.org` lists all elements
> with their confirmed `id` and `type_element`.
>
> **Skip condition:** if no KB org slot has a `Frame ref` or `→` annotation (see
> `chorus-engine-infra.md §3`), skip Phase 3.5 entirely and go directly to Phase 4.
> Print: `[Phase 3.5] No inter-frame relationships defined in KB — skipped.`

This phase detects explicit cross-element relationships in the project document and
generates the `*_ref` fields that Feed.pm's inter-frame mechanism requires.

---

### Step 3.5-1 — Build the relationship blueprint from KB

Scan the KB org slot dictionaries (loaded in Phase 1) for slots whose `type` column
contains `Frame ref` or whose description contains `→ <target_type>`.  Build:

```
blueprint = { source_type → { slot_name → target_type } }
# Derived ref_field name: slot_name + "_ref"
# e.g.:
#   buttressing_wall → { supports → external_wall }     ← ref_field: supports_ref
#   external_wall    → { building → residential_building|non_residential_building }
#                                                        ← ref_field: building_ref
```

If the blueprint is empty after scanning, skip Phase 3.5.

---

### Step 3.5-2 — Scan the project document for relationship signals

For each `(source_type, slot_name, target_type)` entry in the blueprint, scan
the source document for signals that a source element is linked to a target element.

**Recognised signal patterns:**

| Signal type | Example | Confidence |
|---|---|---|
| Table column containing IDs of target type | "Building" column in a wall schedule | ✅ |
| Explicit language of containment | "Wall EW-01, located in Building B1" | ✅ |
| Explicit language of structural link | "BW-01 buttresses / supports EW-01" | ✅ |
| BIM-style attributes | "Host: RES-01", "Level: FL-01" | ✅ |
| Section/sub-section hierarchy | H2 = building, H3 = walls within it | ⚠️ |
| Spatial co-location (same figure, same row) | EW-01 and B1 on same drawing sheet | ⚠️ |
| No signal found | — | ❓ unresolved |

---

### Step 3.5-3 — Resolve target labels to element IDs

For each found relationship signal, resolve the target label to a concrete `id`
already present in `.import-alignment-<NNN>.org`:

1. **Direct match** — target label equals an `id` in the alignment → ✅
2. **Alias match** — target label matches a `_labels` alias or project term → ✅
3. **Type-filtered guess** — only one element of the expected target type → ⚠️
4. **Unresolved** — no match or multiple ambiguous matches → ❓

⛔ **Never generate a `*_ref` pointing to an ID not in the current import.**
⛔ **Never invent a relationship** absent from the document and not in the KB blueprint.

---

### Step 3.5-4 — Record findings in alignment file

Append an `* Inter-Element Relationships` section to `.import-alignment-<NNN>.org`:

```org
* Inter-Element Relationships (Phase 3.5)
  Blueprint: KB org → annotations (chorus-engine-infra.md §3)

  | element_id | slot_name | ref_field    | target_id | confidence | source_signal               |
  |------------|-----------|--------------|-----------|------------|-----------------------------|
  | BW-01      | supports  | supports_ref | EW-01     | ✅         | "BW-01 buttresses EW-01"    |
  | EW-01      | building  | building_ref | RES-01    | ✅         | Wall schedule, Building col |
  | EW-02      | building  | building_ref | RES-01    | ⚠️         | Same drawing as EW-01       |
  | IW-01      | building  | building_ref | (none)    | ❓         | No signal found in document |
```

**Confidence rules for Phase 4/5:**
- ✅ → include `*_ref` field in JSON output (Phase 5)
- ⚠️ → include with `_note` warning; flag for engineer review in import report
- ❓ → omit from JSON; report as optional gap in Phase 4

---

### Step 3.5 Print summary

```
[Phase 3.5] Inter-element relationships detected
  Blueprint entries : N (from KB org → annotations)
  ✅ resolved       : N  (will generate *_ref fields)
  ⚠️ inferred       : N  (included with warning)
  ❓ unresolved     : N  (optional — link absent from document)
```

---

### Impact on Phase 5 (JSON generation)

Phase 5 must include `*_ref` fields from the Phase 3.5 section of
`.import-alignment-<NNN>.org`:

- For each element with a ✅ or ⚠️ relationship entry → add `"<ref_field>": "<target_id>"`
- ⚠️ entries get an additional `"_note_<ref_field>": "inferred — verify"` annotation
- ❓ entries → omit silently (optional link)

```json
{
  "id": "EW-01",
  "type_element": "external_wall",
  "building_ref": "RES-01",
  "thickness_mm": 290,
  ...
}
```

> Note: `*_ref` fields are OPTIONAL in `%SLOTS_REQUIS` — their absence never causes
> Feed.pm to reject an element.  Rules use the Option A fallback pattern (direct slot
> when no link is present).  See `chorus-engine-yaml.md § Navigating a slot→Frame link`.


## Phase 4 — Identify Gaps

For each element, cross-reference the present slots against the KB `Catalogue des Frames`:

```
Type            Mandatory slot      Present?    Source
──────────────────────────────────────────────────────────
montant_porteur classe_bois         ✅          "C24"
montant_porteur humidite_pct        ⛔ ABSENT   not mentioned
montant_porteur hauteur_libre_m     ✅          "h=2.5m"
```

### Gap Handling

| Gap type | Action |
|---|---|
| Mandatory slot absent | Ask the engineer — do not assume |
| Optional slot absent | Omit from JSON — the pipeline handles it |
| `Derived:` slot absent (annotated `_NEEDED` in KB org) | **Not a gap** — omit from JSON silently; Feed.pm will compute it at runtime via `_NEEDED` coderef. Do NOT ask the engineer. |
| Out-of-domain value (e.g. `classe_bois: "C12"`) | Report — let the engineer correct it |
| Entire element unmappable | Include with `_incomplet: 1` — will be cleanly rejected by Feed |
| `Frame ref` slot (❓ in Phase 3.5) | Report as optional gap — `*_ref` absent is acceptable; rules use direct-slot fallback |


## Phase 5 — Produce the JSON

### Pre-flight — reload consolidated files (keepalive + integrity check)

Before generating the JSON, **read the two consolidated files** produced by Phases 2 and 3.
Each read is a tool call that resets the IDE token TTL and guarantees the JSON is built
from the canonical on-disk state rather than from context that may have drifted.

```
# Reload consolidated inventory (Phase 2 output)
Read eca__read_file:
  path: $SANDBOX/agent/.import-inventory-<NNN>.org
→ confirms element list, ids, source lines

# Reload consolidated alignment (Phase 3 output)
Read eca__read_file:
  path: $SANDBOX/agent/.import-alignment-<NNN>.org
→ confirms term → slot/value mappings, confidence levels, ❓/⚠️/⬜ flags

Print: "[Phase 5] Sources reloaded — <N_elements> elements / <N_terms> aligned terms"
```

> **Why reloading matters:** on a large project the agent may have spent 15–20 minutes
> thinking across Phases 2–4. Reloading from disk ensures the JSON is derived from the
> files that will persist in `$SANDBOX/agent/` — not from an in-context summary that
> could have silently compressed some detail.

### Output JSON location

The produced JSON (`project-import-<NNN>.json` in Single/Merge mode, or one such file
per source in Batch mode — see below) is written to:

```
1. --out <filename> passed explicitly       → write exactly there (path as given by
   the engineer — absolute or relative to the invocation's working directory).
   Explicit override, highest priority, unchanged behaviour.

2. Otherwise, if this import's Scope C != "global" (i.e. it was resolved from
   $WORKSPACE/<C>/sources/ or from --context <C> — see "Scope derivation", Phase 1.2b)
   → $SANDBOX/$WORKSPACE/<C>/project-import-<NNN>.json
   (same <client>/ folder as this import's sources/ and reports/ — keeps everything
   belonging to one client together, per the workspace/<client>/ conformance rule:
   AGENTS.md § "$WORKSPACE/<client>/ convention" only requires sources/ and reports/
   to exist — a project JSON sitting alongside them at the <client>/ root is exactly
   the kind of "extra content" that convention explicitly tolerates)

3. Otherwise (Scope = global — no client folder involved)
   → $SANDBOX/agent/project-import-<NNN>.json  (unchanged legacy default)
```

`<NNN>` increments independently per Scope/location — a fresh `<client>/` folder starts
its own `project-import-001.json`, it does not continue the numbering of `global`'s or
another client's sequence.

> ⚠️ This only concerns the **produced project JSON**. It does not change where any
> other artefact is written: `import-report-<NNN>.org` / `align-review-<NNN>.org`
> already follow their own Scope-aware rule (`$WORKSPACE/reports/` or
> `$WORKSPACE/<C>/reports/` — see Phase 6), and thesaurus shards follow their own rule
> (`agent/thesaurus/global.org` or `agent/thesaurus/<C>.org` — see Phase 1.2b). All
> three now consistently key off the same Scope `C`.

### Construction de `_labels` (avant écriture du JSON)

À partir de la table d'alignement rechargée (`.import-alignment-<NNN>.org`),
construire pour chaque élément l'objet `_labels` selon l'algorithme suivant :

```
For each element E in the alignment table:
  labels = {}

  # 1. type_element : inclure si terme project ≠ valeur KB
  if alignment[E].project_term_type != alignment[E].kb_type_element:
    labels["type_element"] = alignment[E].project_term_type

  # 2. slots : inclure si terme source ≠ nom de slot KB
  for each (project_term, slot_kb, kb_value) in alignment[E].slots:
    if project_term != slot_kb:        # le document n'utilisait pas le nom exact du slot
      labels[slot_kb] = project_term

  # 3. N'inclure _labels dans le JSON que s'il est non vide
  if labels:
    E["_labels"] = labels
```

> **Règle de comparaison :** normaliser les deux termes (minuscules, underscores → espaces)
> avant comparaison. Si après normalisation ils sont identiques, ne pas inclure dans `_labels`.
> Exemple : `"section_bois"` (document) vs `"section_bois"` (KB) → identiques → pas de `_labels`.
>
> **Thésaurus hits à ✅ :** tous les slots résolus via le thésaurus ont par définition
> subi une substitution — inclure systématiquement dans `_labels` sauf si les termes
> normalisés sont identiques.

### Post-JSON — cleanup of transient partial files

After writing the final JSON (and before Phase 6), delete all transient block files:

```bash
rm -f $SANDBOX/agent/.import-inventory-<NNN>-blk*.org
rm -f $SANDBOX/agent/.import-alignment-<NNN>-blk*.org
```

The two consolidated files (`.import-inventory-<NNN>.org` and `.import-alignment-<NNN>.org`)
are **kept** — they serve as the audit trail for this import and are referenced by Phase 6
(import report) and by future `chorus-import-project` runs (Phase 1.3 secondary memory).

---

> **⚠️ Language rule — JSON annotation values:** technical structural keys (`"project"`,
> `"elements"`, `"id"`, `"type_element"`, `"_a_confirmer"`, `"_conflit"`, `"_incomplet"`,
> `"_hors_perimetre"`, `"_labels"`, etc.) are invariant; but all **annotation string values**
> (descriptions, notes, conflict messages, out-of-scope reasons) must be written in the
> **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

### Single / Merge Mode — one JSON

Once all ❓ items are resolved and critical gaps are filled:

```json
{
  "project": "<nom-project-ingenieur>",
  "description": "Import from <source> — <date> — <N> elements",
  "_import": {
    "source": "<nom-fichier-ou-inline>",
    "sources": ["<f1>", "<f2>"],
    "mode": "unitaire|fusion",
    "date": "<date>",
    "gaps": ["<id>: <slot manquant>", "..."],
    "a_confirmer": ["<id>: <terme ambigu>", "..."],
    "conflits": ["<id>: present in f1 and f2 — duplicate renamed", "..."]
  },
  "elements": [
    {
      "id": "<id-issu-du-document>",
      "type_element": "<type_kb>",
      "<slot_1>": "<valeur>",
      "_labels": {
        "type_element": "<terme project d'origine, si différent de type_kb>",
        "<slot_1>": "<terme project d'origine, si différent du nom de slot KB>"
      },
      "_source_fichier": "<nom-fichier>",
      "_a_confirmer": 1,
      "_conflit": 1,
      "_conflit_source": ["<f1>", "<f2>"]
    }
  ]
}
```

> **`_labels` — règle de population :**
> `_labels` est un objet plat `{ slot_kb → terme_projet_original }`.
> Il est construit lors de la Phase 5 à partir de la table d'alignement (Phase 3).
> **Seuls** les slots pour lesquels le terme project diffère du nom de slot KB sont inclus.
> Un slot dont le nom source est identique au slot KB (ex. `"id"`) n'est pas listé dans `_labels`.
> Si aucun slot n'a subi de substitution terminologique, `_labels` est omis (pas de clé vide `{}`).
>
> **Exemple concret :**
> ```json
> {
>   "id": "P1",
>   "type_element": "montant_porteur",
>   "section_bois": "45x145",
>   "classe_bois": "C24",
>   "epaisseur_mm": 200,
>   "_labels": {
>     "type_element": "poteau porteur",
>     "section_bois": "section",
>     "classe_bois": "classe résistance"
>   }
> }
> ```
> Ici `epaisseur_mm` n'a pas d'entrée dans `_labels` car le document source utilisait
> déjà le terme `epaisseur_mm` (pas de substitution).

> **`id` convention**: keep the source document identifier if available
> (e.g. "Poteau P1", "IPE-01"), otherwise generate `<TYPE_ABREV>-<NN>`.
> Document ↔ JSON traceability is the priority.
> In merge mode, `_source_fichier` is always set on each element.

### Batch Mode — one JSON per file

Each file produces its own JSON named `project-import-<NNN>.json`, written to the same
location as any other mode — see "Output JSON location" above (Scope-aware: under
`$WORKSPACE/<client>/` if the batch's sources were all under a `<client>/sources/`
folder, per the Mixed-context batch guard already enforced for Scope derivation).
The `_import.mode` field is `"batch"`.
No cross-file merging — each JSON is self-contained and can be piped independently.


## Phase 6 — Produce the Import Report

> **⚠️ Language rule — import report and thesaurus org files:** all section headings,
> column labels, notes, gap descriptions, and out-of-scope explanations in
> `import-report-<NNN>.org`, `align-review-<NNN>.org`, and every thesaurus shard
> (`agent/thesaurus/global.org`, `agent/thesaurus/<client>.org`, or the legacy
> monolithic `thesaurus.org`)
> must be written in the **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

Create `$WORKSPACE/import-report-<NNN>.org` (`$WORKSPACE` = `$SANDBOX/workspace/`, or
`$SANDBOX/workspace/<client>/reports/` if this import's Scope was resolved to a
non-`global` client context — see "Scope derivation", Phase 1.2b — created if absent):

```org
#+TITLE: Import report — <source> — <date>
#+STATUS: draft

* Source
  File    : <path or "inline">
  Date    : <date>
  Elements extracted: N

* Alignment table
  | Project term | KB slot | KB value | Confidence | Decision |
  |---|---|---|---|---|
  | ...          | ...     | ...      | ✅/⚠️/❓   | ...      |

* Unit transformations applied
  | Source | Transformation | KB slot |
  |---|---|---|

* Gaps identified
  | Element | Missing slot | Action |
  |---|---|---|

* Ambiguities resolved
  | Term | Options | Engineer decision |
  |---|---|---|

* Elements with _a_confirmer
  | id | Reason |
  |---|---|

* Out-of-scope elements (⬜)
  | id | source type_element | Recommended sandbox |
  |---|---|---|

* Inter-element relationships (Phase 3.5)
  #+BEGIN_COMMENT Generated only when the KB org contains Frame ref / → annotations #+END_COMMENT
  Blueprint entries : N  (from KB org slot dictionary)
  | element_id | ref_field    | target_id | confidence | signal                    | In JSON? |
  |------------|--------------|-----------|------------|---------------------------|----------|
  | BW-01      | supports_ref | EW-01     | ✅         | "buttresses EW-01" (p.3)  | yes      |
  | EW-02      | building_ref | RES-01    | ⚠️         | same drawing as EW-01     | yes+note |
  | IW-01      | building_ref | (none)    | ❓         | no signal found            | omitted  |

  #+BEGIN_COMMENT
  ✅ → included in JSON as "<ref_field>": "<target_id>"
  ⚠️ → included with "_note_<ref_field>": "inferred — verify"
  ❓ → omitted (optional link, engineer fills manually if needed)
  #+END_COMMENT

* Unmatched figure identifiers
  Identifiers found in figures but not mapped to any KB slot or type_element.
  Candidates for a future chorus-feed --enrich run to extend KB aliases.
  | Identifier | Figure | Page | Snippets seen | Action |
  |---|---|---|---|---|

* Output file
  <path project-*.json>
  N elements retained / N complete / N with gaps / N to confirm / N out-of-scope (excluded)
```

> This report is the **alignment decision memory** for this sandbox.
> It is automatically re-read during the next `chorus-import-project` run on the same sandbox.

### Patch the `README.org` imported-documents row

If Phase 0 (auto-conversion) recorded a row with `(pending)` in the
`* Imported project documents (not corpus — chorus-import-project artefacts)`
section (see Phase 0 Step 4), replace `(pending)` with the actual output filename
(e.g. `project-import-<NNN>.json`) now that it is known.

⛔ Never add or move this row into `* Corpus` — that table is reserved for
normative texts read by `chorus-feed` (see Phase 0 warning). An imported project
document stays under the dedicated section regardless of format or mode
(Single/Merge/Batch).

### Post-import — thesaurus consolidation (automatic)

After writing the import report, perform a **thesaurus consolidation pass** to ensure
the relevant shard(s) (`agent/thesaurus/global.org` + `agent/thesaurus/<C>.org` if this
import's Scope `C != global`) are fully up to date — even if Phase 3 already wrote
entries incrementally, this pass catches any edge cases (batch mode, interrupted
sessions, confirmed ⚠️ items). This pass never touches any other client's shard.

#### Consolidation rules

```
For each alignment produced in this import (C = current import's context, `global` by default):

  ✅ certain (newly confirmed in this session):
    → if a row with the same (term, Scope=C) already exists WITH THE SAME mapping:
      update confidence + source + KB hash @ validation (see "KB hash tracking &
      revalidation", Phase 1.2b)
    → if a row with the same (term, Scope=C) already exists WITH A DIFFERENT mapping:
      do NOT overwrite — append to * Conflicts (Scope=C) instead (see Deduplication
      rule, Phase 3 § Immediate thesaurus update). The existing Aliases row stays untouched.
    → if the term exists only at a *different* Scope (≠ C): not a conflict — append a
      new independent (term, Scope=C) row (see "Thesaurus scoping by context")
    → if NOT already in thesaurus Aliases at any Scope: append to appropriate Aliases
      section with Scope=C, recording the current `.kb-hash` (or `—` if absent)
    → if present in thesaurus Pending: move to Aliases at Scope=C, update confidence
      + source + KB hash

  ⚠️ confirmed by engineer in this session:
    → move from Pending to Aliases (type_element or slot values) at Scope=C
    → record source import as current import-report-NNN
    → same (term, Scope) conflict check as above applies

  ⚠️ newly seen (no prior record):
    → append to Pending (if not already present)

  ⬜ out-of-scope (confirmed by engineer):
    → append to Out-of-scope (if not already present)
    → remove from Pending if present there

  ⛔ gap (mandatory slot absent — not a mapping decision):
    → do NOT write to thesaurus (gaps are import-specific, not terminology mappings)
```

**Deduplication / conflict rule:** before any write to a shard's `* Aliases`, verify
whether `(project term, Scope)` is already present there.
- Same mapping → update the existing row (confidence, source import) — no duplicate.
- Different mapping → **do not overwrite** — this is a conflict, not a duplicate. Append
  an entry to `* Conflicts` in `global.org` instead (full rule: Phase 3 § "Immediate
  thesaurus update after each resolution" → Deduplication rule).

**Update the `#+UPDATED:` header** of every shard file touched during this
consolidation pass (`global.org`, and `<C>.org` if applicable) with today's date.

#### Consolidation summary (displayed to engineer)

```
📚 Thesaurus updated — $SANDBOX/agent/thesaurus/ (Scope: <C>)
   ✅ N new aliases added   (type_element: n / slot values: n) — shard: <C>.org or global.org
   🔄 N pending → confirmed  (global.org)
   ⬜ N out-of-scope added   (global.org)
   📋 Shard <C>.org now covers M distinct project terms (global.org: M' terms)
```

If nothing changed (all terms already in thesaurus) → display silently:
```
📚 Thesaurus already up to date — no new entries.
```

### Post-import — optional KB harvest (secondary)

The thesaurus is the **primary** persistence mechanism for project terminology.
`chorus-feed --harvest-aliases $SANDBOX/agent/thesaurus/global.org` is a **secondary,
optional** step for promoting validated project terms into the normative KB and
purging them from the thesaurus (see `chorus-feed.md § Mode C — Alias Harvest`).
**Only `global.org` is ever harvested** — client shards (`<client>.org`) are never
harvest candidates, since the KB is shared across all clients and a client-scoped
mapping must never leak into it (see `chorus-feed.md § Phase C1 — Scope guard`).

```
N_promotable      = count of ✅ Aliases rows in global.org not yet present in any KB <slug>.org
N_total_aliases   = total row count across global.org's * Aliases — type_element
                    + * Aliases — slot values (client shards excluded — they are never
                    harvest candidates, so their size does not affect this heuristic)
imports_since_last_harvest = number of distinct source-import references in global.org's
                              * Aliases newer than #+LAST_HARVEST (see below)
```

**`#+LAST_HARVEST:` header:** `agent/thesaurus/global.org` carries a
`#+LAST_HARVEST: <date | never>` header (alongside `#+UPDATED:`), set by
`chorus-feed --harvest-aliases` (Phase C4) at every harvest, `never` until the first
one. Client shards never carry this header. Use it to compute
`imports_since_last_harvest`.

**Recommendation thresholds** (heuristic — surface as a suggestion, never blocking):

| Signal | Threshold | Rationale |
|---|---|---|
| `N_promotable` | ≥ 20 | Enough accumulated value to justify a harvest pass |
| `N_total_aliases` (global.org only) | ≥ 100 | global.org read-in-full cost starts becoming noticeable at every import (client shards don't count — they aren't read unless their own Scope is active) |
| `imports_since_last_harvest` | ≥ 15 | Long-running sandbox — periodic consolidation checkpoint, independent of volume |

If **any** threshold is crossed, display:

```
💡 KB harvest recommended — $SANDBOX/agent/thesaurus/global.org
   ✅ Promotable now      : N_promotable aliases (not yet in KB)
   📋 global.org size     : N_total_aliases confirmed aliases (client shards not counted)
   🕒 Since last harvest  : imports_since_last_harvest imports (last: <#+LAST_HARVEST value>)
   Reason(s): <list of thresholds crossed>

   This is useful if the same project terminology is expected to recur in other
   sandboxes sharing this KB, or simply to keep global.org from growing unbounded.
   To promote: chorus-feed --harvest-aliases $SANDBOX/agent/thesaurus/global.org
   (harvested rows are automatically purged from global.org — see chorus-feed.md § C3.5)
   Skip if the mappings are genuinely project-specific / sandbox-specific.
```

If no threshold is crossed → skip silently (no noise on small/young sandboxes).

> ⚠️ This is a **suggestion only** — never auto-invoke `chorus-feed --harvest-aliases`
> from within `chorus-import-project`. Harvesting is a deliberate, separate operation
> the engineer must trigger explicitly.
>
> **Client shards have no harvest/growth signal of their own** — since they are never
> harvested and only ever read when their own Scope is active, an individual client
> shard growing large only affects imports for *that* client, never others. If a
> single client shard becomes unusually large on its own, this is better addressed by
> point #5 (Pending/Out-of-scope rotation — not yet implemented) than by harvesting,
> since harvest cannot touch client-scoped rows by design.

### Phase 6-BATCH — Summary Report (batch mode only)

In addition to the individual reports, create `$WORKSPACE/import-batch-<NNN>.org`
(`$WORKSPACE` = `$SANDBOX/workspace/`, created if absent):

```org
#+TITLE: Batch summary report — <directory or glob> — <date>
#+STATUS: draft

* Parameters
  Source    : <directory or file list>
  Sandbox   : <sandbox-name>
  Files     : N processed / M skipped (unsupported format)
  Date      : <date>

* Results per file
  | File    | JSON produced | Elements | Retained | Gaps | To confirm | Conflicts | Out-of-scope |
  |---|---|---|---|---|---|---|---|
  | f1.pdf  | project-import-001.json | 34 | 26 | 6 | 2 | 0 | 0 |
  | f2.xlsx | project-import-002.json | 18 | 15 | 3 | 0 | 0 | 3 |
  | ...     | ...                    | .. | .. | . | . | . | . |

* Totals
  Elements processed  : N
  Retained (in JSON)  : N
  With gaps           : N
  To confirm          : N
  Out-of-scope        : N (excluded from JSON — import in another sandbox)
  Id conflicts        : N (merge mode only — N/A in batch)

* New terms detected
  Terms absent from the thesaurus (appropriate shard) → newly added in this batch run
  | Source term | File | Alignment | Confidence | Thesaurus action |
  |---|---|---|---|---|

* Skipped files
  | File | Reason |
  |---|---|
  | scan-brouillon.pdf | Empty text extraction — re-read or provide inline |

* Suggested next step
  perl $SANDBOX/run.pl <JSON1> <JSON2> ...
  (run the pipeline on each produced JSON)
```

> **New terms**: if a source term received a ✅ alignment and was not already in the
> thesaurus, it has been automatically added to the appropriate shard's Aliases
> section (`global.org`, or the current Scope's `<client>.org`).
> No manual action required — the thesaurus is the primary persistence mechanism.
> Use `chorus-feed --harvest-aliases $SANDBOX/agent/thesaurus/global.org` only if you
> want to promote these mappings to the normative KB for cross-sandbox reuse.


## Phase 7 — Run the Pipeline (optional)

If the engineer explicitly requests it, follow up with `chorus-check`:

```bash
perl $SANDBOX/run.pl $SANDBOX/<project-import-NNN.json>
```

If `run.pl` does not yet exist → indicate that `chorus-check` should be run first.


## Separation of Responsibilities

| | `chorus-feed` | `chorus-import-project` | `chorus-create-project` | `chorus-check` |
|---|---|---|---|---|
| **Reads** | normative corpus | engineer project docs + org KB | org KB | org KB + YAML |
| **Produces** | KB org, YAML, Helpers.pm | `project-import-*.json` + `.org` report | `project-*.json` | Feed.pm, shells, Expert.pm, run.pl |
| **Threshold source** | corpus | org KB only | org KB only | org KB |
| **Gaps** | n/a | reported, never invented | computed from KB | n/a |
| **Never reads** | — | Helpers.pm, Feed.pm | Helpers.pm, Feed.pm | — |


## Architectural Principle — sandbox granularity = JSON granularity

> **The granularity of a sandbox defines the granularity of the project JSON intended for it.**

A sandbox covers a coherent normative domain (e.g. structural, thermal, hygrometry).
A multi-domain project produces as many import JSONs as there are target sandboxes.
**`chorus-import-project` is the partitioning tool — not `run.pl`.**

Out-of-scope elements (⬜) are cleanly excluded at import time; `run.pl` and
`Feed.pm` only receive the types they know.

```
dossier-project/                      ← single source (all domains mixed)
  charpente.pdf
  isolation.xlsx
  bardage.docx

  ↓ chorus-import-project sandbox-structurel ./dossier-project/ --batch
project-structurel-001.json           ← montants, lisses, chevrons
                                        # → elements isolant_laine, membrane_etanche → ⬜ excluded + report

  ↓ chorus-import-project sandbox-thermique ./dossier-project/ --batch
project-thermique-001.json            ← isolants, membranes
                                        # → elements montant_porteur, lisse_basse → ⬜ excluded + report

  ↓
perl sandbox-structurel/run.pl project-structurel-001.json → rapport_struct.txt
perl sandbox-thermique/run.pl  project-thermique-001.json  → rapport_thermo.txt
```

**Consequence for `Feed.pm`** (generated by `chorus-check`):
The template uses `warn + next` instead of `die` on an unknown type, as a safety net
in case a mixed JSON somehow reached `run.pl`. Partitioning remains the responsibility
of `chorus-import-project`.
