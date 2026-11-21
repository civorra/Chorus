# Skill — chorus-compare-kb

> Trigger: `chorus-compare-kb <sandbox-A> <sandbox-B> [--step <0|1|2|3|4|5|W>] [--thesaurus <file>] [--out <matrix-file>] [--no-witness] [--report [--report-lang fr|en] [--report-out <file>]]`
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
> - `--report`: after Phase OUT, generate a legally-focused comparison report (see `## Option --report`).
>   Can be combined with any `--step` option; if `matrix-compare.org` already exists, runs report generation only.
> - `--report-lang fr|en`: language of the `--report` output. Overrides auto-detection (default: `fr`).
> - `--report-out <file>`: custom output path for the report (default: `$COMPARE/rapport-comparatif-<A>-vs-<B>.md`).
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

> **Invariant (one-sided rows).** A row where only ONE side has a normative atom
> (`Section A` or `Section B` is `—`) can NEVER be `legal-divergence`. It stays
> `kb-gap` until the targeted corpus search of Phase 4.3 has ruled out the
> provision in the other corpus (`absence_proof` filled). A `legal-divergence`
> requires atoms on BOTH sides.

**Method tag** — every matrix row also carries a `method` field:

| Value | Meaning |
|---|---|
| `deterministic` | Computed mechanically from YAML metadata (thresholds, slot sets, CORPUS: refs) |
| `llm-assisted` | LLM interpretation of ACTION semantics or concept alignment |
| `human-validated` | Operator has confirmed or corrected the finding |

**Direction tag** — every `legal-divergence` row also carries a `direction` field
(set by the operator or the LLM, tagged accordingly), because the legal reading
differs: a national rule STRICTER than a directive is generally lawful, a rule
WEAKER than the directive is a potential non-transposition.

| Value | Meaning |
|---|---|
| `B_stricter_than_A` / `A_stricter_than_B` | Same obligation, tighter threshold/scope/duty on one side |
| `B_weaker_than_A` / `A_weaker_than_B` | One side grants less protection or imposes less than the other |
| `different_structure` | Different mechanism (not comparable on a strict/weak axis) |
| `undetermined` | Cannot be ordered without a legal opinion |

When one corpus is a minimum-harmonisation instrument (e.g. an EU directive) and
the other its national implementation, express direction relative to that
instrument.

**Evidence tag** — every `legal-divergence` row carries an `evidence` field. The
two levels are never merged under the single word "confirmed":

| Value | Meaning |
|---|---|
| `text-anchored` | Both atoms cite distinct texts (`corpus_ref` on both sides) and the difference was computed deterministically |
| `witness-confirmed` | Phase W produced differing verdicts on boundary cases (engine-level proof) |
| `witness-artefact` | Phase W produced identical verdicts — textual difference, no behavioural one |
| `llm-only` | Alignment or description is LLM-assisted and not corroborated |

**Absence proof** — every one-sided row that the operator upgrades to a legal
absence carries `absence_proof: <corpus file + section/line searched, search terms>`.

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

→ Présenter les deux options dans la réponse et attendre le choix de l'opérateur
avant de continuer :

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

### 0.4 — Scoping policy parity check (warn, do not block)

A comparison is only as fair as the two scopes are alike. If sandbox A treats a
class of provisions as `Deferred` (behavioural, procedural, reporting deadlines…)
while sandbox B models them, every such provision surfaces as a false divergence.

For each sandbox, read the `Deferred-S` / `Deferred-C` rows of its `README.org`
`* Coverage` section and extract the stated criteria:

```
Scoping policy A : <criteria / count by reason>
Scoping policy B : <criteria / count by reason>
```

Compare the two. If a provision class is Deferred or Uncovered in one sandbox but
integrated in the other, list it:

```
⚠️  Scoping asymmetry: <class> (e.g. 'deadlines for distribution of amounts')
    is Deferred in <A> (§…) but modelled in <B> (§…).
    Rows in this class will be labelled kb-gap, never legal-divergence, until
    <A> is re-fed with the same policy (chorus-feed <A> --enrich).
```

Record `scoping_asymmetries[]` for Phase 4 and for the report annex.
Rows touching these sections **default to `kb-gap`** but are NOT permanently locked:
they still go through the Phase 4.3a targeted corpus search. If the search confirms
the provision is genuinely absent from corpus A's raw text → upgradeable to
`legal-absence` (with `absence_proof` filled, as usual). The asymmetry is a
**warning and a default**, not a forced classification.

---

## Phase 0.5 — Corpus relationship type

> **Goal:** determine the type of relationship between the two corpora.
> This drives the labels, section titles, and risk semantics of `--report` output.
>
> **Method:** automatic inference from available artefacts — no user interaction
> unless inference is inconclusive.

### 0.5.1 — Auto-inference (in priority order)

Read the following artefacts and apply the **first matching heuristic**:

**1. Sandbox names**
- One name contains "EU", "UE", "ISO", "EN-", "directive", "regulation" and the
  other contains a country name or national identifier
  → `hierarchical`, `reference_sandbox` = the EU/ISO/EN side

**2. README.org § Domain (each sandbox)**
- Contains "transposition of", "implémentation de", "based on Directive/Regulation",
  "national implementation of"
  → `hierarchical`, `reference_sandbox` = the instrument mentioned as source
- Contains "v1", "v2", "edition YYYY", "version N", "amendment N"
  → `sequential`, A is the earlier version (verify from dates in corpus names)
- Neither heuristic matches → candidate for `parallel`

**3. Corpus filenames (each sandbox)**
- One side has files named with "directive", "regulation", "ISO-", "EN-",
  or an international standard prefix
  → `hierarchical`, `reference_sandbox` = that side

**4. index.org pipeline description**
- Explicit mention of normative hierarchy → extract and use

### 0.5.2 — Display inferred relationship

If inference is **confident** (at least two heuristics agree):

```
ℹ Relation détectée : <relationship_type>
  [cadre A] : <label — from R.1 substitution table>
              rôle : <référence | implémentation | version antérieure | parallèle>
  [cadre B] : <label — from R.1 substitution table>
              rôle : <référence | implémentation | version postérieure | parallèle>
  instrument_type : <free label — e.g. "minimum harmonisé", "standard obligatoire">
  → Corriger au prochain message si incorrect.
```

If inference is **inconclusive** (heuristics disagree or insufficient data):

```
⚠ Type de relation entre les deux corpus non déterminable automatiquement.

  Options :
    hierarchical — [cadre A] est l'instrument de référence (minimum), [cadre B] est l'implémentation
    parallel     — les deux référentiels ont le même statut normatif
    sequential   — [cadre A] est une version antérieure de [cadre B]

  Quelle relation s'applique ici ?
```

→ Attendre la réponse de l'opérateur avant de continuer.

### 0.5.3 — Store for downstream phases

Store the following values for use by all `--report` sections
(R.0-bis, R.1-bis, R.1-ter, R.3-bis):

| Variable            | Values                                | Applies to         |
|---------------------|---------------------------------------|--------------------|
| `relationship_type` | `hierarchical` / `parallel` / `sequential` | all report sections |
| `reference_sandbox` | `A` / `B`                             | hierarchical only  |
| `instrument_type`   | free label (e.g. "minimum harmonisé") | hierarchical only  |

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

### 4.3 — Targeted corpus search, then human checkpoint

**4.3a — Targeted search (mandatory, before any upgrade).** For each one-sided
item, search the RAW corpus of the sandbox that lacks the atom, using the
concept's thesaurus terms and the key figures of the atom (e.g. `nine months`,
`three years`, `notice`, article titles). Rows touching a `scoping_asymmetries` section are **not skipped** — run the
targeted search normally. Present the result to the operator with an asymmetry
flag: `⚠️ scoping-asymmetric in <A> — targeted search result: <found|not found>`.
The operator may still upgrade to `legal-absence` if `absence_proof` is filled.
Default remains `kb-gap` if the search is inconclusive or the provision is
found in corpus A (meaning A simply hasn't fed it yet).

Classify the result:

| Search result | Action |
|---|---|
| Provision found in the other corpus (same or other article) | `kb-gap` (or `thesaurus-mismatch` if only naming differs); record the found reference; the pair returns to Phase 5 once the KB is fed |
| Nothing found after searching all relevant files | candidate `legal-absence`; fill `absence_proof` (files, terms searched) |
| Corpus incomplete / search not conclusive | `uncertain` |

Never classify from memory of the law: the proof must come from the corpus files
or be flagged for a lawyer.

**4.3b — Human checkpoint: kb-gap vs legal-absence.**

Present the `sections_only_in_A` and `sections_only_in_B` lists to the operator,
WITH the 4.3a result for each item, and ask per item (or per batch if the list is long):

```
Phase 4 — Coverage gaps requiring your input:

For each of the following sections, is the ABSENCE from the other corpus:
  [KB]     a coverage gap (chorus-feed incomplete) — label kb-gap
  [LEGAL]  a genuine legal absence (the other normative text truly has no equivalent)
  [THES]   a thesaurus miss (the equivalent section exists under a different name)
```

`[LEGAL]` is accepted only when `absence_proof` is filled (4.3a). Update `origin`
accordingly. `THES` items → add entry to thesaurus-cross.org and
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

→ Présenter la liste complète dans la réponse et attendre les confirmations/corrections
de l'opérateur avant de continuer. Mettre à jour `method: human-validated` pour
chaque item confirmé ou corrigé.

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

### 6.4 — Direction and evidence

For each divergence set `direction` (see Conventions) and `evidence = text-anchored`
(or `llm-only` for 6.3 findings). Threshold divergences get `direction` from the
delta and the semantic of the slot (a higher minimum retention period is
'stricter'; a higher maximum delay is 'weaker'): when the slot semantic is not
obvious, set `undetermined` rather than guess.

### 6.5 — Display divergence report

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

Update the matrix row with `witness_result: confirmed | artefact | failure` and
`evidence = witness-confirmed | witness-artefact` (failure leaves `evidence`
unchanged). A row never shows 'confirmed' without saying which level.

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
   (one-sided rows: origin is kb-gap | legal-absence | uncertain — never legal-divergence; legal-absence requires absence_proof)

** Aligned concepts — equivalent
   | Concept           | Section A   | Section B   | Status         | Origin            | Method           | Rules A   | Rules B   | Witness   | Validated |
   |-------------------|-------------|-------------|----------------|-------------------|------------------|-----------|-----------|-----------|-----------|
   | <term>            | §X.Y        | §P.Q        | equivalent     | —                 | llm-assisted     | R01       | R02       | —         | ✓         |

** Divergences — threshold
   | Concept     | Section A | Section B | Status     | Slot        | Value A | Value B | Delta | Unit match | Origin            | Direction | Evidence      | Method        | Witness      | Validated |
   |-------------|-----------|-----------|------------|-------------|---------|---------|-------|------------|-------------------|-----------|---------------|---------------|--------------|-----------|
   | <term>      | §X.Y      | §P.Q      | A_stricter | <slot_name> | 70      | 60      | +10   | ✓          | legal-divergence  | B_weaker_than_A | text-anchored | deterministic | confirmed ✅ | ✓         |

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
  Threshold divergences    : N  (text-anchored: N · witness-confirmed: N · witness-artefact: N)
  Scope divergences        : N  (text-anchored: N · witness-confirmed: N · witness-artefact: N)
  Obligation divergences   : N  (llm-only: N)
  By direction             : <side>_stricter: N · <side>_weaker: N · different_structure: N · undetermined: N
  Scoping asymmetries      : N  (default kb-gap · N upgraded to legal-absence after 4.3a)
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

## Option --report — Legal comparison report for external readers

> **Trigger:** `chorus-compare-kb <A> <B> --report [--report-lang fr|en] [--report-out <file>]`
>
> **Prerequisite:** `$COMPARE/matrix-compare.org` must exist (run `chorus-compare-kb` without
> `--report` first, or combine both in a single invocation).
>
> **Purpose:** transform the technical divergence matrix into a legally-focused comparison
> document readable by legal professionals with no knowledge of Chorus internals.
> All Chorus-specific vocabulary is replaced by legal language (see substitution table below).
> The report never mentions: sandbox, KB, pipeline, agent, rule, slot, YAML, Feed,
> `Deferred`, `converged`, `corpus`, `run.pl`, or any other Chorus technical term.

### R.1 — Term substitution table

| Chorus term | Legal report equivalent |
|---|---|
| sandbox A / B | *cadre normatif A / B* (e.g. "droit européen du droit d'auteur" / "droit finlandais du droit d'auteur") |
| KB / knowledge base | *référentiel d'analyse* (never mentioned directly) |
| rule / YAML rule | *disposition analysée* / *obligation* / *droit* / *exception* |
| agent | *domaine thématique* (e.g. "droits patrimoniaux", "exceptions", "gestion collective") |
| slot | *critère* / *paramètre* / *condition* |
| corpus / corpus ref | *texte de référence* / *article* (cite the actual article number) |
| kb-gap | *non couvert dans le périmètre de la présente analyse* |
| legal-divergence | *divergence substantielle* |
| equivalent | *dispositions équivalentes* |
| Deferred-S | *disposition procédurale ou comportementale hors périmètre* |
| structural gap | *domaine présent dans un seul référentiel* |
| A_stricter / B_stricter | *exigence plus stricte en [droit A/B]* |
| scope_different | *champs d'application distincts* |
| granularity_different | *degré de précision différent* |
| llm-assisted | *issu de l'analyse automatisée — à confirmer* |
| human-validated | *(aucune mention — résultat intégré directement)* |
| deterministic | *(aucune mention — résultat intégré directement)* |
| uncertain | *point nécessitant une analyse juridique complémentaire* |
| witness-confirmed | *divergence confirmée par test comparatif* |
| text-anchored (no witness) | *divergence établie par comparaison des textes — non testée* |
| direction `*_stricter` | *exigence plus stricte en [droit A/B]* |
| direction `*_weaker` | *protection ou exigence moindre en [droit A/B] — point d'attention (conformité à l'instrument de référence)* |
| direction `different_structure` | *mécanismes différents, non comparables terme à terme* |
| threshold | *seuil* / *délai* / *plafond* (avec valeur et unité en clair) |

### R.2 — Agent-to-theme mapping

For each sandbox, map agent slugs to legal domain labels:

| Agent slug (02a — EU) | Legal theme label |
|---|---|
| `agent-exclusive-rights` | Droits patrimoniaux et durées de protection |
| `agent-exceptions` | Exceptions et limitations |
| `agent-digital-services` | Services numériques et obligations des plateformes |
| `agent-collective-management` | Gestion collective des droits |
| `agent-author-performer-rights` | Droits des auteurs et artistes-interprètes |

| Agent slug (02b — FI) | Legal theme label |
|---|---|
| `agent-protection-scope` | Périmètre de la protection |
| `agent-permitted-use` | Utilisations autorisées |
| `agent-financial-rights` | Droits financiers (rémunération, droit de suite) |
| `agent-rights-transfer` | Cession et transfert de droits |
| `agent-collective-management` | Gestion collective des droits |

> For other sandbox pairs: derive theme labels from the agent KB org `* Domain` section —
> use the first sentence, stripped of Chorus vocabulary. Never use the agent slug as-is.

### R.0-bis — Correspondence table

> **Position in report:** before §1 (Résumé exécutif).
> **Always generated.**
> **Method:** deterministic — derived from `matrix-compare.org` rows. No LLM.

For each row of `matrix-compare.org`, build one table row:
- **Concept** — canonical label from the thesaurus (or concept name from the matrix)
- **Section [cadre A]** — value of `corpus_ref_A` (or `—` if absent)
- **Section [cadre B]** — value of `corpus_ref_B` (or `—` if absent)
- **Statut** — icon derived from the table below

**Status icon derivation (generic — no domain knowledge required):**

| Matrix `origin` + `status` / `direction`                                     | Icon |
|-------------------------------------------------------------------------------|------|
| `status: equivalent`                                                          | `≡`  |
| `legal-divergence` + `direction: *_stricter` or `direction: different_structure` | `⚡`  |
| `legal-divergence` + `direction: *_weaker`                                   | `⚠`  |
| `kb-gap` (one side only — `—` in one column)                                 | `○`  |
| `legal-absence` (absence_proof confirmed)                                     | `✗`  |
| `uncertain`                                                                   | `?`  |

Column headers use R.1 substitution labels (legal names) — never raw sandbox names.
Group rows by legal theme (from R.2 agent-to-theme mapping) — one sub-table per theme.

Output in report:
```markdown
## Tableau de correspondance

### [Thème 1]
| Concept | [Cadre A] | [Cadre B] | Statut |
|---------|-----------|-----------|--------|
| ...     | Art. X    | §Y        | ≡      |

### [Thème 2]
...
```

### R.1-bis — Alignment / transposition status

> **Position in report:** after §1 (Résumé exécutif).
> **Always generated** — section title and label mapping adapt to `relationship_type`.
> **Method:** deterministic — derived from `direction` + `origin` in `matrix-compare.org`.

**`relationship_type: hierarchical`** → section title: *Statut de transposition*

| Matrix condition | Label |
|---|---|
| `direction: *_weaker` | `⚠ Non conforme — protection moindre que le minimum [instrument_type]` |
| `direction: *_stricter` | `✅ Conforme — exigence plus stricte (licite)` |
| `status: equivalent` | `✅ Transposé` |
| `legal-absence` absent in `reference_sandbox` opposite | `❌ Absent du texte d'implémentation` |
| `kb-gap` | `○ Non modélisé dans le périmètre analysé` |

**`relationship_type: parallel`** → section title: *Statut d'alignement entre référentiels*

| Matrix condition | Label |
|---|---|
| `status: equivalent` | `≡ Aligné` |
| `direction: *_stricter` or `*_weaker` | `⚡ Divergent ([A] plus strict / [B] plus strict)` |
| `direction: different_structure` | `≠ Mécanismes différents` |
| `legal-absence` | `✗ Présent dans un seul référentiel` |

**`relationship_type: sequential`** → section title: *Évolution entre versions*

| Matrix condition | Label |
|---|---|
| `status: equivalent` | `→ Maintenu` |
| `direction: *_stricter` | `↑ Renforcé` |
| `direction: *_weaker` | `↓ Assoupli` |
| `legal-absence` absent in B | `✗ Supprimé` |
| `legal-absence` absent in A | `✚ Ajouté` |

Output in report (same structure for all types — only title and labels vary):
```markdown
## [Section title]

| Concept | Texte [cadre A] | Texte [cadre B] | Statut |
|---------|-----------------|-----------------|--------|
| ...     | Art. X Dir. Y   | §Z Loi W        | ✅ Transposé |
```

### R.1-ter — Risk map

> **Position in report:** after R.1-bis.
> **Always generated.**
> **Method:** 100% deterministic — derived from `direction` + `evidence` in `matrix-compare.org`.
> No LLM involved.

Three levels. Labels adapt according to `relationship_type`:

**Level 🔴 (critical — requires action):**
- `hierarchical` : `direction: *_weaker`  → *Conformité à vérifier*
- `parallel`     : `direction: *_weaker`  → *Divergence substantielle défavorable à [B]*
- `sequential`   : `direction: *_weaker`  → *Régression par rapport à la version précédente*

**Level 🟡 (attention — clarification needed):**
- All types: `direction: different_structure` | `direction: undetermined` | `status: uncertain`

**Level 🟢 (informative):**
- `hierarchical` : `direction: *_stricter` → *Plus strict que le minimum [instrument_type] (licite)*
- `parallel`     : `direction: *_stricter` → *Plus protecteur en [cadre A/B]*
- `sequential`   : `direction: *_stricter` → *Renforcement*

For each item: one line `• <concept> — <one-line impact> (<article refs>)`.
Omit a level entirely if it has 0 items.

Output in report:
```markdown
## Priorités d'analyse

🔴 [label critique] (N)
   • <concept> — <une ligne impact> (<ref articles>)
   • …

🟡 Mécanismes à clarifier (N)
   • …

🟢 [label positif] (N)
   • …
```

### R.3 — Report structure

Write the report section by section in this order:

```markdown
# Analyse comparative — [Titre cadre normatif A] × [Titre cadre normatif B]

**Date :** <ISO date>
**Périmètre :** <brief one-line scope from matrix header>
**Note méthodologique :** <two sentences — what was compared, how, and what is out of scope>

---

## Tableau de correspondance

<See R.0-bis — deterministic, generated from matrix-compare.org. Group by legal theme.>

---

## 1. Résumé exécutif

<3–5 bullet points: overall picture, number of equivalences, major divergences,
 notable gaps. No technical terms. Written for a decision-maker.>

---

## [Statut de transposition | d'alignement | Évolution entre versions]

<See R.1-bis — section title and label mapping adapt to relationship_type.
 Generated from direction + origin values in matrix-compare.org.>

---

## Priorités d'analyse

<See R.1-ter — 🔴/🟡/🟢 derived deterministically from direction + evidence.
 Labels adapt to relationship_type. Omit a level if it has 0 items.>

---

## 2. Dispositions équivalentes

> Les obligations suivantes sont couvertes de manière équivalente dans les deux
> référentiels — elles n'appellent pas d'analyse complémentaire.

<Grouped by legal theme. For each group, one paragraph naming the concept and
 its legal basis in both texts (article numbers). No rule IDs, no agent names.>

---

## 3. Divergences substantielles

> Les points suivants révèlent une différence de fond entre les deux référentiels.
> Chaque fiche indique la nature de la divergence et son impact pratique.

<Section 3 lists ONLY rows with origin `legal-divergence` (atoms on both sides).
 A provision found on one side only goes to section 4, never here — even when
 the other column reads "non couvert". Order the fiches by direction: weaker/
 different first (conformity risk), stricter after. Open the section with a
 count by direction, and make it equal to the number of fiches.>

<One "fiche" per divergence:>

### [Thème] — [Concept en langage clair]

| | [Cadre normatif A] | [Cadre normatif B] |
|---|---|---|
| Texte de référence | Art. X Dir. Y | Art. Z Loi W |
| Obligation / condition | <plain language> | <plain language> |
| Seuil / paramètre | <value + unit> | <value + unit> |

**Nature de la divergence :** <A stricter / B stricter / champs d'application distincts>
**Impact pratique :** <one sentence for a legal professional>
**Nature :** <direction in plain language: plus stricte / moindre protection / mécanismes différents>
**Statut :** ✅ établi par test comparatif / 📄 établi par comparaison des textes (non testé) / ⚠️ à confirmer
<Use ⚠️ whenever the alignment is llm-only or the pair rests on a different
 legal mechanism (e.g. different instrument for the same concept).>

---

## 4. Dispositions sans équivalent

### 4.1 — Présentes dans [cadre A] uniquement

<List by theme. For each: concept name, article reference, one-line description.
 State explicitly: "absence confirmée dans le texte" (absence_proof present) or
 "non modélisé dans le périmètre de l'analyse" (kb-gap). Never present a
 kb-gap as a divergence. In 4.2, if the provision belongs to a general regime of
 the other framework (e.g. an EU directive), say so rather than implying a
 national specificity.>

### 4.2 — Présentes dans [cadre B] uniquement

<Same format.>

---

## 5. Points nécessitant une analyse juridique complémentaire

<Items with status uncertain, low confidence, or helpers-opaque.
 Present as a numbered list with: concept, reason for uncertainty, suggested action.>

---

## Recommandations

<See R.3-bis — LLM-assisted, restricted to 🔴 items from R.1-ter.
 Section subtitle adapts to relationship_type.
 Always end with the non-legal-advice disclaimer.>

---

## Annexe — Périmètre de l'analyse et limites

**Textes analysés :**
- [Cadre A] : <list of normative sources from corpus>
- [Cadre B] : <list of normative sources from corpus>

**Cohérence interne :** the counts in section 1, the matrix and sections 3–5 must
agree; if a figure counts matrix rows and another counts fiches, label each.
State the temporal scope of each text (consolidated version / last amendment
included).

**Asymétries de périmètre :** <list `scoping_asymmetries` in legal language:
"Les dispositions suivantes ont été analysées dans [cadre B] mais non dans
[cadre A] ; l'absence de correspondant ne vaut pas absence de la règle.">

**Hors périmètre de la présente analyse :**
<Paraphrase the Deferred-S items in legal language:
 "Les dispositions suivantes n'ont pas été intégrées dans l'analyse formelle,
 car elles relèvent d'obligations comportementales ou procédurales dont
 la vérification requiert une appréciation au cas par cas :">
<Bullet list of Deferred-S items — article + one-line description, no Chorus terms.>

**Méthode :** <two sentences: deterministic threshold comparison + LLM-assisted
 concept alignment, without mentioning Chorus, KB, or rules.>
```

### R.3-bis — Recommendations

> **Position in report:** before the Annexe.
> **Always generated** — section subtitle and framing adapt to `relationship_type`.
> **Method:** LLM-assisted, strictly limited to what is derivable from the matrix.

**Input:** all rows with `direction: *_weaker` + `legal-absence` on the
`reference_sandbox` side (level 🔴 items from R.1-ter).

**Section subtitle adapts to `relationship_type`:**
- `hierarchical` : *Pour aligner [cadre B] sur [cadre A / instrument_type]*
- `parallel`     : *Pistes d'harmonisation entre les deux référentiels*
- `sequential`   : *Points à traiter dans la prochaine version*

**LLM instructions (generic — domain-independent):**

For each 🔴 item, formulate in one sentence what should change in [cadre B] to
reach [cadre A]'s level on this point.
- Do NOT cite jurisprudence, case law, or preparatory works.
- Restrict to what is directly derivable from the compared thresholds / obligations.
- If `evidence: llm-only` → prefix with `⚠ à confirmer`.
- Label each item with its confidence level: `établi` (evidence: text-anchored or
  witness-confirmed) | `à confirmer` (evidence: llm-only).
- If 🔴 list is empty → emit: *"Aucune divergence de conformité identifiée dans
  le périmètre analysé."*

Output in report:
```markdown
## Recommandations

### [Section subtitle]

1. **[Concept]** — [action concrète en une phrase]
   Base : [ref cadre A] vs [ref cadre B] · Niveau de certitude : [établi / à confirmer]

2. …

> Note : ces recommandations sont dérivées mécaniquement des divergences identifiées.
> Elles ne constituent pas un avis juridique.
```

### R.4 — Output

Write the report to `$COMPARE/rapport-comparatif-<A>-vs-<B>.md`
(or `--report-out` path if specified).

Then convert to PDF:
```bash
python3 $ENGINE/scripts/md2pdf.py \
  $COMPARE/rapport-comparatif-<A>-vs-<B>.md \
  $COMPARE/rapport-comparatif-<A>-vs-<B>.pdf
```

Display on completion:
```
📄 Rapport juridique comparatif généré :
   MD  → $COMPARE/rapport-comparatif-<A>-vs-<B>.md
   PDF → $COMPARE/rapport-comparatif-<A>-vs-<B>.pdf

   Sections : 1 résumé · N équivalences · N divergences · N sans équivalent · N incertains
   Prochaine étape : relire la section 5 (points à confirmer) avec un juriste.
```

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
