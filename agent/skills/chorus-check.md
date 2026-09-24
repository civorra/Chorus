# Skill — chorus-check

> Trigger: `chorus-check <sandbox-name> <fichier-project> [--all] [--explain] [--summary]`
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
>
> **Single responsibility: validate a project against the knowledge base.**
> The project file is **runtime input data** — it does not influence
> infrastructure generation. Two `chorus-check` runs on the same sandbox
> with different projects share exactly the same infrastructure.
>
> Prerequisite: `chorus-feed <sandbox-name>` must have been run beforehand
> (KB org + YAML present in the sandbox).


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

- `$SANDBOX/agent/.kb-hash` **absent** → the infrastructure predates hash tracking
  → treat as stale → **FULL PATH** (forced regeneration)
- `$SANDBOX/agent/.kb-hash` **present**, content **identical** to current hash
  → **FAST PATH**: go directly to Phase 6 (single project) or Phase 6-all (`--all`).
  Do not load `chorus-engine.md`.
  Do not read `index.org`. Do not read agent KBs. Do not generate anything.
- `$SANDBOX/agent/.kb-hash` **present**, content **differs** → KB was enriched
  since last generation → **FULL PATH** (forced regeneration, no user prompt needed)

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

Then execute Phases 0, 1–5, 6, 7 in order.


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
> **Incident (2026-09-21, sandbox `05-cyber-sec-ANSSI-PG-083+RGS_v-2-0_B2-KB-OPTIM-3`):**
> `Feed.pm` written with the stripped-suffix convention (`generateur_alea_ref => 'generateur_alea'`)
> while `R02-check-generation-locale.yml`/`R03-check-generation-centralisee.yml`
> called `$f->get('generateur_alea_ref qualite_alea')` (suffix kept, matching
> the KB org `Slot Dictionary`). Result: `conforme_generation` stayed `undef`
> forever on any element carrying `generateur_alea_ref`/`algorithme_ref`, which
> in turn blocked `R14`'s termination `CONDITION` — a silent infinite loop
> indistinguishable, from the outside, from a `_MAX_CYCLES` sizing problem.
> Found only by bisecting a hung `chorus_process` down to individual frame state.


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


## Phase 5.5 — Record KB hash *(full path only, after Phases 1–5)*

Once all infrastructure files have been generated successfully, record the
current KB fingerprint so that the next `chorus-check` can detect staleness:

```bash
sha256sum $SANDBOX/agent/chorus/*.org > $SANDBOX/agent/.kb-hash
```

This file is **never committed** (local artefact, like `sessions/`).
It is invalidated (deleted) by `chorus-feed` at the end of each run.


## Phase 6 — Execution and report

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
                  json_path:  "$SANDBOX/project.json",
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

Run the pipeline via the generated `run.pl`:

```bash
perl $SANDBOX/run.pl $SANDBOX/project.json
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

> ⚠️ **Language:** this block (section heading + field labels) must be rendered
> in the **corpus language** (`#+CORPUS_LANG` in `index.org`, or inferred from
> corpus content — see `chorus-engine.md § Canonical Language Rule`), exactly
> like every other artefact in the sandbox. The French labels below are the
> **default illustration** for a French-corpus sandbox; for an English-corpus
> sandbox, render the English equivalent shown beneath it. Do not mix languages
> within a single generated file.

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

   > **Incident (2026-09-24, sandbox `09b-ANSSI-PG-083_MULTI-SOURCES`):** before
   > `_rule_trace` existed, an earlier single-scalar `_rule_id`/`_corpus_ref` design
   > was tried — each rule overwrote the previous rule's reference on the same
   > Frame. Aggregation rules (`publish-qualite-alea-algo`, `publish-statut-cle`, …)
   > always run last in their pipeline, so their generic
   > `CORPUS: (agrégation — pas de règle nommée spécifique)` header systematically
   > overwrote and hid the specific `RègleArchiGénAléa.3`/etc. reference from the
   > `check-*` rule that actually computed the verdict — exactly the failure mode
   > `--explain` exists to prevent. `_rule_trace` (cumulative, never overwriting)
   > fixes this at the source; do not reintroduce a single-scalar traceability slot.

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

> ⚠️ **Language:** render this block in the **corpus language**, per the
> canonical rule in `chorus-engine.md § Canonical Language Rule`. The French
> template below is the default illustration; use the English equivalent
> beneath it for an English-corpus sandbox. Never mix languages within one file.

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

**Pourquoi cette règle s'applique (et pas une autre) :**
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

**Why this rule applies (and not another):**
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

> ⚠️ **Language:** render section headings, labels, and free text below in the
> **corpus language** (see canonical rule). French template is the default
> illustration; use the English equivalent for an English-corpus sandbox.

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

Write to: `$WORKSPACE/explain-<project-slug>-<NNN>.md` (`$WORKSPACE` =
`$SANDBOX/workspace/`, created if absent).
(`<project-slug>` derived from the project filename; `<NNN>` = next available
3-digit counter in `workspace/`, matching the numbering convention of
`import-report-*.org` / `audit-import-*.md`.)

For `--all` mode, produce a single consolidated file:
`$WORKSPACE/explain-all-<NNN>.md`, with per-project-file sub-sections.

Print: `[explain] Explanation file written → workspace/explain-<project-slug>-<NNN>.md (<N> element(s))`


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

Write `$WORKSPACE/synthese-<project-slug>-<NNN>.md` using this exact template
(`$WORKSPACE` = `$SANDBOX/workspace/`, created if absent).

> ⚠️ **Language:** render section headings, labels, and free text in the
> **corpus language** (see canonical rule). French template is the default
> illustration; use the English equivalent for an English-corpus sandbox.
> Never mix languages within one file. The filename itself
> (`synthese-<slug>-<NNN>.md`) keeps its French-derived name regardless of
> corpus language, for numbering-convention consistency with `explain-*`.

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
`workspace/explain-<project-slug>-<NNN>.md` pour le détail règle-par-règle de
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
`workspace/explain-<project-slug>-<NNN>.md` for the full rule-by-rule detail of
each element.*
```

Print: `[summary] Synthesis written → workspace/synthese-<project-slug>-<NNN>.md`

> **Consultation ergonomics:** this file is deliberately kept under one printed
> page. It never repeats the full YAML/corpus traceability of `--explain` —
> it only links to it. If both `--explain` and `--summary` are requested, generate
> `--explain` first (Phase E1–E4) so `--summary`'s classification (Phase S1) can
> reuse its per-element classification without recomputing it twice.


## Phase 6-all — `--all` mode (batch run)


> This phase is used **instead of Phase 6** when `--all` is present.
> Infrastructure detection (Step 0) is shared — the hash check runs once.
>
> **Orchestrator mode:** the current agent discovers project files and spawns
> one sub-agent per project file via `eca__spawn_agent`. Each sub-agent has its
> own IDE session and token — no timeout risk from extended thinking between runs
> or during output analysis.

### 6-all.1 Discover project files

```bash
ls $SANDBOX/project-*.json
```

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

```json
{
  "kb_hash": "<content of $SANDBOX/agent/.kb-hash — verbatim>",
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
- [ ] `_MAX_CYCLES`: value calibrated to the actual expected Frame volume **and rule chain depth**.
      Heuristic: `N_frames × N_rules_total × N_agents × D × 10 < _MAX_CYCLES`
      where **D** = depth of the longest intra-agent rule dependency chain
      (if R03 reads a slot written by R02, which reads a slot written by R01 → D = 3).
      A chain of depth D requires at least D cycles for a single Frame to converge.
      Estimate D by counting the longest `CONDITION: defined $p->{slot_from_Rxx}` chain in the KB.
      If no cross-rule dependencies → D = 1 (the formula reduces to the previous heuristic).
      ⚠️ **Dependency direction is independent of rule numbering:** a chain where R01 reads
      a slot written by R03 (which reads one written by R05) also gives D = 3 and requires
      the same number of cycles. Rule numbers reflect load order only.
      In `run.pl`: compute from `scalar(@elements)` and pass via `Expert->run(max_cycles => ...)`.
      Never leave the default value (`10_000`) for a production pipeline.
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
