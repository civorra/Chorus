# Skill — chorus-create-project

> Trigger: `chorus-create-project <sandbox-name> <output-file.json> [--batch] [--batch-seq] [--strategy iso|edges|cross|scale]`
> Agent: `architect`
>
> `<sandbox-name>`: sandbox containing a KB produced by `chorus-feed`
> `<output-file.json>`: name of the JSON file to create in `$SANDBOX/`
>                       (ignored in `--batch` and `--strategy` modes — filenames are fixed, see Phase 6)
> `--batch`: generate the full coverage suite (4 files) via sub-agents in one pass (see Phase 6.1).
>            Reduces main-agent generation volume but session stays open while waiting — risk on large sandboxes.
> `--batch-seq`: **timeout-safe** orchestration — Phase 0+1 once, writes KB context to
>                `.chorus-batch-ctx.md`, then displays 4 ready-to-run `--strategy` commands.
>                The user runs each command in a separate short session (see Phase 6.3).
> `--strategy <slug>`: generate exactly **one** file. Use manually, after `--batch-seq`,
>                      or to resume a failed `--batch`.
>                      Slugs: `iso` → `projet-rules-iso.json` · `edges` → `projet-edges.json`
>                             `cross` → `projet-cross.json`  · `scale` → `projet-scale.json`
>
> **Choosing between modes:**
> | Mode | Sessions | Timeout risk | User steps |
> |---|---|---|---|
> | `--batch` | 1 (long) | ⚠️ large sandboxes | aucune |
> | `--batch-seq` | 1 courte + 4 courtes | ✅ aucun | copier-coller 4 commandes |
> | `--strategy × 4` | 4 courtes | ✅ aucun | 4 commandes manuelles |
>
> **Single responsibility: create a valid project JSON file.**
> This skill reads the sandbox KB to infer types, slots, and thresholds,
> then generates a JSON file populated with both conforming AND non-conforming
> elements that explore the variety of the domain.
>
> Prerequisites: `chorus-feed <sandbox-name>` must have been run beforehand.
>
> **⚡ Timeout note:** `--batch` reduces generation volume but the main agent's session
> stays open while waiting for sub-agents — large sandboxes can still trigger `java.net.ConnectException`.
> Use **`--batch-seq`** for guaranteed safety: Phase 0+1 once, then 4 short independent sessions.

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

> **`type_element` — canonical name guard:** while reading the KB, verify that
> the element type slot is named **`type_element`** in the `Dictionnaire des slots` of
> each `<slug>.org`. Then, immediately after reading the directory tree of
> `$SANDBOX/rules/<slug>/`, read one representative `.yml` file from that agent and
> verify that its `FIND`/`CHERCHER` block uses `attribut: type_element` (not
> `element_type`, `type`, `kind`, or any variant).
> If a different name is found → **stop and report** before generating any JSON:
> ```
> ⛔ Slot name mismatch detected:
>    KB org uses '<found_org_name>' / YAML uses 'attribut: <found_yaml_name>'
>    but the project JSON template uses "type_element".
>    Fix: rename to `type_element` in the KB org (Slot dictionary), all YAML rules,
>    and any existing project JSON files before proceeding.
>    (See chorus-feed.md § Naming Conventions and chorus-engine-yaml.md § YAML Rules checklist)
> ```
> Do not generate a JSON that will silently produce 0 processed elements.

> **Why the immediate tool call:** Opus extended thinking after reading a dense KB file
> can be long enough to expire the IDE token. Reading the directory tree right after
> each read resets the token TTL and produces a useful rules inventory at no extra cost.
>
> **Rule:** threshold tables are in the `Helpers Perl` section of the org KBs —
> they are supposed to be identical to the code in `Helpers.pm`. Do not open `Helpers.pm`.
> ⚠️ **If any value looks suspicious** (e.g. an ep_min that seems too low for the zone,
> an R_min that doesn't match standard memory), flag it before generating elements and
> ask the user to verify org ↔ Helpers.pm parity — a divergence here corrupts all
> generated JSON files (see `chorus-feed.md` Helpers Checklist rule "Org KB parity").

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

## Phase 1.5 — Plan inter-element relationships

> **Skip condition:** if no KB org slot has a `Frame ref` or `→` annotation (see
> `chorus-engine-infra.md §3`), skip Phase 1.5 entirely.
> Print: `[Phase 1.5] No inter-frame relationships defined in KB — skipped.`

Unlike `chorus-import-project` (which *detects* relationships from a real document),
`chorus-create-project` *plans* relationships synthetically from the KB blueprint.
The goal is to produce a project JSON that exercises the inter-frame navigation paths
defined in the KB — not to represent a real project.

---

### Step 1.5-1 — Build the relationship blueprint

Scan KB org slot dictionaries for `Frame ref` / `→` entries (same algorithm as
`chorus-import-project` Phase 3.5-1).  Build:

```
blueprint = { source_type → { slot_name → target_type, ref_field → ref_field_name } }
```

If the blueprint is empty after scanning, skip Phase 1.5.

---

### Step 1.5-2 — Plan target elements

For each unique `target_type` in the blueprint that is **not already in the coverage
table**, add it now.  Minimum plan:

- **1–2 target elements per target type** (enough to test distinct link targets)
- Give them clear synthetic IDs that reflect their role: `<TTYPE>-TARGET-01`

> ⚠️ Target elements are **not test elements** — they are structural anchors.
> They still need valid mandatory slots (from their own KB catalogue entry).
> Run the same Phase 2 computation for them (conforming only — no KO variants needed
> for pure structural anchors unless the target type also has its own rules to test).

---

### Step 1.5-3 — Assign source elements to target elements

For each source element planned in Phase 1, assign it to a target element:

```
Assignment table:
| source_id        | ref_field    | target_id     |
|------------------|--------------|---------------|
| EL-OK-01         | <ref_field>  | TTYPE-01      |
| EL-KO-SEC-01     | <ref_field>  | TTYPE-01      |
| EL-OK-02         | <ref_field>  | TTYPE-02      |
```

**Assignment rules:**
- Spread source elements across available targets to demonstrate variety
- For `--strategy iso`: each test element gets its OWN target element
  (maximum isolation — each `*_ref` is unique, no shared state)
- For `--strategy scale`: target elements are shared (realistic bulk scenario)
- All source elements must have a `*_ref` entry — do not leave any unassigned

---

### Step 1.5-4 — Plan backward-compatibility elements

Add at least **1–2 elements per source type WITHOUT `*_ref`** to validate that rules
use the Option A fallback (direct slot) correctly.  These elements must carry the
direct fallback slot value explicitly in the JSON.

```
| source_id      | *_ref present? | purpose                          |
|----------------|----------------|----------------------------------|
| EL-NOLINK-01   | ❌ absent       | tests Option A fallback in rules |
| EL-OK-01       | ✅ present      | tests inter-frame navigation     |
```

> This ensures the test suite covers both the new pattern (link) and the legacy
> format (direct slot), confirming backward compatibility of every rule.

---

### Step 1.5 — Output: relationship plan

Record the plan for use in Phase 3:

```
[Phase 1.5] Inter-element relationship plan
  Blueprint entries : N source types → M target types
  Target elements added to coverage : N
  Source elements with *_ref : N
  Backward-compat elements (no *_ref) : N
```

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

> ⚠️ **Cross-cutting slots in conforming elements.** Some rules apply to ALL element
> types regardless of their primary role (no type-guard in `CONDITION`/`EXCEPTION`).
> For any element expected to be globally COMPLIANT, every slot checked by any such
> universal rule — across ALL agents of the pipeline — must satisfy its constraint,
> even if that slot is not relevant to the primary test case for this element.
>
> **Procedure:** before generating a conforming element, enumerate the "universal" rules
> of each agent (rules whose `CONDITION` contains no `type_element` guard) and verify
> every corresponding slot. Common examples: `moisture_content` (qualification, applies
> to all types), `fire_resistance_period` / `pb_thickness_mm` (fire, applies to all types).
>
> A conforming element that has `moisture_content: 0` or an undefined fire slot will be
> rejected by a universal rule even if it was designed to test a completely different criterion.
> Annotate the verification in `_note_calc` with the agent name and rule reference.

---

## Phase 3 — Generate the JSON

> **⚠️ Language rule — JSON user-facing values:** the technical structural keys (`"projet"`,
> `"elements"`, `"id"`, `"type_element"`, `"_note_calc"`) are invariant; but all **values** that
> carry domain meaning (`"description"` content, `"_note_calc"` annotations, any free-text string)
> must be written in the **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

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

### Element ordering in the JSON array

If Phase 1.5 identified inter-element relationships, generate elements in this order:

1. **Target elements first** (e.g. building frames, parent frames) — they have no `*_ref`
2. **Source elements with `*_ref`** — their `*_ref` fields reference IDs already in the array
3. **Backward-compat elements** (no `*_ref`, direct fallback slot) — last

This ordering ensures Feed.pm pass 1 creates targets before pass 2 resolves references.

### Slots to include

For each type, include in order:
1. `id` and `type_element` — always first
2. Mandatory slots (extracted from the `Catalogue des Frames` KB)
3. Targeting slot(s) for agent 1 (exact name in the KB: `Slots de ciblage` section)
4. **`*_ref` fields** (if Phase 1.5 assigned a target) — e.g. `"building_ref": "TTYPE-01"`
5. Optional slots relevant to the rules being exercised
6. ⛔ Do not include system slots (`_*`), nor slots set and computed by the agents
   (results, statuses, qualifications) — these slots are computed by the pipeline, not supplied in the project JSON

> **`*_ref` are OPTIONAL** — Feed.pm never requires them; rules use the Option A
> fallback when absent.  Backward-compat elements (Step 1.5-4) intentionally omit `*_ref`
> and supply the direct fallback slot instead.

### `_note_calc` annotation for inter-frame cases

For elements with `*_ref` fields, annotate the navigation path in `_note_calc`:

```json
"_note_calc": "building_ref → TTYPE-01 (height_m=6.0 read via inter-frame link). Wall R01: ..."
```

For backward-compat elements (no `*_ref`), annotate the fallback:

```json
"_note_calc": "No building_ref — Rule uses direct slot fallback (Option A). height_m=3.2 direct."
```

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
- [ ] ⛔ **`type_element` name cross-check:** verify that the JSON key used for the element type
      (`"type_element"`) matches exactly the `attribut:` name in the YAML `FIND`/`CHERCHER` blocks
      of the sandbox rules. A mismatch → SOLVED pipeline with 0 processed elements.
      If a mismatch is detected here at validation time → do not run `perl run.pl`;
      report the mismatch and correct the YAML rules or the JSON key first.
- [ ] All types are present in `%SLOTS_REQUIS` of `Feed.pm`
  (or verify in the `Catalogue des Frames` of the KB — equivalent source)
- [ ] No slot computed by the pipeline (result slots, qualification/evaluation status slots) is provided
- [ ] Non-conforming values actually cross the threshold (recompute if in doubt)
- [ ] ⚠️ **For CONFORMING cases: verify ALL criteria of ALL rules** that apply
  to the type — not just the primary criterion.
  An element may pass the first criterion and fail a secondary criterion of the same rule.
  For each type, list all criteria from the KB and check them one by one.
  Annotate each verified criterion in the `_note_calc` field of the JSON.
- [ ] ⚠️ **Universal rules (no type guard) — check ALL agents:** some rules apply to every
  element regardless of type (e.g. moisture check in Qualification, pb_thickness in Fire).
  For every conforming element, verify that ALL slots touched by universal rules across
  the full pipeline hold valid values. A `moisture_content: 0` or a missing fire slot
  silently breaks a conforming element even when its primary rule is unrelated.
  These checks span agent boundaries — enumerate universal rules from every agent KB.

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

## Phase 6 — Multi-file mode (`--batch`, `--batch-seq`, or `--strategy`)

> `--batch`: **orchestrator mode** — runs Phases 0+1, then spawns 4 sub-agents via
>            `eca__spawn_agent`. Reduces generation volume but main-agent session stays
>            open while waiting (timeout risk on large sandboxes — see header note).
>
> `--batch-seq`: **safe orchestrator mode** — runs Phases 0+1 once, writes the KB summary
>            to `.chorus-batch-ctx.md`, then displays 4 `--strategy` commands for the user
>            to run in separate sessions. **Guaranteed timeout-safe** (see Phase 6.3).
>
> `--strategy <slug>`: **single-file mode** — generates exactly one targeted file.
>            Use manually, after `--batch-seq`, or to resume a failed `--batch`.

### 6.1 `--batch` — Orchestrator workflow

#### Step 1 — Run Phases 0+1

Run Phase 0 in full (inventory + KB reading + keepalives) and Phase 1 (coverage table).
Do NOT generate any JSON here — stop after the coverage table is built.

#### Step 2 — Build the compact KB summary

Distil the KB into a self-contained block (≤ 60 lines).
This is the **only** KB context passed to sub-agents — do NOT pass raw org file content.

```
SANDBOX: <absolute path>
NAMESPACE: <Perl namespace>
AGENTS: <slug1>, <slug2>, …
TYPES: <type1>, <type2>, …
TARGETING_SLOT_AGENT1: <slot>

THRESHOLDS:
  <slot>: <value> [<unit>] — <source §>
  …

RULES:
  <agent_slug> R<NN> (<slot_written>) : <threshold or condition summary>
  …

COVERAGE TABLE:
  <type> | OK: N | KO: N | variants: …
  …
```

#### Step 3 — Spawn 4 sub-agents

Spawn 4 sub-agents via `eca__spawn_agent` (agent: `general`).
They can run in parallel if the IDE permits, otherwise spawn sequentially.

Use this task template for each, substituting `<slug>`, `<FILE>`, and `<PREFIX>`:

| slug | FILE | PREFIX |
|---|---|---|
| `iso` | `projet-rules-iso.json` | `I-` |
| `edges` | `projet-edges.json` | `E-` |
| `cross` | `projet-cross.json` | `X-` |
| `scale` | `projet-scale.json` | `S-` |

```
You are a chorus-create-project sub-agent.

STRATEGY: <slug>
TARGET FILE: <SANDBOX>/<FILE>
ID PREFIX: <PREFIX>  (prepend to every element id, e.g. <PREFIX>TYPE-OK-01)

━━━ KB SUMMARY (do NOT read any file — all context is here) ━━━
<compact KB summary from Step 2>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

STRATEGY GOAL:
  iso   → 1 OK + 1 KO per rule, one rule exercised per element  (≈ 2 × N_rules elements)
  edges → threshold−ε (KO) / threshold (OK) / threshold+ε for every continuous slot
  cross → elements that trigger multiple rules simultaneously (1–3 per rule pair)
  scale → ≥ 100 elements, all types × all classes/zones (termination stress test)

YOUR TASKS:
1. Compute element values from the threshold tables in the KB summary (never by intuition).
2. Generate <FILE> following Phase 3 conventions:
   - id: <PREFIX><TYPE>-<VARIANTE>-<NN>  (e.g. I-MUR-KO-R03-01)
   - include the targeting slot for agent 1, all mandatory slots
   - ⛔ do NOT include slots computed by the pipeline (result/status slots)
   - annotate non-obvious values in a _note_calc field
   - ⚠️ **For every CONFORMING element** (id contains `-OK-`): verify that ALL slots
     checked by universal rules across the FULL pipeline hold valid values — not just
     the slots relevant to the primary test case. Universal rules have no `type_element`
     guard and will reject any element whose cross-cutting slot is out of range, regardless
     of its intended role (e.g. `moisture_content` must be in [10%,18%] for ALL types,
     `fire_resistance_period` must meet REI requirements for ALL types, etc.).
     A conforming element with `moisture_content: 0` will be rejected even if it was
     designed to test a thermal rule. Annotate each cross-check in `_note_calc`.
3. Write the file using eca__write_file.
4. Validate:
   python3 -c "import json; json.load(open('<SANDBOX>/<FILE>')); print('JSON valide')"
5. If <SANDBOX>/run.pl exists:
   perl <SANDBOX>/run.pl <SANDBOX>/<FILE>
6. Return exactly this block:
   FILE: <SANDBOX>/<FILE>
   ELEMENTS: <N> CONFORME / <N> NON_CONFORME
   PIPELINE: SOLVED ✅  |  <error summary if failed>
```

#### Step 4 — Collect results and report

After all sub-agents complete, display the synthesis table:

```
projet-rules-iso  │ SOLVED ✅ │  N CONFORME │  N NON_CONFORME │  0 unprocessed
projet-edges      │ SOLVED ✅ │  N CONFORME │  N NON_CONFORME │  0 unprocessed
projet-cross      │ SOLVED ✅ │  N CONFORME │  N NON_CONFORME │  0 unprocessed
projet-scale      │ SOLVED ✅ │  N CONFORME │  N NON_CONFORME │  0 unprocessed
```

If a sub-agent failed → re-run with `chorus-create-project <sandbox> --strategy <slug>`
in a new session, pasting the compact KB summary as context to skip Phase 0.

### 6.2 `--strategy` — Single-file workflow

> This is also the internal workflow of each sub-agent spawned by `--batch`.

**Context detection (first action):** check whether `$SANDBOX/.chorus-batch-ctx.md` exists.
- If **yes** → read it; skip Phase 0+1 entirely (KB already summarised by `--batch-seq`).
- If **no** → run Phase 0+1 in full to build the KB summary before generating.

Using the KB summary and coverage table (from `.chorus-batch-ctx.md`, Phase 0+1, or passed by the orchestrator):

1. **Generate** — compute values from threshold tables; write elements following Phase 3
   conventions (id with strategy prefix, mandatory slots, no pipeline-computed slots,
   `_note_calc` annotations where useful).
2. **Validate** — run the Phase 4 checklist:
   ```bash
   python3 -c "import json; json.load(open('$SANDBOX/projet-<slug>.json')); print('JSON valide')"
   ```
3. **Execute** — if `run.pl` exists:
   ```bash
   perl $SANDBOX/run.pl $SANDBOX/projet-<slug>.json
   ```
   Check: `Pipeline : SOLVED ✅`, `Unprocessed: 0`, expected verdicts match.
   If an expected KO is CONFORME → apply the Phase 5 diagnosis.

### 6.3 `--batch-seq` — Safe sequential orchestration

> **Goal:** run Phase 0+1 once (the expensive part), persist the KB summary to disk,
> then hand off to 4 short independent `--strategy` sessions — each guaranteed to finish
> before any timeout can occur.

#### Step 1 — Run Phases 0+1

Run Phase 0 in full (inventory + KB reading + keepalives) and Phase 1 (coverage table).
Do NOT generate any JSON.

#### Step 2 — Build the compact KB summary

Distil the KB into the same self-contained block as `--batch` Step 2 (≤ 60 lines):

```
SANDBOX: <absolute path>
NAMESPACE: <Perl namespace>
AGENTS: <slug1>, <slug2>, …
TYPES: <type1>, <type2>, …
TARGETING_SLOT_AGENT1: <slot>

THRESHOLDS:
  <slot>: <value> [<unit>] — <source §>
  …

RULES:
  <agent_slug> R<NN> (<slot_written>) : <threshold or condition summary>
  …

COVERAGE TABLE:
  <type> | OK: N | KO: N | variants: …
  …
```

#### Step 3 — Write `.chorus-batch-ctx.md`

Write the compact KB summary to `$SANDBOX/.chorus-batch-ctx.md` using `eca__write_file`.

```markdown
<!-- chorus-batch-ctx — generated by chorus-create-project --batch-seq -->
<!-- Delete this file once all 4 strategies have been generated.       -->

<compact KB summary from Step 2>
```

This file is the shared context for all 4 subsequent `--strategy` sessions.
It avoids re-reading the full KB each time.

#### Step 4 — Display the 4 commands and close

Output the following block and **stop** — do not generate any JSON in this session:

```
✅ KB context written to $SANDBOX/.chorus-batch-ctx.md

Run each command below in a separate ECA session (in any order):

  chorus-create-project <sandbox-name> --strategy iso
  chorus-create-project <sandbox-name> --strategy edges
  chorus-create-project <sandbox-name> --strategy cross
  chorus-create-project <sandbox-name> --strategy scale

Each session will read .chorus-batch-ctx.md and skip Phase 0+1 automatically.
Delete .chorus-batch-ctx.md once all 4 files are generated.
```

> **Why stop here?** This session has done the expensive work (KB reading + summary).
> Each `--strategy` session will be short (generation only) — guaranteed timeout-safe.

### 6.4 ID prefix and strategy reference

| Strategy | File | ID prefix | Goal | Volume |
|---|---|---|---|---|
| `iso` | `projet-rules-iso.json` | `I-` | 1 OK + 1 KO per rule in isolation | ≈ 2 × N_rules |
| `edges` | `projet-edges.json` | `E-` | boundary values (threshold ±ε) | ≈ 2 × N_thresholds |
| `cross` | `projet-cross.json` | `X-` | multi-rule interactions | 1–3 per rule pair |
| `scale` | `projet-scale.json` | `S-` | all types × all classes/zones | ≥ 100 elements |

> **ID stability rule:** IDs must be stable across regenerations of the same file.
> Use deterministic conventions so that successive `chorus-check --all` runs
> can be compared diff-style. Never use random suffixes or timestamps.

### 6.5 Convergence criterion

The batch is **converged** when all four files satisfy:
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
