#!/usr/bin/env python3
"""
corpus-inventory.py — Mechanical count-based audit of chorus-feed's Step 1
enumeration against the corpus pre-split's own structural markers.

RATIONALE
---------
chorus-feed's Step 1 ("Scan the corpus for all normative sections") is a
semantic reading pass performed entirely by the LLM agent. Nothing today
checks that pass against the corpus structurally — Step 1b audits
rules-to-corpus traceability (# CORPUS: headers), Step 1c audits
HELPER-SOURCE extraction, but nothing audits whether every PRIMARY /
HELPER-SOURCE section identified by `chorus-corpus-scoping` Phase 2 actually
produced *something* traceable in the coverage report.

DESIGN NOTE — why this is count-based, not identity-based
-----------------------------------------------------------
An earlier draft of this script attempted to re-derive the corpus section
list from scratch via regex over Markdown headings (`§N`, `Article N`, ...)
and match each one, by title text, against `README.org`'s Coverage tables.
That approach was tested against `sandboxes/test-kb-multiSource` and
produced a 57% false-positive rate (4 of 7 sections flagged UNSCANNED
despite being genuinely covered) — caused by (a) legitimate title
abbreviation between the corpus heading and the coverage report entry
("Article 5 — Load conformance" vs "CIR-1.0 Art.5 — Load conf."), and
(b) CONTEXT sections legitimately duplicated across multiple agent files,
double-counted as separate unmatched sections. Free-text matching between
two independently-worded documents is fundamentally unreliable without a
shared stable identifier that does not currently exist end-to-end in the
pipeline.

This script uses a different, coarser but reliable ground truth instead:
the `<!-- SECTION: ... | STATUS: ... -->` markers that `chorus-corpus-scoping`
Phase 2 already writes into every pre-split corpus file — a fixed,
machine-generated format (not re-derived from arbitrary document headings).
It counts `STATUS: PRIMARY` and `STATUS: HELPER-SOURCE` markers per corpus
file, and cross-checks that count against the number of rows recorded in
the matching agent's `* Coverage` block in `README.org` (Integrated +
Deferred + Helper-source pending). No title text is ever compared between
the two documents — only integers.

TRADE-OFF (documented, not hidden): this is an *existence* check, not an
*identification* check. A single PRIMARY section can legitimately produce
several rules (row count > section count) or several PRIMARY sections can
share one rule (row count < section count) — so this script cannot promise
"this exact section is missing", only "this agent's coverage report has
fewer accounted rows than PRIMARY/HELPER-SOURCE markers in its corpus file,
go look". That is a deliberately weaker claim than the discarded title-
matching approach, traded for eliminating its false-positive class entirely.

EXIT CODES
----------
  0 — every corpus file's PRIMARY/HELPER-SOURCE marker count is met or
      exceeded by its matching agent's accounted row count in README.org
  1 — at least one corpus file is under-accounted (possible gap — manual
      review required, this script does not identify which section)
  2 — usage / file-access error
"""

import os
import re
import sys

SECTION_MARKER_RE = re.compile(
    r'<!--\s*SECTION:.*?\|\s*STATUS:\s*([\w-]+)', re.IGNORECASE
)
COVERAGE_BLOCK_RE = re.compile(
    r'^\* Coverage\b(.*?)(?=^\* |\Z)', re.MULTILINE | re.DOTALL
)
CORPUS_LINE_RE = re.compile(r'^\s*Corpus:\s*(.+)$', re.MULTILINE)
TABLE_ROW_RE = re.compile(r'^\s*\|(?!-)(.+)\|\s*$')
SUBSECTION_RE = re.compile(
    r'^\*\*\s*(✅ Integrated|⏭ Deferred|🧮 Helper-source pending)\b.*$'
)


def count_corpus_markers(md_path):
    """Return (primary_count, helper_source_count) for one pre-split corpus
    file, purely from its own mechanical markers."""
    with open(md_path, encoding='utf-8', errors='replace') as f:
        text = f.read()

    primary = 0
    helper = 0
    for m in SECTION_MARKER_RE.finditer(text):
        status = m.group(1).upper()
        if status == 'PRIMARY':
            primary += 1
        elif status == 'HELPER-SOURCE':
            helper += 1
    return primary, helper


def count_readme_accounted_rows(readme_org_path, corpus_basename):
    """Sum table data rows under Integrated / Deferred / Helper-source
    pending, within every '* Coverage' block whose 'Corpus:' line mentions
    this corpus file — the anchor already used by the chorus-feed/
    chorus-corpus-scoping convention itself (not an assumption of this
    script), since one Coverage block may legitimately span several corpus
    files (e.g. a later agent pass that also reads earlier agents' files
    for cross-reference)."""
    if not os.path.isfile(readme_org_path):
        return 0

    with open(readme_org_path, encoding='utf-8', errors='replace') as f:
        text = f.read()

    total = 0
    for block_m in COVERAGE_BLOCK_RE.finditer(text):
        block = block_m.group(1)
        corpus_m = CORPUS_LINE_RE.search(block)
        if not corpus_m or corpus_basename not in corpus_m.group(1):
            continue

        current_subsection = None
        for line in block.split('\n'):
            sub_m = SUBSECTION_RE.match(line)
            if sub_m:
                current_subsection = sub_m.group(1)
                continue
            if line.startswith('**'):
                current_subsection = None
                continue
            if current_subsection and TABLE_ROW_RE.match(line):
                total += 1
    return total


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        print("Usage: corpus-inventory.py <README.org> <corpus.md> [<corpus2.md> ...]")
        sys.exit(2)

    readme_path = sys.argv[1]
    corpus_paths = sys.argv[2:]

    for p in corpus_paths:
        if not os.path.isfile(p):
            print(f"⛔ Corpus file not found: {p}")
            sys.exit(2)

    print("=" * 72)
    print("  corpus-inventory — mechanical count-based completeness audit")
    print("=" * 72)
    print(f"  README.org : {readme_path}"
          f"{'  (not found)' if not os.path.isfile(readme_path) else ''}")
    print("-" * 72)

    under_accounted = []
    for p in corpus_paths:
        basename = os.path.basename(p)
        primary, helper = count_corpus_markers(p)
        expected = primary + helper

        accounted = count_readme_accounted_rows(readme_path, basename)
        status = "✅" if accounted >= expected else "🔍"
        print(f"  {status} {basename:<28} "
              f"PRIMARY={primary} HELPER-SOURCE={helper} "
              f"→ expected≥{expected}, accounted={accounted}")

        if accounted < expected:
            under_accounted.append((p, expected, accounted))

    print("-" * 72)
    if under_accounted:
        print(f"\n  🔍 UNDER-ACCOUNTED ({len(under_accounted)} corpus file(s)):\n")
        for p, expected, accounted in under_accounted:
            print(f"      {os.path.basename(p)}: "
                  f"{accounted} row(s) accounted vs {expected} PRIMARY/HELPER-SOURCE "
                  f"marker(s) expected")
        print("\n" + "=" * 72)
        print("  🔴 RESULT: possible gap — this script cannot identify which section(s)")
        print("     are missing (count-based check only, see script docstring for why).")
        print("     Manually re-check the listed agent's corpus file section-by-section")
        print("     against its README.org Coverage block before declaring SP1/SP2.")
        print("=" * 72)
        sys.exit(1)
    else:
        print("\n  ✅ RESULT: every corpus file's PRIMARY/HELPER-SOURCE marker count")
        print("     is met or exceeded by its agent's accounted rows in README.org.")
        print("=" * 72)
        sys.exit(0)


if __name__ == "__main__":
    main()
