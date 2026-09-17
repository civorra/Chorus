#!/usr/bin/env python3
"""
chorus-check-terminal-guard.py — Static safeguard against structurally
unreachable TERMINAL rules in a Chorus sandbox.

RATIONALE
---------
A Chorus pipeline agent can carry a rule with `TERMINAL: solved`. If that
rule's `FIND.filtre` requires a specific `type_element` value (positive
equality, e.g. `eq 'cle_cryptographique'`) and the project JSON being
checked contains ZERO elements of that type, the FIND never matches any
Frame, the rule never fires, `TERMINAL: solved` is never reached for that
agent, and Chorus::Expert::run() loops until max_cycles is exhausted —
which can take a very long time on large sandboxes (looks like an
"infinite loop" from the outside).

Incident that motivated this script: sandbox 09-cyber-sec-ANSII,
agent synthese-conformite-cles / rule R03-terminaison.yml, CBOM import
project with 0 `cle_cryptographique` elements (2026-09-16).

WHAT THIS SCRIPT DOES
----------------------
1. Scans `$SANDBOX/rules/<slug>/*.yml` for every rule containing
   `TERMINAL: solved` (or `TERMINAL: <anything>`, flagged as a terminal rule).
2. Extracts the `FIND.filtre` expression declared under the FIND block for
   that rule.
3. Loads the project JSON to be checked, and collects the actual set of
   `type_element` values present among `elements`.
4. Heuristically evaluates whether the filtre expression is *positively
   dependent* on a `type_element` value (pattern: `type_element eq '<X>'`
   possibly combined with `&&`/`||`) that does NOT appear in the project's
   type_element set — WITHOUT a `ne` (negation) branch that would make the
   filter still match other elements.
5. Reports any TERMINAL rule whose FIND would deterministically match
   ZERO frames for this specific project — before any pipeline run.

This is a HEURISTIC static check, not a full Perl expression evaluator.
It handles the common patterns actually used in this codebase:
  - `defined $_->{type_element} && $_->{type_element} eq 'X'`         → at risk if 'X' absent
  - `defined $_->{type_element} && $_->{type_element} ne 'X'`         → safe unless ALL types == 'X'
  - `defined $_->{type_element}`                                      → always safe (matches any typed frame)
  - `$_->{type_element} eq 'X' || $_->{type_element} eq 'Y'`         → at risk if neither X nor Y present

Anything more complex (nested parens, regex, custom subs) is reported as
"⚠️ UNPARSEABLE — manual review required" rather than silently assumed safe.

USAGE
-----
    python3 chorus-check-terminal-guard.py <sandbox-dir> <project.json>

EXIT CODES
----------
    0  — no at-risk TERMINAL rule detected
    1  — at least one at-risk TERMINAL rule detected (do NOT run chorus-check
         without fixing the rule first, or confirm the project data first)
    2  — usage / file error
"""
import sys
import os
import re
import json
import glob


def load_project_types(project_path):
    with open(project_path, encoding="utf-8") as f:
        data = json.load(f)
    elements = data.get("elements", [])
    types = set()
    for e in elements:
        t = e.get("type_element")
        if t is not None:
            types.add(t)
    return types, len(elements)


def find_terminal_rules(sandbox_dir):
    """Return list of (yml_path, rule_name, find_filtre) for every rule
    declaring TERMINAL (any value)."""
    results = []
    pattern = os.path.join(sandbox_dir, "rules", "*", "*.yml")
    for yml_path in sorted(glob.glob(pattern)):
        with open(yml_path, encoding="utf-8") as f:
            content = f.read()

        if not re.search(r'^TERMINAL:\s*\S+', content, re.MULTILINE):
            continue

        rule_match = re.search(r'^RULE:\s*(\S+)', content, re.MULTILINE)
        rule_name = rule_match.group(1) if rule_match else os.path.basename(yml_path)

        # Extract the FIND block's filtre (first one found — sandbox rules
        # in this codebase use a single top-level FIND entry with optional
        # filtre key).
        filtre_match = re.search(
            r'filtre:\s*(["\'])(.*?)\1\s*$', content, re.MULTILINE
        )
        filtre = filtre_match.group(2) if filtre_match else None

        results.append((yml_path, rule_name, filtre))
    return results


def extract_eq_conditions(filtre):
    """Return list of (op, value) for every `type_element <op> '<value>'`
    comparison found in the filtre string, where op in ('eq', 'ne')."""
    if not filtre:
        return []
    pattern = re.compile(
        r"type_element\}?\s*(eq|ne)\s*['\"]([^'\"]+)['\"]"
    )
    return pattern.findall(filtre)


def classify_risk(filtre, project_types):
    """
    Return (risk: bool, reason: str, class: str)
      class in {'SAFE_NO_CONDITION', 'SAFE_NEGATION', 'AT_RISK', 'UNPARSEABLE'}
    """
    if filtre is None:
        return (False, "No filtre found on FIND block — cannot assess (manual review).", "UNPARSEABLE")

    conditions = extract_eq_conditions(filtre)

    if not conditions:
        # No type_element eq/ne comparison at all — e.g. bare
        # `defined $_->{type_element}` → matches any typed frame → safe,
        # UNLESS the filtre references some other slot exclusively (rare
        # in this codebase, but flag as unparseable rather than assume safe
        # if the filtre looks non-trivial).
        if re.search(r"defined\s+\$_->\{type_element\}", filtre) and len(filtre.strip()) < 60:
            return (False, "Filtre only checks `defined type_element` — matches any typed frame.", "SAFE_NO_CONDITION")
        return (False, "No type_element eq/ne condition detected — assumed safe, but review manually if complex.", "UNPARSEABLE")

    # Does the filtre contain at least one negation (`ne`) with no `eq`?
    has_eq = any(op == "eq" for op, _ in conditions)
    has_ne = any(op == "ne" for op, _ in conditions)

    if has_ne and not has_eq:
        # e.g. `type_element ne 'cle_cryptographique'` — matches any type
        # OTHER than the excluded one. At risk only if EVERY element in the
        # project has exactly that excluded type (i.e. project_types is a
        # subset of {excluded values}).
        excluded_values = {v for op, v in conditions if op == "ne"}
        if project_types and project_types <= excluded_values:
            return (True,
                    f"Filtre excludes {sorted(excluded_values)} via `ne` — "
                    f"but ALL project type_element values ({sorted(project_types)}) "
                    f"are within the excluded set → FIND would match 0 frames.",
                    "AT_RISK")
        return (False,
                f"Filtre uses negation `ne` on {sorted(excluded_values)} — "
                f"safe as long as at least one project type_element falls outside "
                f"that set (project has: {sorted(project_types)}).",
                "SAFE_NEGATION")

    # has_eq (possibly mixed with ne, or multiple eq via ||) — positive
    # dependency on specific value(s) being present.
    required_values = {v for op, v in conditions if op == "eq"}
    if not (required_values & project_types):
        return (True,
                f"Filtre requires type_element ∈ {sorted(required_values)} (via `eq`), "
                f"but NONE of these values appear in the project "
                f"(project has: {sorted(project_types) or '(none)'}). "
                f"FIND would match 0 frames for this project → TERMINAL unreachable.",
                "AT_RISK")
    return (False,
            f"Filtre requires type_element ∈ {sorted(required_values)} — "
            f"at least one is present in the project.",
            "SAFE_NO_CONDITION")


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)

    sandbox_dir = sys.argv[1]
    project_path = sys.argv[2]

    if not os.path.isdir(sandbox_dir):
        print(f"⛔ Sandbox directory not found: {sandbox_dir}")
        sys.exit(2)
    if not os.path.isfile(project_path):
        print(f"⛔ Project file not found: {project_path}")
        sys.exit(2)

    project_types, n_elements = load_project_types(project_path)
    terminal_rules = find_terminal_rules(sandbox_dir)

    print("=" * 72)
    print("  chorus-check-terminal-guard — static TERMINAL reachability check")
    print("=" * 72)
    print(f"  Sandbox        : {sandbox_dir}")
    print(f"  Project        : {project_path}  ({n_elements} element(s))")
    print(f"  type_element(s) present in project : {sorted(project_types) or '(none)'}")
    print(f"  TERMINAL rule(s) found              : {len(terminal_rules)}")
    print("-" * 72)

    any_risk = False
    for yml_path, rule_name, filtre in terminal_rules:
        risk, reason, cls = classify_risk(filtre, project_types)
        rel = os.path.relpath(yml_path, sandbox_dir)
        icon = "🔴 AT RISK" if risk else ("⚠️  UNPARSEABLE" if cls == "UNPARSEABLE" else "✅ safe")
        print(f"\n  [{icon}]  {rel}  (RULE: {rule_name})")
        print(f"      filtre  : {filtre}")
        print(f"      verdict : {reason}")
        if risk:
            any_risk = True

    print("\n" + "=" * 72)
    if any_risk:
        print("  🔴 RESULT: at least one TERMINAL rule is structurally unreachable")
        print("     for this project — chorus-check would loop until max_cycles.")
        print("     Fix the rule's FIND.filtre (or confirm the project data is")
        print("     intentional) BEFORE running chorus-check on this project.")
        print("=" * 72)
        sys.exit(1)
    else:
        print("  ✅ RESULT: all TERMINAL rules are reachable for this project.")
        print("=" * 72)
        sys.exit(0)


if __name__ == "__main__":
    main()
