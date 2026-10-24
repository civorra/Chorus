#!/usr/bin/env python3
"""
validate-kb-consistency.py — Chorus KB internal consistency gate

Four mechanical checks per agent (deterministic, no LLM):

  1. HELPERS-EXIST  : every function called via `use ...::Helpers qw(f)` in
                      a YAML ACTION block must appear in Helpers.pm @EXPORT_OK
  2. HELPERS-SYNC   : @EXPORT_OK ↔ '* Perl Helpers' org section (bidirectional)
  3. TYPE-ORPHAN    : type_element value documented in org but matched by
                      no YAML filtre: — potential dead org entry
  4. TYPE-DEAD      : type_element value used in a YAML filtre: but absent
                      from the org catalogue — rule that can never fire

Annotation: a comment `# intentionally uncovered — <reason>` in the org
immediately before a `*** type_element = <value>` entry suppresses the
TYPE-ORPHAN alert for that value.

Usage : python3 validate-kb-consistency.py <sandbox-path> [--agent <slug>] [--quiet]
Exit  : 0 = clean, 1 = divergences found, 2 = usage / IO error
"""

import sys
import re
from pathlib import Path

_UNCOVERED_RE = re.compile(r'#\s*intentionally\s+uncovered', re.IGNORECASE)


# ── Parsers ────────────────────────────────────────────────────────────────────

def parse_export_ok(pm_path: Path) -> set:
    """Extract function names from 'our @EXPORT_OK = qw(...)' in Helpers.pm."""
    try:
        text = pm_path.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return set()
    m = re.search(r'our\s+@EXPORT_OK\s*=\s*qw\(([^)]+)\)', text, re.DOTALL)
    if not m:
        return set()
    return set(m.group(1).split())


def parse_yaml_helper_calls(yml_path: Path) -> set:
    """Extract function names from 'use Package::Helpers qw(...)' in YAML."""
    try:
        text = yml_path.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return set()
    funcs = set()
    for m in re.finditer(r'use\s+\S+::Helpers\s+qw\(([^)]+)\)', text):
        funcs.update(m.group(1).split())
    return funcs


def parse_org_helpers_section(org_text: str) -> dict:
    """
    Parse '* Perl Helpers' section of an org KB file.
    Returns {func_name: {'called_by': [rule_slug, ...]}} or {}.
    """
    m = re.search(r'^\* Perl Helpers\s*$', org_text, re.MULTILINE)
    if not m:
        return {}
    section = org_text[m.end():]
    end = re.search(r'^\* \S', section, re.MULTILINE)
    if end:
        section = section[:end.start()]

    funcs = {}
    current = None
    for line in section.splitlines():
        h2 = re.match(r'^\*{2}\s+(\w+)\s*$', line.strip())
        if h2:
            current = h2.group(1)
            funcs[current] = {'called_by': []}
        elif current:
            cb = re.search(r'Called by\s*:\s*(.+)', line)
            if cb:
                funcs[current]['called_by'] = [
                    r.strip().split()[0] for r in cb.group(1).split(',')
                ]
    return funcs


def parse_org_type_elements(org_text: str) -> tuple:
    """
    Extract type_element values and intentionally-uncovered set from org.
    Sources: '*** type_element = <value>' headings and '* Targeting slots' tables.
    Returns (all_values: set[str], uncovered: set[str]).
    """
    values = set()
    uncovered = set()
    last_intentional = False

    for line in org_text.splitlines():
        # Intentionally-uncovered annotation
        if _UNCOVERED_RE.search(line):
            last_intentional = True
            continue

        # *** type_element = value  (Frame catalogue sub-headings)
        m = re.match(r'^\*{3}\s+type_element\s*=\s*(\S+)', line.strip())
        if m:
            v = m.group(1).strip("'\"")
            values.add(v)
            if last_intentional:
                uncovered.add(v)
            last_intentional = False
            continue

        # Targeting slots table: lines where type_element IS the cell value
        # (not a substring of another slot name like 'conforme_type_element').
        # Matches: | type_element | ... | 'val1' \vert 'val2' | ...
        if re.search(r'\|\s*type_element\s*\|', line) and "'" in line:
            for vm in re.finditer(r"'([^']+)'", line):
                v = vm.group(1)
                # Skip placeholders (<valeur>, <slug>...) and descriptions (spaces)
                if ' ' not in v and not v.startswith('<'):
                    values.add(v)
            last_intentional = False
            continue

        if line.strip():
            last_intentional = False

    return values, uncovered


def parse_yaml_type_elements(rules_dir: Path) -> dict:
    """
    Extract type_element values from YAML filtre: lines.
    Handles both eq 'value' and eq "value" patterns.
    Returns {value: [yml_filename, ...]}
    """
    val_map: dict = {}
    for yml in sorted(rules_dir.glob('*.yml')):
        try:
            text = yml.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        for m in re.finditer(
                r'type_element\s*\}\s*(?:eq|==)\s*[\'"]([^\'"]+)[\'"]', text):
            val_map.setdefault(m.group(1), []).append(yml.name)
    return val_map


# ── Agent discovery ────────────────────────────────────────────────────────────

def discover_agents(sandbox: Path) -> list:
    """
    Discover agents from agent/chorus/*.org (index.org excluded).
    Returns list of dicts: {slug, org_path, rules_dir, pm_path|None}
    """
    chorus_dir = sandbox / 'agent' / 'chorus'
    if not chorus_dir.is_dir():
        return []
    agents = []
    for org in sorted(chorus_dir.glob('*.org')):
        if org.stem == 'index':
            continue
        try:
            text = org.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue

        # #+RULES_DIR: rules/<slug>/
        rules_m = re.search(r'^#\+RULES_DIR:\s*(.+)', text, re.MULTILINE)
        rules_dir = (sandbox / rules_m.group(1).strip().rstrip('/')) \
                    if rules_m else (sandbox / 'rules' / org.stem)

        # #+AGENT: Package::Name → lib/Package/Name/Helpers.pm
        agent_m = re.search(r'^#\+AGENT:\s*(\S+)', text, re.MULTILINE)
        pm_path = None
        if agent_m:
            pkg_path = Path(agent_m.group(1).replace('::', '/')) / 'Helpers.pm'
            candidate = sandbox / 'lib' / pkg_path
            if candidate.exists():
                pm_path = candidate

        agents.append({
            'slug':      org.stem,
            'org_path':  org,
            'org_text':  text,
            'rules_dir': rules_dir,
            'pm_path':   pm_path,
        })
    return agents


# ── Per-agent checks ───────────────────────────────────────────────────────────

def check_agent(agent: dict) -> list:
    """Run all 4 checks for one agent. Return list of issue dicts."""
    issues = []
    slug      = agent['slug']
    org_text  = agent['org_text']
    rules_dir = agent['rules_dir']
    pm_path   = agent['pm_path']

    export_ok   = parse_export_ok(pm_path) if pm_path else set()
    org_helpers = parse_org_helpers_section(org_text)
    org_types, uncovered = parse_org_type_elements(org_text)
    yaml_types  = parse_yaml_type_elements(rules_dir) \
                  if rules_dir.is_dir() else {}

    # ── Check 1 — HELPERS-EXIST ──────────────────────────────────────────────
    if pm_path and rules_dir.is_dir():
        for yml in sorted(rules_dir.glob('*.yml')):
            for func in sorted(parse_yaml_helper_calls(yml)):
                if func not in export_ok:
                    issues.append({
                        'kind': 'HELPERS-EXIST', 'agent': slug,
                        'rule': yml.name,
                        'msg':  f"call '{func}()' not in @EXPORT_OK",
                    })

    # ── Check 2 — HELPERS-SYNC ───────────────────────────────────────────────
    if pm_path and org_helpers:
        for func in sorted(export_ok - set(org_helpers)):
            issues.append({
                'kind': 'HELPERS-SYNC', 'agent': slug,
                'msg':  f"'{func}' in @EXPORT_OK but absent from org '* Perl Helpers'",
            })
        for func in sorted(set(org_helpers) - export_ok):
            issues.append({
                'kind': 'HELPERS-SYNC', 'agent': slug,
                'msg':  f"'** {func}' in org but not in @EXPORT_OK",
            })

    # ── Check 3 — TYPE-ORPHAN ────────────────────────────────────────────────
    # Only meaningful when SOME rules use specific type_element filters.
    # If yaml_types is empty the agent uses generic `attribut: type_element`
    # rules (no per-value filter) — all values are intentionally universal.
    if org_types and yaml_types:
        for v in sorted(org_types - set(yaml_types) - uncovered):
            issues.append({
                'kind': 'TYPE-ORPHAN', 'agent': slug,
                'msg':  f"type_element '{v}' in org but matched by no YAML filtre",
            })

    # ── Check 4 — TYPE-DEAD ──────────────────────────────────────────────────
    if yaml_types and org_types:
        for v, ymls in sorted(yaml_types.items()):
            if v not in org_types:
                issues.append({
                    'kind': 'TYPE-DEAD', 'agent': slug, 'rule': ymls[0],
                    'msg':  f"type_element '{v}' in filtre but absent from org catalogue",
                })

    return issues


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    if not args or args[0] in ('-h', '--help'):
        print(__doc__)
        sys.exit(2)

    sandbox = Path(args[0])
    filter_slug = args[args.index('--agent') + 1] \
                  if '--agent' in args else None
    quiet = '--quiet' in args

    if not sandbox.is_dir():
        print(f"ERROR: sandbox not found: {sandbox}", file=sys.stderr)
        sys.exit(2)

    agents = discover_agents(sandbox)
    if filter_slug:
        agents = [a for a in agents if a['slug'] == filter_slug]
    if not agents:
        print("No agents found.", file=sys.stderr)
        sys.exit(2)

    all_issues = []
    for agent in agents:
        issues = check_agent(agent)
        all_issues.extend(issues)
        if not quiet:
            for iss in issues:
                rule_part = f"  rule:{iss['rule']}" if 'rule' in iss else ''
                print(f"[{iss['kind']}]  agent:{iss['agent']}{rule_part}  {iss['msg']}")

    if not all_issues:
        print(f"✅  {len(agents)} agent(s) — no divergence found.")
        sys.exit(0)

    counts = {}
    for iss in all_issues:
        counts[iss['kind']] = counts.get(iss['kind'], 0) + 1
    summary = '  '.join(f"{k}:{v}" for k, v in sorted(counts.items()))
    print(f"\n⚠️  {len(all_issues)} divergence(s) — {summary}")
    sys.exit(1)


if __name__ == '__main__':
    main()
