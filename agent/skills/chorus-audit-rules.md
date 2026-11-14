# Skill — chorus-audit-rules

> Trigger: `chorus-audit-rules <sandbox-name> [--agent <slug>] [--fix] [--report]`
> Agent: `code`
>
> `<sandbox-name>` : sandbox containing a KB produced by `chorus-feed`
> `--agent <slug>` : restrict audit to one agent (default: all agents)
> `--fix`          : auto-correct purely syntactic pitfalls (Phase 3 subset only)
> `--report`       : write `$SANDBOX/workspace/reports/audit-rules-<NNN>.md`

**Single responsibility:** verify that every YAML rule's implementation matches
its definition in the agent's `.org` file (header, Catalogue de règles, Contraintes & Pitfalls).

> ⚠️ **This skill is read-only by default.** With `--fix`, only syntactic corrections
> (Phase 3 subset) are applied automatically. Semantic findings (Phases 1, 2, 4)
> are always report-only — they require human decision before any change.

> **Relation to other skills:**
> - `chorus-kb-maintenance` : structural pitfalls + `.org` ↔ YAML bijection → Phase 3 overlap
> - `chorus-check` Phase 1.5 : mechanical fixups during run audit → runtime, not definition
> - `chorus-audit-rules` : **semantic** conformance of implementation vs definition — pre-run

---

## Prerequisites

**Before Phase 0**, load the authoritative engine YAML reference:

```
eca__read_file("$ENGINE/agent/skills/chorus-engine-yaml.md")
```

This ensures Phase 3 pitfall checks are always aligned with the latest engine
conventions — CONDITION vs EXCEPTION semantics, `filtre` string rule, `fmatch`
limitations, `do{}` wrapping requirement, etc.

> Phase 3 of this skill inlines the pitfall patterns for standalone execution,
> but `chorus-engine-yaml.md` is the **authoritative source**. If the two diverge
> (new pitfall added to `chorus-engine-yaml.md` but not yet propagated here),
> `chorus-engine-yaml.md` takes precedence. Any new pitfall added there must be
> reflected in Phase 3 of this skill in the same commit.

---

## Phase 0 — Sandbox inventory

**Before any file read**, call `eca__directory_tree($SANDBOX/rules/)` and
`eca__directory_tree($SANDBOX/agent/chorus/)`.

Collect:
- Agent slugs: list of `rules/<slug>/` directories
- Rule files per agent: `rules/<slug>/R*.yml` (sorted by name)
- Org files: `agent/chorus/<slug>.org` for each agent

If `--agent <slug>` present: restrict to that agent only.

Print:
```
[chorus-audit-rules] sandbox: <name>
  Agents : <N>  (<slug1>, <slug2>, ...)
  Rules  : <total> across <N> agents
  Mode   : <audit-only | audit+fix>
```

---

## Phase 1 — Header slots vs EFFET

> **Purpose:** verify that every slot declared in the rule header comment
> is actually read/written in the EFFET, and vice versa.

For each rule file `R<NN>-<slug>.yml`:

### 1.1 — Parse rule header

Extract from the `##` comment block:

```
INPUTS / ENTRÉES   → list of slot names declared as inputs
OUTPUTS / SORTIES  → list of slot names declared as outputs
HELPERS            → list of helper function names declared
```

Heuristic: each line matching `#   <slot_name>` or `#   <slot_name>  :` contributes
one slot name. Ignore lines starting with `#   #` (sub-comments) and system slots
(`_rule_trace`, `_DEFAULT`, `_NEEDED`).

### 1.2 — Parse EFFET body

Scan the EFFET Perl code for:
- **Reads** : `$<var>->get('<slot>')` or `$<var>->{<slot>}` patterns → extract slot names
- **Writes** : `$<var>->set('<slot>',` patterns → extract slot names
- **Helper imports** : `qw(<name1> <name2>...)` after `use ...::Helpers` → extract names

> ⚠️ Use text heuristics only — do not attempt full Perl parsing.
> A slot appearing in a string literal or comment is a false positive; apply
> minimum context filtering (preceded by `->get('` or `->set('`).

### 1.3 — Cross-checks

| Check | Classification |
|---|---|
| Input slot declared in header but `->get(...)` absent from EFFET | ⚠️ MISSING-READ |
| Output slot declared in header but `->set(...)` absent from EFFET | ⚠️ MISSING-WRITE |
| Helper declared in header but absent from `qw(...)` import | ⚠️ MISSING-IMPORT |
| Slot written in EFFET (`->set(...)`) but absent from header SORTIES | 📝 UNDECLARED-WRITE |
| Slot read in EFFET (`->get(...)`) but absent from header ENTRÉES | 📝 UNDECLARED-READ |

> **UNDECLARED** findings are informational only — the header may legitimately omit
> `_rule_trace` or intermediate computed variables. Flag but do not block.

> **MISSING** findings are ⚠️ warnings — a declared slot that is never actually
> used is likely a header documentation error or a silently dropped implementation.

---

## Phase 2 — .org Catalogue conformance

> **Purpose:** verify that documented constraints from the agent `.org` are
> reflected in the rule's CONDITION, filtre, or EFFET.

For each agent, read `agent/chorus/<slug>.org` and extract:

### 2.1 — Catalogue de règles entry

For each rule, find the matching row in `* Catalogue de règles`:
```
| R02 | R02-isolement-aerien.yml | Art. 2 — DnT,A ≥ seuil (10 combinaisons émission/réception) |
```

Extract: rule description text. Flag if no matching row found → ❌ ORPHAN-RULE.

### 2.2 — Contraintes & Pitfalls scan

Read the `* Contraintes & Pitfalls` section of the `.org`.
For each documented constraint, apply heuristic keyword matching:

| .org keyword pattern | Expected YAML element | Check |
|---|---|---|
| *"non applicable.*agrandissement"* or *"type_travaux.*agrandissement"* | `CONDITION` containing `type_travaux` | ⚠️ if absent |
| *"local_exclus"* (exception documented) | EFFET branch `$e->get('local_exclus')` | ⚠️ if absent |
| *"`_DEFAULT` = `<val>`"* for slot `<s>` | `$e->get('<s>') // <val>` in EFFET | 📝 if absent |
| *"agrandissement : seul Art. 7"* | R02/R03: `CONDITION type_travaux`; R05: no restriction | ⚠️ if R02/R03 missing |
| *"jamais déduire.*automatiquement"* | No auto-assignment of that slot in EFFET | 📝 advisory |

> These are **heuristic** checks based on keyword patterns in the `.org` text.
> They cannot cover all constraints — only the most common, high-impact ones
> (exclusion conditions, _DEFAULT values, type guards).
> Always display the matched `.org` text alongside the finding so the operator
> can judge relevance.

### 2.3 — Dictionnaire des slots cross-check

For each slot written by the rule (from Phase 1.2 EFFET writes):
- Verify the slot appears in `* Dictionnaire des slots` of the `.org`
- If absent → ⚠️ UNDOCUMENTED-SLOT (rule writes a slot not in the KB dictionary)

---

## Phase 3 — Pitfalls moteur

> **Purpose:** detect known engine pitfalls, including those covered by
> `chorus-kb-maintenance` (reproduced here for a single-command audit entry point)
> and ENG-047 (new).

For each rule, scan the raw YAML text:

### 3.1 — PREMISSES with Perl expressions (ENG-047) — 🔴 CRITICAL

```
Pattern: PREMISSES: block containing any of:
  $  →  Perl variable
  ->  →  method call
  do {  →  do block
  CODE:  →  YAML sub-key with Perl code
  \b(ne|eq|lt|gt|le|ge)\b  →  Perl comparison operator
  //  →  defined-or operator
  &&  →  boolean operator
```

Finding: `🔴 PREMISSES-PERL-EXPR — expression Perl inerte, déplacer dans CONDITION`

If `--fix`: **remove the PREMISSES block entirely** and emit a manual correction
recommendation (do not auto-generate CONDITION — semantic decision required).

### 3.2 — `filtre:` as YAML structure (not string) — 🔴 CRITICAL

```
Pattern: filtre: followed by a YAML mapping (key: value) or sequence (- item)
  instead of a quoted/block Perl string
```

Finding: `🔴 FILTRE-NOT-STRING — filtre parsed as YAML structure → constant truthy, matches ALL Frames`

### 3.3 — Unconditional `return 1` / `1` without conditional writes — 🔴 CRITICAL

```
Pattern: EFFET body ends with bare `1` or `return 1` but contains no
  `if (...) { ... return 1 }` or `$e->set(...)` before the final `1`
```

Finding: `🔴 UNCONDITIONAL-RETURN-1 — règle retourne toujours 1 sans écrire de slot → boucle infinie potentielle`

> This check is intentionally conservative — a rule with any `$e->set(...)` call
> is assumed to be productive. Only flag if EFFET appears to do nothing but return 1.

### 3.4 — `$f->{slot}` for domain reads outside EXCEPTION — 🟠 SIGNIFICANT

```
Pattern: in EFFET body: $<var>->{<slot>} where <slot> is not a system slot
  (_KEY, _VALUE, _DEFAULT, _NEEDED, _ISA, _PARENT_KEY, _BEFORE, _AFTER, _REQUIRE)
  AND the occurrence is not in the EXCEPTION: line
```

Finding: `🟠 HASH-READ-DOMAIN — $f->{slot} contourne ->get(), ignore _DEFAULT/_ISA`

### 3.5 — Multi-statement CONDITION/EXCEPTION without `do{}` — 🟠 SIGNIFICANT

```
Pattern: CONDITION or EXCEPTION value contains ';' (after stripping trailing ';')
  AND does not start with 'do {'
```

Finding: `🟠 MULTISTATEMENT-GUARD — CONDITION multi-instruction sans do{} → seule la première expression est gardée`

### 3.6 — `non_conformity_motif` absent on NON_CONFORME branch — 🟡 MINOR

```
Pattern: EFFET contains `'NON_CONFORME'` but no `->set('non_conformity_motif',`
```

Finding: `🟡 MISSING-MOTIF — branche NON_CONFORME sans non_conformity_motif → webapp affiche motif vide`

### 3.7 — `_rule_trace` absent from EFFET — 🟡 MINOR

```
Pattern: EFFET does not contain 'push @$trace,' or '_rule_trace'
```

Finding: `🟡 MISSING-RULE-TRACE — pas de _rule_trace → rapport sans traçabilité article corpus`

### 3.8 — `fmatch(value =>)` — unsupported parameter — 🟠 SIGNIFICANT

```
Pattern: fmatch(slot => '...', value => ...)
```

Finding: `🟠 FMATCH-VALUE-UNSUPPORTED — paramètre value => ignoré par Chorus::Frame::fmatch (non implémenté)`

---

## Phase 4 — CHERCHER / CONDITION / EFFET coherence

> **Purpose:** detect mismatches between how scope variables are bound in
> CHERCHER and how they are used in CONDITION/EFFET.

### 4.1 — Scope variable consistency

For each scope variable declared in CHERCHER (e.g., `e:`, `p:`, `facade:`):
- Verify the same variable name appears in CONDITION and EFFET
- If CONDITION uses `$logement` but CHERCHER bound `$e:` → ⚠️ SCOPE-MISMATCH

### 4.2 — `fmatch` in EFFET without type filter (multi-agent sandboxes)

```
Pattern: EFFET contains fmatch(slot => 'type_element')
  AND the sandbox has > 1 agent
  AND no grep { ... type_element ... } filter immediately follows
```

Finding: `📝 FMATCH-UNFILTERED — fmatch(type_element) sans filtre sur sandbox multi-agent → collecte toutes les Frames (PMR, acoustique, façades...)`

> This is informational (📝) — often benign due to implicit filtering via
> `if defined $v` on verdict slots. Flag for human review.

### 4.3 — CONDITION references slot not in CHERCHER scope

```
Pattern: CONDITION contains $<X>->get(...) where $<X> is not a declared
  CHERCHER scope variable and not $SELF
```

Finding: `⚠️ CONDITION-UNDEFINED-VAR — variable $X dans CONDITION non déclarée dans CHERCHER`

---

## Output format

### Console summary (always)

```
[chorus-audit-rules] sandbox: <name>  agent(s): <slug1>, <slug2>

PHASE 1 — Header ↔ EFFET
  agent-acoustique/R02-isolement-aerien :
    ⚠️ MISSING-READ  : slot 'type_emission' in ENTRÉES — no ->get('type_emission') in EFFET

PHASE 2 — .org Catalogue conformance
  agent-acoustique/R02-isolement-aerien :
    ⚠️ CONSTRAINT-MISSING : Pitfall n°3 "type_travaux ne agrandissement"
       .org text: "R02 et R03 incluent une PREMISSE type_travaux ne 'agrandissement'"
       CONDITION: type_travaux absent from CONDITION

PHASE 3 — Pitfalls moteur
  agent-acoustique/R02-isolement-aerien :
    🔴 PREMISSES-PERL-EXPR  : "defined $e->get('type_emission')" — inert (ENG-047)
  agent-accessibilite-pmr/R08-publication-verdict-access :
    🔴 FILTRE-NOT-STRING    : filtre: is a YAML sequence, not a Perl string
    🟠 FMATCH-VALUE-UNSUPPORTED : fmatch(slot => 'type_element', value => $t)

PHASE 4 — CHERCHER/EFFET coherence
  (none found)

──────────────────────────────────────────────
Summary: 7 findings (2 🔴  2 🟠  1 ⚠️  2 📝)
  🔴 2 critical  — fix before running chorus-check
  🟠 2 significant — review recommended
  ⚠️ 1 warning   — human decision required
  📝 2 info      — informational

Report: workspace/reports/audit-rules-001.md  (--report flag)
```

### Report file (`--report`)

Markdown file `$SANDBOX/workspace/reports/audit-rules-<NNN>.md` containing:
- Full console output above
- For each finding: the matched `.org` text and the actual YAML snippet side by side
- For Phase 3 `--fix` corrections: before/after diff per rule

---

## Pitfall checklist integration

> This skill's Phase 3 overlaps partially with `chorus-kb-maintenance`.
> When both are run on the same sandbox, findings may duplicate.
> Recommended workflow:
> 1. `chorus-audit-rules` first (pre-run, definition conformance)
> 2. `chorus-check --all` (run, verdict quality)
> 3. `chorus-kb-maintenance` (post-run, structural drift)
