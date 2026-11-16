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

### 3.9 — Unfiltered `fmatch` in `EXCEPTION`/`CONDITION` — 🔴 CRITICAL

```
Pattern: EXCEPTION or CONDITION contains fmatch(slot => 'X')
  AND no grep { $_->{type_element} =~ /.../ } filter immediately precedes
  the domain-slot test in the same expression.
```

```bash
grep -rnE "(EXCEPTION|CONDITION):.*fmatch\(" $SANDBOX/rules/*/*.yml \
  | grep -v "grep[^)]*type_element"
```

Finding: `🔴 FMATCH-UNFILTERED-GUARD — fmatch() dans EXCEPTION/CONDITION sans filtre famille → rule dormante ou multi-Frame erreur`

If `--fix`: **cannot auto-fix** — family filter depends on the agent's own `FIND.filtre`. Report with the agent's existing filter pattern as a suggestion. Operator must apply manually.

### 3.10 — `$agent->` misuse in YAML rule — 🔴 CRITICAL

```
Pattern: any .yml file contains $agent->
  ($agent is valid in addrule() Perl closures but always out-of-scope
   inside a .yml EFFET/ACTION/EXCEPTION — only $SELF is bound there)
```

```bash
grep -rn '\$agent->' $SANDBOX/rules/
```

Finding: `🔴 AGENT-MISUSE — $agent-> utilisé dans une règle YAML (hors scope → crash silencieux au premier déclenchement)`

If `--fix`: replace every `$agent->` with `$SELF->` (identical semantics inside a rule ACTION). Re-run grep to confirm zero matches.

### 3.11 — Cross-agent targeting-slot BOARD vs Frame-local wiring — 🔴 CRITICAL

```
Pattern: a slot S appears in CONDITION/EXCEPTION via $e->{S} or $w->{S}
  (Frame-local read) in agent B, but S is ONLY written as
  $SELF->BOARD->{S} (BOARD write) in agent A.
  → Frame-local read of a BOARD-only slot → always undef → rule dormant.
```

```bash
# Step 1: collect cross-agent candidate slots
grep -rhoE "(CONDITION|EXCEPTION):.*\\\$\w+->\{(\w+)\}" $SANDBOX/rules/*/*.yml \
  | grep -oE '\{(\w+)\}' | tr -d '{}' | sort | uniq -c | sort -rn
# Step 2: for each candidate slot S in N>1 agents, check if it is BOARD-only
grep -rn "set('<S>'" $SANDBOX/rules/*/*.yml       # Frame-local writers
grep -rn "BOARD->{'<S>'}" $SANDBOX/rules/*/*.yml  # BOARD writers
```

Finding: `🔴 CROSS-AGENT-WIRING — slot S lu Frame-local ($e->{S}) mais jamais écrit Frame-local → toujours undef`

If `--fix`: **cannot auto-fix** (semantic decision: Frame-local propagation rule vs BOARD promotion). Report affected rules with suggested fix pattern.

### 3.12 — Unbounded aggregate wait (`fmatch`/`return 0` forever) — 🔴 CRITICAL

```
Pattern: ACTION splits a comma-joined expected-id slot, resolves each via fmatch(),
  AND uses `return 0` if any lookup misses, with no retry counter (_decl_wait_cycles)
  and no MAX_WAIT fallback.
```

```bash
grep -rlP 'split\(/,/.*elements' $SANDBOX/rules/*/*.yml 2>/dev/null \
  | xargs -I{} sh -c 'grep -q "_decl_wait_cycles\|MAX_WAIT" {} || echo {}'
```

Finding: `🔴 UNBOUNDED-AGGREGATE — aggregate rule attend indéfiniment des sous-éléments → pipeline TIMEOUT`

If `--fix`: **cannot auto-fix** (MAX_WAIT value is domain-specific). Report with the bounded-wait pattern from `chorus-engine-yaml.md § Aggregate rule bounded-wait`.

### 3.13 — Duplicate `TERMINAL: solved`/`failed` — 🔴 CRITICAL

```
Pattern: more than one .yml file in the sandbox contains the literal
  `^TERMINAL: solved` or `^TERMINAL: failed` on its own line.
  (Only the pipeline's final aggregation agent may carry this key.)
```

```bash
grep -rl "^TERMINAL: solved$\|^TERMINAL: failed$" $SANDBOX/rules/*/*.yml
```

Finding: `🔴 DUPLICATE-TERMINAL — plusieurs règles TERMINAL: solved → pipeline s'arrête avant que tous les agents aient tourné`

If `--fix`: remove the `TERMINAL: solved`/`failed` line from every file except the legitimate final aggregation agent's rule. The surrounding rule content (BOARD phase-done flag, etc.) must be preserved.

### 3.14 — `FIND.attribut` slot-existence — 🟠 SIGNIFICANT

```
Pattern: a FIND.attribut value that is not `type_element`, not written by any
  rule's ACTION ($x->set('<attribut>', ...)), and not a literal key in any
  project JSON fixture in the sandbox.
```

```bash
grep -rhA1 "^FIND:" $SANDBOX/rules/*/*.yml | grep "attribut:" \
  | sed 's/.*attribut:\s*//' | sort -u > /tmp/find_attributs.txt
while read -r attr; do
  [ "$attr" = "type_element" ] && continue
  grep -rq "set('$attr'" "$SANDBOX/rules/"*/*.yml && continue
  grep -rlq "\"$attr\"" "$SANDBOX/"*.json "$SANDBOX/workspace/"*/*.json 2>/dev/null && continue
  echo "⚠️  FIND.attribut '$attr' — jamais écrit par une règle, jamais clé JSON projet"
done < /tmp/find_attributs.txt
```

Finding: `🟠 FIND-ATTRIBUT-DANGLING — FIND.attribut pointe un slot inconnu → règle dormante (zéro Frame candidate)`

If `--fix`: **cannot auto-fix** (requires domain knowledge to determine correct slot name). Report with candidate replacements from KB org Slot dictionary.

### 3.15 — BOARD-flag self-refiring rule — 🔴 CRITICAL

```
Pattern: a rule whose ACTION publishes a BOARD flag ($SELF->BOARD->{X} = ...)
  BUT whose EXCEPTION/CONDITION never guards on that same flag already being set
  (defined $SELF->BOARD->{X} absent from guards).
  → rule re-fires every engine cycle once its aggregation condition is met.
```

```bash
for f in $SANDBOX/rules/*/*.yml; do
  flag=$(grep -oP "BOARD->\{?\K\w+(?=\}?\s*=|'\s*,)" "$f" | head -1)
  [ -z "$flag" ] && continue
  grep -qE "EXCEPTION:.*defined \\\$SELF->BOARD->\{?$flag\}?|CONDITION:.*defined \\\$SELF->BOARD->\{?$flag\}?" "$f" \
    || echo "⚠️  $f — publie BOARD->{$flag} sans guard self sur ce flag"
done
```

Finding: `🔴 BOARD-SELF-REFIRING — règle BOARD sans guard idempotent → re-fire chaque cycle → CPU burn jusqu'à _MAX_CYCLES`

If `--fix`: add `defined $SELF->BOARD->{<flag>}` to the EXCEPTION as a short-circuit guard. Pattern: `EXCEPTION: "defined $SELF->BOARD->{<flag>} || (<original condition>)"`.

### 3.16 — Unguarded `_rule_trace` push on fmatch-based EXCEPTION — 🟡 MINOR

```
Pattern: ACTION pushes to _rule_trace (push @$trace, {...})
  AND EXCEPTION is an fmatch()-based aggregate check
  AND no `unless (grep { ... rule_id ... } @$trace)` guard wraps the push.
  → push fires every cycle → flooded _rule_trace array → inflated run-report JSON.
```

```bash
for f in $SANDBOX/rules/*/*.yml; do
  grep -q "push @\$trace" "$f" || continue
  grep -q "unless (grep" "$f" && continue
  exc=$(awk '/^EXCEPTION:/{flag=1} flag{print} /^ACTION:/{exit}' "$f")
  echo "$exc" | grep -q "fmatch" || continue
  echo "$exc" | grep -q "BOARD->{" && continue
  echo "🟡  $f — push _rule_trace non gardé sur EXCEPTION fmatch"
done
```

Finding: `🟡 UNGUARDED-TRACE-PUSH — _rule_trace push sans guard unless-grep → doublons massifs dans run-report JSON`

If `--fix`: wrap the push in `unless (grep { ($_->{rule_id} // '') eq '<rule-id>' } @$trace)`.

### 3.17 — `return 0` on `!@elements` fixpoint trap — 🔴 CRITICAL

```
Pattern: a bounded-wait aggregate rule (uses _decl_wait_cycles / MAX_WAIT_CYCLES)
  AND its !@elements branch uses `return 0`
  (correct for @pending, ALWAYS WRONG for !@elements — prevents fixpoint completion).
```

```bash
for f in $SANDBOX/rules/*/*.yml; do
  grep -q "MAX_WAIT_CYCLES\|_decl_wait_cycles" "$f" || continue
  perl -0777 -ne '
    if (/if\s*\(!\@elements\).*?return\s+0/s) { print "⚠️  FIXPOINT TRAP: '"$f"'\n" }
  ' "$f"
done
```

Finding: `🔴 FIXPOINT-TRAP-ELEMENTS — return 0 sur !@elements dans un aggregate borné → élément jamais traité si sous-éléments absents`

If `--fix`: remove the `return 0` branch inside `!@elements` — replace with immediate set of the aggregate slot using the domain's "not applicable" or zero-count variant. See `chorus-engine-yaml.md § Bounded-wait !@elements`.

### 3.18 — Multi-BOARD gate rule missing `CONDITION` — 🔴 CRITICAL

```
Pattern: a rule whose ACTION reads ≥ 2 distinct BOARD flags
  (BOARD->{flagA} && BOARD->{flagB}) but has NO `CONDITION:` line.
  → fires on first cycle before any upstream agent publishes those flags
  → gate slot set to 0/false permanently.
```

```bash
for f in $SANDBOX/rules/*/*.yml; do
  grep -qE "BOARD->\{[a-z_]+\}" "$f" || continue
  board_count=$(grep -oE "BOARD->\{[a-z_]+\}" "$f" | sort -u | wc -l)
  [ "$board_count" -lt 2 ] && continue
  grep -q "^CONDITION:" "$f" || echo "⚠️  $f — lit $board_count BOARD flags sans CONDITION gate"
done
```

Finding: `🔴 MULTI-BOARD-NO-CONDITION — gate multi-BOARD sans CONDITION → s'exécute cycle 1, verrouille le slot à 0 définitivement`

If `--fix`: add `CONDITION:` clause checking `defined $SELF->BOARD->{flagA} && defined $SELF->BOARD->{flagB}` for each flag read. See `chorus-engine-yaml.md § Multi-BOARD gate rule must have CONDITION`.

### 3.19 — `CONDITION`/`EXCEPTION` plain scalar tronqué (ENG-051) — 🔴 CRITICAL

```
Pattern: CONDITION: or EXCEPTION: value that starts with an unquoted,
  non-| token (e.g. `do {` without `|`) → YAML parser truncates the
  value at the first } at zero indent → Perl block incomplete →
  codeRule() returns undef → rule never fires.
```

```bash
grep -rnE "^(CONDITION|EXCEPTION): [^|'\"0-9]" $SANDBOX/rules/*/*.yml \
  | grep -vE ":(CONDITION|EXCEPTION): '.*'$"
```

Finding: `🔴 PLAIN-SCALAR-TRUNCATED — CONDITION/EXCEPTION sans | → bloc Perl tronqué → règle ne se déclenche jamais`

If `--fix`: prepend `|` to the CONDITION/EXCEPTION line and indent its body by 2 spaces. Auto-fixable for the `do {` pattern; other cases require manual review.

### 3.20 — Worst-verdict BOARD init `// 'CONFORME'` (ENG-053) — 🟠 SIGNIFICANT

```
Pattern: BOARD->{slot} // 'CONFORME' used in a worst-verdict comparison
  → when all verdicts are CONFORME the BOARD slot is never written
  → TERMINAL rule waits on that slot → pipeline TIMEOUT.
```

```bash
grep -rn "BOARD->{[a-z_]*} // 'CONFORME'\|BOARD->{[a-z_]*} // \"CONFORME\"" \
  $SANDBOX/rules/*/*.yml
```

Finding: `🟠 WORST-VERDICT-INIT — BOARD init via // 'CONFORME' bloque l'écriture → pipeline TIMEOUT sur projet 100% conforme`

If `--fix`: replace with the canonical `!defined $SELF->BOARD->{slot} || (prio{v} > prio{...})` pattern. See `chorus-engine-yaml.md § Pitfall — Worst-verdict BOARD` (ENG-053).

### 3.21 — Helper qualified-name collision (ENG-032) — 🔴 CRITICAL

```
Pattern: two or more Helpers.pm files across different agents define a sub
  with the same name. Chorus::Engine uses a single shared typeglob namespace
  → second agent's build() silently overwrites the first's closure.
```

```bash
for pm in $SANDBOX/lib/*/Agent/*/Helpers.pm $SANDBOX/lib/*/Agent/*/*/Helpers.pm 2>/dev/null; do
  slug=$(basename $(dirname "$pm"))
  grep -oP '^sub \K\w+' "$pm" | while read fn; do echo "$fn $slug $pm"; done
done | sort > /tmp/helper-names.txt
awk '{print $1}' /tmp/helper-names.txt | sort | uniq -d | while read dup; do
  echo "🔴 HELPER-COLLISION '$dup':"
  grep "^$dup " /tmp/helper-names.txt | awk '{print "    " $2 " → " $3}'
done
```

Finding: `🔴 HELPER-COLLISION — même nom de Helper dans ≥ 2 agents → écrasement silencieux → verdicts incorrects`

If `--fix`: rename to `<slug>_<name>` in the Helpers.pm declaration **and** typeglob line, and update every YAML ACTION calling it. See ENG-032.

### 3.22 — `use utf8;` manquant dans Helpers.pm (ENG-052) — 🟠 SIGNIFICANT

```
Pattern: a Helpers.pm contains non-ASCII characters (accented French)
  but does not declare `use utf8;`.
  → Perl stores literals as byte strings while YAML rules produce Unicode strings
  → eq comparisons silently fail → Helper returns undef → _a_confirmer verdicts.
```

```bash
for pm in $SANDBOX/lib/*/Agent/*/Helpers.pm \
          $SANDBOX/lib/*/Agent/*/*/Helpers.pm 2>/dev/null; do
  [ -f "$pm" ] || continue
  grep -qP '[^\x00-\x7F]' "$pm" || continue
  grep -q "^use utf8" "$pm" || \
    echo "🟠 USE-UTF8-MISSING: $pm — chaînes non-ASCII sans 'use utf8;'"
done
```

Finding: `🟠 USE-UTF8-MISSING — Helpers.pm non-ASCII sans use utf8 → comparaisons eq silencieusement fausses (ENG-052)`

If `--fix`: add `use utf8;` immediately after `use warnings;` in the Helpers.pm. Run `perl -c` to confirm syntax.

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
