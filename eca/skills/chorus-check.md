# Skill — chorus-check

> Trigger: `chorus-check <sandbox-name> <fichier-projet>`
> Agent: `architect`
>
> `<sandbox-name>`: sandbox containing the KB and YAML rules (produced by `chorus-feed`)
> `<fichier-projet>`: JSON file describing the project elements to validate,
>                      or data provided inline by the user
>
> **Single responsibility: validate a project against the knowledge base.**
> The project file is **runtime input data** — it does not influence
> infrastructure generation. Two `chorus-check` runs on the same sandbox
> with different projects share exactly the same infrastructure.
>
> Prerequisite: `chorus-feed <sandbox-name>` must have been run beforehand
> (KB org + YAML present in the sandbox).

---

## ⚡ Step 0 — Infrastructure detection (PRIORITY, before any loading)

**This is the first action to execute, without exception.**

Call `eca__directory_tree` on `$SANDBOX` (max_depth=3) and verify:

```
$SANDBOX/run.pl
$SANDBOX/lib/<Namespace>/Feed.pm
$SANDBOX/lib/<Namespace>/Expert.pm
$SANDBOX/lib/<Namespace>/Agent/<Nom>.pm  ← au moins un
```

### ✅ Infrastructure present → FAST PATH

**Go directly to Phase 6. Do not load `chorus-engine.md`. Do not read
`index.org`. Do not read agent KBs. Do not generate anything.**

The infrastructure is tied to the corpus/KB, not to the project. Changing the project file
justifies no regeneration.

> **Forced regeneration**: only if the user explicitly mentions
> that a `chorus-feed` has been run since the last generation, or explicitly asks
> to "regenerate" / "rebuild" the infrastructure.
> A second `chorus-check` with a different project is **never** a
> forced regeneration.

### ❌ Infrastructure absent or incomplete → FULL PATH

Load:
- `chorus-engine-infra.md` — Perl infrastructure reference (Core Mechanisms, Multi-Specialty Pattern, checklists)
- `chorus-templates.md` — Perl infrastructure templates (T1–T5)
- `$SANDBOX/eca/agents/index.org` — pipeline, agents, namespace

> ⚠️ Do not read agent KBs (`<slug>.org`) or YAML files at this stage.
> They are only needed during generation (infrastructure absent).

Then execute Phases 0, 1–5, 6, 7 in order.

---

## Phase 0 — KB prerequisite check *(full path only)*

```
$SANDBOX/eca/agents/index.org     ← doit exister
$SANDBOX/eca/agents/<slug>.org    ← au moins un agent
$SANDBOX/rules/<slug>/            ← au moins un fichier YAML par agent
```

If any of these is missing → stop and report:
`"KB incomplete — run chorus-feed <sandbox-name> <corpus> first."`

Extract from `index.org`:
- The Perl namespace of the project
- The ordered list of agents (pos, slug, Perl module)
- The termination agent (last)

---

## Phase 1 — Analyse the project file

### 1.1 Expected format

```json
{
  "projet": "<nom>",
  "elements": [
    {
      "id": "<identifiant unique>",
      "type": "<type d'élément>",
      "<slot1>": <valeur1>,
      "<slot2>": <valeur2>
    }
  ]
}
```

If the project file is provided **inline** (data pasted in the message) →
write it to `$SANDBOX/projet.json` before continuing.

### 1.2 Deduce mandatory slots

For each element type present in the project file, cross-reference with the
`Catalogue des Frames` in the KBs to identify slots marked `obligatoire`.
These slots will drive the Feed validation.

### 1.3 Identify the targeting slot for agent 1

Read the `Slots de ciblage` section of the KB for the agent at position 1.
This slot must be present on all Frames created by the Feed.

---

## Phase 2 — Generate `Feed.pm`

Create `$SANDBOX/lib/<Namespace>/Feed.pm` from template **T1** (`chorus-templates.md`).

**Substitutions from the KBs:**
- `%SLOTS_REQUIS` ← `obligatoire` slots from the Catalogue des Frames of each KB
- agent 1 targeting slot comment ← `Slots de ciblage` section KB pos 1

---

## Phase 3 — Generate Agent modules

For each agent in the index, create `$SANDBOX/lib/<Namespace>/Agent/<Nom>.pm`
from template **T2** (`chorus-templates.md`).

This module is **pure infrastructure** — it contains no business logic.
Business logic lives in the YAML files (rules) and in `Helpers.pm` (produced by `chorus-feed`).

**Rule for the termination agent:**
If the KB indicates `TERMINAL: solved` in a YAML → no additional Perl code needed.
If termination requires a global test (e.g. verifying that ALL Frames have
their status set) → **do not code this in a YAML** (risk of infinite loop with a global `fmatch`)
— add a pure Perl rule via `addrule()` after `loadRules()`, using template **T3** (`chorus-templates.md`).

> ⚠️ **`$SELF` (YAML EFFET) vs `$agent` (pure Perl addrule()):**
> | Context | Correct variable | Reason |
> |---|---|---|
> | YAML EFFET | **`$SELF`** | `$agent` is out of scope in the Engine eval → `Global symbol` crash |
> | `_APPLY` in `addrule()` | **`$agent` (closure)** | `$SELF` is the rule-Frame, not the Engine |
>
> - In a **`.yml` file** → always `$SELF->solved()`, `$SELF->cut()`, etc.
> - In a **pure Perl `addrule()`** → capture `$agent` as a closure, never `$SELF`.

---

## Phase 4 — Generate `Expert.pm`

Create `$SANDBOX/lib/<Namespace>/Expert.pm` from template **T4** (`chorus-templates.md`).

**Substitutions:** one `use` + one `->build()` per agent in `#+PIPELINE_POS` order.
Force `$xprt->{_MAX_ITER}` after `new()` (known bug: `new()` ignores its arguments).
Document BOARD inter-agent keys in `index.org` if agents communicate via BOARD slots.

---

## Phase 5 — Generate `run.pl`

Create `$SANDBOX/run.pl` from template **T5** (`chorus-templates.md`).

**Substitutions:**
- `<Namespace>` ← from `index.org`
- `@slots_resultat_display` ← result slots from the pipeline KB (statut_conformite, raison_non_conformite, motif_refus, besoin_*, etc.)
- `@pipeline_def` ← one entry per agent: `[ label, slot_ciblage, slot_resultat_ok ]` from `index.org` pipeline table

**Rule:** `run.pl` contains **no hardcoded data** — all project input comes from the JSON argument.

---

## Phase 6 — Execution and report

Run the pipeline:

```bash
perl $SANDBOX/run.pl $SANDBOX/projet.json
```

Capture the output. If Perl errors occur:
- `loadRules` error → check the YAML files (syntax, indentation)
- `Can't locate` error → check `use lib` and the namespace
- `FAILED/TIMEOUT` pipeline → check the termination rule

**Display the complete verbatim output** in a code block — always, without
summarizing or rephrasing in its place. This is the main report; never replace it
with a tabular summary.

After the verbatim output, note briefly (optional):
- `NON_CONFORME` elements with their reason if `ref_corpus` is absent
- `(non traité)` elements → targeting slot probably missing from the Feed
- Discrepancies with `_resultats_attendus` in the project file (if present)

---

## Phase 7 — Final verification *(post-generation only)*

> ⚠️ This checklist applies **only after generation** of Phases 1–5.
> Do not run it on the fast path (infrastructure already present).

- [ ] `Feed.pm`: agent 1 targeting slot present in `%SLOTS_REQUIS`
- [ ] `Feed.pm`: mandatory slot validation covers all element types in the project
- [ ] `Feed.pm`: unknown types → `warn + next` (not `die`) — safety net for mixed-sandbox JSON
- [ ] `Expert.pm`: `register()` order = `#+PIPELINE_POS` order
- [ ] `Expert.pm`: `$xprt->{_MAX_ITER}` forced **after** `new()` (known bug: `new()` ignores its arguments)
- [ ] `run.pl`: `../../Engine/lib` path correct from the sandbox
- [ ] `run.pl`: no hardcoded data
- [ ] Report: no unexpected `(non traité)` elements
- [ ] `_MAX_CYCLES`: value calibrated to the actual expected Frame volume.
      Heuristic: `N_frames × N_règles_total × N_agents × 10 < _MAX_CYCLES`.
      In `run.pl`: compute from `scalar(@elements)` and pass via `Expert->run(max_cycles => ...)`.
      Never leave the default value (`10_000`) for a production pipeline.
- [ ] Termination agent: `solved()` called on `$agent` (closure) in `addrule()`, never on `$SELF`.
      In a YAML EFFET → `$SELF->solved()`. In a pure Perl `addrule()` → `$agent->solved()` (captured as closure).
      ⛔ **Never code a termination via global `fmatch` in a YAML** → guaranteed infinite loop.
- [ ] If `reorder()` is used: the sort function consults `_PREMISSES` — consistent with the YAML files
- [ ] If `_LOCK_UNTIL_STABLE` is enabled: the agent may be skipped — verify this is the intended behaviour
- [ ] BOARD: inter-agent keys are documented in `index.org`
- [ ] **YAML — conditional EFFET without `else`**: if the `if` modifies nothing and the rule returns `1`,
      the engine loops until `_MAX_CYCLES` (warning). Check every YAML whose EFFET
      contains an `if` without `else` → return `0` when no slot is modified:
      `if (...) { ...; return 1 } 0`

---

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
