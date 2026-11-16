# Skill — chorus-create-project

> **⚠️ Ce skill fait ~1291 lignes et 4 modes (`--batch` · `--batch-seq` · `--strategy` · défaut) — lire en entier avant tout plan.**
> **Phases NON-OPTIONAL : Phase 5 validation statique JSON (ENG-060 — ⛔ JAMAIS `perl run.pl`) · Phase README.org**
> **→ `chorus-check --all` est la SEULE étape qui valide les `expected_verdict` en exécutant le pipeline.**
> **→ Créer un plan `eca__task` adapté au mode détecté avant la Phase 0.**

> Trigger: `chorus-create-project <sandbox-name> <output-file.json> [--batch] [--batch-seq] [--strategy iso|edges|cross|scale] [--no-archive]`
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
>                      Slugs: `iso` → `project-rules-iso.json` · `edges` → `project-edges.json`
>                             `cross` → `project-cross.json`  · `scale` → `project-scale.json`
> `--no-archive`: skip the automatic archiving of the previous `project-<slug>.json`
>                 generation before overwrite (see Phase 0.4 bis). Default behaviour
>                 (no flag) always archives — use only for a deliberate no-trace overwrite.
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
> 3. An existing `project-*.json` file in `$SANDBOX/` → reference format
>
> ⛔ **Never read** `Helpers.pm`, `Feed.pm`, `Agent/*.pm`, `Expert.pm`, `run.pl`
> to create a project. These files are derived from the org KBs — the canonical
> source is always the org KB.

---

## Phase 0 — Read the KB (single source)

### 0.0 Sandbox inventory (first tool call — token keepalive)

**KB consistency pre-flight (before generating any JSON)**

If `scripts/validate-kb-consistency.py` is available in `$ENGINE/scripts/`,
run it silently on the sandbox:

```bash
python3 $ENGINE/scripts/validate-kb-consistency.py $SANDBOX --quiet
```

| Result | Action |
|---|---|
| ✅ 0 divergences | Proceed normally |
| ⚠️ divergences present | **Warn the operator** with the divergence list; continue only if the operator confirms or passes `--force`. Do not silently generate JSON over a known-inconsistent KB — values inferred from a mismatched KB may be wrong by construction. |

> Skip this pre-flight if `$ENGINE` is unavailable (standalone sandbox,
> no engine checkout). Never block generation for a missing script.

**Before reading any file**, read the directory tree $SANDBOX/` immediately.

This serves two purposes:
1. Acquires the full sandbox structure early (agents list, rules dirs, existing JSON files)
2. Ensures at least one tool call happens before any long reading+thinking cycle,
   keeping the IDE token active from the very start.

Use this inventory to:
- Confirm the list of `<slug>.org` files to read in 0.2
- Detect any existing `project-*.json` file (for Phase 0.3)
- Know which `rules/<slug>/` directories exist (for the keepalive calls in 0.2)

### 0.0-ctx — Context file check (`--strategy` only)

**Applicable only when `--strategy <slug>` is active** (i.e. the trigger contains `--strategy`).

Immediately after the sandbox inventory (0.0), before reading any `.org` file:

1. Check whether `$SANDBOX/.chorus-batch-ctx.md` exists.
2. If **yes** → read it immediately, then **jump directly to Phase 6.2**.
   Skip Phases 0.1, 0.2, 0.3, 1, 1.5, 2 entirely — the compact KB summary already
   contains all thresholds, types, rules, and coverage data needed for generation.
3. If **no** → continue with Phase 0.1 as normal (full KB reading).

> ⚠️ This check must happen **before Phase 0.1** — not at Phase 6.2.
> An agent that reads all `.org` files first and only then checks for `.chorus-batch-ctx.md`
> defeats the entire purpose of `--batch-seq` (timeout safety via short sessions).

---

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

> ⛔ **`type_element` VALUE guard — never use the Frame/concept name itself as a
> `type_element` value.** KB org files name their domain concepts generically in
> prose and section headings (e.g. `** sfr_component`, `** sar_element` — these
> are **Frame/category labels for documentation purposes only**). The actual
> `type_element` **value** every rule's `FIND.filtre` matches against is always
> a concrete domain identifier matching the pattern documented immediately
> below that heading (e.g. `*** type_element =~ /^FAU_/` → real values are
> `FAU_GEN.1`, `FAU_GEN.1.1`, `FAU_ADP_EXT.1`, …never the literal string
> `"sfr_component"` or `"sfr_element"`). Before writing any element's
> `type_element` value, re-read the KB org's own `*** type_element =~ /.../`
> or `*** type_element = "<value>"` line for that Frame section and use a
> value that **actually matches that pattern/equality** — never the section
> heading's own label.
> ```json
> // ⛔ WRONG — "sfr_component" is the KB's own Frame-category label, never a
> // real type_element value; no rule's filtre ever matches this literal string
> { "id": "E-FAU_STG.2-OK-01", "type_element": "sfr_component", "besoin_conformite": 1 }
>
> // ✅ CORRECT — a concrete domain identifier matching the KB's own
> // documented pattern (*** type_element =~ /^FAU_/)
> { "id": "E-FAU_STG.2-OK-01", "type_element": "FAU_STG.2", "besoin_conformite": 1, "dependances_declarees": "FAU_STG.1" }
> ```
> **Mandatory pre-write check:** for every `type_element` value about to be
> written, confirm it independently against **at least one** rule's own
> `FIND.filtre` regex/equality in `$SANDBOX/rules/<slug>/*.yml` — if no rule's
> filtre would ever match the literal value you are about to write, it is
> wrong, regardless of how plausible it looks next to the KB's own section
> headings.
> **Context:** a project file generated for a boundary-value coverage
> strategy used `type_element` values like `sfr_component`, `sfr_element`,
> `sar_component`, `sar_element`, `st` — literal Frame-category labels
> copied from KB org section headings — for all of its elements. Every
> agent's `FIND.filtre` regex targets real CC identifiers
> (`^FAU_[A-Z]+\.\d+$`, `^ASE_(INT|CCL|...)\.\d+$`, etc.) and never matches
> any of these literal category names — so every single element in the
> file was invisible to every rule in the pipeline, `pipeline_solved=False`,
> `n_conforme=0`. Not a crash, not a KB defect — a generation-time mistake
> that silently produced a structurally unprocessable project file. Caught
> only by comparing the file against other correctly-generated strategy
> files (which used real CC identifiers) and noticing the systematic
> absence of any recognisable domain identifier.

> **Enum-valued slots — rule-coverage guard (not just org-declared domain).** For any
> slot whose value is an enum/closed set (e.g. `mode_generation`, `usage`, `classe_*`) and
> that gates which rule fires via a `CONDITION`/`filtre` string match (`eq`, `=~ /.../`, a
> finite set of literals) — **before using a value for this slot in a generated element**,
> verify the value appears literally in at least one rule's `CONDITION`/`FIND`/`filtre` in
> `$SANDBOX/rules/<slug>/*.yml` for this agent. The KB org's `Dictionnaire des slots` may
> describe the domain in prose ("enum", a short list, or a reference to an external
> taxonomy) without every documented/plausible value necessarily being matched by an
> existing rule — using a semantically plausible but rule-uncovered value produces a
> Frame that **silently never reaches its aggregating/terminal slot**, not a crash or an
> `Unprocessed` entry (no rule's `CONDITION` is satisfied, so nothing fires for this slot
> at all — contrast with a slot that IS checked but found non-conforming, which produces
> a normal `NON_CONFORME` or `Unprocessed` outcome, both visible in the run report).
>
> **Why this is dangerous specifically in combination with a lifecycle/aggregation rule**
> (see note below, same phase): if the ungoverned value sits on a type also subject to a
> multi-slot aggregation rule, the missing aggregated slot keeps a downstream termination
> rule's `EXCEPTION` permanently true — **the pipeline loops until `_MAX_CYCLES`/timeout
> instead of failing cleanly or reporting the element as unprocessed.**
>
> **Context:** a scale-strategy generation populated `mode_generation` with
> values like `locale_derivee`, `importee`, `generee_par_tiers`, `recouvree`
> for several `cle_cryptographique` elements — plausible English/French
> paraphrases of real-world key-generation scenarios, but none of them
> matched any rule's `CONDITION` (`locale_aleatoire|locale_differentiee|echange` in R02,
> `derivation` in R04/R05, `centralisee_aleatoire` in R03). Combined with the
> lifecycle/aggregation pattern below, this caused the same silent infinite loop as the
> `type_element` guard above, on a seemingly unrelated enum-value mistake.
>
> **Verification procedure:** while reading each agent's `.yml` files (already being read
> for the `type_element` guard above), collect every literal value compared against each
> enum-valued slot across all `CONDITION`/`FIND`/`filtre` blocks of that agent — this is
> the **actual** accepted domain, more authoritative than the org's prose description for
> generation purposes. Use only these collected literal values when assigning that slot in
> generated elements. If you want to test an "unsupported value" scenario on purpose
> (e.g. to verify graceful degradation), use the `Unprocessed` section of Phase 4's
> checklist and flag the element explicitly as an intentional gap-coverage case in
> `_note_calc` — do not assume an unmatched value is harmless by default.

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

If a `project-*.json` file exists in `$SANDBOX/`, read its first 30 lines
to confirm the JSON format (keys `project`, `description`, `elements`, fields `id`, `type_element`).
Do not read individual elements — types and slots are in the KB.

---

### 0.4 bis — Archive before write

> **Applies to every mode** (`--strategy`, `--batch`, `--batch-seq` via sub-agents) and
> runs **immediately before** the target `project-<slug>.json` is written (Phase 3 / 6.1
> Step 3 / 6.2), for every strategy slug (`iso`, `edges`, `cross`, `scale`).
>
> **Goal:** preserve the previous generation of a `project-<slug>.json` file so that
> successive `chorus-check --all` runs can be compared diff-style — the "ID stability
> rule" documented in § Coverage strategies is useless if the file it should be diffed
> against no longer exists.

**Skip condition:** if `--no-archive` is present on the trigger, skip this step entirely
and overwrite the target file directly (explicit no-trace overwrite, non-default).

**Procedure (default, no flag):**

1. Check whether `$SANDBOX/project-<slug>.json` already exists.
   - If **absent** → nothing to archive, proceed directly to generation. This is the
     normal case on a sandbox's first generation — not an error, not a warning.
2. If **present**:
   a. Determine the next archive counter `<NNN>` for this slug: list
      `$SANDBOX/archive/<slug>/project-<slug>-*.json`, take the highest existing
      `<NNN>`, increment by 1 (3-digit, zero-padded). If `archive/<slug>/` does not
      exist yet, create it and start at `001`.
   b. Move the existing file to:
      ```
      $SANDBOX/archive/<slug>/project-<slug>-<NNN>-<YYYY-MM-DD>.json
      ```
      using today's date (`YYYY-MM-DD`).
   c. Append one line to `$SANDBOX/archive/<slug>/INDEX.md` (create the file with a
      header row if it does not exist yet):
      ```
      | NNN | date | n_rules | n_thresholds | pipeline | n_conforme | n_non_conforme | note |
      |-----|------|---------|--------------|----------|------------|----------------|------|
      | <NNN> | <YYYY-MM-DD> | <N> | <N> | <SOLVED/FAILED/not-run> | <N> | <N> | <short note> |
      ```
      Best-effort fields: `n_rules`/`n_thresholds` from the KB summary already read in
      Phase 0; `pipeline`/`n_conforme`/`n_non_conforme` from the archived file's own last
      known run report if available, otherwise `not-run`. Never block archiving on
      missing metrics — write `?` rather than skip the line.
3. Proceed to generate and write the new `project-<slug>.json` as usual (Phase 3 / 6.1 / 6.2).

**Non-destructive guarantee:** this step never deletes a file — it only moves (archives)
or appends (INDEX.md). A sandbox without a pre-existing `archive/` directory incurs no
behaviour change beyond its creation on first archive.

**Out of scope for `chorus-check --all`:** `$SANDBOX/archive/` must never be scanned by
`chorus-check --all`'s flat `project-*.json` discovery (see `chorus-check.md § 6-all.1`)
— same convention as `chorus-stress.md § --out`. Since archived files live one directory
level deeper (`archive/<slug>/...`), a flat `ls $SANDBOX/project-*.json` naturally excludes
them; no extra filtering logic is required, but do not weaken that discovery glob to a
recursive one without re-adding an explicit `archive/` exclusion.

---

## Coverage strategies

When generating one or more project files, use the following four angles to
maximise the chance of exposing gaps in the YAML rules:

| Project file | Goal | Typical content |
|---|---|---|
| `project-rules-iso.json` | Test each rule in isolation | 1 OK + 1 KO per rule R01, R02 … — one rule exercised per element |
| `project-edges.json` | Stress boundary values | value = threshold (OK) and threshold − ε / threshold + ε (KO) for every continuous slot |
| `project-cross.json` | Expose inter-rule interactions | elements that trigger R01 AND R02 simultaneously; conflict cases |
| `project-scale.json` | Calibrate `_MAX_CYCLES` | ≥ 100 elements, all types, all classes — stress test for the termination agent. ⛔ Do not calibrate `_MAX_CYCLES` from a volume-proportional formula (`N_frames × N_rules_total × D × 10` is retired, see `chorus-check.md`'s `_MAX_CYCLES` checklist entry — chorus-check 2026-10 perf incident) — use `run.pl`'s flat default (`200`) and only increase it if this specific project's bounded-wait/cross-rule chains genuinely need more, verified empirically. |

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

Scan the KB org slot dictionaries (already loaded in Phase 0) for slots whose
`type` column contains `Frame ref` or whose description contains `→ <target_type>`.
Build:

```
blueprint = { source_type → { slot_name → target_type, ref_field → slot_name + "_ref" } }
# e.g.:
#   buttressing_wall → { supports → external_wall,   ref_field: supports_ref }
#   external_wall    → { building → residential_building, ref_field: building_ref }
```

If the blueprint is empty after scanning all slug.org files, skip Phase 1.5.

---

### Step 1.5-2 — Plan target elements

> ⛔ **Distinguish Pattern A targets (structural, freely inventable) from
> Pattern B targets (`_ISA` prototype catalog, NEVER freely inventable).**
> `chorus-engine-infra.md §3.3`'s decision table distinguishes two kinds of
> `*_ref` link: Pattern A (`slot → Frame`, e.g. `wall_ref`, `pier_ref` — the
> target is an ordinary element you invent yourself, with its own
> `type_element` and plausible slots) and Pattern B (`_ISA` prototype,
> e.g. `masonry_unit_ref`, `ground_type_ref` — the target must match an
> EXISTING entry already produced by a `_build_*_catalog()`-equivalent
> Perl Helper in the sandbox's `lib/<Namespace>/Agent/<Slug>/Helpers.pm`,
> built from a normative table transcribed in the KB org's `* Perl Helpers`
> section).
>
> For a Pattern B target: **never invent a synthetic id and a plausible
> set of discriminator values** (e.g. `standard_family`, `condition`,
> `group`) independently — the catalog Helper (read its source, or read
> the KB org's `* Perl Helpers` entry documenting it) defines the EXACT
> set of valid discriminator-value combinations and the EXACT normative
> number attached to each. A `masonry_unit`/`ground_type`-style target
> element you write must reproduce one of those exact combinations,
> including the catalog's own internal vocabulary for `standard_family`
> (e.g. `'clay'`, not `'BS EN 771-1'` — check the Helper's actual keys,
> do not assume the corpus's own standard-number form is accepted as-is).
>
> **Context:** project files referenced `masonry_unit_ref` ids that matched
> no element in the same file — `Feed.pm` left the ref unresolved
> (`undef`), silently preventing the dependent rule from ever firing. The
> JSON elements that WERE eventually added used `standard_family: "BS EN
> 771-1"` (the corpus's own standard-number vocabulary) while the actual
> catalog Helper indexed entries by `'clay'` — a second mismatch, only
> caught because the consuming rule was later rewritten to do a genuine
> value-vs-threshold comparison instead of a label-vs-label one. Read the
> Helper's source (or its KB org documentation) for the literal
> discriminator values it uses — never infer them from the corpus's own
> prose vocabulary.


For each unique `target_type` in the blueprint that is **not already in the coverage
table**, add it now.  Minimum plan:

- **1–2 target elements per target type** (enough to test distinct link targets)
- Give them clear synthetic IDs that reflect their role: `<TTYPE>-TARGET-01`

> ⚠️ Target elements are **not test elements** — they are structural anchors.
> They still need valid mandatory slots (from their own KB catalogue entry).

> **Generic pitfall — declared tier/level vs. the set of items that must back it:**
> when an element declares a tier/level/grade value (any slot whose semantics is
> "this element claims to satisfy level X"), and a separate rule checks that level
> against a **set** of other declared items (not a single value) — e.g. "all items
> required for level X must be present in the declared list/count" — never assign
> the tier/level value independently from the accompanying set. Read the KB org's
> normative table (or the catalog Helper's source) for the EXACT list/count of
> items required at the declared level, and make the set match it exactly for a
> conforming element — or deliberately omit/shrink the set for a non-conforming
> one. **Never pick a plausible-looking subset and a plausible-looking level
> label independently** — the two must be cross-checked against the same
> normative table before writing the element, or the generated "conforming"
> element will in fact be rejected by the rule (the rule being correct, the
> fixture being wrong).
>
> **Also applies in reverse** — never write an `_note_calc` annotation asserting
> a property of an item (e.g. "no dependency/requirement attached to this item")
> without first confirming it against the catalog Helper's actual source (or its
> KB org transcription). An annotation that contradicts the catalog is a fixture
> bug, not a rule bug, and will surface as a false discordance in
> `chorus-strengthen` — always verify the catalog before writing such a claim,
> never assert it from memory or prose-level familiarity with the domain.
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

### Step 1.5-5 — Reference-target elements must carry their own valid content

> **Generic pitfall — applies to any sandbox/domain where one element type is
> referenced by another via a `*_ref`/`*_refs` link** (e.g. a "base" element
> pointed to by several dependent elements under test).

When an element is generated **solely to serve as the target of another
element's `*_ref`/`*_refs`** (Step 1.5-3), it still undergoes its own
independent rule evaluation — it is a Frame like any other, subject to
whatever rules apply to its own `type_element`. If that element is given
only the minimal slot(s) needed for the *referencing* element's rule under
test, and nothing else, its **own** verdict may come out non-conforming
by omission — even though its id follows the `-OK-`/conforming naming
convention, because no rule under test was actually targeting *it*.

**Symptom:** a `chorus-check`/`chorus-strengthen` run reports a discordance
on a reference-target element whose id signals "conforming" but whose own
mandatory-content rule(s) never received the slots they require — not
because any rule is wrong, but because the target element's own content
was never populated, only the link to it.

**Generation rule:** for every element assigned as a `*_ref`/`*_refs` target
(Step 1.5-3), after planning the slot(s) relevant to the *referencing*
element's rule under test, also pre-fill **all slots required by the
target element's own mandatory-content/completeness rule(s)** (identified
by reading the target type's own `.yml` rules in `$SANDBOX/rules/<slug>/`)
with a passing value — unless the target element's own non-conformance is
itself part of what is being tested (e.g. a dedicated "`*-KO-*` propagates
to referencing element" case, which should be planned explicitly as such,
not left as an accidental side effect).

Annotate in `_note_calc`:
`"_note_calc": "<ref-field> target for <source_id>'s R<NN> test; own mandatory-
content slots pre-filled to a passing value so this element's independent
verdict is CONFORME — see chorus-create-project.md § Step 1.5-5"`.

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

> ⚠️ **KO fixtures — CONDITION-satisfying slots mandatory (silent-rule trap).**
> A KO fixture that **omits a slot required by its target rule's `CONDITION`** will
> silently get the **wrong verdict**: the rule never fires → the element passes as CONFORME
> → the fixture appears as a Bucket B discordance in `chorus-strengthen` — but the gap is
> in the *fixture*, not in the rule. This is distinct from Bucket B (rule too permissive):
> here the rule IS correct, the fixture is just never reaching it.
>
> **Canonical example:**
> R13b targets `encapsulation_chiffrement` with:
> ```
> CONDITION: $f->{pq_vise} && defined $f->{type_produit} && $f->{type_produit} eq 'produit_final'
> ```
> Fixture `S-ENC-KO-02` had `pq_vise=1` but **no `type_produit`** → R13b silent →
> element CONFORME despite intended KO → appeared as Bucket B discordance after
> 3 sessions of chorus-fix/enrich, root cause only discovered by reading R13b's CONDITION.
>
> **⛔ Rule — KO fixtures:** for every KO test case, read the **full `CONDITION`** of its
> target rule and include **every slot** that appears in it with a value that **satisfies**
> the CONDITION (so the rule actually fires). Only the specific "KO" slot should carry
> a failing value. Optional slots required by CONDITION are **not optional in KO fixtures**.
>
> **Procedure (apply per KO element in Phase 2/3):**
> 1. Identify the target rule in `$SANDBOX/rules/<slug>/` (the rule this KO element tests).
> 2. Extract its full `CONDITION` clause.
> 3. For each slot in CONDITION: include it in the fixture with a value satisfying the CONDITION.
> 4. Annotate in `_note_calc`: `"<slot> inclus pour satisfaire CONDITION <rule-id>"`.
>
> **Detection in `chorus-strengthen`:** if a KO element gets CONFORME but no rule fired
> on it (no rule appears in the pipeline output for that element), suspect this trap before
> classifying as Bucket B — check the CONDITION of the expected target rule first.

> ⚠️ **Lifecycle/aggregation rules — multi-slot `CONDITION`, pipeline-blocking if never satisfied.**
> Some rules (typically the last rule of an agent, aggregating a verdict across several
> prior phases) have a `CONDITION` requiring **several `conforme_*`/status slots to be
> simultaneously defined** before writing the slot a termination rule (`TERMINAL: solved`,
> cf. `chorus-engine-yaml.md § TERMINAL`) is waiting for. Example pattern:
> ```yaml
> CONDITION: |
>   defined $f->{conforme_phase_a} && defined $f->{conforme_phase_b}
>   && defined $f->{conforme_phase_c} ...
> ACTION: |
>   ...
>   $f->set('statut_global', ...);   # ← a later TERMINAL rule's EXCEPTION waits for this
> ```
> **Why this matters for `--strategy iso`/`cross`:** these strategies deliberately populate
> only the slot(s) relevant to the ONE rule/interaction under test — by design, for maximum
> isolation (see Step 1.5-3). But if the element's type is also subject to a multi-slot
> aggregation rule like the one above, the aggregation `CONDITION` will **never** be
> satisfied (only 1 of N required `conforme_*` slots is ever set), so the aggregating
> slot (`statut_cle`/`statut_global`/...) is **never written** — and if a separate
> termination rule's `EXCEPTION` is waiting specifically for that slot to be defined on
> every Frame of this type (not just on the one currently tested), **the pipeline never
> reaches `TERMINAL: solved` and loops until `_MAX_CYCLES`/timeout** (CPU-bound infinite
> loop, no crash, no error message — the only visible symptom is a `run.pl` process that
> never returns). This is NOT a KB bug and NOT something `--strategy iso`/`cross` can
> avoid by construction — it must be compensated for explicitly at generation time.
>
> **Context:** project files each populated only 1 of 6 mandatory `conforme_*`
> slots on every `cle_cryptographique` element (by design, for rule isolation) — the aggregation
> rule `R14-publish-statut-cle.yml` never wrote `statut_cle` for any of them, and the
> separate termination rule `R15-terminate-pipeline.yml` (`EXCEPTION`: any
> `cle_cryptographique` Frame still missing `statut_cle`) never became false. `run.pl`
> looped silently, consuming CPU indefinitely, until killed manually from outside the
> pipeline (no self-reported failure).
>
> **Detection procedure (apply during Phase 0.2, per agent):**
> 1. For each `<slug>.org` read, identify the agent's terminal/aggregation rule(s) by
>    reading its `.yml` files in `$SANDBOX/rules/<slug>/` — look for a `CONDITION` that
>    references **more than one** `conforme_*`/phase-status slot via `&&`.
> 2. If found, note: (a) the full list of required slots, (b) the slot it writes once
>    satisfied, (c) whether any OTHER rule (same agent or a later one) has an
>    `EXCEPTION`/`FIND` depending on that written slot being defined for **every** Frame
>    of the relevant type (not just the one bound by its own `FIND`) — this is the
>    actual pipeline-blocking risk, not the aggregation rule itself.
> 3. Record this in the coverage table as a per-type annotation:
>    `⚠️ <type> requires full-lifecycle aggregation (<slug> R<NN>) — see Phase 2 note below.`
>
> **Generation procedure (apply in Phase 2/3, for `--strategy iso`/`cross`/`scale` only —
> `--strategy edges` rarely touches full-type elements this way, but verify if in doubt):**
> For every element of a type flagged above, **in addition to** the slot(s) relevant to
> the rule/interaction under test, pre-fill **all other slots required by the aggregation
> rule's `CONDITION`** with a neutral `CONFORME` (or equivalent passing) value — so the
> aggregation rule's `CONDITION` is satisfied and the aggregating slot gets written
> regardless of which single rule is actually under test. Annotate in `_note_calc`:
> `"_note_calc": "<slot_a>/<slot_b>/... pre-filled CONFORME (not under test) to satisfy
> <aggregation-rule-name> CONDITION and avoid termination-rule deadlock — see
> chorus-create-project.md § Lifecycle/aggregation rules"`.
> This does **not** compromise isolation of the rule actually under test: the targeted
> slot(s) still carry the OK/KO value being exercised, only the *other* mandatory slots
> of the same aggregation are padded to a passing value.
>
> **If regenerating an existing project file after this rule was added to the skill:**
> check every element of a flagged type for the missing pre-fill — a prior-generation
> file created before this detection procedure existed is likely to still be broken.

---

## Phase 3 — Generate the JSON

> **⚠️ Language rule — JSON user-facing values:** the technical structural keys (`"project"`,
> `"elements"`, `"id"`, `"type_element"`, `"_note_calc"`) are invariant; but all **values** that
> carry domain meaning (`"description"` content, `"_note_calc"` annotations, any free-text string)
> must be written in the **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

### Mandatory structure

```json
{
  "project": "<nom-sans-espaces>",
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
7. **`expected_verdict`** — mandatory on every element that has a testable verdict intention:
   - `id` contains `-OK-` (case-insensitive) → `"expected_verdict": "CONFORME"`
   - `id` contains `-KO-` (case-insensitive) → `"expected_verdict": "NON_CONFORME"`
   - For elements without `-OK-`/`-KO-` in the id (reference objects, boundary
     elements with BELOW/EXACT/ABOVE/PROT/PD suffixes), derive from `_note_calc`:
     - mentions `protected`, `CONFORME`, `AUTHORIZED`, `APPLIES` (without "NOT")
       → `"expected_verdict": "CONFORME"`
     - mentions `public_domain`, `NON_CONFORME`, `EXPIRED`, `NOT AUTHORIZED`,
       `DOES NOT APPLY` → `"expected_verdict": "NON_CONFORME"`
     - Ambiguous or reference-only elements (no derivable verdict) → omit `expected_verdict`
   > **Why:** `run.pl` (T5) and the webapp calculate `n_discordances` from
   > `expected_verdict`. Without this field, `chorus-check --all` always reports
   > 0 discordances regardless of real gaps → `chorus-strengthen` cannot classify
   > any gap. (ENG-036)

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

> **⚠️ Cross-test scenarios — pre-setting a guard slot:**
> When an element intentionally pre-sets a slot to trigger a rule's `EXCEPTION` guard
> (causing the rule to be skipped), **every slot that the skipped rule would normally
> write must also be provided manually in the JSON** — since the rule is bypassed,
> those slots will never be computed.
>
> Example: if rule R04 has `EXCEPTION: "defined $f->{mandatory}"` and its ACTION writes
> `article_source`, and you pre-set `mandatory: "OUI"` in the JSON to test the guard bypass,
> you must ALSO provide `article_source: "Article 5(1)"` in the JSON. Otherwise the slot
> is absent both at load time (triggering `Feed.pm` die) and post-run (never computed).
>
> **Procedure:** for each slot pre-set in a cross-test element, identify the rule(s)
> whose EXCEPTION guard that slot triggers, list all slots those rules write, and add
> them to the JSON element.

---

## Phase 4 — Validate the JSON before execution

**Validation statique obligatoire** (Phase 4 — avant de passer à `chorus-check`) :

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
- [ ] ⛔ **`type_element` VALUE cross-check (distinct from the name check above):** for
      every distinct `type_element` **value** used in the file, confirm it actually
      matches at least one rule's `FIND.filtre` regex/equality somewhere in
      `$SANDBOX/rules/*/*.yml` — not just that the slot name is correct, but that the
      literal value itself is one any rule would ever select. A value copied from a KB
      org section heading (Frame/category label, e.g. `sfr_component`, `sar_element`)
      rather than from that same section's own `*** type_element =~ /.../` pattern
      produces a file where every element is silently invisible to the whole pipeline —
      see `chorus-create-project.md` § "type_element VALUE guard" above for the full
      incident writeup. Quick mechanical check:
      ```bash
      # Every distinct type_element value in the JSON...
      python3 -c "import json; d=json.load(open('<fichier.json>')); print('\n'.join(sorted(set(e.get('type_element','') for e in (d if isinstance(d,list) else d.get('elements',d))))))" \
        | while read -r val; do
            grep -rq "$val" "$SANDBOX/rules/"*/*.yml \
              || echo "⚠️  '$val' matches no literal substring in any rule's FIND.filtre — verify it matches a regex pattern instead, or it is likely wrong"
          done
      ```
      (This substring check is a coarse first pass — regex-pattern values like `FAU_GEN.1`
      won't literally appear in a `filtre` written as `/^FAU_/`, so treat any flagged value
      as a prompt to manually verify against the agent's own `FIND.filtre`, not as a
      definitive verdict.)
- [ ] ⛔ **Business-slot name cross-check (generic — applies to every non-`type_element`
      slot, any domain):** for every element in the JSON, cross-check each of its
      business-data keys (everything except `id`, `type_element`, and any `_*`
      annotation field) against the `INPUTS` header of the rule(s) whose `CONDITION`/
      `FIND.filtre` targets that element's `type_element` value — the exact slot names
      a rule actually reads are listed there, one per line, as transcribed from the KB
      org's own `Dictionnaire des slots`/`Slot dictionary` table. A JSON key that does
      not appear in any targeting rule's `INPUTS` list is either (a) a typo/near-miss of
      a real slot name (the rule silently never sees it, a fixture reads as
      `(unprocessed)` or resolves via an unrelated rule/branch instead) or (b) a slot
      genuinely unused by any rule for this type (dead weight, harmless but worth
      removing). Unlike the `type_element` mismatches above, this class of error does
      **not** make the pipeline fail visibly — the element still gets processed (just
      by the wrong branch, or not fully), producing a **silently wrong verdict** that
      looks superficially plausible until manually traced back to the rule's own
      `INPUTS` header. This is the single hardest-to-detect fixture bug class; always
      run this check before trusting any "boundary"/"exactly at minimum" fixture.
      Quick mechanical check per type:
      ```bash
      # List every distinct business-slot key used across all elements of one type_element value...
      python3 -c "
      import json
      d = json.load(open('<fichier.json>'))
      elements = d if isinstance(d, list) else d.get('elements', d)
      target_type = '<type_element value>'
      keys = set()
      for e in elements:
          if e.get('type_element') == target_type:
              keys |= set(e.keys()) - {'id', 'type_element'} - {k for k in e if k.startswith('_')}
      print('\n'.join(sorted(keys)))
      "
      # ...then diff that list against the rule's own INPUTS header (read manually,
      # or grep the rule file's INPUTS comment block for each key — any JSON key with
      # zero occurrences in any targeting rule's INPUTS section is suspect):
      grep -c '<slot_name>' "$SANDBOX/rules/<agent-slug>/"*.yml
      ```
      **Incident (2026-11-06, sandbox `06-CC-3.1.5`):** `E-AGD-OK-01`/`I-EVAL-OK-14`
      carried `ope_secure_settings_described`, `ope_operational_modes_described`, and
      `ope_misuse_consequences_described` — none of which appear in
      `R06-agd-ope-content-complete.yml`'s actual 7-slot `INPUTS` list
      (`ope_secure_interface_usage_described`, `ope_operation_modes_described`, and no
      `ope_misuse_consequences_described` slot at all; `ope_security_parameters_described`
      was entirely missing from the fixture). The rule silently treated 2 of its 7
      required slots as absent → `agd_ope_content_complete='NO'` on a fixture intended
      as `-OK-`/exactly-at-minimum — initially misclassified as a rule-side
      "too strict" gap requiring a garde-fou/security-guard decision, when it was in
      fact a pure slot-naming typo, only found by manually diffing the fixture's keys
      against R06's own `INPUTS` header line by line.
- [ ] All types are present in `%SLOTS_REQUIS` of `Feed.pm`
  (or verify in the `Catalogue des Frames` of the KB — equivalent source).
  ⚠️ `%SLOTS_REQUIS` must contain **INPUT-REQUIRED slots only** — the targeting slot plus
  any project-data slot that no rule computes. For a type whose slots are all rule-computed,
  the entry must be `[qw(type_element)]`.
  ⛔ If `%SLOTS_REQUIS` contains output slots (written by rules), `Feed.pm` will die at
  load time because those slots are absent in any project generated by `chorus-create-project`.
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
- [ ] ⚠️ **Lifecycle/aggregation types flagged in Phase 0.2 (iso/cross/scale only):** for
  every element whose type was flagged as requiring full-lifecycle aggregation, confirm
  all non-tested mandatory slots of that aggregation are pre-filled with a passing value
  (see Phase 2 note above) — otherwise the aggregating slot is never written and a
  downstream termination rule may loop indefinitely instead of failing cleanly.

---

## Phase 5 — Validation statique finale (ENG-060)

> ⛔ **JAMAIS lancer `perl run.pl` ici — interdiction stricte (ENG-060).**
>
> `chorus-create-project` est un **générateur pur** (KB → JSON).
> L'exécution du pipeline et la détection de discordances sont la responsabilité
> exclusive de **`chorus-check`**.
>
> **Pourquoi cette interdiction :**
> - Un bug de règle YAML (boucle infinie, `_MAX_CYCLES`) planterait les sous-agents
>   sans diagnostic utile, déclenchant des corrections hors-scope (sur les JSON
>   générés plutôt que sur les règles).
> - `chorus-check --all` détecte les mêmes discordances avec plus de contexte
>   (`_rule_trace`, motifs, rapport complet).
> - Lancer le pipeline deux fois ne prouve rien de plus.
>
> ⛔ **Ne pas appeler `chorus-check`, `chorus-feed`, ni aucun autre skill.**
> ⛔ **Ne pas générer ni modifier `run.pl`, `Feed.pm`, `Expert.pm`, `Agent/*.pm`.**

**Checklist de validation statique** (complémentaire à Phase 4 — s'applique à tous les modes) :

- [ ] JSON syntaxiquement valide : `python3 -c "import json; json.load(open('<fichier.json>')); print('JSON valide')"`
- [ ] Chaque élément a `id` et `type_element`
- [ ] Chaque `type_element` reconnu dans le KB (`%SLOTS_REQUIS` / KB org)
- [ ] Convention `-OK-` / `-KO-` cohérente avec `expected_verdict` ∈ `{CONFORME, NON_CONFORME}`
- [ ] `expected_verdict` présent sur chaque élément avec un `id` contenant `-OK-` ou `-KO-`
- [ ] Pas de slots calculés par le pipeline inclus dans le JSON (résultats, verdicts)
- [ ] IDs uniques — pas de doublons dans le fichier

**Étape suivante obligatoire :**
```bash
chorus-check <sandbox-name> --all
```
C'est la seule étape qui exécute le pipeline et valide les `expected_verdict`.

---

## Phase 5b — ⛔ REMOVED (ENG-060) — Corrections post-pipeline

> ⛔ **Cette phase est supprimée (ENG-060).**
>
> Les corrections C1–C5 (catalog errors, `besoin_conformite`, naming, SAR dependency)
> dépendent toutes de la sortie de `perl run.pl` — ce qui viole l'interdiction
> d'exécuter le pipeline dans `chorus-create-project`.
>
> **Ce qui remplace C1–C5 :**
> - **C1 (catalog errors)** → détectées par `chorus-check --all` via `Unprocessed: N`
> - **C2 (`besoin_conformite`)** → à corriger manuellement dans le JSON généré si
>   signalé par `chorus-check --all`
> - **C3–C5 (naming conventions)** → les `Discordances > 0` détectées par
>   `chorus-check --all` guident `chorus-strengthen` pour diagnostiquer et corriger
>
> **Workflow correct :**
> ```
> chorus-create-project --batch   → génère 4 JSON + validation statique (Phase 5)
> chorus-check --all              → SEUL responsable de l'exécution pipeline
>                                   et de la détection de discordances
> chorus-strengthen               → si discordances > 0
> ```

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

#### Step 0-pre — ⛔ REMOVED (ENG-060)

> ~~ENG-049 `run.pl` pre-flight check~~ — supprimé (ENG-060).
> Les sous-agents ne lancent plus `perl run.pl` → le check d'existence de `run.pl`
> est inutile. Procéder directement à Step 0-bis.

#### Step 0-bis — Task planning

Call `eca__task` once before Step 1 to give the webapp terminal a live checklist (☐⏳☑):

```
eca__task(op="plan", tasks=[
  { subject: "Step 1 — KB reading (Phase 0+1)",    description: "Full KB inventory + coverage table" },
  { subject: "Step 2 — Compact KB summary",         description: "Distil KB into ≤ 60 lines for sub-agents" },
  { subject: "Step 3a — Generate iso",              description: "Sub-agent: project-rules-iso.json" },
  { subject: "Step 3b — Generate edges",            description: "Sub-agent: project-edges.json" },
  { subject: "Step 3c — Generate cross",            description: "Sub-agent: project-cross.json" },
  { subject: "Step 3d — Generate scale",            description: "Sub-agent: project-scale.json" },
  { subject: "Step 4 — Synthesis + cache update",   description: "Collect results + upsert .last-check-results.json" },
])
```

Mark each step `start` / `complete` as it executes. Steps 3a–3d may complete out of
order (parallel sub-agents) — mark them complete as each sub-agent returns its block.

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
| `iso` | `project-rules-iso.json` | `I-` |
| `edges` | `project-edges.json` | `E-` |
| `cross` | `project-cross.json` | `X-` |
| `scale` | `project-scale.json` | `S-` |

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

⛔ STRICT CONSTRAINTS (ENG-049 + ENG-060 — do NOT deviate):
   - NEVER call `chorus-check`, `chorus-feed`, or any other Chorus skill or command.
   - NEVER generate or modify `run.pl`, `Feed.pm`, `Expert.pm`, or any `Agent/*.pm` file.
   - NEVER run `perl run.pl` or any pipeline command (ENG-060).
   - Your ONLY responsibilities: generate <FILE>, validate JSON statically (Phase 5)
     if it already exists, return the result block. Nothing else.

YOUR TASKS:
0. **Archive before write** (unless `--no-archive` was passed to the orchestrator): if
   <SANDBOX>/<FILE> already exists, move it to
   <SANDBOX>/archive/<slug>/project-<slug>-<NNN>-<YYYY-MM-DD>.json (next 3-digit counter
   for this slug) and append a line to <SANDBOX>/archive/<slug>/INDEX.md. See
   `chorus-create-project.md § Phase 0.4 bis` for the exact procedure. Skip silently if
   <FILE> does not exist yet.
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
5. **Validation statique (ENG-060 — ⛔ JAMAIS lancer perl run.pl):**
   - Vérifier la syntaxe JSON (python3 -c "import json; json.load(open('...'))")
   - Vérifier que chaque `type_element` est reconnu dans le KB summary ci-dessus
   - Vérifier la cohérence `-OK-`/`-KO-` ↔ `expected_verdict`
   - ⛔ NE PAS lancer `perl run.pl` — NE PAS appeler `chorus-check` ni aucun autre skill
   - ⛔ NE PAS générer ni modifier `run.pl`, `Feed.pm`, `Expert.pm`, `Agent/*.pm`

6. Return exactly this block:
   FILE: <SANDBOX>/<FILE>
   ELEMENTS: <N total> (<N OK> expected CONFORME / <N KO> expected NON_CONFORME)
   VALIDATION: JSON ✅ | type_element ✅ | naming convention ✅
   (or flag any static validation failure with ⚠️ + detail)
   NEXT_STEP: chorus-check <sandbox-name> --all
```

#### Step 4 — Collect results and report

After all sub-agents complete, display the synthesis table (ENG-060 — no pipeline execution, no Corrections column) :

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-create-project --batch  <sandbox-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Strategy │ Éléments total │ OK attendus │ KO attendus │ Validation JSON
  ─────────┼────────────────┼─────────────┼─────────────┼────────────────
  iso      │      N         │      N      │      N      │ ✅
  edges    │      N         │      N      │      N      │ ✅
  cross    │      N         │      N      │      N      │ ✅
  scale    │      N         │      N      │      N      │ ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⛔ Aucun pipeline exécuté — validation statique uniquement
  ✅ Prochaine étape : chorus-check <sandbox-name> --all
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If a sub-agent failed → re-run with `chorus-create-project <sandbox> --strategy <slug>`
in a new session, pasting the compact KB summary as context to skip Phase 0.

> **⛔ Step 5 (upsert `.last-check-results.json`) — REMOVED (ENG-060).**
> Ce fichier est mis à jour par `chorus-check --all`, seul responsable de l'exécution
> du pipeline. `chorus-create-project` ne connaît pas les discordances réelles —
> il n'a jamais lancé `run.pl` — et ne doit pas écrire un cache de résultats vide
> ou fictif qui fausserait la lecture du webapp (onglet Tests).

### 6.2 `--strategy` — Single-file workflow

> This is also the internal workflow of each sub-agent spawned by `--batch`.

**Context detection (first action):** check whether `$SANDBOX/.chorus-batch-ctx.md` exists.
- If **yes** → read it; skip Phase 0+1 entirely (KB already summarised by `--batch-seq`).
- If **no** → run Phase 0+1 in full to build the KB summary before generating.

Using the KB summary and coverage table (from `.chorus-batch-ctx.md`, Phase 0+1, or passed by the orchestrator):

0. **Archive before write** (unless `--no-archive`): if `$SANDBOX/project-<slug>.json`
   already exists, archive it first — see Phase 0.4 bis for the exact procedure
   (move to `archive/<slug>/project-<slug>-<NNN>-<YYYY-MM-DD>.json` + `INDEX.md` entry).
   Skip silently if the file does not exist yet.
1. **Generate** — compute values from threshold tables; write elements following Phase 3
   conventions (id with strategy prefix, mandatory slots, no pipeline-computed slots,
   `_note_calc` annotations where useful).
2. **Validate** — run the Phase 4 checklist:
   ```bash
   python3 -c "import json; json.load(open('$SANDBOX/project-<slug>.json')); print('JSON valide')"
   ```
3. **Validate statically (ENG-060)** — Phase 5 checklist :
   ```bash
   python3 -c "import json; json.load(open('$SANDBOX/project-<slug>.json')); print('JSON valide')"
   ```
   - Vérifier chaque `type_element` dans le KB summary
   - Vérifier cohérence `-OK-`/`-KO-` ↔ `expected_verdict`
   - ⛔ NE PAS lancer `perl run.pl` — NE PAS appeler `chorus-check`
   
4. ~~**Apply Phase 5b corrections**~~ — ⛔ REMOVED (ENG-060).
   Les corrections C1–C5 dépendent de la sortie de `perl run.pl`.
   Les discordances éventuelles seront détectées par `chorus-check --all`.

5. ~~**Upsert `.last-check-results.json`**~~ — ⛔ REMOVED (ENG-060).
   Ce fichier est mis à jour par `chorus-check --all` uniquement.

   Prochaine étape : `chorus-check <sandbox-name> --all`

   ```
   placeholder (removed — no run.pl output available)
      disc_detail and unproc_detail from the last run.pl output.
   5. Recompute overall_discordances, overall_total, converged.
   6. Write $SANDBOX/.last-check-results.json with updated kb_hash, proj_hash, timestamp.
   ```

   > **Why here:** `chorus-create-project --strategy X` produces fresh results from a
   > ~~freshly generated project file. Writing them immediately to `.last-check-results.json`~~
   > ~~means the webapp Tests tab reflects the correct convergence state as soon as the~~
   > ~~generation is done — without requiring a separate `chorus-check --all`.~~
   >
   > ⛔ **REMOVED (ENG-060)** — `.last-check-results.json` est écrit par `chorus-check --all`
   > uniquement. `chorus-create-project --strategy` ne lance pas `perl run.pl` → il n'a
   > aucun résultat de pipeline à persister.

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
| `iso` | `project-rules-iso.json` | `I-` | 1 OK + 1 KO per rule in isolation | ≈ 2 × N_rules |
| `edges` | `project-edges.json` | `E-` | boundary values (threshold ±ε) | ≈ 2 × N_thresholds |
| `cross` | `project-cross.json` | `X-` | multi-rule interactions | 1–3 per rule pair |
| `scale` | `project-scale.json` | `S-` | all types × all classes/zones | ≥ 100 elements |

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
| **Produces** | org KB, YAML, Helpers.pm | `project-*.json` file | Feed.pm, Agent shells, Expert.pm, run.pl |
| **Source of thresholds** | corpus | org KB (Helpers Perl section) | org KB |
| **Never reads** | — | Helpers.pm, Feed.pm, *.pm | — |
