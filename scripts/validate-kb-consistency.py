#!/usr/bin/env python3
"""
validate-kb-consistency.py — Chorus KB internal consistency gate

Five groups of mechanical checks per agent (deterministic, no LLM):

  1. HELPERS-EXIST  : YAML `use ...::Helpers qw(f)` → f in @EXPORT_OK
  2. HELPERS-SYNC   : @EXPORT_OK ↔ '* Perl Helpers' org section (bidi)
  3. TYPE-ORPHAN    : type_element in org not matched by any YAML filtre
  4. TYPE-DEAD      : type_element in YAML filtre absent from org catalogue
  5. SLOT-MISMATCH  : slot read in YAML ($f->{x}, attribut: x) absent
                      from org '** Inputs' table  [critical — causes bad JSON]
     SLOT-ORPHAN    : slot written in YAML ($f->set('x',...)) absent
                      from org '** Outputs' table
     SLOT-DEAD      : slot in org '** Inputs' not read by any YAML rule  [info]

Annotations (org file):
  `# intentionally uncovered — <reason>` immediately before a
  `*** type_element = <value>` entry  →  suppresses TYPE-ORPHAN.
  Same annotation before a slot row in the Inputs table  →  suppresses SLOT-DEAD.

Slots starting with '_' are always excluded (Chorus internal machinery).

Usage : python3 validate-kb-consistency.py <sandbox-path> [--agent <slug>] [--quiet]
Exit  : 0 = clean, 1 = divergences found, 2 = usage / IO error
"""

import sys
import re
from pathlib import Path

_UNCOVERED_RE  = re.compile(r'#\s*intentionally\s+uncovered', re.IGNORECASE)
_INTERNAL_SLOT = re.compile(r'^_')   # exclude _rule_trace, _KEY, _ISA, etc.


# ── Helpers checks parsers ─────────────────────────────────────────────────────

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
    Parse '* Perl Helpers' section.
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


# ── Type checks parsers ────────────────────────────────────────────────────────

def parse_org_type_elements(org_text: str) -> tuple:
    """
    Returns (type_element_values: set[str], uncovered: set[str]).
    """
    values, uncovered = set(), set()
    last_intentional = False
    for line in org_text.splitlines():
        if _UNCOVERED_RE.search(line):
            last_intentional = True
            continue
        m = re.match(r'^\*{3}\s+type_element\s*=\s*(\S+)', line.strip())
        if m:
            v = m.group(1).strip("'\"")
            values.add(v)
            if last_intentional:
                uncovered.add(v)
            last_intentional = False
            continue
        if re.search(r'\|\s*type_element\s*\|', line) and "'" in line:
            for vm in re.finditer(r"'([^']+)'", line):
                v = vm.group(1)
                if ' ' not in v and not v.startswith('<'):
                    values.add(v)
            last_intentional = False
            continue
        if line.strip():
            last_intentional = False
    return values, uncovered


def parse_yaml_type_elements(rules_dir: Path) -> dict:
    """Returns {type_element_value: [yml_filename, ...]}"""
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


# ── Slot checks parsers (ENG-026) ──────────────────────────────────────────────

def _org_table_first_col(section_text: str, uncovered_before: set) -> tuple:
    """
    Parse an org-mode table within a section; return (slots, uncovered_slots).
    First column = slot name. Skips header/separator rows and internal slots.
    Strips inline annotations like '(réutilisé)', '(optionnel)'.
    """
    slots: set = set()
    uncovered: set = set()
    last_intentional = False
    for line in section_text.splitlines():
        if _UNCOVERED_RE.search(line):
            last_intentional = True
            continue
        stripped = line.strip()
        if not stripped.startswith('|'):
            if stripped:
                last_intentional = False
            continue
        # Separator row: |---+---+---|
        if re.match(r'^\|[-+\s]+\|', stripped):
            continue
        cells = [c.strip() for c in stripped.split('|')[1:-1]]
        if not cells:
            continue
        raw = cells[0]
        # Strip inline annotation: 'slot (réutilisé)' → 'slot'
        slot = re.sub(r'\s*\([^)]*\)\s*$', '', raw).strip()
        # Skip header rows and empty/internal slots
        if (not slot
                or slot.lower() in ('slot', 'slots', 'targeting slot')
                or _INTERNAL_SLOT.match(slot)):
            last_intentional = False
            continue
        slots.add(slot)
        if last_intentional:
            uncovered.add(slot)
        last_intentional = False
    return slots, uncovered


def parse_org_io_slots(org_text: str) -> tuple:
    """
    Parse '* Pipeline I/O' → '** Inputs' and '** Outputs' tables.
    Returns (input_slots: set, output_slots: set, uncovered_inputs: set).
    """
    # Locate * Pipeline I/O section
    io_m = re.search(r'^\* Pipeline I/O\s*$', org_text, re.MULTILINE)
    if not io_m:
        return set(), set(), set()
    io_section = org_text[io_m.end():]
    io_end = re.search(r'^\* \S', io_section, re.MULTILINE)
    if io_end:
        io_section = io_section[:io_end.start()]

    # ** Inputs sub-section
    in_m = re.search(r'^\*{2}\s+Inputs?\b', io_section, re.MULTILINE | re.IGNORECASE)
    out_m = re.search(r'^\*{2}\s+Outputs?\b', io_section, re.MULTILINE | re.IGNORECASE)

    def _extract(start_m, end_m):
        if not start_m:
            return set(), set()
        seg = io_section[start_m.end():]
        if end_m and end_m.start() > start_m.start():
            seg = io_section[start_m.end(): end_m.start()]
        elif end_m:
            # end_m is before start_m — find next ** heading after start
            nxt = re.search(r'^\*{2}\s+\S', seg, re.MULTILINE)
            if nxt:
                seg = seg[:nxt.start()]
        return _org_table_first_col(seg, set())

    in_slots, in_uncovered = _extract(in_m, out_m)
    out_slots, _ = _extract(out_m, None)
    return in_slots, out_slots, in_uncovered


def parse_yaml_slot_reads_all(rules_dir: Path) -> dict:
    """
    Extract all slot names READ across all YAML rules in rules_dir.
    Patterns: attribut: x  |  $f->{x}  |  $_->{x}  |  $f->get('x')
    Returns {slot_name: [yml_filename, ...]}
    """
    slot_map: dict = {}
    for yml in sorted(rules_dir.glob('*.yml')):
        try:
            text = yml.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        found: set = set()
        # attribut: slot_name  (in FIND block)
        for m in re.finditer(r'\battribut:\s*(\w+)', text):
            found.add(m.group(1))
        # $f->{slot} or $_->{slot}  (CONDITION / EXCEPTION / filtre / ACTION)
        for m in re.finditer(r'\$[f_]\s*->\s*\{[\'"]?(\w+)[\'"]?\}', text):
            found.add(m.group(1))
        # $f->get('slot')
        for m in re.finditer(r'\$f\s*->\s*get\s*\([\'"](\w+)[\'"]', text):
            found.add(m.group(1))
        for s in found:
            if not _INTERNAL_SLOT.match(s):
                slot_map.setdefault(s, []).append(yml.name)
    return slot_map


def parse_yaml_slot_writes_all(rules_dir: Path) -> dict:
    """
    Extract all slot names WRITTEN across all YAML rules in rules_dir.
    Patterns: $f->set('x', ...)
    Returns {slot_name: [yml_filename, ...]}
    """
    slot_map: dict = {}
    for yml in sorted(rules_dir.glob('*.yml')):
        try:
            text = yml.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        for m in re.finditer(r'\$(?:f|SELF)\s*->\s*set\s*\([\'"](\w+)[\'"]', text):
            s = m.group(1)
            if not _INTERNAL_SLOT.match(s):
                slot_map.setdefault(s, []).append(yml.name)
    return slot_map


# ── Agent discovery ────────────────────────────────────────────────────────────

def discover_agents(sandbox: Path) -> list:
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
        rules_m = re.search(r'^#\+RULES_DIR:\s*(.+)', text, re.MULTILINE)
        rules_dir = (sandbox / rules_m.group(1).strip().rstrip('/')) \
                    if rules_m else (sandbox / 'rules' / org.stem)
        agent_m = re.search(r'^#\+AGENT:\s*(\S+)', text, re.MULTILINE)
        pm_path = None
        if agent_m:
            pkg_path = Path(agent_m.group(1).replace('::', '/')) / 'Helpers.pm'
            candidate = sandbox / 'lib' / pkg_path
            if candidate.exists():
                pm_path = candidate
        agents.append({
            'slug': org.stem, 'org_path': org, 'org_text': text,
            'rules_dir': rules_dir, 'pm_path': pm_path,
        })
    return agents


# ── Per-agent checks ───────────────────────────────────────────────────────────

def check_agent(agent: dict) -> list:
    issues = []
    slug      = agent['slug']
    org_text  = agent['org_text']
    rules_dir = agent['rules_dir']
    pm_path   = agent['pm_path']

    export_ok    = parse_export_ok(pm_path) if pm_path else set()
    org_helpers  = parse_org_helpers_section(org_text)
    org_types, uncovered_types = parse_org_type_elements(org_text)
    yaml_types   = parse_yaml_type_elements(rules_dir) if rules_dir.is_dir() else {}
    org_in, org_out, uncovered_in = parse_org_io_slots(org_text)
    yaml_reads   = parse_yaml_slot_reads_all(rules_dir) if rules_dir.is_dir() else {}
    yaml_writes  = parse_yaml_slot_writes_all(rules_dir) if rules_dir.is_dir() else {}

    # ── Check 1 — HELPERS-EXIST ──────────────────────────────────────────────
    if pm_path and rules_dir.is_dir():
        for yml in sorted(rules_dir.glob('*.yml')):
            for func in sorted(parse_yaml_helper_calls(yml)):
                if func not in export_ok:
                    issues.append({'kind': 'HELPERS-EXIST', 'agent': slug,
                                   'rule': yml.name,
                                   'msg': f"call '{func}()' not in @EXPORT_OK"})

    # ── Check 2 — HELPERS-SYNC ───────────────────────────────────────────────
    if pm_path and org_helpers:
        for func in sorted(export_ok - set(org_helpers)):
            issues.append({'kind': 'HELPERS-SYNC', 'agent': slug,
                           'msg': f"'{func}' in @EXPORT_OK but absent from org '* Perl Helpers'"})
        for func in sorted(set(org_helpers) - export_ok):
            issues.append({'kind': 'HELPERS-SYNC', 'agent': slug,
                           'msg': f"'** {func}' in org but not in @EXPORT_OK"})

    # ── Check 3 — TYPE-ORPHAN ────────────────────────────────────────────────
    if org_types and yaml_types:
        for v in sorted(org_types - set(yaml_types) - uncovered_types):
            issues.append({'kind': 'TYPE-ORPHAN', 'agent': slug,
                           'msg': f"type_element '{v}' in org but matched by no YAML filtre"})

    # ── Check 4 — TYPE-DEAD ──────────────────────────────────────────────────
    if yaml_types and org_types:
        for v, ymls in sorted(yaml_types.items()):
            if v not in org_types:
                issues.append({'kind': 'TYPE-DEAD', 'agent': slug, 'rule': ymls[0],
                               'msg': f"type_element '{v}' in filtre but absent from org catalogue"})

    # ── Check 5 — SLOT-MISMATCH / SLOT-ORPHAN / SLOT-DEAD ───────────────────
    if org_in and yaml_reads:
        # 5a SLOT-MISMATCH: YAML reads slot not in org Inputs
        for slot, ymls in sorted(yaml_reads.items()):
            if slot not in org_in and slot not in org_out:
                issues.append({'kind': 'SLOT-MISMATCH', 'agent': slug,
                               'rule': ymls[0],
                               'msg': f"slot '{slot}' read in YAML but absent from org Pipeline I/O"})

    if org_out and yaml_writes:
        # 5b SLOT-ORPHAN: YAML writes slot not in org Outputs
        for slot, ymls in sorted(yaml_writes.items()):
            if slot not in org_out and slot not in org_in:
                issues.append({'kind': 'SLOT-ORPHAN', 'agent': slug,
                               'rule': ymls[0],
                               'msg': f"slot '{slot}' written in YAML but absent from org Outputs"})

    if org_in and yaml_reads:
        # 5c SLOT-DEAD [info]: org Input slot never read by any YAML
        for slot in sorted(org_in - set(yaml_reads) - uncovered_in):
            issues.append({'kind': 'SLOT-DEAD', 'agent': slug,
                           'msg': f"slot '{slot}' in org Inputs but not read by any YAML rule"})

    return issues


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    if not args or args[0] in ('-h', '--help'):
        print(__doc__)
        sys.exit(2)

    sandbox = Path(args[0])
    filter_slug = args[args.index('--agent') + 1] if '--agent' in args else None
    quiet   = '--quiet' in args
    no_info = '--no-info' in args   # suppress SLOT-DEAD [info] entries

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
        for iss in check_agent(agent):
            if no_info and iss['kind'] == 'SLOT-DEAD':
                continue
            all_issues.append(iss)
            if not quiet:
                rule_part = f"  rule:{iss['rule']}" if 'rule' in iss else ''
                tag = '  [info]' if iss['kind'] == 'SLOT-DEAD' else ''
                print(f"[{iss['kind']}]{tag}  agent:{iss['agent']}{rule_part}  {iss['msg']}")

    blocking = [i for i in all_issues if i['kind'] != 'SLOT-DEAD']
    if not all_issues:
        print(f"✅  {len(agents)} agent(s) — no divergence found.")
        sys.exit(0)

    counts = {}
    for iss in all_issues:
        counts[iss['kind']] = counts.get(iss['kind'], 0) + 1
    summary = '  '.join(f"{k}:{v}" for k, v in sorted(counts.items()))
    print(f"\n{'⚠️' if blocking else 'ℹ️'}  {len(all_issues)} divergence(s) — {summary}")
    sys.exit(1 if blocking else 0)


if __name__ == '__main__':
    main()
