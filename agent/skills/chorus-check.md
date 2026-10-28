# Skill — chorus-check

> Trigger: `chorus-check <sandbox-name> <fichier-project> [--all] [--explain] [--summary] [--lang <fr|en>]`
> Trigger: `chorus-check <sandbox-name> --from-report <run-report-path> [--explain] [--summary] [--lang <fr|en>]`
> Agent: `architect`
>
> `<sandbox-name>`: sandbox containing the KB and YAML rules (produced by `chorus-feed`)
> `<fichier-project>`: JSON file describing the project elements to validate,
>                      or data provided inline by the user
>                      (ignored when `--all` is present — all `project-*.json` are used)
> `--all`: run all `project-*.json` files found in `$SANDBOX/` and produce a synthesis report
> `--explain`: produce a human-readable, rule-by-rule explanation file for every
>              NON_CONFORME (and optionally `_a_confirmer`) element — see § Option
>              `--explain` below. Compatible with both single-file mode and `--all`
>              (one consolidated explanation file covering all runs in the latter case).
> `--summary`: produce a one-page, consultation-friendly synthesis document (headline
>              figures, substantive vs. mapping-anomaly breakdown, recommendation) — see
>              § Option `--summary` below. Can be combined with `--explain` (recommended)
>              or used standalone.
> `--lang <fr|en>`: force the language of `--explain`/`--summary` reports. Overrides
>                   auto-detection. Only affects report output — never the YAML rules,
>                   KB org files, or run.pl output (those follow the YAML language
>                   convention documented in `AGENTS.md`). See `## Phase L0` below.
> `--from-report <path>`: **pipeline-free mode** — skip Phases 0–6 entirely; read
>                         element data directly from an existing run-report JSON.
>                         `<path>` is relative to `$SANDBOX`
>                         (e.g. `workspace/eviden/reports/run-report-20261002-172839.json`).
>                         Must be combined with `--explain` and/or `--summary`.
>                         `<fichier-project>` must be **omitted** in this mode.
>                         → See `## Option --from-report` below.
>
> **Single responsibility: validate a project against the knowledge base.**
> The project file is **runtime input data** — it does not influence
> infrastructure generation. Two `chorus-check` runs on the same sandbox
> with different projects share exactly the same infrastructure.
>
> Prerequisite: `chorus-feed <sandbox-name>` must have been run beforehand
> (KB org + YAML present in the sandbox).

> 📋 **`agent/org/incidents-log.org`** — incident registry for Steps 5b–5l.
> Not loaded during normal execution (the operational rules — grep scans,
> WRONG/CORRECT examples, fix guidance — are self-contained in each Step).
> Read on demand when: (a) explaining to the user *why* a rule exists,
> (b) documenting a new incident after a debug session (add entry + one-line
> reference in the relevant Step), or (c) auditing rule-to-incident coverage.

> ⚠️ **`$WORKSPACE` / `$ENTITY` — mandatory convention, read before Step 0.**
> Every chorus-web–managed sandbox stores projects and reports per-entity:
> `$SANDBOX/workspace/<entity>/<projId>.json` (project input) and
> `$SANDBOX/workspace/<entity>/reports/` (run-report JSON **and** any
> `--explain`/`--summary` file — all three share the same directory, never
> the bare `workspace/` root). `<entity>` is the first path segment of
> `<fichier-project>` under `workspace/` — derive it **once**, at the very
> start of the run, from the resolved path of the project file actually
> being processed:
> ```
> $ENTITY    = <fichier-project> with "$SANDBOX/workspace/" stripped from the
>              front and everything from the next "/" onward stripped from
>              the back (e.g. "workspace/eviden/foo.json" → $ENTITY = "eviden")
> $WORKSPACE = $SANDBOX/workspace/$ENTITY/reports/
> ```
> In `--all` mode (Phase 6-all — batch run over `$SANDBOX/project-*.json`,
> synthetic/stress test projects at the sandbox root, not per-entity
> production projects), this `$ENTITY`/`$WORKSPACE` derivation does not apply
> the same way — see Phase 6-all for that mode's own (flat, root-level)
> conventions. The per-entity derivation above applies to the **normal**
> single-project invocation and to `--from-report`.
> In `--from-report` mode, derive `$ENTITY` the same way from the
> `<run-report-path>` argument itself (e.g.
> `workspace/eviden/reports/run-report-...json` → `$ENTITY = "eviden"`) — see
> Phase FR0, which must set `$ENTITY`/`$WORKSPACE` alongside `$RUN_TIMESTAMP`.
> A sandbox with no entity sub-folder at all (flat legacy layout, no
> `workspace/<entity>/` level) falls back to `$WORKSPACE = $SANDBOX/workspace/reports/`
> — never the bare `$SANDBOX/workspace/` root, and never `$SANDBOX/reports/`
> (legacy root location reserved for `run-report-*.json` produced by very old
> `run.pl` versions — never for `--explain`/`--summary` output).
>
> Every subsequent mention of `$WORKSPACE` in this document means exactly
> this per-entity `reports/` directory — not the bare `workspace/` root.


## 🔌 Preliminary — MCP mode detection

**Execute before Step 0, once per `chorus-check` invocation.**

Probe the MCP server by calling `chorus_engine_create` (ident: `"_probe"`):

- **Probe succeeds** → MCP mode active. Immediately call `chorus_reset` to
  discard the probe handle. Set `$MCP_AVAILABLE = true` for this run.
- **Probe fails / tool unavailable** → fallback mode. Set `$MCP_AVAILABLE = false`.

This probe is silent (no user message). The chosen mode is noted at the end
of Phase 6 in the report header.

> ⚠️ `$MCP_AVAILABLE` is a local decision variable for this skill run only.
> It does not affect Phases 0–5 (infrastructure generation) — those are
> identical in both modes.


## ⚡ Step 0 — Infrastructure detection (PRIORITY, before any loading)

**This is the first action to execute, without exception.**

Read the directory tree `$SANDBOX` (max_depth=3) and verify:

```
$SANDBOX/run.pl
$SANDBOX/lib/<Namespace>/Feed.pm
$SANDBOX/lib/<Namespace>/Expert.pm
$SANDBOX/lib/<Namespace>/Agent/<Nom>.pm  ← au moins un
```

### ✅ Infrastructure present → hash check

Compare the current KB hash against the stored one:

```bash
sha256sum $SANDBOX/agent/chorus/*.org > /tmp/kb-hash-current
```

- `$SANDBOX/agent/.kb-hash` **absent** → predates hash tracking → **FULL PATH**
- `$SANDBOX/agent/.kb-hash` matches AND `$SANDBOX/agent/.template-hash` matches
  → **FAST PATH**: go directly to Phase 6. Do not load `chorus-engine.md`,
  do not read `index.org`, do not read agent KBs, do not generate anything.
- `$SANDBOX/agent/.kb-hash` **differs** → KB enriched → **FULL PATH** (silent, no prompt)
- `$SANDBOX/agent/.kb-hash` **matches** but `.template-hash` **absent or differs**
  → template updated since last generation → **FULL PATH** with user notification
  (see Phase 5.5 § Template staleness display — unlike KB changes, template changes
  are external and must be surfaced to the user before overwriting artefacts)
- `.kb-hash` absent → predates hash tracking → **FULL PATH** regardless of template hash

> **Manual forced regeneration**: the user explicitly asks to
> "regenerate" / "rebuild" the infrastructure → FULL PATH regardless of the hash.
> A second `chorus-check` with a different project is **never** a
> forced regeneration (hash comparison handles it automatically).

### ❌ Infrastructure absent or incomplete → FULL PATH

Load:
- `chorus-engine-infra.md` — Perl infrastructure reference (Core Mechanisms, Multi-Specialty Pattern, checklists)
- `chorus-templates.md` — Perl infrastructure templates (T1–T5)
- `$SANDBOX/agent/chorus/index.org` — pipeline, agents, namespace

> ⚠️ Do not read agent KBs (`<slug>.org`) or YAML files at this stage.
> They are only needed during generation (infrastructure absent).

Then execute Phases 0, 1–5, 5.6, 6, 7 in order.
(Phase 5 includes Steps 5b–5l; Steps 5k and 5l are new — mandatory for pipelines
with bounded-wait aggregate rules and/or multi-BOARD gate rules.)


## Phase 0 — KB prerequisite check *(full path only)*

```
$SANDBOX/agent/chorus/index.org     ← must exist
$SANDBOX/agent/chorus/<slug>.org    ← at least one agent
$SANDBOX/rules/<slug>/            ← at least one YAML file per agent
```

If any of these is missing → stop and report:
`"KB incomplete — run chorus-feed <sandbox-name> <corpus> first."`

Extract from `index.org`:
- The Perl namespace of the project
- The ordered list of agents (pos, slug, Perl module)
- The termination agent (last)


## Phase 1 — Analyse the project file

### 1.1 Expected format

```json
{
  "project": "<nom>",
  "elements": [
    {
      "id": "<identifiant unique>",
      "type": "<element type>",
      "<slot1>": <valeur1>,
      "<slot2>": <valeur2>
    }
  ]
}
```

If the project file is provided **inline** (data pasted in the message) →
write it to `$SANDBOX/project.json` before continuing.

### 1.2 Deduce input-required slots

For each element type present in the project file, the input-required slots
(those that must be present in the project JSON at load time) are determined
by **Phase 1.5** (YAML slot analysis) — not by reading the KB org.
Phase 1.5 produces `computed_slots` (slots written by rules) from which
`input_slots = all_known_slots − computed_slots` is derived mechanically.
The result feeds directly into `%SLOTS_REQUIS` in Phase 2.

### 1.3 Identify the targeting slot for agent 1

Read the `Slots de ciblage` section of the KB for the agent at position 1.
This slot must be present on all Frames created by the Feed.


## Phase 1.5 — YAML slot analysis *(full path only)*

> **Purpose:** determine mechanically, from the YAML rule files themselves,
> which slots are *written* by rules (`computed_slots`) and which must be
> *provided* in the project JSON (`input_slots`).
> This is the authoritative source for `%SLOTS_REQUIS` in Phase 2.
> It also detects mismatched `EXCEPTION` guards automatically.

### Step 1 — Scan all YAML files

For each agent in the pipeline (from `index.org`), read every `.yml` file
in `$SANDBOX/rules/<slug>/`.

### Step 2 — Extract per-rule metadata

For each `.yml` file, extract:

**a) Targeted `type_element` values** — from the `FIND`/`CHERCHER` block:
```
filtre: "$_->{type_element} eq 'X'"          → targets: ['X']
filtre: "... eq 'X' || ... eq 'Y'"           → targets: ['X', 'Y']
filtre: "defined $_->{type_element}"         → targets: ALL
(no filtre, attribut: type_element)          → targets: ALL
```

**b) Written slots** — all `$f->set('slot', ...)` calls in the `ACTION`/`EFFET` block:
```
regex: \$\w+->set\(\s*['"](\w+)['"]
```

**c) Guard slot** — the slot tested in `EXCEPTION: "defined $f->{X}"`:
```
regex: EXCEPTION:\s+"defined \$\w+->\{(\w+)\}"
```

### Step 3 — Build `computed_slots`

```
computed_slots = {}   # { type_element → Set(slot_name) }

For each rule:
  for each targeted type_element T (or ALL known types if universal):
    computed_slots[T] += written_slots_of_this_rule
```

### Step 4 — Derive `input_slots`

```
For each known type_element T:
  input_slots[T] = { type_element }   # targeting slot always required
  # Add any slot that appears in FIND filtre expressions (read, never written)
  # AND is not in computed_slots[T]:
  + { s | s appears in filtre of any rule targeting T
          AND s ∉ computed_slots[T] }
```

> In a sandbox where all non-`type_element` slots are rule-computed,
> `input_slots[T] = { type_element }` for every type T.

### Step 5 — Guard coherence check

> **⚠️ This step is now handled automatically by `Chorus::Engine::loadRules()`.**
> At every `perl run.pl` execution, `loadRules()` emits a `warn` for any rule whose
> `EXCEPTION: "defined $f->{X}"` guard slot is not among the slots written by that
> rule's ACTION (`$f->set('X', ...)`).  No LLM action needed here — the engine
> provides immediate feedback before Phase 1.5 is ever invoked.
>
> Phase 1.5 does **not** need to perform this check.

### Step 5b — `$agent` misuse scan (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** `$agent` is a valid identifier in a
> pure-Perl `addrule()` closure (`Agent/<Nom>.pm`) but is **always out of scope**
> inside a `.yml` rule's `ACTION`/`EFFET`/`EXCEPTION` block (those are `eval`'d
> inside `Chorus::Engine` — only `$SELF` is bound there). This mistake does **not**
> surface as an immediate, obvious crash at `loadRules()` time — the die/crash only
> fires the first time the offending ACTION actually executes (e.g. a BOARD-publishing
> terminal rule reached late in a run), which can be deep into a `--batch`/`--all`
> smoke test on an unrelated project file. Treat it with the same mechanical rigor
> as the `*_ref` field-naming check (§ above), not as something a sub-agent might
> happen to notice while reading code.

Run, for every agent's rules directory, before writing any infrastructure file:

```bash
grep -rn '\$agent->' $SANDBOX/rules/
```

- **No matches** → proceed to Phase 2.
- **Matches found** → every one of them is a bug in the YAML KB (not a template/
  infrastructure issue) — fix each occurrence in place, replacing `$agent->` with
  `$SELF->` (identical semantics: `$SELF->BOARD` and `$agent->BOARD` are the same
  Frame instance inside a rule's own ACTION). Do this **before** generating any
  `.pm`/`run.pl` file — a smoke test run against a KB still carrying this bug will
  either crash on the first BOARD-publishing rule reached, or silently skip the
  BOARD write (depending on where in the ACTION body the crash occurs relative to
  prior statements), producing a confusing downstream symptom (e.g. an empty
  `applicable_codes_set` read by a later agent) instead of a clear error at the
  source.
- After fixing, re-run the grep to confirm zero remaining matches, then regenerate
  `agent/.kb-hash` (the YAML content changed) before proceeding to Phase 2.

> **Incident:** `agent/org/incidents-log.org § build-en-01`

### Step 5c — `_rule_trace` / `non_conformity_motif` coverage scan (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** both mechanisms degrade **100%
> silently** by design (no error, no warning, no JSON key, nothing printed —
> see `chorus-templates.md` § Traceability) — the exact property that makes
> `$agent->` misuse (Step 5b) dangerous also applies here, except there isn't
> even a crash to eventually surface the problem. A KB can reach SP1, pass
> `chorus-strengthen`, and run cleanly for the sandbox's entire lifetime
> without anyone noticing these fields are simply never written.

Run, for every agent's rules directory, before writing any infrastructure file:

```bash
# Rules that can write a failing verdict (grep for the "NO"/"NON" literal commonly
# used in a result slot) but never push to _rule_trace:
for f in $SANDBOX/rules/*/*.yml; do
  grep -qE "rule_trace" "$f" || echo "MISSING _rule_trace: $f"
done

# Rules whose ACTION sets a result slot to a failing value but never writes a
# non_conformity_motif / motif_non_conformite in the same file:
for f in $SANDBOX/rules/*/*.yml; do
  if grep -qE "set\('[a-z_]+_ok', 'NO'\)|set\(\"[a-z_]+_ok\", \"NO\"\)|'NON'" "$f"; then
    grep -qE "non_conformity_motif|motif_non_conformite" "$f" || echo "MISSING motif: $f"
  fi
done
```

(Adapt the grep patterns to the sandbox's actual verdict-slot naming convention —
`_ok`/`YES`/`NO` for an English corpus, `_conforme`/`OUI`/`NON` for a French one.
The exact regex matters less than the principle: **every rule file that can
produce a failing verdict must also appear in both scans' "no match" case.**)

- **No matches (all rules covered)** → proceed to Phase 2.
- **Matches found** → for each flagged file:
  - Missing `_rule_trace`: add the mandatory push block at the top of `ACTION`
    (see `chorus-engine-yaml.md` checklist for the exact snippet).
  - Missing `non_conformity_motif`: add an explicit, rule-authored motif in each
    failing branch (one motif per distinct failure cause — never a single generic
    motif covering several branches), guarded by `unless $f->get('non_conformity_motif')`.
  - Fix in place, do **not** defer to a later `chorus-strengthen`/`chorus-review-kb`
    pass — those tools check KB *correctness*, not *traceability completeness*,
    and will not catch this.
- After fixing, re-run both scans to confirm zero remaining matches, then
  regenerate `agent/.kb-hash` before proceeding to Phase 2.
- **Also verify `run.pl`'s own JSON-report block** (not just the `.yml` rules)
  actually reads `_rule_trace` back off the element and includes a
  `generic_motif_from_trace()` fallback (see `chorus-templates.md` T5) — a KB
  that correctly pushes `_rule_trace` is still silently useless downstream if
  the hand-written/previously-generated `run.pl` never reads it back into the
  JSON report.

> **Incident:** `agent/org/incidents-log.org § build-en-02`

### Step 5d — Cross-agent targeting-slot wiring scan (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** same silent-degradation class as
> Step 5b/5c, but at the level of whole-pipeline convergence rather than a
> single rule or report column. A `CONDITION`/`EXCEPTION` referencing a
> cross-agent targeting slot via `$e->{slot}` (Frame-local read) when the
> publishing agent only ever writes that slot on BOARD (or on a *different*
> Frame type) produces **zero errors anywhere** — no `loadRules()` warning (the
> guard slot *is* written by *some* rule, just never read where expected),
> no crash, no JSON report anomaly. The only symptom is that the final
> aggregation agent never reaches `$SELF->solved()`/`failed()`, and
> `Chorus::Expert::process()`'s outer loop silently runs until `_MAX_ITER`
> (default 50,000 — potentially over an hour) before giving up with a single
> generic `warn`. See `chorus-feed.md` § "Mandatory check before authoring any
> CONDITION/EXCEPTION on a cross-agent targeting slot" and
> `chorus-engine-yaml.md` § "INPUTS header convention for Frame-linked slots"
> for the authoring-time safeguard this check backstops mechanically.

Run, for every targeting slot name that appears in more than one agent's
rules directory (cross-agent candidate):

```bash
# 1. Identify candidate cross-agent targeting slots: any slot name read via
#    $var->{slot} in a CONDITION/EXCEPTION, appearing in ≥ 2 different
#    agents' rules/ subdirectories.
grep -rhoE "(CONDITION|EXCEPTION):.*\\\$\w+->\{(\w+)\}" $SANDBOX/rules/*/*.yml \
  | grep -oE '\{(\w+)\}' | tr -d '{}' | sort | uniq -c | sort -rn

# 2. For each candidate slot <S> appearing in N > 1 agents, check how it is
#    actually published — Frame-local (via $w->set('<S>', ...) in a rule
#    whose FIND targets the SAME type_element pattern as the consuming
#    rules) or BOARD-only (via $SELF->BOARD->{<S>} = ... / ->set('<S>', ...)):
grep -rn "set('<S>'" $SANDBOX/rules/*/*.yml          # Frame-local writers
grep -rn "BOARD->{<S>}\|BOARD->set('<S>'" $SANDBOX/rules/*/*.yml   # BOARD writers
```

- **Slot is written on BOARD only, but read via `$e->{slot}`/`$w->{slot}`/`$c->{slot}`
  anywhere** → this is the exact bug class from the `05-CC-3.1.4` incident
  (see `chorus-engine-yaml.md` for the full writeup). Fix every offending
  `CONDITION`/`EXCEPTION` to read `$SELF->BOARD->{slot}` instead. Do this
  **before** generating any infrastructure file.
- **Slot is written Frame-local on a Frame type that never matches the
  `FIND`/`filtre` of the rule reading it** (e.g. written only on `ST`/`PP`/`TOE`,
  read on `FAU_*`) → same bug class, opposite direction: either add an
  explicit propagation rule (documented in both agents' KB org) that copies
  the value onto the consuming Frame type, or — the far more common correct
  fix — promote the slot to BOARD at the publishing rule (`$SELF->BOARD->{slot}
  = 1` in addition to, or instead of, the Frame-local copy) and update every
  consuming `CONDITION`/`EXCEPTION` accordingly.
- **No cross-agent slot found in this state** → proceed to Phase 2.

> **Incident:** `agent/org/incidents-log.org § cc314-01`

### Step 5e — Unbounded "expected children" aggregate scan (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** an aggregate rule waiting on a
> list of expected sibling Frame ids (`elements`/`composants_requis`/similar,
> computed by an earlier levelling/catalog rule) that `return 0`s forever
> whenever an expected id has no matching Frame degrades identically to the
> BOARD-wiring bug above: no error, no warning, just permanent
> `(unprocessed)` on the parent Frame — invisible until someone runs the
> pipeline against a project that does not supply every single expected
> child (which any minimal/smoke-test project legitimately does not). See
> the full pattern + fix template in `chorus-engine-yaml.md` § "Aggregate
> rule waiting on an 'expected children' list".

Run, for every agent's rules directory, before writing any infrastructure file:

```bash
# Find ACTION blocks that resolve an expected-id list against fmatch() and
# `return 0` without ever bounding the wait (no retry counter, no `missing`
# bucket distinct from `pending`).
grep -rlP 'split\(/,/.*elements.*\n' $SANDBOX/rules/*/*.yml 2>/dev/null \
  | xargs -I{} sh -c 'grep -q "_decl_wait_cycles\|MAX_WAIT" {} || echo {}'
```

- **No matches** → proceed to Phase 2.
- **Matches found** → each one is a candidate unbounded aggregate wait. Open it,
  confirm it matches the pattern (splits a comma-joined expected-id slot,
  resolves each via `fmatch`, `return 0` if any lookup misses), and apply the
  bounded-wait fix from `chorus-engine-yaml.md` — a `_decl_wait_cycles` counter
  per Frame, falling through to an explicit `non_conformity_motif` + a
  non-blocking verdict after `MAX_WAIT_CYCLES` (5 is a reasonable default)
  cycles still missing the same expected id(s). Do this **before** generating
  any infrastructure file — regenerate `agent/.kb-hash` afterward (the YAML
  content changed).

> **Incident:** `agent/org/incidents-log.org § cc314-02`

### Step 5f — Duplicate `TERMINAL: solved`/`failed` scan across agents (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** `TERMINAL: solved`/`failed` writes
> a single pipeline-wide `BOARD->{SOLVED}`/`BOARD->{FAILED}` flag, not an
> agent-local one. `Chorus::Expert::process()`'s outer loop stops the instant
> this flag is set — every agent registered after the one whose rule fired
> **never runs at all**, silently (no crash, `perl run.pl` produces a seemingly
> normal report with most Frames `(unprocessed)`). This degrades identically
> to the BOARD-wiring (Step 5d) and unbounded-aggregate (Step 5e) bugs above:
> zero error surface, only visible as missing downstream results. See the full
> pattern + fix in `chorus-feed.md` § "Multi-agent pipelines — TERMINAL: solved
> must appear EXACTLY ONCE".

Run, across the entire sandbox's rules directory, before writing any
infrastructure file:

```bash
grep -rl "^TERMINAL: solved$\|^TERMINAL: failed$" $SANDBOX/rules/*/*.yml
```

- **Exactly one matching file, and it belongs to the pipeline's own final
  aggregation agent** (the agent occupying the last `#+PIPELINE_POS` in
  `index.org`, whose rule reads every upstream BOARD phase-done flag before
  concluding) → proceed to Phase 2.
- **Zero matches** → the pipeline has no explicit termination rule at all;
  confirm this is intentional (e.g. termination handled via `$SELF->solved()`
  called directly in some agent's `ACTION` instead of via the `TERMINAL:` key
  — search for `->solved()`/`->failed()` as well) before proceeding.
- **More than one matching file** → every file beyond the legitimate final
  aggregator's own rule is a bug. For each one: remove the `TERMINAL: solved`/
  `failed` line entirely (keep the rest of the rule — it almost always also
  publishes a legitimate per-agent BOARD phase-done flag, which must remain).
  Do this **before** generating any infrastructure file — regenerate
  `agent/.kb-hash` afterward (the YAML content changed).

> **Incident:** `agent/org/incidents-log.org § cc314-03`

### Step 5g — Unfiltered `fmatch` in `EXCEPTION`/`CONDITION` scan (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** an `EXCEPTION`/`CONDITION` that
> calls `Chorus::Frame::fmatch(slot => 'type_element')` (or any similarly
> broad slot) without first narrowing the result to the agent's own Frame
> family tests a domain slot against **every** Frame in the project — Frames
> of unrelated types will essentially never carry that slot, so the guard
> reads as permanently true (or permanently false, depending on polarity),
> silently blocking the rule on every cycle. No crash, no warning — the rule
> simply never fires, and whatever it was supposed to publish (a BOARD
> phase-done flag, most commonly) never happens.

Run, for every agent's rules directory, before writing any infrastructure file:

```bash
# Find EXCEPTION/CONDITION lines calling fmatch() without an immediately
# preceding `grep { $_->{type_element} =~ ... }` (or equivalent family
# filter) between the fmatch() call and the outer grep that tests the
# domain slot.
grep -rnE "(EXCEPTION|CONDITION):.*fmatch\(" $SANDBOX/rules/*/*.yml \
  | grep -v "grep[^)]*type_element"
```

- **No matches** → every `fmatch` call in a guard already filters by Frame
  family before testing a domain slot → proceed to Phase 2.
- **Matches found** → open each one and confirm whether the missing filter
  is a genuine bug (the intent was clearly to scope to this agent's own
  Frame family, matching its own `FIND.filtre`) or a deliberate
  pipeline-wide check (rare — e.g. a true cross-agent gate reading a BOARD
  slot instead, which does not need Frame filtering at all since BOARD is
  not Frame-scoped). For the former, add the same family filter already used
  by the agent's own `FIND` clause, as a `grep { $_->{type_element} =~ /.../ }`
  immediately wrapping the `fmatch()` result before the slot-presence test.

> **Incident:** `agent/org/incidents-log.org § cc314-04`

### Step 5h — `FIND.attribut` slot-existence cross-check (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** a `FIND.attribut:` naming a slot
> that no project Frame ever carries makes the rule permanently dormant —
> zero candidate Frames, `_APPLY` never runs, no error, no warning. This is
> structurally identical to the canonical `type_element` vs `element_type`
> mismatch pitfall already documented (Phase 1.2 ⛔ note) but can happen on
> **any** targeting slot, not just `type_element` — any rule whose `FIND`
> targets a derived/internal slot name that drifted from what upstream rules
> or project data actually produce.

Run, for every agent's rules directory, before writing any infrastructure file:

```bash
# Collect every FIND.attribut value used across the sandbox…
grep -rhA1 "^FIND:" $SANDBOX/rules/*/*.yml | grep "attribut:" | sed 's/.*attribut:\s*//' | sort -u > /tmp/find_attributs.txt

# …then for each one, confirm it is either:
#  (a) 'type_element' (always valid — the canonical targeting slot), or
#  (b) written by at least one rule's ACTION somewhere in the sandbox
#      ($x->set('<attribut>', ...)), or
#  (c) present as a literal key in at least one project JSON fixture
#      (grep -l "\"<attribut>\"" $SANDBOX/*.json $SANDBOX/workspace/*/*.json)
# A FIND.attribut satisfying none of (a)/(b)/(c) is a strong signal of a
# dangling/renamed slot reference — investigate before proceeding.
while read -r attr; do
  [ "$attr" = "type_element" ] && continue
  if ! grep -rq "set('$attr'" "$SANDBOX/rules/"*/*.yml \
     && ! grep -rlq "\"$attr\"" "$SANDBOX/"*.json "$SANDBOX/workspace/"*/*.json 2>/dev/null; then
    echo "⚠️  FIND.attribut '$attr' — never written by any rule, never a literal project JSON key"
  fi
done < /tmp/find_attributs.txt
```

- **No warnings printed** → every non-`type_element` `FIND.attribut` is
  traceable to either a rule's own `ACTION` or a project data key → proceed
  to Phase 2.
- **Warnings printed** → for each flagged attribut, open the rule(s) using it
  and confirm against the sandbox's own domain model (KB org Slot dictionary,
  or the corpus itself) whether the name is simply not yet produced in the
  project fixtures used for this scan (acceptable — document and move on) or
  a genuine typo/drift from the real slot name (fix the `FIND.attribut`
  value).

> **Incident:** `agent/org/incidents-log.org § cc314-05`

### Step 5i — BOARD-flag self-refiring rule scan (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** a rule whose `ACTION` publishes
> a BOARD flag (`$SELF->BOARD->{<flag>} = ...` or `$SELF->BOARD->set('<flag>',
> ...)`) but whose `EXCEPTION`/`CONDITION` guard tests only the *original*
> aggregation condition (e.g. "no pending Frame remains") — never whether the
> flag has *already* been published — degrades identically to the other
> silent classes above: no crash, no warning, `loadRules()` sees nothing wrong
> (the flag genuinely is written). The only symptom is that once the
> aggregation condition becomes permanently true, the `ACTION` **re-fires on
> every single engine cycle, forever**, burning CPU/memory until `_MAX_CYCLES`
> (default 10000) is reached — once per such rule, which multiplies badly
> across a multi-agent pipeline (e.g. 19 agents × 10000 wasted cycles ≈ 13+
> minutes observed, see incident below). This is distinct from Step 5f
> (duplicate `TERMINAL: solved`/`failed`) — these rules rarely carry the
> literal `TERMINAL:` key at all (they are pure BOARD-publishing rules calling
> `solved()`/`failed()` indirectly, or not at all), so Step 5f's grep does not
> catch them.

Run, for every agent's rules directory, before writing any infrastructure file:

```bash
# Find rules whose ACTION writes a BOARD flag but whose EXCEPTION/CONDITION
# does not guard on that same flag already being set.
for f in $SANDBOX/rules/*/*.yml; do
  flag=$(grep -oP "BOARD->\{?\K\w+(?=\}?\s*=|'\s*,)" "$f" | head -1)
  [ -z "$flag" ] && continue
  grep -qE "EXCEPTION:.*defined \\\$SELF->BOARD->\{?$flag\}?|CONDITION:.*defined \\\$SELF->BOARD->\{?$flag\}?" "$f" \
    || echo "⚠️  $f — publishes BOARD flag '$flag' but EXCEPTION/CONDITION never guards on it"
done
```

- **No warnings printed** → every BOARD-publishing rule already guards against
  re-firing once its own flag is set → proceed to Phase 2.
- **Warnings printed** → for each flagged rule, add `defined $SELF->BOARD->{<flag>}
  || (<original aggregation condition>)` to the `EXCEPTION` (or the inverse
  polarity for `CONDITION`), so the rule becomes permanently inert once it has
  published its flag once. Do this **before** generating any infrastructure
  file — regenerate `agent/.kb-hash` afterward (the YAML content changed).
- Re-run the scan after fixing to confirm zero remaining matches.

> **Incident:** `agent/org/incidents-log.org § cc314-06`

### Step 5j — Unguarded `_rule_trace` push on a non-self-terminating rule (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** a rule whose `ACTION` pushes to
> `_rule_trace` but whose `EXCEPTION`/`CONDITION` guard is based purely on an
> external/global state check (e.g. "has every Frame in the project reached
> a final verdict?") — rather than on whether *this rule itself* has
> already fired for *this Frame* — re-fires on every single engine cycle for
> as long as that external condition remains false. This is a distinct bug
> class from Step 5i (BOARD self-refiring): the engine-level consequence is
> different (no hang, no wasted CPU cycles beyond the rule's own trivial
> push — `_MAX_CYCLES` is reached exactly as fast either way) but the
> **downstream consequence is a flooded `_rule_trace` array**: hundreds of
> duplicate entries for the same `rule_id` on a single Frame, inflating the
> run-report JSON file size by orders of magnitude (observed: ~8MB → ~1MB
> after fix, on a single Frame's trace shrinking from ~195 duplicate entries
> to 1) and rendering any UI panel that displays the rule-chain column
> unusable ("completely polluted by empty-looking rows ending in
> `termination → termination → ...`").
>
> This typically affects a pipeline's own **termination rule** (the
> `TERMINAL: solved`/`$SELF->solved()` rule, or an earlier per-agent
> "global convergence check" rule like `toe-structure`'s own
> `R09-termination.yml`) — any rule whose `EXCEPTION` is a pure
> `fmatch(...)`-based aggregate test over *other* Frames, without a
> `unless (grep { ... } @$trace)` (or equivalent) guard on its own push.

Run, for every agent's rules directory, before writing any infrastructure file:

```bash
# Find ACTION blocks that push unconditionally to _rule_trace (no "unless
# (grep ..." guard immediately around the push) while their own EXCEPTION
# contains an unguarded fmatch() aggregate check (not a BOARD flag
# short-circuit, already covered by Step 5i; not a Pattern-1
# "defined $x->{own_slot}" guard, which already prevents re-firing once the
# slot is first written).
for f in $SANDBOX/rules/*/*.yml; do
  grep -q "push @\$trace" "$f" || continue
  grep -q "unless (grep" "$f" && continue   # already guarded — skip
  exc=$(awk '/^EXCEPTION:/{flag=1} flag{print} /^ACTION:/{exit}' "$f")
  echo "$exc" | grep -q "fmatch" || continue   # not an fmatch-based guard — skip
  echo "$exc" | grep -q "BOARD->{" && continue   # already covered by Step 5i — skip
  echo "⚠️  $f — unguarded _rule_trace push with an fmatch-based EXCEPTION"
done
```

- **No warnings printed** → every `_rule_trace` push on an fmatch-guarded
  rule is already protected against duplication → proceed to Phase 2.
- **Warnings printed** → for each flagged rule, wrap the push in a guard
  that checks whether this `rule_id` already appears in the Frame's own
  `_rule_trace` before pushing again:
  ```perl
  my $trace = $dummy->{_rule_trace} // [];
  unless (grep { ($_->{rule_id} // '') eq '<rule-id>' } @$trace) {
    push @$trace, { rule_id => '<rule-id>', corpus_ref => '<corpus_ref>' };
    $dummy->{_rule_trace} = $trace;
  }
  1
  ```
  Do this **before** generating any infrastructure file — regenerate
  `agent/.kb-hash` afterward (the YAML content changed).
- Re-run the scan after fixing to confirm zero remaining matches.

> **Incident:** `agent/org/incidents-log.org § cc314-07`

### Step 5k — `return 0` on `!@elements` in bounded-wait aggregate scan (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** an aggregate rule that applies a
> bounded wait (`_decl_wait_cycles / MAX_WAIT_CYCLES`) to the "no sub-elements
> found" case will **never complete** in a pipeline that includes a TERMINAL rule
> (one that calls `solved()` or `failed()` early). The engine's inner loop stops
> at fixpoint — as soon as every rule returns 0 in a cycle. `return 0` on
> `!@elements` IS the only action in that cycle → fixpoint declared after 1 cycle
> → `_decl_wait_cycles` never reaches `MAX_WAIT_CYCLES` → aggregate slot never
> set → element permanently `(unprocessed)`. Invisible in long-running sessions
> (`pipeline_solved=false`, engine runs all `_MAX_CYCLES` cycles); surfaces only
> when a TERMINAL shortcut fires. Distinct from Step 5e (unbounded aggregate wait
> forever) — here the wait IS bounded, but `return 0` makes bounding ineffective.

Run, for every agent's rules directory:

```bash
# Find aggregate rules that apply a bounded-wait (MAX_WAIT_CYCLES / _decl_wait_cycles)
# AND use return 0 in the !@elements branch (no sub-elements found at all).
# Signature: the pattern "if (!@elements)" followed by a return 0 somewhere
# inside that block — distinct from the @pending branch which correctly uses return 0.
for f in $SANDBOX/rules/*/*.yml; do
  grep -q "MAX_WAIT_CYCLES\|_decl_wait_cycles" "$f" || continue
  # Look for the !@elements return 0 pattern (as opposed to @pending return 0)
  perl -0777 -ne '
    if (/if\s*\(!\@elements\).*?return\s+0/s) {
      print "⚠️  FIXPOINT TRAP (!@elements + return 0): '"$f"'\n"
    }
  ' "$f"
done
```

- **No matches** → bounded-wait aggregate rules do not trap fixpoint on empty sub-element lists → proceed.
- **Matches found** → for each flagged rule: **remove the `return 0` branch inside `!@elements`** — replace with an immediate set of the aggregate slot (see `chorus-engine-yaml.md § Bounded-wait !@elements — fixpoint trap` for the correct pattern). The `return 0` / `_decl_wait_cycles` wait is only correct for the `@pending` branch (sub-elements exist but are not yet scored); it is always wrong for `!@elements` (sub-elements will never arrive).
- After fixing, regenerate `agent/.kb-hash` before proceeding to Phase 2.

> **Incident:** `agent/org/incidents-log.org § cc314-08`

### Step 5l — Multi-BOARD gate rule missing `CONDITION` scan (mandatory, before Phase 2)

> ⚠️ **Why this is mandatory, not optional:** a rule that reads N BOARD flags to
> compute a downstream gate slot (e.g. `pipeline_complete_ok`) but has **no
> `CONDITION`** fires on the **first engine cycle** — before any upstream agent
> has published those flags. It evaluates all flags as `undef`, sets the gate
> slot to `0`/`false`, and is **permanently blocked** by Pattern 1
> (`EXCEPTION: defined $w->{gate_slot}`). Downstream rules gating on
> `gate_slot=1` (e.g. via `FIND: { attribut: gate_slot, filtre: 'defined... &&
> ...' }` or `CONDITION: $w->get('gate_slot')`) never fire. The entire
> downstream chain is silently dead for the pipeline lifetime — no error,
> no warning, just missing results.

Run, for every agent's rules directory:

```bash
# Find rules whose ACTION reads multiple BOARD flags (BOARD->{X} && BOARD->{Y})
# but whose YAML block has no CONDITION: line at all.
for f in $SANDBOX/rules/*/*.yml; do
  grep -qE "BOARD->\{[a-z_]+\}" "$f" || continue   # rule reads a BOARD flag
  # Count distinct BOARD reads in ACTION
  board_count=$(grep -oE "BOARD->\{[a-z_]+\}" "$f" | sort -u | wc -l)
  [ "$board_count" -lt 2 ] && continue   # single BOARD read — not a multi-flag gate
  # Check for CONDITION: line in the same YAML block
  grep -q "^CONDITION:" "$f" || echo "⚠️  $f — reads $board_count BOARD flags but has no CONDITION gate"
done
```

- **No matches** → all multi-BOARD-flag readers have a `CONDITION` → proceed.
- **Matches found** → for each flagged rule: add a `CONDITION:` clause checking
  `defined $SELF->BOARD->{flagA} && defined $SELF->BOARD->{flagB} ...` for each
  flag the ACTION reads (see `chorus-engine-yaml.md § Multi-BOARD gate rule must
  have CONDITION` for the correct pattern). Do this **before** generating any
  infrastructure file.

> **Incident:** `agent/org/incidents-log.org § cc314-09`

### Step 6 — Output

Produce a structured slot map (used by Phase 2):

```
YAML Slot Analysis — <sandbox-name>
─────────────────────────────────────────────────────────
type_element                   │ input_slots    │ computed_slots (written by)
───────────────────────────────┼────────────────┼──────────────────────────────
reproduction_right             │ type_element   │ titulaire (R01), article_source (R01), …
temporary_reproduction         │ type_element   │ article_source (R04), mandatory (R04), …
…
─────────────────────────────────────────────────────────
```

Guard mismatches, if any, will have already been reported to STDERR by
`Chorus::Engine::loadRules()` during the previous pipeline run.
Do not duplicate that check here — proceed to Phase 2.

---

## ⚠️ Language Rule — All Generated Perl Files

> All **comments** in every generated Perl file (`Feed.pm`, `Agent/<Nom>.pm`, `Expert.pm`, `run.pl`)
> must be written in the **corpus language** — read from `#+CORPUS_LANG` in `index.org`
> (or inferred from the KB org content if the property is absent).
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

---

## Phase 2 — Generate `Feed.pm`

Create `$SANDBOX/lib/<Namespace>/Feed.pm` from template **T1** (`chorus-templates.md`).

**Substitutions from the KBs:**
- `%SLOTS_REQUIS` ← use **`input_slots`** from **Phase 1.5** (YAML slot analysis).
  Phase 1.5 already computed, for each `type_element`, the exact set of slots that
  must come from the project JSON (never written by any rule).

  ```
  For each type_element T in input_slots:
    %SLOTS_REQUIS{T} = [ sort keys %{ input_slots{T} } ]
  ```

  > In a sandbox where all non-`type_element` slots are rule-computed, every entry
  > is `[qw(type_element)]` — this is the expected result, not a degenerate case.

  **Fallback (no YAML files yet / Phase 1.5 skipped):** read `Slots d'entrée` lines
  from the KB org `Catalogue des Frames`. If still absent (legacy `Slots obligatoires`),
  use that list but emit:
  ```
  ⚠️ Frame '<name>': using legacy 'Slots obligatoires' — run Phase 1.5 or migrate
     to 'Slots d'entrée' / 'Slots calculés' (chorus-feed.md § Frame catalog format).
  ```
- agent 1 targeting slot comment ← `Slots de ciblage` section KB pos 1

### ⚠️ `*_ref` field naming — verify against the YAML, never assume the convention

> If any KB org documents a `*_ref` slot (Pattern A, `chorus-engine-infra.md §3.1`),
> **do not** write `Feed.pm`'s `%REF_FIELDS` from the documented "strip the `_ref`
> suffix" convention alone. Grep the actual rules for the exact string passed to
> `$f->get(...)`:
> ```bash
> grep -rn "get('.*_ref " $SANDBOX/rules/
> ```
> Two forms are both legitimate and **must be matched exactly**, because a
> mismatch produces no error at load time — the linked slot is simply always
> `undef`, silently falling back to the declarative boolean (Option A) or, if no
> fallback exists, leaving the verdict slot permanently unset (blocking a
> terminal-agent `EXCEPTION`/`CONDITION` chain indefinitely — see incident below):
>
> | Form found in YAML | `%REF_FIELDS` entry in `Feed.pm` |
> |---|---|
> | `$f->get('supports_ref building')` (suffix **kept** as the Frame slot name) | `supports_ref => 'supports_ref'` — do **not** strip; pass 2 must assign the resolved Frame object back to the *same* key |
> | `$f->get('supports building')` (suffix **stripped**, canonical `chorus-engine-infra.md §3.1` convention) | `supports_ref => 'supports'` — strip, per the documented convention |
>
> **Never assume** the second form (stripped) just because it is the documented
> default — a prior `chorus-feed --enrich` pass may have generated the first
> form consistently across both the YAML and the KB org `Slot Dictionary`. When
> both artefacts agree with each other but disagree with this convention, match
> the artefacts (YAML + KB org), not the doc — then flag the divergence to the
> user instead of silently "fixing" it one way or the other.
>
> **Incident:** `agent/org/incidents-log.org § anssi-01`


## Phase 2.5 — Generate procedural slot coderefs (_NEEDED, _AFTER) in Feed.pm

> See also: `chorus-feed.md § Procedural Slots`, `chorus-frame-advanced.md § Procedural Slots — $SELF Capture Rules`

Inside the `load_projet()` subroutine generated in Phase 2, after Frame creation,
inject coderefs for procedural slots annotated in the KB org:

### _NEEDED — Lazy derivation

**Detect:** KB org `Slot dictionary` entries marked with `Derived:` annotation

```org
| epaisseur_totale_mm | float | Derived via _NEEDED from couches[].epaisseur_mm |
```

**Generate** (inside `load_projet()`, after Frame creation):

```perl
# For each Frame with Derived slots, inject _NEEDED
$frame->set('_NEEDED', sub {
    # Derivation formula from KB org annotation
    # E.g.: sum of array elements
    my @items = @{ $SELF->get('items') // [] };
    my $total = 0;
    $total += ($_->get('value') // 0) for @items;
    return $total;
});
```

**Rules:**
- `_NEEDED` must be a **pure function** — no side effects, no Engine calls
- Formula comes from **KB org** annotation (e.g., "sum of X", "product of Y")
- Result is **not cached** — every `get()` re-evaluates; use explicit `set()` if needed
- Never return inside `_NEEDED` — use idiomatic return at the end

### _AFTER — Forward propagation (guardrails enforced)

**Detect:** KB org `Slot dictionary` entries marked with `Triggers X on Y (_AFTER)` notation

```org
| classe_conductivite | enum | Triggers besoin_thermique on dependent frames (_AFTER) |
```

**Generate** (inside `load_projet()`, after Frame creation):

```perl
# ⚠️ Only for slots that trigger propagation to other Frames
$frame->set('_AFTER', sub {
    my ($slot, $new_val) = @_;
    return unless $slot eq 'classe_conductivite';
    my $ctx = $SELF;  # capture BEFORE any set() on another Frame
    
    # Find dependent Frames
    for my $dependent (fmatch(slot => 'materiau_ref')) {
        next unless ($dependent->get('materiau_ref') // '') == $ctx;
        $dependent->set('besoin_thermique', 1);  # targeting slot
    }
});
```

**Rules:**
- **Never auto-generate** `_AFTER` — too risky for business logic. Document in KB org only.
- If human reviewer approves: manually add the closure to Feed.pm after `chorus-check` generation.
- Always capture `$SELF` before any `set()` on another Frame
- Only write **targeting slots** (never result slots) — maintain idempotence
- Include a `return unless $slot eq '...'` guard to limit scope

**Automation decision table:**

| Component | Responsibility | Automatic? | Notes |
|---|---|---|---|
| Detect `Derived:` annotation | `chorus-feed` | ✅ yes | KB org marks slots as derivable |
| Detect `Triggers` notation | `chorus-feed` | ✅ yes | KB org marks propagation dependencies |
| Generate `_NEEDED` coderef | `chorus-check` | 🟠 partial | Formula from KB org; code structure automatic |
| Generate `_AFTER` coderef | `chorus-check` | ❌ no | Too risky; requires human validation |

---

## Phase 3 — Generate Agent modules

For each agent in the index, create `$SANDBOX/lib/<Namespace>/Agent/<Nom>.pm`
from template **T2** (`chorus-templates.md`).

This module is **pure infrastructure** — it contains no business logic.
Business logic lives in the YAML files (rules) and in `Helpers.pm` (produced by `chorus-feed`).

**Rule for the termination agent:**
If the KB indicates `TERMINAL: solved` in a YAML → no additional Perl code needed.
If termination requires a global test (e.g. verifying that ALL Frames have
their status set), two approaches are valid:

**Preferred — YAML EXCEPTION + TERMINAL pattern** (MCP-compatible):
```yaml
RULE: check-all-done
TERMINAL: solved
FIND:
  dummy:
    attribut: <targeting_slot>
EXCEPTION: |
  scalar(grep { !defined $_->{<result_slot>} }
         Chorus::Frame::fmatch(slot => '<targeting_slot>')) > 0
ACTION: "1"
```
The `EXCEPTION` fires a fmatch on every cycle but **does not bind** — the rule
is only triggered when no pending frame remains. No infinite loop risk.
`TERMINAL: solved` is handled directly by the Engine's `applyrules()` → reliable termination.
This form is loaded by `loadRules()` and therefore **works natively in MCP mode**.

> `TERMINAL: solved` and `$SELF->solved()` are both valid for termination.
> They can be combined (both in the same rule) or used independently.

> ⚠️ `FIND`/`CHERCHER` must use `attribut:` (not `slot:`) — `slot:` is not a
> recognized YAML DSL key and will silently drop the rule from the engine.

**Fallback — pure Perl `addrule()`** (use only if EXCEPTION pattern is not expressive enough):
Add a pure Perl rule via `addrule()` after `loadRules()`, using template **T3** (`chorus-templates.md`).
⚠️ `addrule()` rules are registered in `build()` — they are **invisible to MCP mode**
(bypass of `build()`), which will cause `chorus_process` to return `failed` even when
all frames are correctly processed.

> ⚠️ **`$SELF` (YAML EFFET) vs `$agent` (pure Perl addrule()):**
> | Context | Correct variable | Reason |
> |---|---|---|
> | YAML EFFET | **`$SELF`** | `$agent` is out of scope in the Engine eval → `Global symbol` crash |
> | `_APPLY` in `addrule()` | **`$agent` (closure)** | `$SELF` is the rule-Frame, not the Engine |
>
> - In a **`.yml` file** → always `$SELF->solved()`, `$SELF->cut()`, etc.
> - In a **pure Perl `addrule()`** → capture `$agent` as a closure, never `$SELF`.


## Phase 4 — Generate `Expert.pm`

Create `$SANDBOX/lib/<Namespace>/Expert.pm` from template **T4** (`chorus-templates.md`).

**Substitutions:** one `use` + one `->build()` per agent in `#+PIPELINE_POS` order.
Force `$xprt->{_MAX_ITER}` after `new()` (known bug: `new()` ignores its arguments).
Document BOARD inter-agent keys in `index.org` if agents communicate via BOARD slots.
For each custom BOARD slot: key name, type, written by (agent), read by (agent).
`register()` order must guarantee producers run before consumers.
Full BOARD API + patterns: `chorus-engine-infra.md § 1.5 BOARD — Shared Publication Space`.


## Phase 5 — Generate `run.pl`

Create `$SANDBOX/run.pl` from template **T5** (`chorus-templates.md`).

**Substitutions:**
- `<Namespace>` ← from `index.org`
- `@slots_resultat_display` ← result slots from the pipeline KB (statut_conformite, raison_non_conformite, motif_refus, besoin_*, etc.)
- `@pipeline_def` ← one entry per agent: `[ label, slot_ciblage, slot_resultat_ok ]` from `index.org` pipeline table

**Rule:** `run.pl` contains **no hardcoded data** — all project input comes from the JSON argument.

> ⚠️ **Reference-valued result slots — do not assume every slot is a scalar.**
> Any slot in `@slots_resultat_display` (or returned by a custom `verdict_of()`
> in the multi-type dispatch variant) may hold an **arrayref** (e.g. a Helper
> returning a list of standard codes), a **hashref**, or a **blessed
> `Chorus::Frame`** (a resolved `*_ref` slot, or any hashref auto-promoted by
> `Chorus::Frame::blessToFrame` once passed through `$f->set()` — see
> `chorus-frame-advanced.md § blessToFrame`). T5 already stringifies these
> defensively (text display loop **and** the JSON report block) — if you hand-edit
> either block instead of copying T5 verbatim, preserve that stringification;
> printing/encoding a reference raw either produces an unreadable `HASH(0x...)`
> in the text report or an outright `JSON->encode` crash
> (`"encountered object ... neither allow_blessed ... enabled"`) deep into a
> `--batch`/`--all` run — on whichever project file happens to be the first to
> populate that particular slot with a non-scalar value, which may not be the
> file used for the Phase 6 smoke test.


## Phase 5.5 — Record KB hash + template hash *(full path only, after Phases 1–5)*

Once all infrastructure files have been generated successfully, record two
fingerprints so that the next `chorus-check` can detect staleness on both dimensions:

```bash
# 1. KB hash — tracks changes to the KB org content
sha256sum $SANDBOX/agent/chorus/*.org > $SANDBOX/agent/.kb-hash

# 2. Template hash — tracks changes to the infrastructure templates
sha256sum "$ENGINE/agent/skills/chorus-templates.md" > $SANDBOX/agent/.template-hash
```

(`$ENGINE` = absolute path to the Chorus Engine repository root, e.g.
`/home/civ/Chorus/engine` — resolved from `AGENTS.md` at skill load time.)

Both files are **never committed** (local artefacts, like `sessions/`).
`.kb-hash` is invalidated (deleted) by `chorus-feed` at the end of each run.
`.template-hash` is NOT invalidated by `chorus-feed` — it persists until the
next infrastructure regeneration.

### Double invalidation — behaviour rules

| State | `.kb-hash` | `.template-hash` | Action |
|---|---|---|---|
| Both current | ✅ match | ✅ match | **FAST PATH** — skip generation entirely |
| KB changed | ❌ differs | any | **FULL PATH** — KB enriched, regenerate silently (no user prompt) |
| Template changed, KB stable | ✅ match | ❌ differs | **FULL PATH** — template updated; **display a summary to the user** before regenerating (unlike KB changes, a template change is an external dependency update invisible from the sandbox — the user must be aware) |
| `.kb-hash` absent | — | — | **FULL PATH** — predates hash tracking |
| `.template-hash` absent | ✅ match | — | **FULL PATH** — predates template tracking; regenerate once to establish baseline |

> ⚠️ **Template staleness display (template-changed case only):** before regenerating,
> print:
> ```
> ⚠️  Template updated since last generation
>     Previous: <content of $SANDBOX/agent/.template-hash>
>     Current : <new sha256 of chorus-templates.md>
>     The sandbox infrastructure will be regenerated with the updated templates.
>     Generated artefacts (Feed.pm, Agent/*.pm, Expert.pm, run.pl) will be overwritten.
>     Any manual edit to those files will be lost — see chorus-templates.md for the
>     canonical template source.
> ```

### ⛔ Never edit generated artefacts directly

`Feed.pm`, `Agent/<Nom>.pm`, `Expert.pm`, and `run.pl` are **generated files**.
Any manual edit to them is volatile: it will be **silently overwritten** on the
next infrastructure regeneration (triggered by either `.kb-hash` or `.template-hash`
staleness), with no warning and no diff displayed.

**Rule:** every fix to generated artefact behaviour belongs in `chorus-templates.md`
(template source, `$ENGINE`) — never in the sandbox copy. Apply the fix in the
template, then trigger a regeneration via `chorus-check` on the affected sandbox.

> **Incident:** `agent/org/incidents-log.org § cc314-template-01` *(to be added
> when a real incident of this class is observed — the pattern is documented in
> `TODO.org § #A` as the motivating case: `CHORUS_MAX_CYCLES`/`CHORUS_MAX_ITER`
> override added manually to `run.pl` of sandbox `05-CC-3.1.4` instead of being
> ported to template T5.)*


## Phase 5.6 — Smoke test *(full path only, mandatory before Phase 6/6-all)*

> **Purpose:** catch infrastructure-generation bugs (crashes, encoding errors,
> malformed JSON report) on a single, controlled run — before they surface
> confusingly deep into a multi-file `--all` batch, on whichever project file
> happens to be first to exercise the buggy code path. A sub-agent spawned for
> `--all` Phase 6-all.2 reports `STATUS: FAILED` the same way for "genuine KB
> non-conformity" and "run.pl crashed with a Perl error" — the structured
> synthesis table cannot tell these apart. Smoke-testing once, here, with full
> error visibility, avoids misdiagnosing an infrastructure bug as a KB/project
> convergence problem three phases later.

**Select one project file** already present in `$SANDBOX/` (any `project-*.json`,
or the single `<fichier-project>` being checked if not in `--all` mode). Prefer
one with **varied element types** (not a single-type minimal fixture) if several
are available — a file exercising only one `type_element` may never populate the
reference-valued slot (arrayref/hashref/blessed Frame) that triggers the
"Reference-valued result slots" pitfall documented in Phase 5.

Run:

```bash
perl $SANDBOX/run.pl $SANDBOX/<selected-project-file>.json 2>&1 | tail -100
```

Check:
- [ ] No Perl crash (`Can't locate object method`, `Not a HASH/ARRAY reference`,
      `Global symbol "$agent"`, `encountered object ... neither allow_blessed`, etc.)
- [ ] Output reaches the final `Pipeline : SOLVED ✅` or `FAILED/TIMEOUT ❌` line
      (a crash mid-report means the run never gets this far — distinct from a
      legitimate `FAILED/TIMEOUT` verdict, which DOES reach this line)
- [ ] The JSON report file was written without error (`JSON report    : <path>`
      line present in the output — its absence alongside a `warn` immediately
      above it means `JSON->encode` died or the file could not be opened)

**If the smoke test crashes:**
1. Diagnose the failure class first — this determines where the fix belongs:
   | Symptom | Likely cause | Fix location |
   |---|---|---|
   | `Global symbol "$agent" requires explicit package name` in a `.yml`-sourced eval | `$agent->` used instead of `$SELF->` inside a rule's ACTION/EFFET/EXCEPTION | the `.yml` rule file itself — see Step 5b above (should have been caught already; a crash here means Step 5b was skipped or a new rule was added after it ran — re-run the grep) |
   | `Not a HASH/ARRAY reference` / `encountered object ... neither allow_blessed` | a result slot holds a reference (arrayref/hashref/blessed Frame) and `run.pl`'s display or JSON-report block printed/encoded it raw | `run.pl` itself — apply the defensive stringification documented in Phase 5's "Reference-valued result slots" note (already built into T5 — re-check you copied it verbatim rather than simplifying it away) |
   | `Can't locate object method "X" via package "Chorus::Frame"` | a `*_ref` field resolved to a plain string instead of a Frame object (naming mismatch between `%REF_FIELDS` and the YAML's actual `get('..._ref ...')` calls) | `Feed.pm` — re-verify the `*_ref` form per Phase 2's mandatory grep check |
   | `Undefined subroutine &Chorus::Engine::<helper>` | typeglob injection missing or ordered after `loadRules()` | the agent's `Agent/<Nom>.pm` — see Phase 3 |
2. Fix at the identified location, re-run the smoke test, repeat until clean.
3. If the fix touched any `.yml` rule file (KB content) → regenerate
   `agent/.kb-hash` (Phase 5.5) before proceeding — the KB fingerprint changed.

**Do not proceed to Phase 6 / Phase 6-all until the smoke test runs cleanly.**


## Phase 6 — Execution and report

### 6.0 — Run timestamp (`$RUN_TIMESTAMP`)

> **Capture once per `chorus-check` invocation, before 6A or 6B.**
> `$RUN_TIMESTAMP` is a string of the form `YYYYMMDD-HHMMSS` (e.g. `20261002-111502`).
> It is shared by the run-report JSON and any `--explain` / `--summary` files
> produced during the same invocation — this 1:1 naming is the sole mechanism
> that lets a UI panel associate the three files without an external index.

**MCP mode (6A):** generate upfront:
```
$RUN_TIMESTAMP = strftime('%Y%m%d-%H%M%S', localtime)   # before chorus_process
```
Use `$RUN_TIMESTAMP` when writing the run-report JSON:
`$WORKSPACE/run-report-<RUN_TIMESTAMP>.json` (`$WORKSPACE` already ends in
`reports/` — see the `$WORKSPACE`/`$ENTITY` note at the top of this document;
do not append an extra `reports/` segment here).

**Fallback mode (6B):** `run.pl` generates its own timestamp internally and prints:
```
  JSON report    : <path>/run-report-<YYYYMMDD-HHMMSS>.json
```
After `perl run.pl` completes, extract `$RUN_TIMESTAMP` by parsing this output line:
```bash
$RUN_TIMESTAMP = capture_from_stdout =~ /run-report-(\d{8}-\d{6})\.json/
```
Use this extracted value for all subsequent `--explain` / `--summary` file naming.


### 6A — MCP mode (`$MCP_AVAILABLE = true`)

Orchestrate the pipeline directly via MCP tools — no `run.pl` invocation:

```
chorus_reset
chorus_engine_create (ident: "<Nom1>")  →  h1
chorus_engine_create (ident: "<Nom2>")  →  h2   (one per agent in pipeline order)

# ⚠️ Inject helpers BEFORE loadRules — one call per Helpers.pm, any order.
# Injection is global (process-wide): a function injected once is available
# to all engines of this run. Skip agents without a Helpers.pm.
chorus_engine_inject (helpers_module: "<Namespace>::Agent::<Nom1>::Helpers",
                      lib_paths: ["$SANDBOX/lib", "$ENGINE/lib"])
chorus_engine_inject (helpers_module: "<Namespace>::Agent::<Nom2>::Helpers",
                      lib_paths: ["$SANDBOX/lib", "$ENGINE/lib"])
# ... repeat for each agent that has a Helpers.pm

chorus_engine_loadrules (h1, "$SANDBOX/rules/<slug1>/")
chorus_engine_loadrules (h2, "$SANDBOX/rules/<slug2>/")
chorus_expert_create (engine_handles: [h1, h2])  →  hX
chorus_feed_load (namespace: "<Namespace>",
                  json_path:  "<resolved path of fichier-project>",
                  lib_paths:  ["$SANDBOX/lib", "$ENGINE/lib"])
chorus_board_set (hX, { INPUT: <project_data> })   ← if agents read BOARD->INPUT
chorus_process   (hX)                               →  "solved" | "failed"
```

After `chorus_process`, collect results:

```
chorus_frames_list (slot: "statut_conformite",
                    extra_slots: ["id", "type", "raison_non_conformite", "_labels", ...])
chorus_board_get   (hX, <inter-agent slot>)   ← repeat for each BOARD slot of interest
chorus_reset                                  ← cleanup after collection
```

Build the compliance report from the collected frame data.
Apply the same report structure as Phase 6B (blocks 1–4 from T5).

> **`_labels` — termes project d'origine (MCP mode) :**
> Si `_labels` est présent sur un frame (hashref `{ slot_kb → terme_projet }`),
> afficher le terme d'origine entre guillemets après la valeur de chaque slot concerné :
> ```
>   section_bois                     : 45x145  ← «section»
>   classe_bois                      : C24     ← «classe résistance»
> ```
> Cette règle s'applique à tous les slots affichés dans le rapport (résultats et slots
> d'entrée). Les slots dont le nom KB est identique au terme source ne génèrent pas
> de suffixe `←`.

> **Advantages over 6B:**
> - No `run.pl` required — infrastructure can be partially absent.
> - Frame introspection between agents (call `chorus_frames_list` after each
>   `chorus_process` step if agents are run individually).
> - Report built directly from MCP responses, without parsing stdout.
> - Helpers injected via `chorus_engine_inject` — same semantics as `build()`.

If `chorus_process` returns `failed`:

**Graceful-failed detection** — before falling through to 6B, inspect frames:
1. Call `chorus_frames_list` with `slot: <termination_targeting_slot>` and
   `extra_slots: ["id", "<result_slot>"]`.
2. If **all** frames have their result slot defined (no `undef`) →
   the pipeline completed correctly but the termination rule was not reached
   (typical cause: `addrule()` in `build()`, bypassed in MCP mode).
   → Build the report from MCP frame data directly. Do **not** fall through to 6B.
   → Note in the report header: `Mode: MCP ✅ (graceful-failed — termination via addrule bypassed)`
3. If one or more frames have `undef` result slots → genuine failure.
   → Call `chorus_reset` to clean up.
   → Report the failure clearly, then fall through to 6B as a safety net.

> ℹ️ To avoid graceful-failed in the future, prefer the YAML EXCEPTION pattern
> for termination (see Phase 3) — it is loaded by `loadRules()` and is fully
> MCP-compatible without requiring `build()`.


### 6B — Fallback mode (`$MCP_AVAILABLE = false`)

Run the pipeline via the generated `run.pl`, passing the **actual resolved
path** of `<fichier-project>` — not a hardcoded `$SANDBOX/project.json`
(that literal path is only ever correct for the inline-data fallback of
§ 1.1; the normal case is the real `$SANDBOX/workspace/<entity>/<projId>.json`
path the user/caller provided, run.pl's own `dirname($fichier)/reports/`
write location depends on it being correct):

**Preferred — streaming mode (background job):**

Use `eca__shell_command` with `background` to stream `run.pl` output live
in the webapp terminal instead of waiting for full completion:

```
job_id = eca__shell_command(
  command    = "perl $SANDBOX/run.pl <resolved path of fichier-project> 2>&1",
  background = "run-<slug>"   # e.g. "run-project-rules-iso"
)
# Stream output progressively — poll until the job finishes:
loop:
  chunk = eca__bg_job(action="read_output", job_id=job_id)
  if chunk.output: display chunk.output as streaming text
  if chunk.status in ("completed", "failed"): break
  sleep ~2s
```

This causes the webapp terminal to display each frame being processed
(`Checking FIA.1/1… CONFORME`, `Checking FCS.1/3… NON_CONFORME`, …)
as it happens, rather than all at once after the run completes.

**Fallback — blocking mode (if background is unavailable or job_id is absent):**

```bash
perl $SANDBOX/run.pl <resolved path of fichier-project>
```

Use this fallback if `eca__shell_command` background mode is not supported
in the current execution environment (job_id absent → silent timeout 0s).
Capture full output after completion.

If Perl errors occur:
- `loadRules` error → check the YAML files (syntax, indentation)
- `Can't locate` error → check `use lib` and the namespace
- `FAILED/TIMEOUT` pipeline → check the termination rule

**Display the complete verbatim output** in a code block — always, without
summarizing or rephrasing in its place. This is the primary report output.

### 6.1 — Post-verbatim structured report (mandatory)

After the verbatim output, always produce the following structured report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-check  <sandbox-name>  <fichier-project>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Status       : SOLVED ✅ / FAILED ❌
  Éléments     : N total  (Bat:N  Voie:N  Fac:N  …)
  CONFORME     : N
  NON_CONFORME : N
  Unprocessed  : N
  Discordances : N / N_total
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Column definitions (identical to Phase 6-all):
- **CONFORME / NON_CONFORME**: count from the verbatim output
- **Unprocessed**: elements that produced no result slot at all (no `statut_conformite`,
  no `voie_acces_ok`, no `famille` — depending on type); targeting slot probably missing from Feed
- **Discordances**: elements whose actual result differs from the expected result implied
  by the ID naming convention (`-OK-` → expected CONFORME or OK, `-KO-` → expected NON_CONFORME or KO)
  or from `_resultats_attendus` in the JSON if present

If **Discordances > 0**, list them:

```
  Discordances :
    <id>  expected CONFORME   → got NON_CONFORME  (<rule_id>)
    <id>  expected NON_CONF   → got CONFORME      (<rule_id> | no rule fired)
    <id>  expected OK         → got KO            (<rule_id>)
```

> **`<rule_id>`** — read from the element's `_rule_trace` (if present, per
> `chorus-engine-yaml.md § Rule Documentation Standard`). Extraction method
> (identical to `run.pl` T5's Block 4 "Non-conformity summary" — see
> `chorus-templates.md`):
> 1. Extract the normative identifier (`RègleXxx`/`RecoXxx`/`RuleXxx`) already
>    present in the element's reason text (`raison_non_conformite`/`motif_refus`).
> 2. Search `_rule_trace` for the entry whose `corpus_ref` contains that exact
>    identifier — this is the rule that actually wrote this specific reason.
> 3. If no reason text is available, or no identifier is found in it, or no
>    `_rule_trace` entry matches → write `no rule fired` — do not fall back to
>    "the last entry" or otherwise guess. A wrong attribution is worse than none.
>
> ⛔ **Do not use "the last non-aggregation entry in the chain"** — on a chain
> with several specific rules (e.g. `check-archi-conformite` →
> `check-retraitement-conformite` → `check-niveau-qualite-reco`), this would
> point to whichever rule happened to run last, not the one that actually wrote
> the cited reason. This exact mistake was found and fixed in `run.pl` on
> sandbox `09b-ANSSI-PG-083_MULTI-SOURCES` (2026-09-24): `ALEA-ALGO-KO-01`'s
> reason cited `RègleArchiGénAléa.3` (written by `check-archi-conformite`,
> 1st in the chain) but "last entry" wrongly attributed it to
> `check-niveau-qualite-reco` (4th, unrelated `RecoArchiGénAléa`).

If **Unprocessed > 0**, list them:

```
  Unprocessed :
    <id>  (<type>) → targeting slot probably missing from Feed
```

### 6.2 — Convergence verdict

```
  CONVERGED ✅   — SOLVED, 0 discordances, 0 unprocessed
  NOT CONVERGED ❌ — N discordance(s) and/or N unprocessed
```

If **NOT CONVERGED** → recommend:
```
  Next step: chorus-strengthen <sandbox-name>
```

### 6.3 — Patch `.last-check-results.json` (single-project upsert)

> **This step runs after every single-project `chorus-check` invocation**
> (Phase 6A or 6B) — not in `--all` mode (Phase 6-all.6 writes the file
> wholesale for all projects; this step is redundant there).
>
> **Purpose:** keep the webapp Tests-tab convergence badges accurate after
> a single-project run, without requiring a full `--all` cycle.
> Synergy with WEB-021: writing this file triggers an immediate SSE `refresh`
> event in the webapp terminal, updating the Tests tab mid-session.

**Algorithm:**

```
1. Read $SANDBOX/agent/.kb-hash                           → kb_hash_current
2. sha256sum $SANDBOX/project-*.json | awk '{print $1}' | sha256sum   → proj_hash_current
3. Read $SANDBOX/.last-check-results.json if it exists    → existing (or {})
4. Build entry for the current project file:
     {
       "file":         "<basename of fichier-project>",
       "status":       "SOLVED" | "FAILED",
       "conforme":     N,
       "non_conforme": N,
       "unprocessed":  N,
       "discordances": N,
       "disc_detail":  [ { "id": "...", "expected": "...", "got": "..." }, ... ],
       "unproc_detail":[ { "id": "...", "type": "..." }, ... ]
     }
5. Upsert: replace the entry with matching "file" in existing["files"],
   or append if absent.
6. Recompute aggregates over the full updated files array:
     overall_discordances = sum of discordances
     overall_total        = len(files)
     converged            = all files SOLVED AND overall_discordances == 0
                            AND sum(unprocessed) == 0
7. Write $SANDBOX/.last-check-results.json:
     {
       "kb_hash":   kb_hash_current,
       "proj_hash": proj_hash_current,
       "timestamp": "<ISO-8601 UTC>",
       "files":     <updated files array>,
       "overall_discordances": N,
       "overall_total":        N,
       "converged":            true|false
     }
```

> **Partial coverage is expected and correct:** after a single-project run,
> `files` may contain only one entry (or a subset of all projects). The webapp
> scanner reads per-file entries individually — a partial file is valid and
> correctly reflected in the Tests tab. Missing projects show their last known
> entry (from a previous run) or "Convergence inconnue" if the file was absent.
>
> **`kb_hash` and `proj_hash` are always recomputed** from the current state,
> even when patching. This ensures the stale-detection logic in the webapp
> (`scanner.js § readLastCheckResults`) stays accurate: if the KB or any
> project file changed since the last `--all`, the new hash reflects it.


## Phase L0 — Report language resolution (`$REPORT_LANG`)

> **Runs once, before Phase E0, whenever `--explain` or `--summary` is present.**
> Produces `$REPORT_LANG ∈ { fr, en }` used by all subsequent phases to select
> French or English templates. Priority (highest first) :

```
1. --lang <fr|en> flag    → use directly, no further check
2. #+CORPUS_LANG in       → read first line matching "^#\+CORPUS_LANG:" in
   agent/chorus/index.org    $SANDBOX/agent/chorus/index.org
                              value must be fr or en (case-insensitive), else skip
3. YAML normative-content  → scan all files in $SANDBOX/rules/**/*.yml
   dominant language          ⚠️ do NOT use the "^RULE:"/"^REGLE:" header keyword —
                              it is a fixed structural tag from the engine's YAML
                              template (English by default, per chorus-engine-yaml.md),
                              not a reflection of the corpus's actual language, and is
                              present as "RULE:" even on French-corpus sandboxes.
                              Instead, scan the free-text normative content of each
                              rule: the "# CORPUS:" line's reference label and the
                              "# PURPOSE" block's prose. Count French-leaning markers
                              (accented characters é/è/à/ê/ç, or words matching
                              "Règle|Recommandation|Reco[A-Z]|conforme|non conforme"
                              case-insensitively) vs English-leaning markers (words
                              matching "Rule|Recommendation|compliant|non-compliant").
                              $REPORT_LANG = language with the higher marker count
                              across all scanned files; tie → fr
4. Default                → fr
```

**Log line (mandatory):**
```
[lang] $REPORT_LANG=<fr|en>  source=<flag|index.org|yaml-scan|default>
```

This log line is the only place `$REPORT_LANG` is announced — do not repeat it.
All phases below consume `$REPORT_LANG` silently; never re-run this resolution.

---

## Option `--explain` — Human-readable non-conformity explanations

> Runs **after** Phase 6 (single-file mode) or Phase 6-all (`--all` mode), once the
> compliance report has been produced and the convergence verdict is known.
> Never replaces the verbatim `run.pl` output or the structured report — it is an
> **additional, optional artefact** aimed at a non-technical reader (product owner,
> quality engineer, technical director) who needs to understand *why* an element was
> classified NON_CONFORME without reading YAML or Perl.
>
> ⚠️ **Skip this option entirely if `--explain` is absent** — it must never run by default,
> to avoid slowing down routine `chorus-check` invocations during iterative debugging.

### Rationale

The verbatim `motif_*` slot printed by `run.pl` (e.g. *"Unrecognised completion state
for a PP assignment (§8.1.2 para 254)"*) is accurate but terse: it does not show
*which* rule fired, *what* input values it read, *why* that specific rule applied
rather than a neighbouring one, nor *what corpus paragraph* it encodes. Reconstructing
this context today requires manually cross-referencing `agent/chorus/<slug>.org`,
`rules/<slug>/R*.yml`, and the project JSON — exactly the work an ECA session does
ad hoc in chat, with no persistent, reusable trace once the conversation ends.
`--explain` formalises and automates that reconstruction into a durable file.

### Phase E0 — KB recap and project recap (mandatory header data)

> Runs once, before Phase E1. Produces **one identical header block** consumed by
> **both** `--explain` (Phase E4) and `--summary` (Phase S2) — the two options
> must render the exact same KB/project recap tables, verbatim, so a reader
> switching between the two documents sees consistent context. Only the content
> *below* this header differs between the two options (per-rule detail vs.
> one-page synthesis).
>
> Keep this header **essential only** — no narrative paragraphs, no architecture/
> engineering notes, no historical commentary. It answers exactly two questions:
> "what corpus built this KB" and "what document produced this project". Anything
> else belongs in `index.org` itself, not in a generated report header.

**a) KB recap — read from `$SANDBOX/agent/chorus/index.org`:**

- `#+TITLE` → pipeline name
- `* Pipeline global` table → agent count and ordered slug list (one line, not
  the full table: `<N> agents : <slug1> → <slug2> → …`)
- `* Integrated corpus` table → reproduce as-is (Num / Fichier / Agents concernés),
  dropping the enrichment-pass narrative if it makes a cell unwieldy — one
  short clause per cell is enough (e.g. "operations (R06 étendu)", not the
  full pass history paragraph)

If `index.org` is missing or has no `* Integrated corpus` table → record
`KB recap: unavailable (index.org incomplete)` and continue (never block
`--explain`/`--summary` generation on this).

**b) Project recap — read from the project JSON file(s) being checked:**

- `project` (name) field
- `description` field, truncated to one sentence if longer (first `.` or first
  120 characters, whichever comes first) — the full description belongs in the
  JSON, not repeated verbatim in every generated report
- `_import` block if present → resolve the **full provenance chain**, not just
  `source_document` verbatim:
  1. `source_document` in `_import` almost always points to a **generated
     intermediate corpus file** (e.g. `enterprise/confluence/<NNN>-<slug>-vision.md`
     produced by `chorus-pdf`/`chorus-word`/`chorus-excel`), not the original
     document handed to the engineer. Displaying only this path silently hides
     which real-world document (docx/pdf/xlsx) the analysis actually traces back to.
  2. **Preferred method — read the provenance header:** open `source_document`
     and read its first line. Files produced by `chorus-pdf`/`chorus-word`/
     `chorus-excel` (all modes) always start with `# ORIGINAL: <path-to-original-document>`
     (see each skill's Phase — "Assemble output" step). If present, use this
     path directly — no heuristic needed.
  3. **Fallback heuristic** (only if the header is absent — e.g. corpus file
     predates this convention, or was hand-written): look for a file with the
     **same basename** (stripping any `<NNN>-` numeric prefix and `-vision`/`-text`
     suffix) and a document extension (`.docx`, `.pdf`, `.xlsx`) in the **same
     directory** as `source_document`. E.g. `005-common-criteria-security-target-id-ca-v7.3-vision.md`
     → look for `common-criteria-security-target-id-ca-v7.3.{docx,pdf,xlsx}`
     (case-insensitive match) in the same folder.
  4. If resolved (header or unique heuristic match) → display both: the
     generated corpus file (traceable, versioned in the sandbox) **and** the
     resolved original document.
  5. If unresolved (no header, zero or multiple heuristic matches) → display
     `source_document` alone and add `(document original non résolu — vérifier <dossier>)`.
  → Render as: `Import — document: <original ou "non résolu"> (converti en <source_document>, mode: <mode>, date: <date>)`
- If `_import` is absent → one line, corpus language:
  French: `Origine : project synthétique (chorus-create-project/chorus-stress)`
  English: `Origin: synthetic project (chorus-create-project/chorus-stress)`
- For `--all` / multi-file synthesis (`explain-all-*.md`) → one such project
  recap block **per project file**, not merged — each file may have a distinct
  origin and conflating them would mislead the reader.

**c) Canonical header block format** (identical in both `--explain` and `--summary`,
inserted verbatim after the document's own title/date/status lines).

> ⚠️ **Language:** render this block using `$REPORT_LANG` resolved in **Phase L0**.
> `fr` → French template below. `en` → English template beneath it.
> Do not mix languages within a single generated file.

French corpus (default template):
```markdown
## 📚 KB & Project

**Pipeline :** <N> agents : <slug1> → <slug2> → … → <slugN>

| Corpus | Fichier | Agents concernés |
|---|---|---|
| <NNN> | <fichier> | <agents, résumé court> |
| ... | | |

**Project :** <project> — <description tronquée>
**Origine :** <Import — document: ... (converti en ...) | project synthétique>
```

English corpus:
```markdown
## 📚 KB & Project

**Pipeline:** <N> agents: <slug1> → <slug2> → … → <slugN>

| Corpus | File | Agents involved |
|---|---|---|
| <NNN> | <file> | <agents, short summary> |
| ... | | |

**Project:** <name> — <truncated description>
**Origin:** <Import — document: ... (converted to ...) | synthetic project>
```

### Phase E1 — Select elements to explain

From the elements collected in Phase 6 (or Phase 6-all across all files):

```
TARGETS = { e | element_status(e) == 'NON_CONFORME' }
        ∪ { e | e has "_a_confirmer": 1 in the project JSON }   (if present)
```

> `_a_confirmer` elements are included because an uncertain terminology mapping
> (e.g. produced by `chorus-import-project`) can silently produce a NON_CONFORME
> verdict for reasons unrelated to genuine non-compliance — the reader needs to see
> both the verdict **and** the mapping uncertainty side by side.

If `TARGETS` is empty → print `[explain] No NON_CONFORME or _a_confirmer element — nothing to explain.` and skip Phases E2–E4 entirely (no file written).

### Phase E2 — Reconstruct the explanation for each target element

For each element `e` in `TARGETS`:

1. **Identify the agent and rule that produced the verdict.**
   - **Preferred — read `e._rule_trace` directly, if present.** Sandboxes whose YAML
     rules follow the `_rule_trace` traceability convention
     (`chorus-engine-yaml.md § Rule Documentation Standard`) publish, on every Frame,
     a cumulative arrayref of every rule that fired on it, in application order:
     `[ { rule_id, corpus_ref }, ... ]`. The **last entry** is normally the
     verdict-writing rule (aggregation/`publish-*` rules run last in most pipelines);
     when several entries carry distinct `corpus_ref` values, list them **all** in
     Phase E3's "Règle appliquée" field — this is precisely the case an aggregation
     rule (generic `CORPUS: (agrégation...)`) would otherwise have hidden the
     specific normative rule that actually computed the KO verdict (see incident
     below). No `agent/chorus/<slug>.org` cross-reference or `rules/<slug>/R*.yml`
     grep is needed in this case — `_rule_trace` is authoritative and already
     resolved by the engine at runtime.
   - **Fallback — `_rule_trace` absent** (sandbox predates the convention, or its
     YAML rules don't yet publish it): reconstruct manually.
     - Determine `e.type_element` → look up the owning agent via `agent/chorus/index.org`.
     - Identify the verdict slot that is `KO` (or the `_a_confirmer` flag) on `e`.
     - Read `agent/chorus/<slug>.org` § Rule Catalogue to find the rule(s) whose
       `Outputs (slots written)` include that slot.
     - Confirm by reading the matching `rules/<slug>/R*.yml` file — the rule that
       actually wrote the `KO` value is identifiable by its `FIND.filtre` condition
       matching `e`'s own slot values (e.g. `document_type`, `operation_kind`).

   > **Incident:** `agent/org/incidents-log.org § anssi-09b-01`

2. **Extract the exact corpus reference.**
   - From the rule's YAML header (`# CORPUS: §N — ...`) or inline comment
     referencing `§N para M`.
   - Quote the referenced paragraph number verbatim — do not paraphrase the
     article number.

3. **List the input values read by the rule.**
   - From the rule's `INPUTS (slots read)` header, read each corresponding value
     directly from the project JSON element `e`.

4. **Identify neighbouring rules that were NOT applied, and why.**
   - Scan sibling rules in the same agent (rules sharing the same targeting slot
     but a different `FIND.filtre` on `type`/`kind`/`document_type`).
   - For each sibling rule whose value domain *would* have accepted the element's
     actual input value, note it explicitly — this surfaces terminology-mapping
     errors (see chorus-audit-import precedent: a value valid for "selection" but
     used on an "assignment" element).
   - Example pattern (Operations agent): if `e.completion_status = "restricted"`
     failed under `R02-assignment-pp-flexible` (assignment domain), check whether
     `R04-selection-pp-flexible` (selection domain) would have accepted it — if so,
     flag this explicitly as a likely terminology-mapping issue, not a genuine
     substantive non-conformity.

5. **Classify the non-conformity nature** (new — not present in the base report):

   | Class | Meaning |
   |---|---|
   | 📋 Non-conformité substantielle | The element's data is correctly captured; the rule correctly identifies a genuine gap against the normative requirement (e.g. OP-03: assignment genuinely left uncompleted in an ST). |
   | 🔤 Anomalie de mapping terminologique | The KO verdict stems from a value that is valid in the KB grammar but for a *different* branch/type than the one carrying it (e.g. OP-07: "restricted" valid only for `selection`, misapplied to `assignment`) — likely a `chorus-import-project` alignment error, not a real defect. |
   | ❓ Incertain | Element carries `_a_confirmer: 1` — verdict may change once the ambiguous mapping is resolved by the engineer. |

   > This classification is the single most valuable addition of `--explain` over
   > the base compliance report: it separates *"the product genuinely fails this
   > requirement"* from *"the import tooling mis-translated a term"* — two very
   > different actions for the reader (fix the product vs. fix the JSON).

### Phase E3 — Per-element explanation block format

> ⚠️ **Language:** render using `$REPORT_LANG` from **Phase L0**.
> `fr` → French template. `en` → English template below. Never mix languages.

French corpus (default template):
```markdown
### <id> — <type_element>  [<classe: 📋 substantielle | 🔤 mapping | ❓ incertain>]

**Verdict :** <verdict_slot> = KO
**Motif (run.pl) :** "<motif_* verbatim string>"

**Règle appliquée :** `rules/<slug>/<R0N-rule-name>.yml`  (agent `<Nom>`, position <N>)
**Référence normative :** §<N> para <M> — <one-line summary of the requirement>
<if e._rule_trace has more than one entry — chaîne complète de traçabilité:>
**Chaîne de règles (`_rule_trace`) :**

| Ordre | Règle | Référence corpus |
|---|---|---|
| 1 | `<rule_id_1>` | <corpus_ref_1> |
| 2 | `<rule_id_2>` | <corpus_ref_2> |
| ... | | |
> La dernière règle (souvent un agrégateur `publish-*`) n'apporte parfois aucune
> référence normative propre (`(agrégation — pas de règle nommée spécifique)`) —
> dans ce cas, **la règle réellement responsable du verdict est une entrée
> antérieure de la chaîne**, pas la dernière. Utiliser cette table plutôt que la
> seule dernière entrée pour citer la référence normative exacte au lecteur.

**Valeurs d'entrée lues par la règle :**

| Slot | Valeur dans le project |
|---|---|
| <slot_a> | <valeur> |
| <slot_b> | <valeur> |

**Pourquoi cette règle s'applique :**
<one or two sentences: which FIND.filtre condition matched, contrasted with the
nearest sibling rule's filtre that did NOT match>

<if class == 🔤 mapping:>
**⚠️ Anomalie de mapping suspectée :** la valeur `<value>` est valide dans le
référentiel KB, mais uniquement pour `<other branch>` (règle
`<sibling-rule-name>.yml`, §<N> para <M>) — non pour `<this element's branch>`.
Vérifier le terme source d'origine (`<project term>`, cf. thesaurus.org / import-report)
avant de considérer cet élément comme réellement non conforme.

<if _a_confirmer present:>
**❓ Élément marqué à confirmer :** <note field from the project JSON>
```

English corpus:
```markdown
### <id> — <type_element>  [<class: 📋 substantial | 🔤 mapping | ❓ uncertain>]

**Verdict:** <verdict_slot> = KO
**Reason (run.pl):** "<motif_* verbatim string>"

**Rule applied:** `rules/<slug>/<R0N-rule-name>.yml`  (agent `<Name>`, position <N>)
**Normative reference:** §<N> para <M> — <one-line summary of the requirement>
<if e._rule_trace has more than one entry — full traceability chain:>
**Rule chain (`_rule_trace`):**

| Order | Rule | Corpus reference |
|---|---|---|
| 1 | `<rule_id_1>` | <corpus_ref_1> |
| 2 | `<rule_id_2>` | <corpus_ref_2> |
| ... | | |
> The last entry (often a `publish-*` aggregation rule) sometimes carries no
> normative reference of its own (`(aggregation — no dedicated rule)`) — in that
> case, **the rule actually responsible for the verdict is an earlier entry in
> the chain**, not the last one. Use this table rather than only the last entry
> to quote the exact normative reference to the reader.

**Input values read by the rule:**

| Slot | Value in the project |
|---|---|
| <slot_a> | <value> |
| <slot_b> | <value> |

**Why this rule applies:**
<one or two sentences: which FIND filtre condition matched, contrasted with the
nearest sibling rule's filtre that did NOT match>

<if class == 🔤 mapping:>
**⚠️ Suspected mapping anomaly:** the value `<value>` is valid in the KB
reference, but only for `<other branch>` (rule `<sibling-rule-name>.yml`,
§<N> para <M>) — not for `<this element's branch>`. Verify the original source
term (`<project term>`, see thesaurus.org / import-report) before treating this
element as genuinely non-compliant.

<if _a_confirmer present:>
**❓ Element marked to confirm:** <note field from the project JSON>
```

### Phase E4 — Assemble and write the explanation file

> ⚠️ **Language:** render using `$REPORT_LANG` from **Phase L0**.
> `fr` → French template. `en` → English template below.

French corpus (default template):
```markdown
# Explication des non-conformités — <sandbox-name> / <fichier-project ou "--all">
Date : <YYYY-MM-DD>
Pipeline : SOLVED ✅ / FAILED ❌
Éléments expliqués : <N> (📋 <n_subst> substantielle(s) · 🔤 <n_map> mapping · ❓ <n_unc> incertain(s))

---

<canonical header block from Phase E0.c — identical format to --summary>

---

<per-element blocks from Phase E3, one per target, in project-file order>

---

## Synthèse

| Élément | Classe | Motif court | Action recommandée |
|---|---|---|---|
| <id> | 📋/🔤/❓ | <motif tronqué> | <"Corriger le produit" \| "Vérifier le mapping <term>" \| "Valider avec l'ingénieur"> |
| ... | | | |

**Bilan :** <N> non-conformité(s) substantielle(s) réelle(s) sur <N_total> élément(s)
évaluable(s) (<X>%) — <N> anomalie(s) de mapping terminologique détectée(s)
séparément, ne comptant pas comme défaut produit.
```

English corpus:
```markdown
# Non-Conformity Explanation — <sandbox-name> / <project-file or "--all">
Date: <YYYY-MM-DD>
Pipeline: SOLVED ✅ / FAILED ❌
Elements explained: <N> (📋 <n_subst> substantial · 🔤 <n_map> mapping · ❓ <n_unc> uncertain)

---

<canonical header block from Phase E0.c — identical format to --summary>

---

<per-element blocks from Phase E3, one per target, in project-file order>

---

## Summary

| Element | Class | Short reason | Recommended action |
|---|---|---|---|
| <id> | 📋/🔤/❓ | <truncated reason> | <"Fix the product" \| "Verify the <term> mapping" \| "Validate with the engineer"> |
| ... | | | |

**Bottom line:** <N> genuine substantial non-conformit(y/ies) out of <N_total>
evaluable element(s) (<X>%) — <N> terminology-mapping anomaly/ies detected
separately, not counted as product defects.
```

**Thesaurus decisions appendix (--explain):** Before writing, check whether
`$WORKSPACE/thesaurus-log-<project-slug>.md` exists.

If it does, append the following section **after** the `## Synthèse` / `## Summary`
table and before the closing horizontal rule at the end of the file:

French corpus:
```markdown
---

## Décisions terminologiques (résolutions manuelles)

> Termes du thésaurus confirmés ou rejetés manuellement depuis chorus-web
> (onglet Thésaurus du projet). Ces décisions sont déjà intégrées dans
> `agent/thesaurus/<shard>.org` et seront prises en compte lors du prochain
> `chorus-import-project`.

<copy the full Markdown table from thesaurus-log-<project-slug>.md here>

📒 Journal complet : `thesaurus-log-<project-slug>.md`
```

English corpus:
```markdown
---

## Terminology Decisions (manual resolutions)

> Thesaurus terms manually confirmed or rejected via the chorus-web Thesaurus tab.
> These decisions are already integrated into `agent/thesaurus/<shard>.org` and
> will be applied on the next `chorus-import-project` run.

<copy the full Markdown table from thesaurus-log-<project-slug>.md here>

📒 Full log: `thesaurus-log-<project-slug>.md`
```

If `thesaurus-log-<project-slug>.md` does not exist: skip this section entirely
(no empty placeholder — the section only appears when there is something to report).

Write to: `$WORKSPACE/explain-<project-slug>-<RUN_TIMESTAMP>.md` (`$WORKSPACE`
as defined at the top of this document — `$SANDBOX/workspace/<entity>/reports/`,
created if absent).
(`<project-slug>` derived from the project filename; `<RUN_TIMESTAMP>` = the
timestamp captured in Phase 6.0 — ensures 1:1 traceability with the
corresponding `run-report-<RUN_TIMESTAMP>.json` produced during the same invocation.
A UI panel can therefore group the three files by timestamp without any external index.)

For `--all` mode (Phase 6-all, flat `$SANDBOX/project-*.json` layout — see
the `$WORKSPACE`/`$ENTITY` note at the top of this document for why this
differs from the per-entity convention), produce a single consolidated file
at the sandbox root: `$SANDBOX/explain-all-<RUN_TIMESTAMP>.md`, with
per-project-file sub-sections.

Print: `[explain] Explanation file written → workspace/<entity>/reports/explain-<project-slug>-<RUN_TIMESTAMP>.md (<N> element(s))`
(or `$SANDBOX/explain-all-<RUN_TIMESTAMP>.md` for `--all` mode)


## Option `--summary` — Consultation-friendly synthesis document

> Runs **after** `--explain` (Phase E1–E4) if both flags are present, or standalone
> after Phase 6/6-all if `--summary` is passed without `--explain`. **Phase E0
> (KB recap + project recap) always runs first, in both cases** — it is cheap
> (no per-element reasoning) and is mandatory header content for `--summary`'s
> own output, independently of whether `--explain` also runs. In standalone mode,
> Phase E1–E2 (element selection + reconstruction) still run internally
> (silently, without producing the full `--explain` file) to gather the data needed
> for the synthesis — only the detailed per-element blocks (Phase E3) are skipped.
>
> **Purpose:** a single, short, skimmable document — one screen, no scrolling
> through YAML/corpus cross-references — intended for a reader who wants the
> verdict and the headline reasons in under a minute (e.g. a technical director
> reviewing a compliance dossier before a meeting), as opposed to `--explain`'s
> engineer-facing per-rule traceability.

### Phase S1 — Compute headline figures

From the same `element_status()` results as Phase 6:

```
n_total       = elements evaluable (excluding reference-catalogue / sentinel types)
n_conforme    = count CONFORME
n_non_conforme = count NON_CONFORME
n_incertain   = count elements with _a_confirmer: 1
taux          = round(100 * n_conforme / n_total)
```

Classify each NON_CONFORME element per Phase E2 step 5 (📋 substantielle / 🔤 mapping)
to compute:

```
n_subst = count NON_CONFORME classified 📋 substantielle
n_map   = count NON_CONFORME classified 🔤 mapping
taux_reel = round(100 * (n_conforme + n_map) / n_total)   # optimistic rate if all
                                                            # mapping anomalies turn
                                                            # out to be import errors,
                                                            # not real defects
```

### Phase S2 — One-page synthesis document

Write `$WORKSPACE/synthese-<project-slug>-<RUN_TIMESTAMP>.md` using this exact template
(`$WORKSPACE` as defined at the top of this document —
`$SANDBOX/workspace/<entity>/reports/`, created if absent).

> ⚠️ **Language:** render using `$REPORT_LANG` from **Phase L0**.
> `fr` → French template. `en` → English template below. Never mix languages.
> The filename (`synthese-<slug>-<RUN_TIMESTAMP>.md`) keeps its French-derived prefix
> regardless of `$REPORT_LANG`; `<RUN_TIMESTAMP>` is shared with the corresponding
> `run-report-<RUN_TIMESTAMP>.json` and `explain-<slug>-<RUN_TIMESTAMP>.md` (Phase 6.0).

French corpus (default template):
```markdown
# Synthèse de conformité — <Nom du produit / dossier, from project JSON if available>

**Dossier :** <fichier-project>
**Date :** <YYYY-MM-DD>
**Statut du pipeline :** SOLVED ✅ / FAILED ❌

---

<canonical header block from Phase E0.c — identical format to --explain>

---

## Résultat en un coup d'œil

┌─────────────────────────────────────────────────────────┐
│   Taux de conformité observé  :  <taux>%  (<n_conforme>/<n_total>)  │
│   Taux de conformité corrigé* :  <taux_reel>%  (si anomalies de mapping résolues) │
└─────────────────────────────────────────────────────────┘

| Indicateur | Valeur |
|---|---|
| Éléments évalués | <n_total> |
| ✅ Conformes | <n_conforme> |
| ❌ Non conformes | <n_non_conforme> |
| — dont non-conformités substantielles 📋 | <n_subst> |
| — dont anomalies de mapping terminologique 🔤 | <n_map> |
| ❓ Éléments à confirmer | <n_incertain> |

## Non-conformités substantielles (action requise sur le produit/dossier)

| Réf. | Domaine | Motif | Référence normative |
|---|---|---|---|
| <id> | <agent/domaine> | <motif court, 1 ligne> | §<N> |
| ... | | | |

<if n_subst == 0:>
Aucune non-conformité substantielle détectée.

## Anomalies de mapping terminologique (action requise sur l'import, pas le produit)

| Réf. | Terme project | Mapping actuel | Anomalie |
|---|---|---|---|
| <id> | "<terme source>" | <slot>=<valeur> | <résumé 1 ligne> |
| ... | | | |

<if n_map == 0:>
Aucune anomalie de mapping détectée.

## Éléments à confirmer

| Réf. | Champ | Note |
|---|---|---|
| <id> | <slot> | <note du JSON> |
| ... | | |

<if n_incertain == 0:>
Aucun élément à confirmer.

## Recommandation

<one short paragraph, auto-generated from the figures above, e.g.:>
"<n_subst> point(s) substantiel(s) à corriger avant soumission. <n_map>
anomalie(s) de mapping à lever avec l'équipe d'import — leur résolution
porterait le taux de conformité de <taux>% à <taux_reel>%.
<Next step: chorus-strengthen <sandbox-name> si des règles sont jugées trop
strictes/permissives, ou correction directe du document project sinon.>"

---
*Document généré automatiquement par `chorus-check --summary` — voir
`workspace/<entity>/reports/explain-<project-slug>-<RUN_TIMESTAMP>.md` pour le détail règle-par-règle de
chaque élément.
```

English corpus:
```markdown
# Compliance Synthesis — <Product/dossier name, from project JSON if available>

**File:** <project-file>
**Date:** <YYYY-MM-DD>
**Pipeline status:** SOLVED ✅ / FAILED ❌

---

<canonical header block from Phase E0.c — identical format to --explain>

---

## Result at a glance

┌─────────────────────────────────────────────────────────────────┐
│   Observed compliance rate  :  <taux>%  (<n_conforme>/<n_total>) │
│   Adjusted compliance rate* :  <taux_reel>%  (if mapping issues resolved) │
└─────────────────────────────────────────────────────────────────┘

| Indicator | Value |
|---|---|
| Elements evaluated | <n_total> |
| ✅ Compliant | <n_conforme> |
| ❌ Non-compliant | <n_non_conforme> |
| — of which substantial non-conformities 📋 | <n_subst> |
| — of which terminology-mapping anomalies 🔤 | <n_map> |
| ❓ Elements to confirm | <n_incertain> |

## Substantial non-conformities (action required on the product/document)

| Ref. | Domain | Reason | Normative reference |
|---|---|---|---|
| <id> | <agent/domain> | <short reason, 1 line> | §<N> |
| ... | | | |

<if n_subst == 0:>
No substantial non-conformity detected.

## Terminology-mapping anomalies (action required on the import, not the product)

| Ref. | Project term | Current mapping | Anomaly |
|---|---|---|---|
| <id> | "<source term>" | <slot>=<value> | <1-line summary> |
| ... | | | |

<if n_map == 0:>
No mapping anomaly detected.

## Elements to confirm

| Ref. | Field | Note |
|---|---|---|
| <id> | <slot> | <note from the JSON> |
| ... | | |

<if n_incertain == 0:>
No element to confirm.

## Recommendation

<one short paragraph, auto-generated from the figures above, e.g.:>
"<n_subst> substantial point(s) to correct before submission. <n_map>
mapping anomaly/ies to resolve with the import team — resolving them would
raise the compliance rate from <taux>% to <taux_reel>%.
<Next step: chorus-strengthen <sandbox-name> if rules are judged too
strict/permissive, or direct correction of the project document otherwise.>"

---
*Document automatically generated by `chorus-check --summary` — see
`workspace/<entity>/reports/explain-<project-slug>-<RUN_TIMESTAMP>.md` for the full rule-by-rule detail of
each element.*
```

**Thesaurus decisions note (--summary):** Before writing, check whether
`$WORKSPACE/thesaurus-log-<project-slug>.md` exists.

If it does, append the following compact section **after** the `## Recommandation` /
`## Recommendation` paragraph and before the closing `---` footnote line:

French corpus:
```markdown

## Décisions terminologiques

<N> terme(s) résolu(s) manuellement depuis chorus-web
(<n_confirm> ✅ confirmé(s) · <n_reject> ❌ rejeté(s)).
Voir le journal complet : `thesaurus-log-<project-slug>.md`
```

English corpus:
```markdown

## Terminology Decisions

<N> term(s) manually resolved via chorus-web
(<n_confirm> ✅ confirmed · <n_reject> ❌ rejected).
Full log: `thesaurus-log-<project-slug>.md`
```

Count `<N>`, `<n_confirm>`, `<n_reject>` by counting table rows (excluding the
header) in `thesaurus-log-<project-slug>.md` and matching `✅ Confirmé`/`❌ Rejeté`
(FR) or `✅ Confirmed`/`❌ Rejected` (EN) in the Action column.

If `thesaurus-log-<project-slug>.md` does not exist: skip this section entirely.

Print: `[summary] Synthesis written → workspace/<entity>/reports/synthese-<project-slug>-<RUN_TIMESTAMP>.md`

> **Consultation ergonomics:** this file is deliberately kept under one printed
> page. It never repeats the full YAML/corpus traceability of `--explain` —
> it only links to it. If both `--explain` and `--summary` are requested, generate
> `--explain` first (Phase E1–E4) so `--summary`'s classification (Phase S1) can
> reuse its per-element classification without recomputing it twice.


## Phase 6-all — `--all` mode (batch run)

### 6-all.0-bis — Task planning

> Call `eca__task` once at the very start of `--all` mode to give the webapp terminal
> a live checklist (☐⏳☑). Use the discovered project files as task subjects.

```
eca__task(op="plan", tasks=[
  { subject: "6-all.1 — Discover project files",  description: "ls $SANDBOX/project-*.json" },
  { subject: "6-all.2 — Run <file1>",             description: "Sub-agent for project-rules-iso.json" },
  { subject: "6-all.2 — Run <file2>",             description: "Sub-agent for project-edges.json" },
  // … one task per discovered file
  { subject: "6-all.3 — Synthesis table",         description: "Aggregate results + write .last-check-results.json" },
  { subject: "6-all.4 — Convergence verdict",     description: "CONVERGED / DISCORDANCES report" },
])
```

> Replace `<file1>`, `<file2>` etc. with the actual filenames found in 6-all.1 once known.
> If files are not yet known at plan time, use generic subjects
> (`"6-all.2 — Run file 1"`, …) and `eca__task(op="update")` to rename them after discovery.

Mark each step `start` / `complete` as it executes.

> This phase is used **instead of Phase 6** when `--all` is present.
> Infrastructure detection (Step 0) is shared — the hash check runs once.
> ⚠️ **Phase 5.6 (smoke test) is NOT optional in `--all` mode** — on the FULL
> PATH (infrastructure just (re)generated), run it on one project file BEFORE
> spawning the 6-all.2 sub-agents. A crash inside `run.pl` and a genuine
> NON_CONFORME/discordance verdict both surface as sub-agent noise otherwise —
> smoke-testing once, here, with full error visibility, prevents 4+ sub-agents
> from independently hitting (and separately, confusingly, reporting) the same
> infrastructure bug. Skip Phase 5.6 only on the FAST PATH (hash unchanged —
> infrastructure already smoke-tested in a prior run).
>
> **Orchestrator mode:** the current agent discovers project files and spawns
> one sub-agent per project file via `eca__spawn_agent`. Each sub-agent has its
> own IDE session and token — no timeout risk from extended thinking between runs
> or during output analysis.

### 6-all.1 Discover project files

```bash
ls $SANDBOX/project-*.json
```

> **`archive/` exclusion (automatic, by construction):** `chorus-create-project`
> archives previous generations under `$SANDBOX/archive/<slug>/project-<slug>-<NNN>-<date>.json`
> (see `chorus-create-project.md § Phase 0.4 bis`). This flat glob naturally excludes
> them since they live one directory level deeper — same convention as `chorus-stress.md
> § --out`. Do not replace this glob with a recursive discovery (`find`/`**`) without
> re-adding an explicit `archive/` exclusion, or archived files will be double-counted
> in `--all` synthesis reports.

If no `project-*.json` file is found → stop and report:
```
⛔ No project-*.json file found in $SANDBOX/.
   Run chorus-create-project <sandbox-name> --batch first.
```

### 6-all.2 Spawn sub-agents

Spawn one sub-agent per discovered project file via `eca__spawn_agent`
(agent: `general`). Sub-agents can run in parallel if the IDE permits,
otherwise spawn sequentially.

Use this task template for each, substituting `<SANDBOX>` and `<FILE>`:

```
You are a chorus-check sub-agent. Your sole task: run ONE project file through
the pipeline and return a structured result block.

SANDBOX: <absolute path>
PROJECT FILE: <SANDBOX>/<FILE>

YOUR TASKS:
1. Run the pipeline:
      perl <SANDBOX>/run.pl <SANDBOX>/<FILE> 2>&1
   Capture the complete output.

2. Parse the output and extract:
   - STATUS  : "SOLVED" if "Pipeline : SOLVED ✅" appears in output, "FAILED" otherwise
   - CONFORME     : count of CONFORME elements
   - NON_CONFORME : count of NON_CONFORME elements
   - UNPROCESSED  : count of elements tagged "(unprocessed)" in output
   - DISCORDANCES : elements whose actual result differs from the expected result
       • id contains "-OK-" or "-ok-" → expected CONFORME
       • id contains "-KO-" or "-ko-" → expected NON_CONFORME
       Also check "_resultats_attendus" in the JSON if present.
       ⚠️ **`_expected_uncertain` filter:** before counting a discordance, read the
       element's `_expected_uncertain` field in the JSON. If `true`, **skip it entirely**
       — do not count it as a discordance, do not list it in DISC_DETAIL.
       Report the count of skipped uncertain elements separately:
       `UNCERTAIN_SKIPPED: N  (stress elements with _expected_uncertain=true — see stress-manifest.org)`

3. Return EXACTLY this block (no other text before or after):
   FILE: <FILE>
   STATUS: SOLVED|FAILED
   CONFORME: N
   NON_CONFORME: N
   UNPROCESSED: N
   DISCORDANCES: N
   UNCERTAIN_SKIPPED: N
   DISC_DETAIL:
     <id>  expected CONFORME  → got NON_CONFORME
     <id>  expected NON_CONF  → got CONFORME
   UNPROC_DETAIL:
     <id>  (<type>) → targeting slot probably missing from Feed
   (omit DISC_DETAIL lines if DISCORDANCES=0; omit UNPROC_DETAIL lines if UNPROCESSED=0;
    omit UNCERTAIN_SKIPPED line if 0)
```

### 6-all.3 Collect results and produce synthesis table

After all sub-agents complete, assemble the synthesis table from the
returned structured blocks:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-check --all  <sandbox-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Project file         │ Status      │ CONFORME │ NON_CONF │ Unproc │ Disc │ Uncertain⁺
  ─────────────────────┼─────────────┼──────────┼──────────┼────────┼──────┼───────────
  project-rules-iso     │ SOLVED ✅   │    N     │    N     │   0    │  0   │  —
  project-edges         │ SOLVED ✅   │    N     │    N     │   0    │  0   │  —
  project-cross         │ SOLVED ✅   │    N     │    N     │   0    │  0   │  —
  project-scale         │ SOLVED ✅   │    N     │    N     │   0    │  0   │  —
  project-stress-*      │ SOLVED ✅   │    N     │    N     │   0    │  0   │  N
  <other-project>       │ FAILED ❌   │    N     │    N     │   N    │  N   │  —
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Overall: SOLVED ✅ / FAILED ❌     Discordances: N / N_total
  ⁺ Uncertain: stress elements with _expected_uncertain=true — excluded from Disc count.
    See stress-manifest.org for manual review list.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Column definitions:
- **Status**: `SOLVED ✅` if sub-agent returned `STATUS: SOLVED`, `FAILED ❌` otherwise
- **CONFORME** / **NON_CONF**: counts from the sub-agent block
- **Unproc**: `UNPROCESSED` count from the sub-agent block
- **Disc**: `DISCORDANCES` count from the sub-agent block

### 6-all.4 Discordance detail

For each file with `Disc > 0`, list the discordant elements
(from sub-agent `DISC_DETAIL`):

```
  project-edges — 2 discordances:
    E-MUR-OK-SLEND-01  expected CONFORME   → got NON_CONFORME  (R03-slenderness)
    E-POT-KO-THICK-02  expected NON_CONF   → got CONFORME      (no rule fired)
```

> **Rule name in parentheses** — same extraction rule as § 6.1: extract the
> normative identifier (`RègleXxx`/`RecoXxx`) from the element's reason text,
> then search `_rule_trace` for the entry whose `corpus_ref` contains it.
> `no rule fired` when no match is found — never guess via "last entry".

For each file with `Unproc > 0`, list the unprocessed elements
(from sub-agent `UNPROC_DETAIL`):

```
  project-scale — 3 unprocessed:
    S-OSS-OK-C24-11    → targeting slot 'besoin_ossature' probably missing from Feed
```

### 6-all.5 Convergence verdict

```
CONVERGED ✅   — all projects SOLVED, 0 discordances, 0 unprocessed
NOT CONVERGED ❌ — N discordances and/or N unprocessed across M project files
```

If **NOT CONVERGED** → `Next step: chorus-strengthen <sandbox-name>`

### 6-all.6 Persist results cache

After the synthesis table and convergence verdict, always write the structured
results to `$SANDBOX/.last-check-results.json`.

This file is consumed by `chorus-strengthen` to skip re-running the full suite
when the KB has not changed since the last `chorus-check --all`.

**Format:**

> ⛔ **Mandatory mechanical-copy procedure for `kb_hash`** — produce this field
> via a literal file-read-then-write (`eca__read_file` on `agent/.kb-hash`,
> insert the exact returned string) — never retype/reconstruct it from memory
> or from an earlier turn's displayed content. A one-line transcription slip
> silently shifts every hash↔filename pairing (undetectable by inspection,
> breaks the webapp's stale-detection permanently — incident confirmed
> 2026-10-27, sandbox 05b-CC-3.1.4-NEW).
>
> **Verification before writing:** confirm the first line's hash token matches
> `sha256sum` of the actual first-listed file in `agent/.kb-hash` — do not
> write `.last-check-results.json` if this check was skipped.

```json
{
  "kb_hash": "<content of $SANDBOX/agent/.kb-hash — verbatim, mechanically copied, see guard above>",
  "proj_hash": "<sha256sum $SANDBOX/project-*.json | awk '{print \$1}' | sha256sum | awk '{print \$1}'>",
  "timestamp": "<ISO-8601 UTC>",
  "files": [
    {
      "file": "project-rules-iso.json",
      "status": "SOLVED",
      "conforme": N,
      "non_conforme": N,
      "unprocessed": N,
      "discordances": N,
      "disc_detail": [
        { "id": "<id>", "expected": "CONFORME",     "got": "NON_CONFORME" },
        { "id": "<id>", "expected": "NON_CONFORME", "got": "CONFORME"     }
      ],
      "unproc_detail": [
        { "id": "<id>", "type": "<type>" }
      ]
    }
  ],
  "overall_discordances": N,
  "overall_total": N,
  "converged": true
}
```

- `disc_detail` and `unproc_detail` may be empty arrays when counts are 0.
- `converged`: `true` only when all files are SOLVED, 0 discordances, 0 unprocessed.
- This file is **never committed** (local artefact, like `.kb-hash`).
- It is **invalidated** (deleted) by `chorus-feed` at the end of each run,
  alongside `.kb-hash`.
- `proj_hash` ensures that regenerating a `project-*.json` (via
  `chorus-create-project --strategy X`) also invalidates the cache, even when the KB
  org files are unchanged. Without this field, `chorus-strengthen` would incorrectly
  read stale discordance counts from the previous project generation.

> **Sub-agent mode guarantee:** each sub-agent has its own IDE session and token.
> No timeout risk regardless of pipeline complexity or number of project files.
> Running N projects costs exactly N sub-agent spawns + N × `perl run.pl`.
> If a sub-agent fails (token error, crash) → re-run
> `chorus-check <sandbox> <project-file>` (single-file mode) for the failed
> project only — no need to rerun the whole batch.


> **Mode used** is reported in the compliance report header:
> `Mode: MCP ✅` or `Mode: run.pl (MCP unavailable)`


## Phase 7 — Final verification *(post-generation only)*

> ⚠️ This checklist applies **only after generation** of Phases 1–5.
> Do not run it on the fast path (infrastructure already present).

- [ ] **Language rule:** all comments in generated Perl files match the corpus language (see `chorus-engine.md § Canonical Language Rule`)
- [ ] `agent/.kb-hash` written after generation — contains `sha256sum` of all `agent/chorus/*.org`
- [ ] ⛔ **`type_element` — YAML ↔ Feed alignment:** verify that the `attribut:` key in every
      `FIND`/`CHERCHER` block of every YAML rule that targets element type is named `type_element`.
      Then verify that `Feed.pm` creates Frames with the slot key `type_element`.
      A mismatch between YAML and Feed causes a SOLVED pipeline with all elements unprocessed.
- [ ] `Feed.pm`: agent 1 targeting slot present in `%SLOTS_REQUIS`
- [ ] `Feed.pm`: `%SLOTS_REQUIS` covers all element types in the project **and contains only
  INPUT-REQUIRED slots** (targeting slot + project data slots that no rule computes).
  ⛔ Output slots written by rules must NOT appear in `%SLOTS_REQUIS` — they will be absent
  at load time when the project was generated by `chorus-create-project`. A type whose slots
  are all rule-computed must have `[qw(type_element)]` as its entry.
- [ ] `Feed.pm`: unknown types → `warn + next` (not `die`) — safety net for mixed-sandbox JSON
- [ ] `Expert.pm`: `register()` order = `#+PIPELINE_POS` order
- [ ] `Expert.pm`: `$xprt->{_MAX_ITER}` forced **after** `new()` (known bug: `new()` ignores its arguments)
- [ ] `run.pl`: `Chorus::*` resolved via system install (no `use lib` pointing to Engine sourcetree)
- [ ] `run.pl`: no hardcoded data
- [ ] Report: no unexpected `(unprocessed)` elements
- [ ] `_MAX_CYCLES`: a **flat, bounded ceiling** — NOT proportional to Frame volume or rule
      count. ⛔ **Do not use** the older `N_frames × N_rules_total × N_agents × D × 10` heuristic
      — empirically (chorus-check 2026-10 perf incident, sandbox `05-CC-3.1.4`), this formula is
      the wrong shape: cycles needed to converge scale with **bounded-wait retry depth**
      (`MAX_WAIT_CYCLES`, typically 5, used by any "aggregate — give up after N cycles if
      expected children never appear" rule — see `chorus-engine-yaml.md` § Aggregate rule
      waiting on an "expected children" list) × the number of components that can be
      simultaneously stuck waiting — small and bounded regardless of total element count —
      **not** with element/rule volume. A project with hundreds of elements but no
      bounded-wait components converges in under a second under any calibration; a project
      with a few dozen components stuck waiting on absent child Frames can take tens of
      thousands of needlessly-calibrated cycles to report a correct, legitimate
      `FAILED/TIMEOUT` verdict several minutes later than necessary.
      **Use a flat default of `200`** (empirically bisected: `max_cycles=200` converges on a
      real-world worst-case bounded-wait fixture in ~25s; `max_cycles=300` already exceeded
      30s on the same fixture) — re-bisect per-sandbox only if its KB uses a deeper
      `MAX_WAIT_CYCLES` or longer cross-rule `CONDITION` chains than the typical case.
      In `run.pl`: `my $max_cycles = $ENV{CHORUS_MAX_CYCLES} // 200;` (T5), passed via
      `Expert->run(max_cycles => ...)`. Never leave an element-count-proportional formula —
      it produces a budget that looks "safe" but is actually orders of magnitude larger
      than needed, with no correctness benefit and a severe wall-clock cost on any project
      exercising bounded-wait rules.
- [ ] `_MAX_ITER`: same flat-ceiling principle — default `200` (not `50_000`/`2_000`), passed
      via `Expert->run(max_iter => ...)` and forced via `$xprt->{_MAX_ITER}` per the known
      `new()`-ignores-arguments bug (see template T4). A converging pipeline normally
      stabilizes in well under 100 outer iterations even for large projects — empirically
      verified `iter=20` already reaches the final, stable verdict on the same worst-case
      fixture above; `200` keeps a comfortable 10x margin without multiplying worst-case
      runtime unnecessarily.
- [ ] Termination agent: use **YAML EXCEPTION pattern** (see Phase 3 template) — MCP-compatible, no infinite loop.
      `addrule()` fallback: `solved()` on `$agent` (closure), never `$SELF`; invisible to MCP mode.
      ⛔ **Never use a global `fmatch` in a YAML `FIND`/`CHERCHER` block** → guaranteed infinite loop.
      ✅ `fmatch` in a YAML `EXCEPTION`/`CONDITION` block is safe (evaluated per-cycle, does not bind).
- [ ] If `reorder()` is used: the sort function consults `_PREMISSES` — consistent with the YAML files
- [ ] If `_LOCK_UNTIL_STABLE` is enabled: the agent may be skipped — verify this is the intended behaviour
- [ ] BOARD: inter-agent keys documented in `index.org` (key, type, written by, read by)
- [ ] BOARD: `register()` order guarantees producer agents before consumer agents
- [ ] BOARD: custom slots reset between `process()` calls if Expert instance is reused
- [ ] BOARD: YAML ACTION uses `$SELF->BOARD` — never `$agent->BOARD`
- [ ] BOARD: no `CONDITION` guard on a slot written by another agent — use `register()` order + ACTION fallback
- [ ] Every `.yml` rule pushes `_rule_trace` at the top of its `ACTION`/`EFFET` (Step 5c)
- [ ] Every rule that can write a failing verdict also writes an explicit, rule-authored
      `non_conformity_motif`/`motif_non_conformite` in the same branch (Step 5c)
- [ ] `run.pl`'s JSON-report block reads `_rule_trace` back and includes the
      `generic_motif_from_trace()` fallback (Step 5c / `chorus-templates.md` T5)
- [ ] **`return 0` vs `return 1` — convergence mechanism:** every ACTION must return `1` only when
      it has written at least one slot. Returning `1` unconditionally signals "productive step" to the
      engine, which schedules a new cycle — causing an infinite loop if no slot is actually written.
      `return 0` signals "nothing done this cycle" and does not count toward cycle productivity.
      The engine stops when **all** rules return `0` in the same cycle (no further progress possible).
      → Check every YAML ACTION: any `if (...)` branch that writes a slot must `return 1` inside the
      branch and fall through to `0` (or `return 0`) otherwise.
      `if (...) { $p->set('slot', $val); return 1 }  0`
- [ ] **YAML — conditional EFFET without `else`**: if the `if` modifies nothing and the rule returns `1`,
      the engine loops until `_MAX_CYCLES` (warning). Check every YAML whose EFFET
      contains an `if` without `else` → return `0` when no slot is modified:
      `if (...) { ...; return 1 } 0`
- [ ] **EXCEPTION permanence (Pattern 1):** an `EXCEPTION: defined $f->{slot}` guard permanently blocks
      the rule on this Frame once any sibling rule has written `slot`. This is intentional for
      classification rules but is a **silent failure mode** when a veto/override rule uses Pattern 1
      instead of Pattern 2. If a discordance shows "expected NON_CONFORME → got CONFORME" and no rule
      fired for this element, check whether a sibling rule wrote the guard slot first in an earlier cycle,
      permanently blocking the veto rule. Fix: switch to Pattern 2
      (`EXCEPTION: '($f->{slot} // "") eq "<veto_value>"'`).
- [ ] **CONDITION transience:** a `CONDITION: defined $p->{slot}` guard is always transient — the rule
      is skipped this cycle and retried the next. If a discordance shows "rule never fired" despite the
      prerequisite slot being eventually set, check whether `CONDITION` was incorrectly replaced by a
      `filtre` expression. A Frame excluded by `filtre` is permanently out of scope and will never be
      retried even after its prerequisite slot appears.
- [ ] **Guard coherence:** handled automatically by `Chorus::Engine::loadRules()` —
      a `warn` is emitted at every `loadRules()` call for any rule whose `EXCEPTION`
      guard slot is not written by that rule's ACTION.
      No manual check needed here; review STDERR output from the previous pipeline run.


## Separation of concerns — summary

| | `chorus-feed` | `chorus-check` |
|---|---|---|
| **Reads** | standards corpus | sandbox KB org + YAML + Helpers.pm |
| **Produces** | KB org, YAML, `Helpers.pm` | `Feed.pm`, `Agent/<Nom>.pm` (shell), `Expert.pm`, `run.pl` |
| **Does not produce** | infrastructure code | KB org, YAML, Helpers.pm |
| **Triggered by** | new standard / enrichment | project to validate |
| **Output** | persistent knowledge | compliance report |

> A sandbox can undergo N successive `chorus-feed` runs (enrichments)
> then N independent `chorus-check` runs (different projects).
> The KB and Helpers are stable and cumulative.
> Infrastructure artefacts (Feed, Agent shell, Expert, run.pl)
> are regenerated at each `chorus-check`.


## Option `--from-report` — Analyse sans relance du pipeline

> **Trigger webapp :** bouton "🔎 Analyse" affiché dans la modale run-report quand
> aucun fichier `explain-*` / `synthese-*` lié par timestamp n'existe pour ce run.
> **Usage manuel :** `chorus-check <sandbox-name> --from-report <path> --summary --explain`

Ce mode permet de produire les rapports `--explain` et/ou `--summary` à partir
d'un run-report JSON **déjà existant**, sans rejouer le pipeline (pas de `run.pl`,
pas d'appel MCP, pas de lecture de la KB org ni des fichiers YAML).

> ⛔ **Interdictions strictes en mode `--from-report` :**
> - Ne jamais appeler `chorus_process`, `chorus_engine_create` ou `chorus_expert_create`
> - Ne jamais exécuter `perl run.pl`
> - Ne jamais lire `agent/chorus/*.org` ni `rules/**/*.yml` (les données sont dans le JSON)
> - Ne jamais régénérer `Feed.pm`, `Agent/*.pm`, `Expert.pm`

### Phase FR0 — Chargement du run-report

1. Lire `$SANDBOX/<run-report-path>` (fichier JSON produit par un précédent `chorus-check`)
2. Extraire `$RUN_TIMESTAMP` du nom de fichier :
   ```
   run-report-(\d{8}-\d{6})\.json  →  $RUN_TIMESTAMP = "YYYYMMDD-HHMMSS"
   ```
3. Extraire `$ENTITY`/`$WORKSPACE` depuis `<run-report-path>` lui-même (voir
   la note `$WORKSPACE`/`$ENTITY` en tête de ce document — même règle de
   dérivation qu'en mode normal, appliquée ici au chemin du run-report plutôt
   qu'à celui du fichier projet) :
   ```
   workspace/<entity>/reports/run-report-....json  →  $ENTITY = "<entity>"
   $WORKSPACE = $SANDBOX/workspace/$ENTITY/reports/
   ```
   ⚠️ Ne jamais écrire `explain-*.md`/`synthese-*.md` à la racine `$SANDBOX/workspace/`
   ou `$SANDBOX/` dans ce mode non plus — mêmes garde-fous qu'en mode normal.
4. Extraire depuis le JSON :
   - `elements[]` → tableau des éléments avec leurs verdicts, motifs, `_rule_trace`
   - `project_file` → déduire `<project-slug>` (basename sans `.json`)
   - `pipeline_solved` → équivalent du statut SOLVED/FAILED de Phase 6
   - `n_total`, `n_conforme`, `n_non_conforme`, `n_incertain` → stats de Phase 6.1

5. Construire le contexte équivalent à la sortie de Phase 6 :
   ```
   $phase6_elements  = data extracted from elements[]
   $phase6_solved    = json.pipeline_solved
   $phase6_stats     = { n_total, n_conforme, n_non_conforme, n_incertain }
   $project_slug     = basename(json.project_file, ".json")
   ```

> Si `elements[]` est absent ou vide → arrêter et afficher :
> `"[--from-report] run-report vide ou invalide — impossible de générer l'analyse."`

### Phase FR1 — Exécution de --explain et/ou --summary

Aller directement aux phases d'analyse en utilisant les données de Phase FR0
**à la place** de la sortie normale de Phase 6 :

- **`--explain`** → exécuter Phase E0 → E1 → E2 → E3 → E4
  - Phase E0 : lire `$SANDBOX/agent/chorus/index.org` pour le recap KB uniquement
    (nécessaire pour le header canonique — lecture seule, aucune génération)
  - Phase E1 : `TARGETS` = éléments de `$phase6_elements` avec `conforme == 'NON_CONFORME'`
    **ou** `a_confirmer == true` — une **union**, pas une intersection ni un filtre
    implicite sur le verdict. ⚠️ Un élément `a_confirmer == true` fait partie de
    `TARGETS` **quel que soit son verdict** (`CONFORME`, `NON_CONFORME`, ou
    `(unprocessed)`) — c'est le même piège que celui documenté en Phase E1 (mode
    normal, voir plus haut) : un élément CONFORME avec `a_confirmer: true` doit
    apparaître dans `explain-*.md` tout autant qu'un NON_CONFORME classique.
    Observed incident: a `--from-report` run included all 5 `a_confirmer` elements
    correctly in the `synthese-*.md` table (Phase S1/S2 iterates `$phase6_elements`
    unconditionally) but **omitted all 5 from `explain-*.md`** — root cause was
    filtering `TARGETS` down to `conforme == 'NON_CONFORME'` only, silently
    dropping the CONFORME/`(unprocessed)` members of the union. Always compute
    `TARGETS` as the full union **before** iterating Phase E2-E4 — never narrow it
    to one verdict class first.
  - Phase E2–E3 : reconstruction depuis `_rule_trace` déjà présent dans le JSON
    (aucune lecture de règles YAML nécessaire — les traces sont déjà résolues)
  - Phase E4 : écrire `$WORKSPACE/explain-<project-slug>-<RUN_TIMESTAMP>.md`

- **`--summary`** → exécuter Phase E0 → S1 → S2
  - Phase S1 : calculer `n_subst`, `n_map`, `taux` depuis `$phase6_elements`
  - Phase S2 : écrire `$WORKSPACE/synthese-<project-slug>-<RUN_TIMESTAMP>.md`

> `$RUN_TIMESTAMP` extrait en Phase FR0 garantit que les fichiers produits partagent
> le même suffixe que le `run-report-<RUN_TIMESTAMP>.json` source — le lien par
> nom de fichier (convention MVP0) est ainsi rétabli automatiquement.

Print en fin d'exécution :
```
[from-report] explain → workspace/.../explain-<slug>-<RUN_TIMESTAMP>.md
[from-report] synthese → workspace/.../synthese-<slug>-<RUN_TIMESTAMP>.md
```
