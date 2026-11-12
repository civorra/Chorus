# Skill — chorus-compare-kb

> Trigger: `chorus-compare-kb <sandbox-A> <sandbox-B> [--step <0|1|2|3|4|5|W>] [--thesaurus <file>] [--out <matrix-file>] [--no-witness]`
> Agent: `architect`
>
> `<sandbox-A>` and `<sandbox-B>`: two Chorus sandboxes with a stable KB each
> (typically modelling two distinct but related normative corpora — e.g. national
> law A vs. EU directive B, or version N vs. version N+1 of the same standard).
>
> **Single responsibility: identify gaps and divergences between two KB,
> at the concept, coverage, threshold, and obligation levels.**
>
> This skill works on KB artefacts (rules, corpus references, slots, thresholds)
> — NOT on project verdicts. It does NOT modify any KB, YAML, or Perl file.
>
> Options:
> - `--step <N>`: run only phase N (0–5) or W (witness). Default: all phases in sequence.
> - `--thesaurus <file>`: reuse an existing cross-sandbox thesaurus (skips Phase 2 construction).
> - `--out <matrix-file>`: write the output matrix to a custom path (default: see Phase OUT).
> - `--no-witness`: skip Phase W (witness test loop) even if both KBs are stable.
>
> Prerequisites:
> - `chorus-feed <sandbox-A>` and `chorus-feed <sandbox-B>` must have been run.
> - `chorus-review-kb <sandbox-A> --format org` and `chorus-review-kb <sandbox-B> --format org`
>   must have been run — their `.org` coverage reports are the primary input of Phase 4.
> - For Phase W (witness test): both sandboxes must be **stable**
>   (Deferred=0, Uncovered=0, Orphan=0 in their respective coverage reports).
>   Phase W is automatically skipped with a warning if either KB is unstable.

---

## Conventions

**Compare workspace:** all artefacts produced by this skill are written to a
dedicated folder outside both sandboxes:

```
$COMPARE = $SANDBOXES/../compare/<sandbox-A>-vs-<sandbox-B>/
```

Created automatically if absent. Contents (never committed):

```
$COMPARE/
  thesaurus-cross.org        ← cross-sandbox thesaurus (Phase 2)
  atoms-<A>.json             ← normative atoms extracted from sandbox-A (Phase 3)
  atoms-<B>.json             ← normative atoms extracted from sandbox-B (Phase 3)
  matrix-compare.org         ← output matrix (Phase OUT, default path)
  .compare-wip.md            ← in-progress marker (deleted on completion)
```

**Origin tag** — every matrix row carries an `origin` field that distinguishes:

| Value | Meaning |
|---|---|
| `kb-gap` | Concept covered in one corpus but absent from the corresponding KB (coverage gap — may not be a legal divergence) |
| `legal-divergence` | Concept present in both KBs, rules aligned, but substantive difference in threshold, scope, or obligation |
| `thesaurus-mismatch` | Same concept, different terminology — resolved by the thesaurus (not a real gap) |
| `structural` | Agents or Frames present in one sandbox but absent in the other |
| `uncertain` | Cannot be determined without human review |

**Method tag** — every matrix row also carries a `method` field:

| Value | Meaning |
|---|---|
| `deterministic` | Computed mechanically from YAML metadata (thresholds, slot sets, CORPUS: refs) |
| `llm-assisted` | LLM interpretation of ACTION semantics or concept alignment |
| `human-validated` | Operator has confirmed or corrected the finding |

---

## Phase 0 — Prerequisites & stability check

### 0.1 — WIP checkpoint detection

```bash
ls $COMPARE/.compare-wip.md
```

If present: display the checkpoint content and ask the operator:

```
⚠️  Interrupted compare-kb session detected — $COMPARE/.compare-wip.md

  Started  : <timestamp>
  Last step: <step>
  Status   : IN_PROGRESS

  Options:
    Resume  — continue from the last completed step
    Restart — delete checkpoint and run from Phase 0
```

Call `eca__ask_user` with options `["Reprendre", "Recommencer depuis Phase 0"]`.

- **Reprendre** → skip completed phases, resume from the interrupted step.
- **Recommencer** → delete `.compare-wip.md`, proceed normally.

Write `.compare-wip.md` at the start of the full run:

```markdown
# chorus-compare-kb WIP checkpoint
sandbox-a: <A>
sandbox-b: <B>
started: <YYYY-MM-DD>
status: IN_PROGRESS
last-completed-step: —
```

### 0.2 — Sandbox existence check

Verify both sandboxes exist and have the required artefacts:

```bash
ls $SANDBOXES/<A>/agent/chorus/     # KB org files
ls $SANDBOXES/<B>/agent/chorus/
ls $SANDBOXES/<A>/rules/            # YAML rules
ls $SANDBOXES/<B>/rules/
```

If either sandbox is missing → stop:
```
⛔ Sandbox <X> is not initialised (KB or rules missing).
   Run: chorus-feed <X> <corpus>
```

### 0.3 — Stability check (warn, do not block)

Read the coverage report for each sandbox:

```bash
# Most recent chorus-review-kb --format org output:
ls $SANDBOXES/<A>/workspace/reports/review-kb-*.org   # most recent
ls $SANDBOXES/<B>/workspace/reports/review-kb-*.org
```

If a coverage report is absent → warn and continue (Phase 4 will degrade gracefully):
```
⚠️  No chorus-review-kb report found for sandbox <X>.
    Phase 4 (coverage comparison) will operate in fallback mode (YAML scan only).
    For best results: run chorus-review-kb <X> --format org first.
```

If a coverage report exists, extract the stability indicators:
```
Deferred   : N
Uncovered  : N
Orphan     : N
```

If Deferred > 0 OR Uncovered > 0 for either sandbox → flag as **unstable**:
```
⚠️  Sandbox <X> KB is not yet stable (Deferred=N, Uncovered=N).
    Phases 0–4 will run. Phases 5, 6, and W may produce false positives
    — 'kb-gap' findings may be coverage gaps rather than legal divergences.
    Phase W (witness test) will be automatically skipped.
```

Record `stability_A` and `stability_B` (true/false) for use in Phase W.

---

## Phase 1 — Structural alignment

> **Goal:** detect structural divergences before any rule-level comparison.
> A missing agent or Frame type in one sandbox is the strongest possible signal
> of a scope difference between the two corpora.
>
> **Method:** deterministic — no LLM involved.

### 1.1 — Agent inventory

For each sandbox, list the agent slugs from the KB org files:

```bash
ls $SANDBOXES/<A>/agent/chorus/*.org   # exclude index.org
ls $SANDBOXES/<B>/agent/chorus/*.org
```

Compute three sets:
- **A∩B** (shared agents) — alignment candidates for Phases 4–6
- **A∖B** (agents in A only) — structural gap in B
- **B∖A** (agents in B only) — structural gap in A

### 1.2 — Frame type inventory

For each shared agent, read its org file and extract the Frame types listed
under the `Frames` or `Types` heading. Compute A∩B, A∖B, B∖A per agent.

### 1.3 — Slot inventory

For each shared agent, extract the slot names from the `Slots` or
`Variables` section of each org file. Compute A∩B, A∖B, B∖A per agent.

### 1.4 — Display structural summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Phase 1 — Structural alignment
  <A> vs <B>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Agents in A only  : <list> → structural gap B
  Agents in B only  : <list> → structural gap A
  Shared agents     : <list> → alignment candidates

  Per shared agent:
    <agent>  Frames A∖B: <N>  Frames B∖A: <N>  Shared: <N>
             Slots  A∖B: <N>  Slots  B∖A: <N>  Shared: <N>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Add all structural divergences to the matrix immediately (origin: `structural`,
method: `deterministic`). These are facts — no LLM validation needed.

---

## Phase 2 — Cross-sandbox thesaurus

> **Goal:** build a shared vocabulary that maps terms from both corpora to
> canonical concepts, so that identical concepts expressed with different words
> do not appear as false gaps in Phases 4–6.
>
> ⚠️ **Critical distinction** — two types of correspondence:
>
> | Type | Definition | Treatment |
> |---|---|---|
> | **Strict synonym** | Same legal concept, different terminology — interchangeable | Normalize to one canonical term: gaps disappear |
> | **Quasi-equivalent** | Concepts are related but NOT identical — one is broader, narrower, or conditionally different | Keep BOTH terms visible; annotate as `quasi-equiv` — gaps MAY reflect a genuine legal divergence |
>
> Collapsing quasi-equivalents into a canonical term is the most dangerous error
> in cross-corpus comparison: it silently erases real legal divergences.
>
> If `--thesaurus <file>` was provided → load it and skip to Phase 2.4 (validation).

### 2.1 — Seed from existing sandbox thesauri

Each sandbox may already carry a thesaurus shard from prior `chorus-import-project` runs:

```bash
cat $SANDBOXES/<A>/agent/thesaurus/global.org   # if present
cat $SANDBOXES/<B>/agent/thesaurus/global.org   # if present
```

Extract the `Aliases` sections (confirmed alignments) as a seed for the cross-thesaurus.

### 2.2 — Extract terms from KB org files

For each sandbox, read its agent org files and collect:
- Slot names (canonical identifiers)
- CORPUS: section labels (normative references)
- Key terms from rule descriptions (`Règle`, `Condition`, `Exception` headings)

This is a mechanical extraction — no LLM yet.

### 2.3 — LLM alignment pass

For each pair of terms (one from A, one from B) that share the same agent context
and are lexically or semantically close, classify:

```
term_A: "<term>"     term_B: "<term>"
→ strict-synonym | quasi-equiv | unrelated
→ canonical: "<canonical label>"  (if strict-synonym)
→ note: "<brief justification>"
```

LLM instructions:
- Strict synonyms ONLY when the concepts are legally interchangeable in both corpora.
- When in doubt → quasi-equiv (err on the side of keeping divergences visible).
- Always provide a one-line justification.

### 2.4 — Write thesaurus-cross.org

Write `$COMPARE/thesaurus-cross.org` with three sections:

```org
* Strict synonyms
  (normalized to canonical — same concept, different wording)
  | Term A          | Term B           | Canonical        | Method        |
  |-----------------|------------------|------------------|---------------|
  | reproduction    | copying          | reproduction     | llm-assisted  |
  | ...             | ...              | ...              | ...           |

* Quasi-equivalents
  (similar but NOT identical — keep both visible in the matrix)
  | Term A          | Term B           | Relationship     | Note          |
  |-----------------|------------------|------------------|---------------|
  | droit moral     | moral rights     | quasi-equiv      | EU: waivable in some MS; FI: not waivable |
  | ...             | ...              | ...              | ...           |

* Unmatched terms
  (present in one corpus only — potential structural gap)
  | Term            | Sandbox          | Note             |
  |-----------------|------------------|------------------|
  | ...             | A | B            | ...              |
```

Display a summary: `N strict synonyms · N quasi-equivalents · N unmatched`.

> **Human checkpoint:** present the quasi-equivalents list and ask the operator
> to validate the relationship annotation before continuing.
> This is the most consequential human review in the entire skill — quasi-equiv
> misclassified as strict-synonym will produce a silent false negative in Phase 5.

---

## Phase 3 — Normative atoms extraction

> **Goal:** for each YAML rule in both sandboxes, extract a structured record
> (the "normative atom") that captures its testable content in a form
> comparable across sandboxes.
>
> **Method:** mechanical parsing of YAML headers + LLM interpretation of
> ACTION semantics. LLM parts are always tagged `llm-assisted`.

For each YAML rule file `$SANDBOX/rules/<agent>/<RNN-slug>.yml`:

Extract mechanically (no LLM):
- `rule_id`: filename without extension
- `sandbox`: A or B
- `agent`: parent directory name
- `corpus_ref`: value of `CORPUS:` header (or `null` if absent)
- `inputs`: slot names listed under `FIND` / `INPUTS` keys
- `outputs`: slot names listed under `ACTION` write operations (regex: `\$f->{(\w+)}\s*=`)
- `rule_name`: value of `RULE:` / `REGLE:` key

Extract with LLM (tag each field `llm-assisted`):
- `condition_summary`: one-line natural-language description of the FIND condition
- `thresholds`: list of `{ slot, operator, value, unit }` extracted from ACTION
- `obligation_type`: `prohibits | requires | permits | classifies`
- `exception_guard`: boolean — does the rule use a Pattern 1 EXCEPTION guard?

> ⚠️ **Helpers.pm opacity:** if the ACTION calls a Perl function from `Helpers.pm`
> (pattern: `Chorus::Expert::.*->` or bare function name from `use Chorus::Expert`),
> the threshold is not in the YAML. Flag the atom:
> `helpers_opaque: true` — read `$SANDBOX/agent/Helpers.pm` for the actual logic.
> LLM interpretation of Helpers functions is lower-confidence; tag as `llm-assisted`
> with `confidence: low`.

Write all atoms to `$COMPARE/atoms-<A>.json` and `$COMPARE/atoms-<B>.json`.

Display: `Extracted N atoms from <A> (H Helpers-opaque) · N atoms from <B> (H Helpers-opaque)`.

---

## Phase 4 — Coverage comparison

> **Goal:** compare which sections of each corpus are covered by rules,
> and identify coverage gaps WITHOUT LLM.
>
> **Method:** entirely deterministic — based on CORPUS: references in YAML
> rules and the coverage reports from `chorus-review-kb`.
>
> ⚠️ **Critical distinction** — two types of gap detected here:
> - **KB coverage gap** (`kb-gap`): a corpus section has no rule citing it.
>   May be an incomplete chorus-feed run — not necessarily a legal divergence.
> - **Legal absence** (`legal-divergence`): a concept covered by rules in A
>   has NO corresponding section in corpus B at all (structural absence in
>   the normative text itself, confirmed by the operator).
>
> Do NOT conflate these. Always label `origin: kb-gap` by default; only upgrade
> to `legal-divergence` after human confirmation (Phase 4.3).

### 4.1 — Build coverage maps

For each sandbox, build a map `corpus_ref → [rule_id, ...]`:

```
# From YAML rule atoms (Phase 3):
coverage_A = { corpus_ref: [rule_ids] for each atom in atoms-A with corpus_ref != null }
coverage_B = { corpus_ref: [rule_ids] for each atom in atoms-B with corpus_ref != null }

# From chorus-review-kb report (if available — richer, includes no_auto_rules sections):
# Parse the org report's "Uncovered articles" and "Orphan rules" sections.
```

Normalize corpus references using the thesaurus (Phase 2): map each ref to its
canonical label before computing set differences.

### 4.2 — Compute coverage gaps

```
sections_only_in_A = coverage_A.keys ∖ coverage_B.keys
sections_only_in_B = coverage_B.keys ∖ coverage_A.keys
sections_in_both   = coverage_A.keys ∩ coverage_B.keys
```

For each section in `sections_only_in_A` or `sections_only_in_B`:
- Label `origin: kb-gap` (provisional).
- Note: "Section present in corpus X, cited by N rules — no corresponding
  section found in corpus Y's KB."

### 4.3 — Human checkpoint: kb-gap vs legal-absence

Present the `sections_only_in_A` and `sections_only_in_B` lists to the operator
and ask per item (or per batch if the list is long):

```
Phase 4 — Coverage gaps requiring your input:

For each of the following sections, is the ABSENCE from the other corpus:
  [KB]     a coverage gap (chorus-feed incomplete) — label kb-gap
  [LEGAL]  a genuine legal absence (the other normative text truly has no equivalent)
  [THES]   a thesaurus miss (the equivalent section exists under a different name)
```

Update `origin` accordingly. `THES` items → add entry to thesaurus-cross.org and
recompute the coverage map (may eliminate the gap entirely).

### 4.4 — Display coverage summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Phase 4 — Coverage comparison
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Sections in A only : N  (kb-gap: N · legal-absence: N · thes-fixed: N)
  Sections in B only : N  (kb-gap: N · legal-absence: N · thes-fixed: N)
  Sections in both   : N  → alignment candidates for Phase 5
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If coverage rates differ by more than 20 percentage points between A and B,
emit a prominent warning:

```
⚠️  Coverage imbalance detected: <A> at N% vs <B> at M%.
    Phases 5–6 will find many 'gaps' that are likely KB coverage gaps, not
    legal divergences. Consider stabilising <X> with chorus-feed before
    running --step 5 and --step 6.
```

---

## Phase 5 — Concept alignment

> **Goal:** for sections covered in both sandboxes, align the corresponding
> rules and classify their relationship using a closed grid.
>
> **Method:** LLM-assisted, with human validation of all non-equivalent findings.
>
> Input: `sections_in_both` from Phase 4 + normative atoms from Phase 3.

### 5.1 — Rule pairing

For each shared corpus section, pair the rules from A and B that cite it:

```
For section S:
  rules_A = coverage_A[S]
  rules_B = coverage_B[S]
```

If |rules_A| ≠ |rules_B|: note the count discrepancy (may indicate different
granularity of modelling, not necessarily a legal divergence).

### 5.2 — LLM alignment pass (closed grid)

For each rule pair (rule_a, rule_b) covering the same section:

```
rule_a: { condition_summary, thresholds, obligation_type, outputs }
rule_b: { condition_summary, thresholds, obligation_type, outputs }

→ alignment status (choose exactly one):
   equivalent          — same condition, same threshold, same obligation
   A_stricter          — A imposes more constraints than B on this concept
   B_stricter          — B imposes more constraints than A
   A_only              — concept is modelled in A, B has no rule for it
   B_only              — concept is modelled in B, A has no rule for it
   scope_different     — both modelled, but different element types / Frame types in scope
   granularity_different — same concept, but A splits it into N rules vs B into M rules
```

LLM instructions:
- Use the thesaurus (Phase 2) for all term comparisons — do NOT rely on surface wording.
- For `A_stricter` / `B_stricter`: always identify the specific slot and threshold
  causing the asymmetry.
- When unsure → `scope_different` (conservative — avoids false strict/permissive claims).
- Confidence score (0.0–1.0) mandatory for each classification.

### 5.3 — Human validation

All findings with status ≠ `equivalent` AND confidence < 0.85 go to a human
validation checkpoint:

```
Phase 5 — Alignment findings requiring your input (N items):

#1  Section: §X — <title>
    Rule A: <id> (<condition_summary>)
    Rule B: <id> (<condition_summary>)
    LLM classification: A_stricter (confidence: 0.72)
    Reason: "threshold for slot Y is 70 in A, 60 in B"
    → Confirm / Override / Mark uncertain
```

Call `eca__ask_user` for the full list. Update `method: human-validated` for
confirmed or overridden items.

---

## Phase 6 — Divergence qualification

> **Goal:** for all non-equivalent aligned pairs (Phase 5), quantify the
> divergence precisely: numeric delta, scope difference, obligation difference.
>
> **Method:** deterministic for thresholds and slot sets;
> LLM-assisted for obligation formulations.

### 6.1 — Threshold divergences (deterministic)

For each `A_stricter` / `B_stricter` pair:

```
For each threshold in rule_a and rule_b (matched by slot name):
  delta = value_A - value_B
  unit_match = (unit_A == unit_B)
  direction = "A higher" | "B higher" | "same value" | "unit mismatch"
```

If `unit_match = false` → flag as `uncertain` (unit conversion required,
may not be a real divergence — e.g. one rule uses bytes, the other uses kbits).

### 6.2 — Scope divergences (deterministic)

For each `scope_different` pair, compare:
- FIND slot sets: which element types / Frame types each rule applies to
- filtre expressions: which attribute values trigger each rule

Produce: `scope_A_extra` (element types in A's scope not in B's) and
`scope_B_extra` (element types in B's scope not in A's).

### 6.3 — Obligation divergences (LLM-assisted)

For each pair where `obligation_type_A ≠ obligation_type_B`:

```
e.g. rule_a: obligation_type = "requires"
     rule_b: obligation_type = "permits"
→ divergence: "A mandates X; B merely authorises X"
```

LLM produces a one-sentence natural-language description of the divergence,
tagged `llm-assisted`.

### 6.4 — Display divergence report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Phase 6 — Divergence qualification
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Threshold divergences   : N  (deterministic)
  Scope divergences       : N  (deterministic)
  Obligation divergences  : N  (llm-assisted)
  Uncertain               : N  (unit mismatch / helpers-opaque / low confidence)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase W — Witness test loop (optional)

> **Prerequisite:** both `stability_A` and `stability_B` must be `true`
> (from Phase 0.3). If either is false → skip Phase W with:
> ```
> ⏭ Phase W skipped — sandbox <X> is not yet stable.
>    Stabilise with chorus-feed, then re-run: chorus-compare-kb <A> <B> --step W
> ```
>
> Also skipped if `--no-witness` was passed.
>
> **Goal:** for each numeric or scope divergence found in Phase 6, generate
> boundary project JSON cases and run them through both sandboxes to confirm
> that the divergence is real at the engine level (not just in the text modelling).
>
> This is the strongest possible evidence of a true divergence.

### W.1 — Generate witness cases

For each threshold divergence (slot S, value_A ≠ value_B):

Generate three project JSON cases per divergence (using `chorus-stress` conventions):

| Case | Value | Expected verdict A | Expected verdict B |
|---|---|---|---|
| `at_A` | value_A | CONFORME boundary | may differ |
| `at_B` | value_B | may differ | CONFORME boundary |
| `between` | (value_A + value_B) / 2 | depends on direction | depends on direction |

Write witness project files to `$COMPARE/witness/projet-witness-<slug>-NNN.json`
for each sandbox.

For scope divergences: generate one case inside scope_A_extra and one inside
scope_B_extra for each divergent pair.

### W.2 — Run witnesses through both sandboxes

```bash
# For each sandbox / witness pair:
(cd $SANDBOXES/<A> && perl run.pl ../compare/<A>-vs-<B>/witness/projet-witness-<slug>-NNN.json)
(cd $SANDBOXES/<B> && perl run.pl ../compare/<A>-vs-<B>/witness/projet-witness-<slug>-NNN.json)
```

Collect verdicts.

### W.3 — Classify witness results

For each witness case:

| Result | Meaning |
|---|---|
| Verdict differs between A and B | ✅ **Confirmed divergence** — the difference is real at the engine level |
| Verdict identical in A and B | ⚠️ **Modelling artefact** — the YAML rules may be equivalent in practice despite textual difference |
| One sandbox errors / unprocessed | ❌ **Witness failure** — check Feed coverage for this element type |

Update the matrix row with `witness_result: confirmed | artefact | failure`.

---

## Phase OUT — Output matrix

Write `$COMPARE/matrix-compare.org` (or `--out` path if specified).

### Matrix format

```org
* Comparison matrix — <sandbox-A> vs <sandbox-B>
  Generated: <ISO 8601>
  Stability: A=<stable|unstable>  B=<stable|unstable>

** Structural divergences
   | Concept           | Section A   | Section B   | Status         | Origin     | Method        | Rules A    | Rules B    | Witness      | Validated |
   |-------------------|-------------|-------------|----------------|------------|---------------|------------|------------|--------------|-----------|
   | <agent/frame>     | present     | absent      | structural     | structural | deterministic | —          | —          | —            | ○         |

** Coverage gaps
   | Concept           | Section A   | Section B   | Status         | Origin     | Method        | Rules A    | Rules B    | Witness      | Validated |
   |-------------------|-------------|-------------|----------------|------------|---------------|------------|------------|--------------|-----------|
   | <term>            | §X.Y        | —           | gap-B          | kb-gap     | deterministic | R01-slug   | —          | —            | ○         |

** Aligned concepts — equivalent
   | Concept           | Section A   | Section B   | Status         | Origin            | Method           | Rules A   | Rules B   | Witness   | Validated |
   |-------------------|-------------|-------------|----------------|-------------------|------------------|-----------|-----------|-----------|-----------|
   | <term>            | §X.Y        | §P.Q        | equivalent     | —                 | llm-assisted     | R01       | R02       | —         | ✓         |

** Divergences — threshold
   | Concept     | Section A | Section B | Status     | Slot        | Value A | Value B | Delta | Unit match | Origin            | Method        | Witness      | Validated |
   |-------------|-----------|-----------|------------|-------------|---------|---------|-------|------------|-------------------|---------------|--------------|-----------|
   | <term>      | §X.Y      | §P.Q      | A_stricter | <slot_name> | 70      | 60      | +10   | ✓          | legal-divergence  | deterministic | confirmed ✅ | ✓         |

** Divergences — scope
   (same columns + scope_A_extra, scope_B_extra)

** Divergences — obligation
   (same columns + obligation_A, obligation_B, description)

** Uncertain — requires human review
   (all items with method=uncertain or witness=failure)
```

### Summary banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-compare-kb  <sandbox-A>  vs  <sandbox-B>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Structural divergences   : N
  Coverage gaps            : N  (kb-gap: N · legal-absence: N)
  Equivalent concepts      : N
  Threshold divergences    : N  (confirmed by witness: N)
  Scope divergences        : N  (confirmed by witness: N)
  Obligation divergences   : N
  Uncertain                : N  → human review required
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Matrix written → $COMPARE/matrix-compare.org
  Thesaurus     → $COMPARE/thesaurus-cross.org
  Next steps:
    1. Review 'uncertain' rows (human review)
    2. For kb-gap rows: stabilise the weaker sandbox → re-run --step 4
    3. For confirmed legal-divergences: document in $WIP or export to report
```

Delete `.compare-wip.md` on successful completion.

---

## Separation of responsibilities

| | `chorus-feed` | `chorus-review-kb` | `chorus-stress` | `chorus-strengthen` | `chorus-compare-kb` |
|---|---|---|---|---|---|
| **Scope** | single sandbox | single sandbox | single sandbox | single sandbox | cross-sandbox |
| **Modifies KB** | ✅ | ✗ | ✗ | ✗ | ✗ |
| **Reads rules** | ✅ | ✅ | ✅ | ✅ | ✅ (both) |
| **Runs pipeline** | ✗ | ✗ | ✗ | ✅ | ✅ (Phase W only) |
| **LLM for thresholds** | ✗ | ✗ | ✗ | ✗ | Phase 3 (tagged) |
| **Human checkpoints** | ✗ | ✗ | ✗ | Phase 4-chk | Phase 2.4 · 4.3 · 5.3 |
| **Output** | KB + YAML | coverage report | stress JSONs | gap report | divergence matrix |

> **Prerequisite chain:**
> ```
> chorus-feed <A>  +  chorus-feed <B>
>        ↓
> chorus-review-kb <A> --format org  +  chorus-review-kb <B> --format org
>        ↓
> chorus-compare-kb <A> <B>          ← this skill
>        ↓  (optional — if both KBs are stable)
> chorus-compare-kb <A> <B> --step W ← witness confirmation
> ```
