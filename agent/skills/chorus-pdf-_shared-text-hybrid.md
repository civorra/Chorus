> **Sub-skill of `chorus-pdf` — shared utilities for Text & Hybrid modes (ENG-042)**
> Loaded via `eca__read_file` from `chorus-pdf-core.md` for text and `--hybrid`.
> Contains: `detect_table_columns()`, `extract_tables_from_page()`, `analyse_pages()`
> (includes `detect_borderless_table()` per ENG-059).
> Note: `detect_and_tag_formulas()` moved to `chorus-pdf-text.md` (Text-only).
> Note: `call_claude_with_retry()` moved to `chorus-pdf-core.md` (all modes).

---

### Shared utilities — Text & Hybrid modes

The following two functions are used verbatim in both the Text and Hybrid script templates.
Include them in the generated script when either mode is active.

```python
def detect_table_columns(page):
    """Detect explicit vertical column separators from V-edges on this pdfplumber page.
    Returns a sorted list of x-coordinates, or None if no table structure found.
    
    Falls back to basic edge detection if page.edges is empty (some PDFs don't expose
    edges reliably). In that case, attempt to infer columns from table content cells.
    """
    edges   = page.edges
    v_edges = [e for e in edges if e['orientation'] == 'v' and e['height'] > 30]
    h_edges = [e for e in edges if e['orientation'] == 'h' and e['width']  > 50]
    
    if len(h_edges) < 2 or len(v_edges) < 1:
        # Fallback: no explicit edges, return None and let pdfplumber auto-detect
        return None
    
         # Cluster x-coordinates — snap duplicates within 3 pt
         # **Threshold: 3pt minimum spacing between clusters**
         # **Rationale:** V-edge detection often produces multiple edges for the same
         #   logical column boundary (rendering artifacts, PDF compression). Clustering
         #   merges these duplicates; 3pt is tight enough to avoid merging distinct
         #   columns in typical PDFs, but loose enough to handle rendering noise.
         xs = sorted(set(e['x0'] for e in v_edges))
         clustered = []
         for x in xs:
             if not clustered or x - clustered[-1] > 3:
                 clustered.append(x)
    
    # Add left/right boundaries from the widest H-edge
    widest = max(h_edges, key=lambda e: e['width'])
    all_xs = sorted(set([widest['x0']] + clustered + [widest['x1']]))
    
    return all_xs if len(all_xs) >= 2 else None


def extract_tables_from_page(page):
    """Extract tables from a pdfplumber page as (bbox, markdown) tuples.
    bbox = (x0, top, x1, bottom) in pdfplumber coords.
    
    Two-strategy approach:
    1. **Explicit Strategy** (if column edges detected): Uses pdfplumber's explicit
       vertical column boundaries with snap_tolerance=3 for strict clustering.
       Sensitive to PDF rendering quality; may over-fragment on complex layouts.
    2. **Fallback (Auto-detect)**: If explicit fails, attempt line-based edge detection.
       More robust to rendering artifacts but less precise on dense matrices.
    
    The quality_check() function (including Filter 3: >40% empty cell detection)
    ensures that over-fragmented extractions from Strategy 1 are rejected, triggering
    Strategy 2 as a safety net. This allows robustness without sacrificing precision.
    """
    col_xs = detect_table_columns(page)
    
    def cell(c):
        return str(c or "").replace("\n", " ").replace("|", "｜").strip()

    def quality_check(rows):
        """Return True if table extraction appears high-quality, False to discard.
        
        Four independent filters are applied; any single filter failure causes rejection:
        - Filter 0: Single-column numbered lists (>30% cells > 100 chars)
        - Filter 1: Overly sparse/mis-detected (>55% empty cells)
        - Filter 2: Garbled/misaligned columns (>30% short lowercase fragments)
        - Filter 3: Over-fragmentation from explicit strategy (>40% empty in multi-col)
        """
        if not rows or not any(any(c for c in row) for row in rows):
            return False
        
        total_cells = sum(len(row) for row in rows)
        empty_cells = sum(1 for row in rows for c in row if not str(c or "").strip())
        
        # Filter 0: Reject single-column tables with long text blocks
        # **Threshold: >30% cells with >100 chars**
        # **Rationale:** Single-column layouts with many long text blocks are almost always
        #   numbered lists or formatted text, not data tables. Multi-column tables with
        #   long cells (e.g., descriptive columns) are allowed.
        # **Example:** "Top 10 Takeaways" (10×1 list) rejected; risk matrix (37×9) with
        #   long header cells allowed.
        if len(rows[0]) == 1:
            long_texts = sum(1 for row in rows for c in row
                            if c and len(str(c).strip()) > 100)
            if total_cells > 0 and long_texts / total_cells > 0.30:
                return False
        
        # Filter 1: Reject overly sparse or mis-detected tables
        # **Threshold: >55% empty cells**
        # **Rationale:** High empty-cell ratio indicates either pdfplumber mis-aligned
        #   column boundaries (common with dense layouts) or truly sparse data that
        #   shouldn't be presented as a table.
        # **Example:** Fragmented 71×12 extraction from 37×9 original may exceed this
        #   (depends on pdfplumber edge detection quality).
        if total_cells > 0 and empty_cells / total_cells > 0.55:
            return False
        
        # Filter 2: Reject garbled/misaligned columns
        # **Threshold: >30% of non-empty cells are short (<20 chars) lowercase fragments**
        # **Rationale:** When pdfplumber's column boundaries cut through words, individual
        #   characters or short lowercase fragments appear. This typically means the
        #   vertical_strategy='explicit' or 'lines' mis-detected column edges.
        # **Example:** A cell containing just "ard" from "Standard" or "infarct" split
        #   across two cells.
        non_empty_cells = [str(c or "").strip() for row in rows for c in row
                           if str(c or "").strip()]
        if non_empty_cells:
            fragments = sum(1 for t in non_empty_cells
                            if len(t) < 20 and t and t[0].islower())
            if fragments / len(non_empty_cells) > 0.30:
                return False
        
        # Filter 3: Reject over-fragmentation from explicit column detection
        # **Threshold: multi-column table with >40% empty cells**
        # **Rationale:** When vertical_strategy='explicit' with snap_tolerance=3,
        #   overly strict column detection can split cells across too many columns,
        #   creating a sparse matrix. This filter triggers fallback to auto-detect.
        #   Single-column tables (Filter 0) and very sparse tables (Filter 1, >55%)
        #   are handled separately.
        # **Example:** KDIGO Figure 4 (37×9 original) mis-extracted as 71×12 with many
        #   empty cells → rejected → fallback auto-detect produces correct 37×9.
        if len(rows[0]) > 1 and total_cells > 0 and empty_cells / total_cells > 0.40:
            return False
        
        return True

    def detect_and_fix_header_split(rows):
        """§1.4e mitigation — mis-split header cells / trailing prose-pollution row.

        Two independent symptoms are addressed here, both observed in real
        extractions (FIPS 186-5 Table A.1/A.2) and previously left as a
        "no automated fix, human check required" blind spot:

        1. **Mid-word header split**: a header cell spans 2+ logical columns
           in the source but pdfplumber's column-boundary detection places a
           cut in the middle of a word/phrase (e.g. "Max. of len(p1) + len(p2)
           and len(q1)" | ") + len(q2) 2"). Detected by checking whether any
           two horizontally-adjacent cells in the first 2 rows, when
           concatenated, look like a split token (one ends without
           whitespace/punctuation and the next starts with a lowercase letter
           or a closing-paren/digit continuation) — conservative best-effort,
           not a dictionary-based reconstruction. When detected, the cells are
           NOT silently merged (risk of inventing a wrong reconstruction) —
           instead this row is tagged for the explicit `[TABLE QUALITY WARNING]`
           banner below, so a human (or chorus-markdown) can verify it.

        2. **Trailing prose-pollution row**: pdfplumber occasionally captures
           the start of the *next* paragraph/section (unrelated prose from
           below the table's visual boundary) as a spurious final "row" of
           the table — recognisable because most of its cells are empty and
           the non-empty cell(s) contain long, multi-word fragments with no
           resemblance to the table's own column content (numbers, short
           codes, bit-length expressions). This row is dropped automatically
           — it is never legitimate tabular data, only mis-captured prose.

        Returns (cleaned_rows, warnings) where warnings is a list of
        human-readable strings describing what was detected/removed.
        """
        if not rows or len(rows) < 2:
            return rows, []

        warnings = []
        cleaned = list(rows)

        # --- Symptom 2: trailing prose-pollution row -----------------------
        # A row is "prose pollution" if: it has >=2 cells, all but one (or all)
        # are empty/whitespace, and the one non-empty cell is long (>60 chars)
        # with multiple whitespace-separated words — i.e. unrelated running
        # text, not a short tabular value.
        while len(cleaned) >= 2:
            last = cleaned[-1]
            non_empty = [str(c or "").strip() for c in last if str(c or "").strip()]
            if len(non_empty) == 0:
                cleaned.pop()
                continue
            if len(non_empty) == 1 and len(non_empty[0]) > 60 and len(non_empty[0].split()) > 6:
                warnings.append(
                    "Trailing row removed — looks like unrelated prose captured "
                    "past the table's visual boundary (§1.4e symptom 2): "
                    f"\"{non_empty[0][:80]}...\""
                )
                cleaned.pop()
                continue
            break

        if not cleaned or len(cleaned) < 2:
            return cleaned, warnings

        # --- Symptom 1: mid-word header split detection (first 2 rows) -----
        def looks_like_split(a, b):
            a = str(a or "").strip()
            b = str(b or "").strip()
            if not a or not b:
                return False
            # heuristic: left fragment has no trailing punctuation/space before
            # cut, right fragment starts with a lowercase letter, a closing
            # paren, or a bare digit immediately followed by more digits that
            # don't look like a standalone unit on their own (e.g. "1" right
            # after "len(p" on the left — reconstitutes "len(p1)").
            if a[-1].isalnum() and (b[0].islower() or b[0] in ")]1234567890"):
                # avoid false positives: both fragments are already full words
                # when they are long AND contain a space (unlikely to be a cut)
                if len(a) > 25 and " " in a and len(b) > 25 and " " in b:
                    return False
                return True
            return False

        for row_idx in range(min(2, len(cleaned))):
            row = cleaned[row_idx]
            for i in range(len(row) - 1):
                if looks_like_split(row[i], row[i + 1]):
                    warnings.append(
                        f"Row {row_idx + 1}, cells {i + 1}-{i + 2} look "
                        f"mid-word split (§1.4e symptom 1): "
                        f"\"{str(row[i]).strip()}\" | \"{str(row[i + 1]).strip()}\" "
                        "— NOT auto-merged (verify against source before trusting "
                        "this header)."
                    )

        return cleaned, warnings

    def format_table(rows):
        """Format extracted rows as Markdown pipe table.

        Applies detect_and_fix_header_split() first (§1.4e mitigation):
        drops trailing prose-pollution rows automatically, and prepends a
        visible [TABLE QUALITY WARNING] banner (instead of silently passing
        quality_check()) when a mid-word header split is suspected — turning
        a previously undetectable blind spot into an explicit, human-reviewable
        signal in the generated .md, consistent with the [FIGURE — not
        extracted] / [FORMULA: ...] placeholder convention already used
        elsewhere in this skill.
        """
        rows, warnings = detect_and_fix_header_split(rows)
        if not rows:
            return None
        lines = []
        if warnings:
            lines.append("[TABLE QUALITY WARNING — §1.4e mis-split header cells / "
                          "prose-pollution check — see chorus-pdf.md Known failure modes]")
            for w in warnings:
                lines.append(f"  - {w}")
            lines.append("[END TABLE QUALITY WARNING]")
        lines.append("| " + " | ".join(cell(c) for c in rows[0]) + " |")
        lines.append("| " + " | ".join("---" for _ in rows[0]) + " |")
        for row in rows[1:]:
            lines.append("| " + " | ".join(cell(c) for c in row) + " |")
        return "\n".join(lines)

    result = []
    try:
        # Strategy 1: Explicit vertical lines (if detected)
        if col_xs:
            settings = {
                'vertical_strategy':       'explicit',
                'horizontal_strategy':     'lines',
                'explicit_vertical_lines': col_xs,
                'snap_tolerance':          3,  # Strict clustering (3pt threshold) avoids
                                               # over-fragmentation while still capturing
                                               # well-spaced column edges. Balanced tradeoff
                                               # vs. the original 6pt (fragmented) or 0 (tight).
            }
            for tobj in page.find_tables(table_settings=settings):
                rows = tobj.extract()
                if quality_check(rows):
                    md = format_table(rows)
                    if md:
                        result.append((tobj.bbox, md))
        
        # Strategy 2: Fallback to automatic detection if no explicit lines
        # or if explicit extraction yielded nothing
        if not result:
            settings = {
                'vertical_strategy':       'lines',
                'horizontal_strategy':     'lines',
            }
            for tobj in page.find_tables(table_settings=settings):
                rows = tobj.extract()
                if quality_check(rows):
                    md = format_table(rows)
                    if md:
                        result.append((tobj.bbox, md))
    
    except Exception as e:
        # Graceful fallback on any pdfplumber error
        pass
    
    return result


def analyse_pages(pdf_path):
    """Extract text blocks, figure bboxes, and vector-table markers per page.
    Returns {page_num: {'texts': [(text, y_center, x0, x1)], 'figures': [(x0,y0,x1,y1)],
                        'height': float, 'has_table': bool,
                        'borderless_table_suspect': bool, 'borderless_reason': str|None}}
    Used verbatim in Text mode (figures checked as bool) and Hybrid mode (figures as crop targets).
    Uses the full 7-parameter LAParams set (from the original text mode) for both modes —
    this is intentional: the hybrid mode previously used only 2 params (boxes_flow, char_margin),
    which was an inconsistency. The unified version applies more precise layout analysis to both.
    
    Table detection heuristic: A table is detected if we find ≥2 horizontally-aligned
    H-lines (same x0 ±10pt and x1 ±10pt, spaced ≥3pt vertically) AND ≥2 V-lines that
    cross all H-lines. This is more lenient than requiring ≥3 aligned H-lines, catching
    simple 2-row tables while still avoiding false positives on scattered lines.
    """
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
        
        # Enhanced table detection:
        # Require ≥2 horizontally-aligned H-lines (stricter matching) AND ≥2 V-lines
        # crossing them. More lenient than the original ≥3 requirement.
        _has_table = False
        if len(h_lines) >= 2 and len(v_lines) >= 2:
            for base in h_lines:
                # Find H-lines aligned with this baseline
                aligned = [h for h in h_lines
                           if abs(h.x0 - base.x0) <= 10 and abs(h.x1 - base.x1) <= 10]
                
                # Need at least 2 aligned lines spaced at least 3 pts apart
                if len(aligned) >= 2:
                    # Check if they're vertically separated (not the same line twice)
                    aligned_sorted = sorted(aligned, key=lambda h: h.y0)
                    min_spacing = min(aligned_sorted[i+1].y0 - aligned_sorted[i].y1
                                     for i in range(len(aligned_sorted) - 1))
                    if min_spacing >= 3:
                        # Now check if V-lines cross all H-lines
                        h_x_span = (min(h.x0 for h in aligned), max(h.x1 for h in aligned))
                        v_crossing = [v for v in v_lines
                                     if h_x_span[0] - 5 <= (v.x0 + v.x1) / 2 <= h_x_span[1] + 5]
                        
                        if len(v_crossing) >= 2:
                            _has_table = True
                            break
        
        # §1.4d — Borderless table detection (ENG-059 fix)
        # Must run AFTER vector-line detection so has_table is already known.
        # detect_borderless_table() uses the dual heuristic:
        #   Signal 1 — explicit text announcement ("le tableau ci-dessous...")
        #   Signal 2 — X-band numeric density (≥5 short blocks in ≥3 bands)
        page_text_joined = ' '.join(t for t, *_ in texts)
        _borderless_suspect, _borderless_reason = detect_borderless_table(
            texts, layout.width, page_text_joined)
        # Suppress false-positive: if the page already has a vector table (has_table),
        # the borderless detector is not needed — vector pdfplumber reconstruction handles it.
        if _has_table:
            _borderless_suspect = False
            _borderless_reason  = None

        result[page_num] = {
            'texts':                    texts,
            'figures':                  figures,
            'height':                   layout.height,
            'has_table':                _has_table,
            'borderless_table_suspect': _borderless_suspect,  # §1.4d
            'borderless_reason':        _borderless_reason,   # §1.4d
        }
    return result


