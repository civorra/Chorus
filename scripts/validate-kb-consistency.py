#!/usr/bin/env python3
"""
validate-kb-consistency.py — Chorus KB internal consistency gate

Five groups of mechanical checks per agent (deterministic, no LLM):

  1. HELPERS-EXIST  : YAML `use ...::Helpers qw(f)` → f in @EXPORT_OK
  2. HELPERS-SYNC   : @EXPORT_OK ↔ '* Perl Helpers' org section (bidi)
  3. TYPE-ORPHAN    : type_element in org not matched by any YAML filtre
                      Supports Strategy A (two-stage targeting): a type is
                      considered covered if a targeting rule matches it via
                      type_element filtre (simple or regex) and sets an
                      intermediate slot (besoin_*), provided at least one
                      downstream verdict rule reads that intermediate slot.
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


def _extract_regex_alternation(regex_inner: str) -> set:
    """
    Extract plain identifier values from a regex alternation inner string
    (delimiters already stripped).

    ``\\A(?:val1|val2|val3)\\z`` → {val1, val2, val3}

    Accepts both single-backslash (``\\A``) and double-backslash (``\\\\A``)
    escaped anchors as produced by YAML file read.
    Returns an empty set when the inner pattern contains unsupported operators.
    """
    inner = regex_inner
    # Remove anchors: \\A \\z \\Z ^ $  (double-backslash and single-backslash)
    inner = re.sub(r'\\\\[AzZ]|\\[AzZ]|[\^$]', '', inner)
    # Remove non-capturing groups (?:...) and plain capturing groups
    inner = re.sub(r'\(\?:', '', inner)
    inner = re.sub(r'[()]', '', inner)
    vals = set()
    for v in inner.split('|'):
        v = v.strip()
        # Accept only clean identifier-like values — reject residual regex chars
        if v and not re.search(r'[\\.*+?{}\[\]]', v):
            vals.add(v)
    return vals


def parse_filtre_values(filtre_str: str) -> set:
    """
    Extract concrete *type_element* values from a YAML ``filtre:`` expression.

    Handles the four formats found in Chorus YAML rules:

    1. **Simple value** — ``'paroi_separative'`` or ``paroi_separative``
       → ``{paroi_separative}``

    2. **Bare regex** — ``'/\\\\A(?:val1|val2)\\\\z/'``
       → ``{val1, val2}``

    3. **Perl ``=~`` expression** — the filtre is a quoted Perl snippet:
       ``'$_->get("type_element") =~ /\\A(?:v1|v2)\\z/'``
       ``'$_->{type_element} =~ /v1|v2/'``
       → values extracted from the regex alternation

    4. **Perl ``eq`` expression**:
       ``'$_->get("type_element") eq "paroi_separative"'``
       ``'$_->{type_element} eq "value"'``
       → ``{value}``

    Compound Perl expressions (``&&`` / ``||``) are supported — only the
    ``type_element``-related clause is extracted; other conditions are ignored.

    Returns an empty set when no recognizable ``type_element`` pattern is found
    or the expression is too complex to parse safely.
    """
    if not filtre_str:
        return set()
    s = filtre_str.strip()

    # Strip outer single or double quotes
    if len(s) >= 2 and s[0] in ('"', "'") and s[-1] == s[0]:
        inner = s[1:-1]
        if '$_' in inner or '$f' in inner:
            # Perl expression — process without further quote-stripping
            s = inner
        else:
            # Quoted simple value or bare regex
            s = inner

    # ── Bare regex: /pattern/ ────────────────────────────────────────────────
    if s.startswith('/') and s.endswith('/') and s.count('/') >= 2:
        return _extract_regex_alternation(s[1:-1])

    # ── Perl =~ expression ───────────────────────────────────────────────────
    # Matches: $_->get("type_element") =~ /pattern/
    #      or: $_->{type_element} =~ /pattern/
    # (possibly preceded/followed by other &&/|| clauses)
    _TYPE_EL = (
        r'\$_\s*->\s*(?:get\s*\(\s*["\']type_element["\']\s*\)'
        r'|{type_element})'
    )
    vals: set = set()
    for m in re.finditer(_TYPE_EL + r'\s*=~\s*/([^/]+)/', s):
        vals.update(_extract_regex_alternation(m.group(1)))
    if vals:
        return vals

    # ── Perl eq expression ───────────────────────────────────────────────────
    for m in re.finditer(_TYPE_EL + r'\s*eq\s*["\']([^"\']+)["\']', s):
        vals.add(m.group(1))
    if vals:
        return vals

    # ── Simple unquoted/bare value ───────────────────────────────────────────
    if '$' not in s and not re.search(r'[/\\.*+?{}\[\]|()]', s):
        return {s} if s else set()

    return set()


def parse_yaml_rules_structured(rules_dir: Path) -> list:
    """
    Parse every YAML rule file in *rules_dir* and return a list of dicts::

        {
          'file':          str,
          'find_pairs':    [(attribut_name, filtre_str), ...],
          'slots_set':     set[str],   # slots written via $f->set(...)
          'writes_verdict': bool,
        }

    ``filtre_str`` is an empty string when no ``filtre:`` line follows the
    ``attribut:`` line in the FIND/CHERCHER block.
    """
    rules = []
    for yml in sorted(rules_dir.glob('*.yml')):
        try:
            text = yml.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue

        # --- (attribut, filtre) pairs ----------------------------------------
        find_pairs = []
        for m in re.finditer(r'\battribut:\s*(\w+)', text):
            attr = m.group(1)
            # Look for filtre: on the lines immediately following attribut:
            # Stop before the next attribut: occurrence to stay within the item.
            snippet = text[m.end(): m.end() + 300]
            next_attr = re.search(r'\battribut:', snippet)
            if next_attr:
                snippet = snippet[:next_attr.start()]
            filtre_m = re.search(r'\bfiltre:\s*(.+?)(?:\n|$)', snippet)
            filtre_str = filtre_m.group(1).strip() if filtre_m else ''
            find_pairs.append((attr, filtre_str))

        # --- slots written via any frame variable ($f / $e / alias / $SELF) ----
        # Chorus CHERCHER blocks may declare a named alias (e.g. `e:`, `src:`),
        # so the frame variable in EFFET can be $e, $src, etc. — not only $f.
        slots_set: set = set()
        for sm in re.finditer(
                r'\$\w+\s*->\s*set\s*\([\'"](\w+)[\'"]', text):
            s = sm.group(1)
            if not _INTERNAL_SLOT.match(s):
                slots_set.add(s)

        writes_verdict = any(s.startswith('verdict') for s in slots_set)

        rules.append({
            'file': yml.name,
            'find_pairs': find_pairs,
            'slots_set': slots_set,
            'writes_verdict': writes_verdict,
        })

    return rules


def build_type_coverage(rules: list) -> tuple:
    """
    Compute type_element coverage with Strategy A (two-stage) transitivity.

    **Strategy A** pattern::

        Stage 1 — targeting rule:
            attribut: type_element
            filtre: "/\\A(?:typeA|typeB|...)\\z/"   ← regex or simple value
            ACTION: $f->set('besoin_X', 1)          ← no verdict_* written

        Stage 2 — verdict rule:
            attribut: besoin_X
            filtre: 1
            ACTION: $f->set('verdict_foo', ...)     ← verdict written

    A type value is *transitively covered* when:
    1. A targeting rule matches it (via type_element filtre) and sets an
       intermediate slot (no verdict_* in its own ACTION).
    2. At least one downstream rule reads that same intermediate slot via
       ``attribut: <slot>`` and writes a ``verdict_*`` slot.

    Returns:
        direct_covered (set[str])      — types directly covered by verdict rules
        transitive_covered (set[str])  — types covered via Strategy A chain
        all_yaml_types (dict[str, list[str]])
                                       — {type_val: [yml_file, ...]}
                                         used for TYPE-DEAD check
    """
    all_yaml_types: dict = {}

    # slot → True when a verdict rule reads it via attribut:
    slot_has_verdict_downstream: dict = {}

    # type_val → set of intermediate slots set by targeting rules
    type_to_intermediates: dict = {}

    direct_covered: set = set()

    # --- Pass 1: classify rules -----------------------------------------------
    for rule in rules:
        type_pairs = [(a, f) for a, f in rule['find_pairs']
                      if a == 'type_element']

        if not type_pairs:
            # No direct type_element targeting.
            # If this rule writes a verdict, record which attribut slots it reads
            # so we can resolve downstream transitivity in pass 2.
            if rule['writes_verdict']:
                for attr, _ in rule['find_pairs']:
                    slot_has_verdict_downstream[attr] = True
            continue

        # Collect all type values matched by this rule
        rule_type_vals: set = set()
        for _, filt in type_pairs:
            for v in parse_filtre_values(filt):
                rule_type_vals.add(v)
                all_yaml_types.setdefault(v, []).append(rule['file'])

        if rule['writes_verdict']:
            # Direct coverage — this rule both targets and decides
            direct_covered.update(rule_type_vals)
        else:
            # Targeting rule (Strategy A stage 1) — sets intermediate slot(s)
            for type_val in rule_type_vals:
                type_to_intermediates.setdefault(
                    type_val, set()).update(rule['slots_set'])

    # --- Pass 2: resolve transitivity -----------------------------------------
    transitive_covered: set = set()
    for type_val, intermediate_slots in type_to_intermediates.items():
        if type_val in direct_covered:
            continue   # already directly covered — no need
        for slot in intermediate_slots:
            if slot_has_verdict_downstream.get(slot, False):
                transitive_covered.add(type_val)
                break

    return direct_covered, transitive_covered, all_yaml_types


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
    _rules_struct  = parse_yaml_rules_structured(rules_dir) if rules_dir.is_dir() else []
    _direct, _transitive, yaml_types = build_type_coverage(_rules_struct)
    _covered_by_yaml = _direct | _transitive
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
    # _covered_by_yaml = direct coverage ∪ transitive Strategy A coverage
    # Guard: only run when at least one YAML filtre was successfully parsed
    # (yaml_types non-empty), to avoid false positives on unknown filtre formats.
    if org_types and yaml_types:
        for v in sorted(org_types - _covered_by_yaml - uncovered_types):
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
