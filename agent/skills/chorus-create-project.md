# Skill — chorus-create-project

> Trigger: `chorus-create-project <sandbox-name> <output-file.json> [--batch]`
> Agent: `architect`
>
> `<sandbox-name>`: sandbox containing a KB produced by `chorus-feed`
> `<output-file.json>`: name of the JSON file to create in `$SANDBOX/`
>                       (ignored in `--batch` mode — filenames are fixed, see Phase 6)
> `--batch`: generate the full coverage suite (4 files) instead of a single project
>
> **Single responsibility: create a valid project JSON file.**
> This skill reads the sandbox KB to infer types, slots, and thresholds,
> then generates a JSON file populated with both conforming AND non-conforming
> elements that explore the variety of the domain.
>
> Prerequisites: `chorus-feed <sandbox-name>` must have been run beforehand.
>
> ⚠️ **Sources to use — strict order:**
> 1. `$SANDBOX/agent/chorus/index.org` → Frame types, pipeline, namespace
> 2. `$SANDBOX/agent/chorus/<slug>.org` → mandatory slots, thresholds, helpers
> 3. An existing `projet-*.json` file in `$SANDBOX/` → reference format
>
> ⛔ **Never read** `Helpers.pm`, `Feed.pm`, `Agent/*.pm`, `Expert.pm`, `run.pl`
> to create a project. These files are derived from the org KBs — the canonical
> source is always the org KB.

---

## Phase 0 — Read the KB (single source)

### 0.0 Sandbox inventory (first tool call — token keepalive)

**Before reading any file**, read the directory tree $SANDBOX/` immediately.

This serves two purposes:
1. Acquires the full sandbox structure early (agents list, rules dirs, existing JSON files)
2. Ensures at least one tool call happens before any long reading+thinking cycle,
   keeping the IDE token active from the very start.

Use this inventory to:
- Confirm the list of `<slug>.org` files to read in 0.2
- Detect any existing `projet-*.json` file (for Phase 0.3)
- Know which `rules/<slug>/` directories exist (for the keepalive calls in 0.2)

### 0.1 Pipeline index

Read `$SANDBOX/agent/chorus/index.org`:
- Perl namespace of the project
- Ordered list of agents (slug, module, pos)
- Global slot dictionary (if present)

### 0.2 KB of each agent

For each agent, apply this two-step sequence:

1. **Read** `$SANDBOX/agent/chorus/<slug>.org` and extract:

| KB Section | What to extract |
|---|---|
| `Catalogue des Frames` | Element types + mandatory/optional slots per type |
| `Dictionnaire des slots` | Exact slot names, value types, valid domains |
| `Slots de ciblage` | Slot(s) that Feed must set for the agent to see the Frame |
| `Helpers Perl` (KB section) | Normative tables: thresholds, ranges, admitted classes |
| `Contraintes & Pitfalls` | Edge cases to cover in the project |

2. **Immediately after** (no thinking between the two calls): read the 
   directory tree $SANDBOX/rules/<slug>/ to list the rule files for this agent.

> **Why the immediate tool call:** Opus extended thinking after reading a dense KB file
> can be long enough to expire the IDE token. Reading the directory tree right after
> each read resets the token TTL and produces a useful rules inventory at no extra cost.
>
> **Rule:** threshold tables are in the `Helpers Perl` section of the org KBs —
> they are identical to the code in `Helpers.pm`. Do not open `Helpers.pm`.

### 0.3 Reference format

If a `projet-*.json` file exists in `$SANDBOX/`, read its first 30 lines
to confirm the JSON format (keys `projet`, `description`, `elements`, fields `id`, `type_element`).
Do not read individual elements — types and slots are in the KB.

---

## Coverage strategies

When generating one or more project files, use the following four angles to
maximise the chance of exposing gaps in the YAML rules:

| Project file | Goal | Typical content |
|---|---|---|
| `projet-rules-iso.json` | Test each rule in isolation | 1 OK + 1 KO per rule R01, R02 … — one rule exercised per element |
| `projet-edges.json` | Stress boundary values | value = threshold (OK) and threshold − ε / threshold + ε (KO) for every continuous slot |
| `projet-cross.json` | Expose inter-rule interactions | elements that trigger R01 AND R02 simultaneously; conflict cases |
| `projet-scale.json` | Calibrate `_MAX_CYCLES` | ≥ 100 elements, all types, all classes — stress test for the termination agent |

> **ID stability rule:** IDs must be stable across regenerations of the same project file.
> Use deterministic conventions (`<TYPE>-<VARIANTE>-<NN>`) so that successive
> `chorus-check --all` runs can be compared diff-style.
> Never use random suffixes or timestamps in project IDs.

---

## Phase 1 — Plan the coverage

Build a coverage table before generating any element:

| Type | Conforming cases | Non-conforming cases | Variants |
|---|---|---|---|
| `<type_1>` | N | N | zones, classes, sections... |
| `<type_2>` | N | N | ... |

**Minimum coverage rules:**
- ✅ At least **2 conforming elements** per type (different nominal values)
- ❌ At least **1 non-conforming element** per known rejection rule (§ corpus)
- 🔀 **Dimensional variety**: cover the extreme ranges of continuous slots
  (e.g. min/max values of normative ranges, admitted categories or classes)
- 📐 **Edge cases**: value exactly at the threshold (conforming) and just below (non-conforming)

**Target volume:** adapt to context. For a scaling test → ≥ 100 elements.
For functional validation → 10–30 elements, all types covered.

---

## Phase 2 — Compute values

For each element, compute values **from the KB tables** — never by intuition.

### Sample computations

Adapt the examples to the normative tables read from the sandbox KB.
For each rejection rule, extract the threshold and compute a value that crosses
the threshold in the correct direction.

> ⚠️ **Compute, don't guess.** For each non-conforming case, verify
> that the chosen value actually crosses the threshold in the correct direction.
> Annotate the computation in a `_note_calc` JSON field if useful.

---

## Phase 3 — Generate the JSON

### Mandatory structure

```json
{
  "projet": "<nom-sans-espaces>",
  "description": "<description concise — types, zones, objectif>",
  "elements": [
    {
      "id":           "<TYPE-VARIANTE-NN>",
      "type_element": "<type>",
      "<slot_1>":     <valeur>,
      "<slot_2>":     <valeur>
    }
  ]
}
```

### `id` naming convention

```
<TYPE>-<VARIANTE>-<NN>
```

| Segment | Examples |
|---|---|
| `<TYPE>` | abbreviation of `type_element` (2–4 uppercase letters) |
| `<VARIANTE>` | `OK`, `KO-<CRITERE>`, significant dimensional values |
| `<NN>` | `01`, `02`... |

Generic examples: `EL-OK-01`, `EL-KO-SEC-01`, `EL-H2500-01`

### Slots to include

For each type, include in order:
1. `id` and `type_element` — always first
2. Mandatory slots (extracted from the `Catalogue des Frames` KB)
3. Targeting slot(s) for agent 1 (exact name in the KB: `Slots de ciblage` section)
4. Optional slots relevant to the rules being exercised
5. ⛔ Do not include system slots (`_*`), nor slots set and computed by the agents
   (results, statuses, qualifications) — these slots are computed by the pipeline, not supplied in the project JSON

### Slots set by Feed vs slots provided in the JSON

Some slots are computed/normalized by `Feed.pm` from a source slot;
they must **not** be provided explicitly if Feed computes them.

> **Rule:** if the KB documents a transformation `slot_source → slot_cible`,
> provide the **source** slot in the JSON, not the target slot.
> Identify these transformations from the `Normalisations` section of `index.org`
> — never from the thresholds or the logic of `Feed.pm`.

---

## Phase 4 — Validate the JSON before execution

Before running `perl run.pl`, perform a quick validation:

```bash
python3 -c "import json; json.load(open('<fichier.json>')); print('JSON valide')"
```

Check:
- [ ] JSON syntactically valid (no trailing comma, correct quotes)
- [ ] Each element has `id` and `type_element`
- [ ] All types are present in `%SLOTS_REQUIS` of `Feed.pm`
  (or verify in the `Catalogue des Frames` of the KB — equivalent source)
- [ ] No slot computed by the pipeline (result slots, qualification/evaluation status slots) is provided
- [ ] Non-conforming values actually cross the threshold (recompute if in doubt)
- [ ] ⚠️ **For CONFORMING cases: verify ALL criteria of ALL rules** that apply
  to the type — not just the primary criterion.
  An element may pass the first criterion and fail a secondary criterion of the same rule.
  For each type, list all criteria from the KB and check them one by one.
  Annotate each verified criterion in the `_note_calc` field of the JSON.

---

## Phase 5 — Execute and verify

```bash
perl $SANDBOX/run.pl $SANDBOX/<fichier.json>
```

Check:
- [ ] No Feed crash (unknown type, missing slot)
- [ ] `Unprocessed: 0` — every element must reach the final conformity status
- [ ] Expected KO elements are indeed `NON_CONFORME` with the correct reason
- [ ] Expected OK elements are indeed `CONFORME`
- [ ] `Pipeline : SOLVED ✅`

If an expected KO element is CONFORME → investigate:
1. Does the CONDITION of the targeted rule exclude this type? ← most common pitfall
2. Does the EXCEPTION short-circuit the rule? (slot already set by a preceding rule)
3. Does the provided value actually cross the threshold? (recompute)

---

## Phase 6 — Batch mode (`--batch` only)

> This phase replaces the single-file workflow when `--batch` is present.
> Instead of one project JSON, generate the full coverage suite in one pass.

### 6.1 Route by strategy

Using the coverage analysis from Phase 1 (coverage table already built),
generate four project files that each target a different angle:

| File | Strategy | Volume |
|---|---|---|
| `projet-rules-iso.json` | One element per rule: 1 OK + 1 KO | 2 × N_rules |
| `projet-edges.json` | Boundary values for every continuous slot | 2 × N_thresholds |
| `projet-cross.json` | Elements triggering multiple rules simultaneously | 1–3 per rule pair |
| `projet-scale.json` | All types × all classes/zones — full volume stress test | ≥ 100 elements |

### 6.2 ID prefix convention

To keep each file self-contained and diff-friendly, prefix element IDs with
a one-letter code reflecting the strategy:

| File | ID prefix |
|---|---|
| `projet-rules-iso.json` | `I-` (isolated) |
| `projet-edges.json` | `E-` (edge) |
| `projet-cross.json` | `X-` (cross) |
| `projet-scale.json` | `S-` (scale) |

Example: `I-MUR-KO-R03-01`, `E-POT-OK-SLEND-01`, `X-MUR-KO-R01R04-01`, `S-OSS-OK-C24-01`

### 6.3 Validation and execution

For each generated file, run the validation checklist from Phase 4 then execute:

```bash
python3 -c "import json; json.load(open('$SANDBOX/<file>.json')); print('JSON valide')"
perl $SANDBOX/run.pl $SANDBOX/<file>.json
```

Report a summary table after all four runs:

```
projet-rules-iso  │ SOLVED ✅ │  N CONFORME │  N NON_CONFORME │  0 unprocessed
projet-edges      │ SOLVED ✅ │  N CONFORME │  N NON_CONFORME │  0 unprocessed
projet-cross      │ SOLVED ✅ │  N CONFORME │  N NON_CONFORME │  0 unprocessed
projet-scale      │ SOLVED ✅ │  N CONFORME │  N NON_CONFORME │  0 unprocessed
```

If any file fails → apply the same diagnosis as Phase 5 before proceeding to the next.

### 6.4 Convergence criterion

The batch is considered **converged** when all four files satisfy:
- `Pipeline : SOLVED ✅`
- `Unprocessed: 0`
- No unexpected discordances (all expected OK are CONFORME, all expected KO are NON_CONFORME)

If the batch does not converge → run `chorus-strengthen <sandbox-name>` to identify
the rules to fix and the enrichment corpus to feed back to `chorus-feed --enrich`.

---

## Separation of responsibilities

| | `chorus-feed` | `chorus-create-project` | `chorus-check` |
|---|---|---|---|
| **Reads** | normative corpus | sandbox org KB | org KB + YAML |
| **Produces** | org KB, YAML, Helpers.pm | `projet-*.json` file | Feed.pm, Agent shells, Expert.pm, run.pl |
| **Source of thresholds** | corpus | org KB (Helpers Perl section) | org KB |
| **Never reads** | — | Helpers.pm, Feed.pm, *.pm | — |
