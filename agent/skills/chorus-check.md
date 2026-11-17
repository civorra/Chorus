# Skill — chorus-check

> **⚠️ Ce skill fait 2978 lignes — lire en entier (plusieurs appels `eca__read_file` avec `line_offset`) avant de créer un plan `eca__task`.**
> **Phases NON-OPTIONAL : Steps 5a–5o (qualité YAML/Perl) · Phase 4 rapport · `--explain`/`--summary` si demandés**
> **→ Créer un plan `eca__task` listant toutes les phases avant la Phase 0.**

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
# ⚠️ Path-independent: cd into the directory first so sha256sum records
# bare filenames, never the $SANDBOX absolute path — a sandbox rename must
# never invalidate this hash (see Phase 5.5 for the full rationale).
(cd $SANDBOX/agent/chorus && sha256sum *.org) > /tmp/kb-hash-org-current

# ENG-041 — YAML hash section: record per-rule-file hashes alongside org hashes.
# Use relative paths (rules/<slug>/<file>.yml) for path-independence.
(find $SANDBOX/rules -name "*.yml" | sort | \
  xargs sha256sum | sed "s|$SANDBOX/||") > /tmp/kb-hash-yaml-current

# Combine into a single current snapshot (org section + YAML section)
cp /tmp/kb-hash-org-current /tmp/kb-hash-current
echo "# rules" >> /tmp/kb-hash-current
cat /tmp/kb-hash-yaml-current >> /tmp/kb-hash-current
```

- `$SANDBOX/agent/.kb-hash` **absent** → predates hash tracking → **FULL PATH**
- `$SANDBOX/agent/.kb-hash` matches (`diff -q /tmp/kb-hash-current $SANDBOX/agent/.kb-hash`
  — both path-independent, reliable byte-for-byte comparison regardless of sandbox
  rename) AND `$SANDBOX/agent/.template-hash` matches
  → **FAST PATH**: go directly to Phase 6. Do not load `chorus-engine.md`,
  do not read `index.org`, do not read agent KBs, do not generate anything.
- `$SANDBOX/agent/.kb-hash` **differs**:
  - Determine *which section* changed before choosing the action:

    ```bash
    # Extract org section of stored hash (lines before "# rules" marker)
    grep -B9999 "^# rules" $SANDBOX/agent/.kb-hash | grep -v "^# rules" \
      > /tmp/kb-hash-org-stored 2>/dev/null || cp $SANDBOX/agent/.kb-hash /tmp/kb-hash-org-stored

    # Compare org sections only
    diff -q /tmp/kb-hash-org-current /tmp/kb-hash-org-stored
    ```

  - **Org section changed** (KB enriched by `chorus-feed`) → **FULL PATH** (silent, no
    prompt — this is the normal enrichment case).
  - **Org section unchanged, YAML section changed** → **FULL PATH** + ⚠️ desync warning:
    ```
    ⚠️  KB org ↔ YAML desync detected (ENG-041)
        .org files are unchanged, but YAML rule files have changed since the last
        .kb-hash snapshot. This indicates that chorus-fix Bucket B, chorus-check
        Phase 1.5 fixup, or a direct YAML edit modified rules without updating the
        corresponding Rule Catalog entries in agent/chorus/<slug>.org.

        Modified rule files:
          <diff output of YAML section — list of changed .yml files>

        Action required: review and update the Rule Catalog in agent/chorus/<slug>.org
        for every modified rule before this run completes — see AGENTS.md § KB org ↔ YAML sync.
    ```
    Proceed with FULL PATH regeneration regardless (the infrastructure may be stale).
  - **Pre-ENG-041 format** (no `# rules` marker in stored `.kb-hash`): treat as org-section
    mismatch → FULL PATH silently (Phase 5.5 will write the new extended format).
  > **⚠️ One-time migration note (commit 23ac4b8, 2026-10-28):** `.kb-hash` files generated
  > before this commit stored **absolute paths** (`sha256sum $SANDBOX/agent/chorus/*.org`).
  > The current formula stores **bare filenames** (`cd … && sha256sum *.org`). The first
  > `chorus-check` run after the update will see a `diff -q` mismatch (format changed, not
  > KB content) → FULL PATH triggered once. Phase 5.5 writes the new bare-filename format
  > → all subsequent runs fast-path correctly. This is expected, not an error.
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

### Steps 5b–5o — `chorus-audit-rules` gate (mandatory, before Step 6, FULL PATH only)

> **ENG-068 / ENG-057:** the 14 individual scan routines previously inlined here
> (Steps 5b–5o, ~640 lines) have been fully delegated to `chorus-audit-rules`,
> which is the mandatory pre-`chorus-check` gate (ENG-057). `chorus-check` now
> verifies the gate status file rather than re-executing the scans.
>
> **All 14 pitfall categories** (PREMISSES-PERL-EXPR, FILTRE-NOT-STRING,
> FMATCH-UNFILTERED-GUARD, AGENT-MISUSE, CROSS-AGENT-WIRING, UNBOUNDED-AGGREGATE,
> DUPLICATE-TERMINAL, BOARD-SELF-REFIRING, UNGUARDED-TRACE-PUSH,
> FIXPOINT-TRAP-ELEMENTS, MULTI-BOARD-NO-CONDITION, PLAIN-SCALAR-TRUNCATED,
> HELPER-COLLISION, USE-UTF8-MISSING, WORST-VERDICT-INIT, MISSING-MOTIF,
> MISSING-RULE-TRACE, FIND-ATTRIBUT-DANGLING) are covered by
> `chorus-audit-rules.md § Phase 3`.

Verify `$SANDBOX/agent/.audit-rules-status` (written by `chorus-audit-rules` at end of every run):

```bash
# Format: <ISO-8601-timestamp> kb=<hash-prefix-8> red=<N> orange=<N>
cat $SANDBOX/agent/.audit-rules-status 2>/dev/null || echo "MISSING"
```

**Decision:**

- **File absent** → ⛔ **HARD STOP — `chorus-audit-rules` has not been run.**
  Run `chorus-audit-rules <sandbox>`. Resolve all 🔴 findings. Re-run until `red=0`.

- **File present, `red=0`** → gate passed → proceed to Step 6.

- **File present, `red=N` (N > 0)** → ⛔ **HARD STOP — N critical finding(s) unresolved.**
  Run `chorus-audit-rules <sandbox> --fix` for auto-correctable pitfalls.
  Resolve remaining 🔴 manually. Re-run until `red=0`.

- **File stale** (timestamp older than any `rules/**/*.yml` modification):
  → ⛔ **HARD STOP — YAML rules modified since last audit.**
  Re-run `chorus-audit-rules <sandbox>` to refresh the gate.

  ```bash
  # Staleness check: any output = stale
  find $SANDBOX/rules -name "*.yml" -newer $SANDBOX/agent/.audit-rules-status 2>/dev/null
  ```

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

> ⛔ **ENG-054 — `%VERDICT_SLOT` : paires explicites uniquement, jamais `map { $_ => 'X' }`.**
> Dans l'initialisation du hash `%VERDICT_SLOT`, Perl peut parser `{ $_ => '...' }` comme
> une hash reference plutôt qu'un code block quand plusieurs `map` s'enchaînent. Résultat :
> tous les types héritent silencieusement de la valeur du **premier** `map`, et les chaînes
> comme `'verdict_facades'` deviennent des **clés** supplémentaires dans le hash. `perl -c`
> passe sans erreur — le bug n'est visible qu'au runtime (compteur `Conformes: 2 / 11` au
> lieu de `9 / 11`). Toujours utiliser des paires explicites :
> ```perl
> # ⛔ CASSÉ (map ambigu)      map { $_ => 'verdict_facades' } qw(rideau lourde ...)
> # ✅ CORRECT (paires)       'rideau' => 'verdict_facades', 'lourde' => 'verdict_facades',
> ```

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
# 1. KB org hash — tracks changes to the KB org content
# ⛔ Path-independent by construction: cd into the directory first so
# sha256sum records bare filenames (e.g. "agent-fau.org"), never the
# $SANDBOX absolute path. A sandbox folder rename changes nothing in this
# file's content, so it must never be treated as a KB change — writing
# `sha256sum $SANDBOX/agent/chorus/*.org > ...` directly (full path recorded
# on every line) is the WRONG form: it silently invalidates `.kb-hash` the
# moment the sandbox is renamed, forcing a spurious full infrastructure
# regeneration with no actual KB change.
(cd $SANDBOX/agent/chorus && sha256sum *.org) > $SANDBOX/agent/.kb-hash

# 2. YAML rules hash — tracks changes to the YAML rule files (ENG-041)
# ⛔ Path-independent: use relative paths (rules/<slug>/<file>.yml) via sed.
# The "# rules" marker separates the two sections; Phase 0 uses it to
# distinguish org-section changes (KB enriched) from YAML-section changes
# (desync — rules modified without .org update).
echo "# rules" >> $SANDBOX/agent/.kb-hash
(find $SANDBOX/rules -name "*.yml" | sort | \
  xargs sha256sum | sed "s|$SANDBOX/||") >> $SANDBOX/agent/.kb-hash

# 3. Template hash — tracks changes to the infrastructure templates
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
| Both current | ✅ match (org + YAML) | ✅ match | **FAST PATH** — skip generation entirely |
| KB org changed | ❌ org section differs | any | **FULL PATH** — KB enriched, regenerate silently (no user prompt) |
| YAML changed, org stable | ❌ YAML section differs | any | **FULL PATH** + ⚠️ **desync warning** (ENG-041) — YAML rules modified without `.org` update |
| Template changed, KB stable | ✅ match | ❌ differs | **FULL PATH** — template updated; **display a summary to the user** before regenerating (unlike KB changes, a template change is an external dependency update invisible from the sandbox — the user must be aware) |
| `.kb-hash` absent | — | — | **FULL PATH** — predates hash tracking |
| `.kb-hash` pre-ENG-041 format | no `# rules` marker | any | **FULL PATH** — old format, Phase 5.5 rewrites with YAML section |
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
> `TODO.org § #A` as the motivating case: a `CHORUS_MAX_CYCLES`/`CHORUS_MAX_ITER`
> override added manually to a sandbox's `run.pl` instead of being
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
> the cited reason. This exact mistake was found and fixed in a `run.pl`: an
> element's reason cited a rule written by the 1st rule in the chain, but
> "last entry" wrongly attributed it to the 4th, unrelated rule.

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

> **This step runs only when `$fichier-project` is a synthetic test project
> located directly at `$SANDBOX/` root** — i.e. its resolved path matches
> `$SANDBOX/project-*.json` or `$SANDBOX/project-test-*.json`.
> It does **NOT** apply to production import projects located under
> `workspace/<entity>/` (e.g. `workspace/EU/project-import-*.json`).
> Those projects have their own run-report under `workspace/<entity>/reports/`
> and are not part of the convergence-badge tracking shown in the Tests tab.
>
> **ENG-038 (2026-11-11):** restriction clarified — previously the step header
> only said "not in `--all` mode", which was ambiguous for per-entity import
> projects. Rule: if `dirname($fichier-project) != $SANDBOX`, skip Phase 6.3.
>
> **This step runs after every single-project `chorus-check` invocation**
> (Phase 6A or 6B) on a root-level test project — not in `--all` mode
> (Phase 6-all.6 writes the file wholesale for all projects; this step is
> redundant there).
>
> **Purpose:** keep the webapp Tests-tab convergence badges accurate after
> a single-project run, without requiring a full `--all` cycle.
> Synergy with WEB-021: writing this file triggers an immediate SSE `refresh`
> event in the webapp terminal, updating the Tests tab mid-session.

**Algorithm:**

```
1. Read $SANDBOX/agent/.kb-hash                           → kb_hash_current
2. sha256sum $SANDBOX/project-*.json | awk '{print $1}' | sha256sum | awk '{print $1}'   → proj_hash_current
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
## Option `--summary` — Consultation-friendly synthesis document

> **⚠️ These options are documented in `chorus-check-report.md` (ENG-068 sub-skill).**
>
> When `--explain`, `--summary`, or `--from-report` is present, load the sub-skill
> **before consuming Phase 6 output:**
>
> ```
> eca__read_file("$ENGINE/agent/skills/chorus-check-report.md")
> ```
>
> `chorus-check-report.md` contains:
> - `## Option --explain` (Phases E0–E4) — per-element non-conformity explanation file
> - `## Option --summary` (Phases S1–S2) — one-page consultation synthesis
> - `## Option --from-report` (Phases FR0–FR1) — pipeline-free mode from existing run-report
>
> ⛔ **Never skip this loading step** when a report flag is present — the Phase L0
> `$REPORT_LANG` resolution (below) feeds directly into these report-generation phases.

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
       Priority order for the expected verdict of each element:
       1. `expected_verdict` field in the project JSON (set by chorus-create-project — ENG-036)
          — covers elements whose id does NOT follow -OK-/-KO- (e.g. boundary BELOW/ABOVE,
          PROT/PD suffix, _note_calc-derived). Read by loading the project JSON alongside
          the run output:
          ```python
          import json
          proj = json.load(open('<SANDBOX>/<FILE>'))
          ev_map = {e['id']: e.get('expected_verdict') for e in proj.get('elements', proj if isinstance(proj, list) else [])}
          ```
       2. Fallback when `expected_verdict` absent:
          • id contains "-OK-" or "-ok-" → expected CONFORME
          • id contains "-KO-" or "-ko-" → expected NON_CONFORME
       3. Also check "_resultats_attendus" in the JSON if present (legacy convention).
       An element with no expected verdict from any source → not counted as a discordance.
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
> breaks the webapp's stale-detection permanently — incident confirmed in practice).
>
> **Verification before writing:** confirm the first line's hash token matches
> `sha256sum` of the actual first-listed file in `agent/.kb-hash` — do not
> write `.last-check-results.json` if this check was skipped.

```json
{
  "kb_hash": "<content of $SANDBOX/agent/.kb-hash — verbatim, mechanically copied, see guard above>",
  "proj_hash": "<sha256sum $SANDBOX/project-*.json | awk '{print \$1}' | sha256sum | awk '{print \$1}'>",
  "timestamp": "<ISO-8601 UTC>",
  "rule_trace_gaps": N,
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
  "rule_trace_gaps": N,
  "converged": true
}
```

- `disc_detail` and `unproc_detail` may be empty arrays when counts are 0.
- `converged`: `true` only when all files are SOLVED, 0 discordances, 0 unprocessed.
- `rule_trace_gaps`: count of YAML rule files in `$SANDBOX/rules/` whose `ACTION` block
  does not publish `_rule_trace` (ENG-037). Computed once after the sub-agent loop using
  Steps 5b–5l output or a direct grep scan:
  ```bash
  rule_trace_gaps=$(find "$SANDBOX/rules" -name "*.yml" -exec grep -L "_rule_trace" {} \; 2>/dev/null | wc -l)
  ```
  `0` = all rules publish traceability. Read by the webapp to display a badge on step ①.
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
      — empirically (a chorus-check performance incident), this formula is
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

> **⚠️ This mode is documented in `chorus-check-report.md` (ENG-068 sub-skill).**
> Load `chorus-check-report.md` before executing this mode.
>
> `chorus-check-report.md` contains phases FR0–FR1 and all `--explain`/`--summary`
> report-generation logic. Loaded via `eca__read_file` when any report flag is present.
