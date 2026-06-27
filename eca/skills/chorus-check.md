# Skill — chorus-check

> Trigger: `chorus-check <sandbox-name> <fichier-projet> [--all]`
> Agent: `architect`
>
> `<sandbox-name>`: sandbox containing the KB and YAML rules (produced by `chorus-feed`)
> `<fichier-projet>`: JSON file describing the project elements to validate,
>                      or data provided inline by the user
>                      (ignored when `--all` is present — all `projet-*.json` are used)
> `--all`: run all `projet-*.json` files found in `$SANDBOX/` and produce a synthesis report
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
sha256sum $SANDBOX/eca/agents/*.org > /tmp/kb-hash-current
```

- `$SANDBOX/eca/.kb-hash` **absent** → the infrastructure predates hash tracking
  → treat as stale → **FULL PATH** (forced regeneration)
- `$SANDBOX/eca/.kb-hash` **present**, content **identical** to current hash
  → **FAST PATH**: go directly to Phase 6 (single project) or Phase 6-all (`--all`).
  Do not load `chorus-engine.md`.
  Do not read `index.org`. Do not read agent KBs. Do not generate anything.
- `$SANDBOX/eca/.kb-hash` **present**, content **differs** → KB was enriched
  since last generation → **FULL PATH** (forced regeneration, no user prompt needed)

> **Manual forced regeneration**: the user explicitly asks to
> "regenerate" / "rebuild" the infrastructure → FULL PATH regardless of the hash.
> A second `chorus-check` with a different project is **never** a
> forced regeneration (hash comparison handles it automatically).

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
$SANDBOX/eca/agents/index.org     ← must exist
$SANDBOX/eca/agents/<slug>.org    ← at least one agent
$SANDBOX/rules/<slug>/            ← at least one YAML file per agent
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
      "type": "<element type>",
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

## Phase 5.5 — Record KB hash *(full path only, after Phases 1–5)*

Once all infrastructure files have been generated successfully, record the
current KB fingerprint so that the next `chorus-check` can detect staleness:

```bash
sha256sum $SANDBOX/eca/agents/*.org > $SANDBOX/eca/.kb-hash
```

This file is **never committed** (local artefact, like `sessions/`).
It is invalidated (deleted) by `chorus-feed` at the end of each run.

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
summarizing or rephrasing in its place. This is the primary report output.

### 6.1 — Post-verbatim structured report (mandatory)

After the verbatim output, always produce the following structured report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-check  <sandbox-name>  <fichier-projet>
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
    <id>  expected CONFORME   → got NON_CONFORME
    <id>  expected NON_CONF   → got CONFORME
    <id>  expected OK         → got KO
```

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

---

## Phase 6-all — `--all` mode (batch run)

> This phase is used **instead of Phase 6** when `--all` is present.
> Infrastructure detection (Step 0) is shared — the hash check runs once,
> then Phase 6-all loops over all project files without regenerating anything.

### 6-all.1 Discover project files

```bash
ls $SANDBOX/projet-*.json
```

If no `projet-*.json` file is found → stop and report:
```
⛔ No projet-*.json file found in $SANDBOX/.
   Run chorus-create-project <sandbox-name> --batch first.
```

### 6-all.2 Run each project

For each file discovered, execute:

```bash
perl $SANDBOX/run.pl $SANDBOX/<projet-file>.json 2>&1
```

Collect the full output of each run. Do **not** display verbatim output
per file at this stage — aggregate into the synthesis table below.

### 6-all.3 Synthesis table

After all runs, display:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-check --all  <sandbox-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Project file         │ Status      │ CONFORME │ NON_CONF │ Unproc │ Disc
  ─────────────────────┼─────────────┼──────────┼──────────┼────────┼─────
  projet-rules-iso     │ SOLVED ✅   │    N     │    N     │   0    │  0
  projet-edges         │ SOLVED ✅   │    N     │    N     │   0    │  0
  projet-cross         │ SOLVED ✅   │    N     │    N     │   0    │  0
  projet-scale         │ SOLVED ✅   │    N     │    N     │   0    │  0
  <other-projet>       │ FAILED ❌   │    N     │    N     │   N    │  N
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Overall: SOLVED ✅ / FAILED ❌     Discordances: N / N_total
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Column definitions:
- **Status**: `SOLVED ✅` if `Pipeline : SOLVED ✅` in output, `FAILED ❌` otherwise
- **CONFORME** / **NON_CONF**: count from the pipeline output
- **Unproc**: count of `(unprocessed)` elements
- **Disc**: discordances — elements whose actual result differs from `_resultats_attendus`
  in the JSON (if present), or from the expected result implied by the ID naming
  (`-OK-` → expected CONFORME, `-KO-` → expected NON_CONFORME)

### 6-all.4 Discordance detail

For each file with `Disc > 0`, list the discordant elements:

```
  projet-edges — 2 discordances:
    E-MUR-OK-SLEND-01  expected CONFORME   → got NON_CONFORME  (R03-slenderness)
    E-POT-KO-THICK-02  expected NON_CONF   → got CONFORME      (no rule fired)
```

For each file with `Unproc > 0`, list the unprocessed elements:

```
  projet-scale — 3 unprocessed:
    S-OSS-OK-C24-11    → targeting slot 'besoin_ossature' probably missing from Feed
```

### 6-all.5 Convergence verdict

```
CONVERGED ✅   — all projects SOLVED, 0 discordances, 0 unprocessed
NOT CONVERGED ❌ — N discordances and/or N unprocessed across M project files
```

If **NOT CONVERGED** → recommend:
```
Next step: chorus-strengthen <sandbox-name>
```

> **Fast path guarantee:** `--all` never regenerates the infrastructure.
> The `.kb-hash` check runs once at Step 0; each subsequent `perl run.pl` call
> is a pure runtime execution with no Perl file generation.
> Running 4 projects costs exactly 4 × `perl run.pl` — no overhead.

---

## Phase 7 — Final verification *(post-generation only)*

> ⚠️ This checklist applies **only after generation** of Phases 1–5.
> Do not run it on the fast path (infrastructure already present).

- [ ] `eca/.kb-hash` written after generation — contains `sha256sum` of all `eca/agents/*.org`
- [ ] `Feed.pm`: agent 1 targeting slot present in `%SLOTS_REQUIS`
- [ ] `Feed.pm`: mandatory slot validation covers all element types in the project
- [ ] `Feed.pm`: unknown types → `warn + next` (not `die`) — safety net for mixed-sandbox JSON
- [ ] `Expert.pm`: `register()` order = `#+PIPELINE_POS` order
- [ ] `Expert.pm`: `$xprt->{_MAX_ITER}` forced **after** `new()` (known bug: `new()` ignores its arguments)
- [ ] `run.pl`: `../../Engine/lib` path correct from the sandbox
- [ ] `run.pl`: no hardcoded data
- [ ] Report: no unexpected `(unprocessed)` elements
- [ ] `_MAX_CYCLES`: value calibrated to the actual expected Frame volume.
      Heuristic: `N_frames × N_rules_total × N_agents × 10 < _MAX_CYCLES`.
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
