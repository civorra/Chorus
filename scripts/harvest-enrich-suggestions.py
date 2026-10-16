#!/usr/bin/env python3
"""
harvest-enrich-suggestions.py — Collect ENRICH-SUGGESTED markers from sandbox
reports and emit a corpus-correctif-harvested-<NNN>.txt ready for
  chorus-feed <sandbox> corpus-correctif-harvested-<NNN>.txt --enrich

RATIONALE
---------
When an engineer reads a chorus-complete-report or chorus-check --explain
output, they may notice gaps that no automated skill surfaced: a normative
rule that exists in the source corpus but was never brought into the KB.
The ENRICH-SUGGESTED inline annotation convention lets them mark such
observations *at the point of reading*, without breaking the review flow:

    > 🌱 **ENRICH-SUGGESTED** — §7 EdDSA/Ed25519 : mécanisme de signature
    > sur courbes de Montgomery non couvert par le catalogue actuel.
    > Le corpus contient FIPS 186-5 §7 — à extraire et à enrichir.

This script scans all report .md files in a sandbox, collects every such
annotation, and writes a single corpus-correctif-harvested-<NNN>.txt using
the [Gap #N — enrichissement-manuel] header format already consumed by
chorus-feed --enrich (no changes to chorus-feed required).

SCAN SCOPE
----------
For a given <sandbox> directory:
  • workspace/**/reports/*.md          (chorus-check, import reports)
  • agent/explain-*.md                 (chorus-check --explain)
  • agent/synthese-*.md                (chorus-check --summary)

The marker text is collected as-is, including any following blockquote
lines (> ...) that form part of the same suggestion, up to the first
blank line or non-blockquote line.

OUTPUT FORMAT (subset of chorus-feed --enrich input)
------------------------------------------------------
  ## Suggestions d'enrichissement — récoltées automatiquement
  ## Source: <relative path to sandbox> — <ISO date>
  ## Commandes suggérées:
  ##   chorus-feed <sandbox-name> corpus-correctif-harvested-<NNN>.txt --enrich
  ##
  [Gap #1 — enrichissement-manuel]
  Source rapport: workspace/eviden/reports/explain-foo-001.md:142
  Fp7n... suggestion text ...

  [Gap #2 — enrichissement-manuel]
  ...

USAGE
-----
  python3 scripts/harvest-enrich-suggestions.py <sandbox-path> [--dry-run]

  --dry-run   Print collected entries to stdout, do not write any file.
  --out <f>   Override output filename (default: corpus-correctif-harvested-NNN.txt
              in the sandbox root, NNN = next available number).
"""

import argparse
import datetime
import os
import re
import sys
from glob import glob
from pathlib import Path

MARKER = "ENRICH-SUGGESTED"
MARKER_RE = re.compile(r"ENRICH-SUGGESTED")


def find_report_files(sandbox: Path) -> list[Path]:
    """Return all .md report files within the scan scope."""
    found = []
    # workspace/**/reports/*.md
    for p in sandbox.glob("workspace/**/reports/*.md"):
        found.append(p)
    # agent/explain-*.md  +  agent/synthese-*.md
    agent_dir = sandbox / "agent"
    if agent_dir.is_dir():
        for pattern in ("explain-*.md", "synthese-*.md"):
            for p in agent_dir.glob(pattern):
                found.append(p)
    # Deduplicate and sort deterministically
    return sorted(set(found))


def collect_suggestion_block(lines: list[str], start: int) -> str:
    """
    Starting at `start` (the line containing ENRICH-SUGGESTED), collect
    the full suggestion text:
    - the trigger line itself (stripped of leading "> " blockquote markers)
    - any immediately following lines that are part of the same blockquote
      (start with ">"), up to the first blank or non-blockquote line.

    Returns the collected text as a single string.
    """
    parts = []
    for i in range(start, len(lines)):
        line = lines[i].rstrip()
        # Strip blockquote prefix ("> " or ">")
        stripped = re.sub(r"^>\s?", "", line)
        if i == start:
            parts.append(stripped)
        else:
            # Continue only if the line is still part of a blockquote
            if lines[i].startswith(">"):
                parts.append(stripped)
            else:
                break
    return "\n".join(parts).strip()


def harvest(sandbox: Path) -> list[dict]:
    """
    Scan all report files in the sandbox and return a list of entries:
      { 'source': <relative path:line>, 'text': <suggestion text> }
    """
    entries = []
    report_files = find_report_files(sandbox)

    for report in report_files:
        try:
            lines = report.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as e:
            print(f"[WARN] Cannot read {report}: {e}", file=sys.stderr)
            continue

        for lineno, line in enumerate(lines, start=1):
            if MARKER_RE.search(line):
                text = collect_suggestion_block(lines, lineno - 1)
                rel = report.relative_to(sandbox)
                entries.append({
                    "source": f"{rel}:{lineno}",
                    "text":   text,
                })

    return entries


def next_nnn(sandbox: Path) -> str:
    """Return the next available 3-digit suffix for corpus-correctif-harvested."""
    existing = list(sandbox.glob("corpus-correctif-harvested-*.txt"))
    used = set()
    pat = re.compile(r"corpus-correctif-harvested-(\d+)\.txt$")
    for p in existing:
        m = pat.search(p.name)
        if m:
            used.add(int(m.group(1)))
    n = 1
    while n in used:
        n += 1
    return f"{n:03d}"


def render_output(sandbox_name: str, entries: list[dict], date_str: str) -> str:
    """Format the list of entries as a corpus-correctif-harvested file."""
    lines = [
        f"## Suggestions d'enrichissement — récoltées automatiquement",
        f"## Sandbox  : {sandbox_name}",
        f"## Date     : {date_str}",
        f"## Script   : scripts/harvest-enrich-suggestions.py",
        f"##",
        f"## Commande suggérée :",
        f"##   chorus-feed {sandbox_name} corpus-correctif-harvested-NNN.txt --enrich",
        f"## (remplacer NNN par le suffixe réel de ce fichier)",
        f"##",
        f"## Entrées  : {len(entries)}",
        f"",
    ]
    for i, entry in enumerate(entries, start=1):
        lines.append(f"[Gap #{i} — enrichissement-manuel]")
        lines.append(f"Source rapport : {entry['source']}")
        lines.append(entry["text"])
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Harvest ENRICH-SUGGESTED markers from sandbox reports "
                    "and emit a corpus-correctif-harvested-NNN.txt."
    )
    parser.add_argument("sandbox", help="Path to the sandbox directory.")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print collected entries to stdout, do not write any file."
    )
    parser.add_argument(
        "--out", metavar="FILE",
        help="Override output file path (default: <sandbox>/corpus-correctif-harvested-NNN.txt)."
    )
    args = parser.parse_args()

    sandbox = Path(args.sandbox).resolve()
    if not sandbox.is_dir():
        print(f"[ERROR] Sandbox not found: {sandbox}", file=sys.stderr)
        return 1

    sandbox_name = sandbox.name
    date_str = datetime.date.today().isoformat()

    print(f"[harvest] Scanning {sandbox} …", file=sys.stderr)
    entries = harvest(sandbox)

    if not entries:
        print(f"[harvest] No {MARKER} marker found in scan scope.", file=sys.stderr)
        print(f"[harvest] Scope: workspace/**/reports/*.md, agent/explain-*.md, agent/synthese-*.md", file=sys.stderr)
        return 0

    print(f"[harvest] {len(entries)} suggestion(s) found.", file=sys.stderr)

    output = render_output(sandbox_name, entries, date_str)

    if args.dry_run:
        print(output)
        return 0

    if args.out:
        out_path = Path(args.out)
    else:
        nnn = next_nnn(sandbox)
        out_path = sandbox / f"corpus-correctif-harvested-{nnn}.txt"

    out_path.write_text(output, encoding="utf-8")
    print(f"[harvest] Written → {out_path}", file=sys.stderr)
    print(f"[harvest] Next step:", file=sys.stderr)
    print(f"[harvest]   chorus-feed {sandbox_name} {out_path.name} --enrich", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
