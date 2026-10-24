# Skill — chorus-strengthen

> Trigger: `chorus-strengthen <sandbox-name>`
> Agent: `architect`
>
> `<sandbox-name>`: sandbox with a KB, YAML rules, and a coverage suite (`project-*.json`)
>
> **Single responsibility: identify rule gaps and produce an enrichment roadmap.**
> This skill runs the full project suite, analyses every discordance and unprocessed
> element, produces a structured gap report, and recommends the enrichment corpus
> to pass to `chorus-feed --enrich`.
>
> It does NOT modify any KB, YAML, or Perl file — it only reads and reports.
>
> Prerequisites:
> - `chorus-feed <sandbox-name>` must have been run (KB + YAML present)
> - `chorus-check <sandbox-name> <any-project>` must have been run at least once (infra present)
> - At least one `project-*.json` file must exist in `$SANDBOX/`
>   (ideally the full batch from `chorus-create-project <sandbox-name> --batch`)

---

## Phase 0 — Sandbox inventory

Read the directory tree $SANDBOX/ (max_depth=3) to confirm:

- `$SANDBOX/run.pl` — infrastructure present
- `$SANDBOX/agent/.kb-hash` — hash present (infra is up to date)
- `$SANDBOX/project-*.json` — at least one project file

If the infrastructure is absent or the hash is missing → stop:
```
⛔ Infrastructure not generated yet.
   Run: chorus-check <sandbox-name> <any-project.json>
```

If no `project-*.json` → stop:
```
⛔ No coverage suite found in $SANDBOX/.
   Run: chorus-create-project <sandbox-name> --batch
```

---

## Phase 1 — Obtain full-suite results

### 1.1 — Check for a cached result (fast path)

Before running anything, probe for a cached result file:

```bash
cat $SANDBOX/.last-check-results.json   # absent → go to 1.2
sha256sum $SANDBOX/agent/chorus/*.org   # compute current KB hash
```

Compare the `kb_hash` field in `.last-check-results.json` against the current
hash of `$SANDBOX/agent/chorus/*.org`:

- **Match** → the KB has not changed since the last `chorus-check --all`.
  Load the structured results directly from the file.
  **Skip Phase 1.2 entirely** — no sub-agent is spawned, no `perl run.pl` is run.
  Note in the gap report header: `Suite results: from cache (.last-check-results.json)`.

- **No file** or **hash mismatch** → the cache is absent or stale. Go to Phase 1.2.

### 1.2 — Run the full suite (fallback)

Execute `chorus-check <sandbox-name> --all` (fast path — no infrastructure
regeneration, but spawns one sub-agent per `project-*.json`).

This produces the synthesis table with CONFORME / NON_CONFORME / Unproc / Disc
counts per project file, and writes a fresh `.last-check-results.json`.
Capture the full output.

---

Whether results come from cache (1.1) or a fresh run (1.2):

If **all files converge** (SOLVED, 0 discordances, 0 unprocessed) → report:

```
✅ Suite converged — no gaps detected.
   The KB covers all tested cases. No enrichment needed at this time.
```

> ⚠️ **Partial convergence warning:** this message is only reliable if a
> `project-stress-*.json` file also exists in `$SANDBOX/`. Without adversarial
> test cases (boundary values, missing mandatory slots, `_AFTER` propagation
> chains), the suite exercises nominal paths only — edge-case gaps remain
> invisible. If no stress file is present, append to the report:
> ```
> ⚠️ Convergence is partial — no chorus-stress suite found.
>    Run: chorus-stress <sandbox-name>  then re-run chorus-strengthen
>    for a complete picture.
> ```

and stop. No gap report is needed.

---

## Phase 2 — Classify discordances

### 2.0 — Uncertain-elements pre-filter (stress files only)

Before classifying any discordance, scan all `project-stress-*.json` files in `$SANDBOX/`
and build the **uncertain-elements exclusion set**:

```
uncertain_ids = Set()

for each project-stress-*.json in $SANDBOX/:
  for each element in elements[]:
    if element._expected_uncertain == true:
      uncertain_ids.add(element.id)
```

If `uncertain_ids` is non-empty, record the count for the gap report:
```
  N element(s) with _expected_uncertain=true — excluded from gap classification.
  See stress-manifest.org for manual review details.
```

**Any discordant element whose id is in `uncertain_ids` is excluded from the
classification below** — it does NOT count as a gap, is NOT listed in Phase 4,
and does NOT appear in the enrichment roadmap. It is reported separately in Phase 4
under a dedicated section (§ Uncertain stress results).

If no `project-stress-*.json` file exists → skip this step silently.

### 2.1 — Gap classification

For each discordant element (expected ≠ actual) **not in `uncertain_ids`**, classify into one of three
gap types:

| Gap type | Pattern | Root cause |
|---|---|---|
| **Rule too strict** | Expected CONFORME → got NON_CONFORME | A rule rejects a valid case — threshold wrong, CONDITION too narrow, or edge case not covered |
| **Rule too permissive** | Expected NON_CONFORME → got CONFORME | No rule fires on this case — missing rule, threshold too high, or CONDITION excludes this type |
| **Rule permanently blocked** | Expected NON_CONFORME → got CONFORME — no rule fired | A sibling rule wrote the EXCEPTION guard slot first in an earlier cycle, permanently blocking the veto/override rule via Pattern 1 (`defined $f->{slot}`). The veto rule will never fire on this Frame regardless of subsequent cycles. |
| **Feed gap** | Element is `(unprocessed)` | Targeting slot not set by Feed for this element type — `besoin_<slug>` missing from `%SLOTS_REQUIS` or Feed logic |

> **Distinguishing "Rule too permissive" from "Rule permanently blocked":**
> Both produce `got CONFORME` when `NON_CONFORME` was expected. Diagnostic:
> - If no rule mentions this element in the pipeline output → could be either.
>   Check: did a sibling rule write the shared EXCEPTION guard slot for this Frame?
>   If yes → permanently blocked (fix: Pattern 2 on the veto rule).
>   If no → rule condition genuinely not met (fix: add/adjust rule or threshold).
> - `CONDITION` is **always transient**: if the rule's prerequisite slot was not yet
>   available, it retried every cycle. If it still didn't fire, the issue is that the
>   prerequisite was never set (Feed gap or missing rule upstream) — not a CONDITION bug.
> - `filtre` exclusion: if the veto rule uses `filtre` instead of `CONDITION` to test
>   for its prerequisite, the Frame is permanently out of scope. Check whether the
>   `filtre` expression references a slot that is computed by another rule (must be
>   in `CONDITION`, never in `filtre`).

For each element, identify:
- The element `id` and `type_element`
- The expected result (from `_resultats_attendus` in the JSON, or from the ID naming convention)
- The actual result (from the pipeline output)
- The rule that fired (if any) — visible in the pipeline output as `raison_non_conformite`
- The project file it belongs to (`project-rules-iso`, `project-edges`, `project-cross`, `project-scale`)

> **Diagnostic method by suite type — run these checks BEFORE modifying any YAML:**
>
> | Suite in discordance | First diagnostic | Rationale |
> |---|---|---|
> | `edges` or `scale` | Run `chorus-markdown --report` on the source `.md` file(s) for the implicated threshold | A discordance concentrated on numeric thresholds may come from an OCR/vision extraction error in the `.md` — fixing the YAML would address a symptom, not the cause |
> | `cross` | Read `agent/chorus/index.org § Slot ownership` for the implicated slot | Cross discordances often trace to a "rule permanently blocked" pattern — a guard EXCEPTION was written too early by an upstream agent. The slot ownership table immediately identifies the responsible agent |
> | `iso` | The gap is most likely a genuine rule quality issue — proceed normally with Phase 3 |
>
> A discordance concentrated on a single suite type is a **diagnostic signal**: apply
> the above check before reading any rule file. If the check reveals an extraction
> error or a slot ownership conflict, fix at that level — do not modify the YAML rule.
  or from the absence of any firing rule
- The project file it belongs to (`project-rules-iso`, `project-edges`, etc.)

---

## Phase 3 — Read the relevant KB sections

For each gap identified in Phase 2, read only the sections of the relevant
agent KB that cover the implicated rule:

- `Règles` / `Rule catalog` section → rule intent, CONDITION, threshold
- `Helpers Perl` section → normative tables for the implicated slot
- `Contraintes & Pitfalls` section → known edge cases

> **Strict isolation:** read only `$SANDBOX/agent/chorus/<slug>.org`.
> Never read any file from another sandbox.

---

## Phase 4 — Produce the gap report

> **⚠️ Language rule — gap report:** all section headings, column labels, field names,
> hypotheses, and suggested fixes in this report must be written in the **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

Display a structured report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-strengthen  <sandbox-name>
  <N> gap(s) detected across <M> project file(s)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

For each gap, one entry:

```
  ── Gap #N — <gap-type> ─────────────────────────────────────
  Element    : <id>  (<type_element>)  in <project-file>
  Expected   : <CONFORME|NON_CONFORME>
  Got        : <CONFORME|NON_CONFORME|unprocessed>
  Rule fired : <R0N-slug> — "<rule name>"  (or: none)
  Agent      : <agent-slug>

  Hypothesis : <concise description of the probable cause>
               e.g. "Threshold for slot 'hauteur_libre' is set to 2.50 m
                     in R02 but the corpus §4.2 states 2.40 m for class C."

  Corpus ref : §<N> — <section title> — <document>
               (or: unknown — needs manual verification)

  Suggested fix:
    → YAML: adjust CONDITION/threshold in <R0N-slug>.yml
    → OR: EXCEPTION Pattern 1→2: replace `EXCEPTION: defined $f->{slot}`
          with `EXCEPTION: '($f->{slot} // "") eq "<veto_value>"'`
          (use when a sibling rule fired first and permanently blocked this rule)
    → OR: filtre→CONDITION: move cross-rule slot tests from `filtre` to `CONDITION`
          (use when the Frame was permanently excluded but should have waited for
           another rule to set its prerequisite)
    → OR: add new rule R<NN>-<slug>.yml covering this case
    → OR: Feed: add 'besoin_<slug>' to %SLOTS_REQUIS for type <X>
```

After all gaps:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Summary by gap type
  Rule too strict       : N gap(s)  → thresholds or CONDITION to relax
  Rule too permissive   : N gap(s)  → missing rules or thresholds to tighten
  Rule perm. blocked    : N gap(s)  → EXCEPTION Pattern 1→2, or filtre→CONDITION
  Feed gap              : N gap(s)  → %SLOTS_REQUIS or Feed logic to extend
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `uncertain_ids` (from Phase 2.0) is non-empty, append a dedicated section:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Uncertain stress results — manual review required
  (excluded from gap classification above)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

For each element in `uncertain_ids` that produced a discordance:

```
  ── Uncertain #N ────────────────────────────────────────────────
  Element   : <id>  in <project-stress-file>
  Got       : <CONFORME|NON_CONFORME|unprocessed>
  Stress    : family=<family>  slot=<slot>  threshold=<value>
  Note      : <_stress_note content from the JSON>

  Action    : Manual review — compare pipeline result against corpus source.
              If result is wrong → treat as a real gap (classify above,
              add to enrichment roadmap).
              If result is correct → set _expected_uncertain=false and
              _resultats_attendus to the verified verdict in the JSON.
              Ref: stress-manifest.org § Uncertain expected results
```

---

## Phase 4.5 — Serialize gap report to JSON

> **This step is mandatory** — it enables `chorus-fix` and the webapp Tests tab
> to consume the gap report without re-parsing the text output.
>
> Write immediately after displaying the text report. Do not skip even if no
> gaps were found (write with `total_gaps: 0` and an empty `gaps[]` array —
> the webapp uses this to distinguish "strengthen ran, no gaps" from "strengthen
> never ran").

Write `$SANDBOX/.last-strengthen-report.json`:

```json
{
  "kb_hash":    "<current sha256 hash of $SANDBOX/agent/chorus/*.org>",
  "timestamp":  "<ISO 8601 — now>",
  "sandbox":    "<sandbox-name>",
  "total_gaps": N,
  "summary": {
    "bucket_b": N,
    "bucket_c": N,
    "bucket_a": N,
    "rule_too_strict":       N,
    "rule_too_permissive":   N,
    "rule_perm_blocked":     N,
    "feed_gap":              N
  },
  "gaps": [
    {
      "id":                1,
      "gap_type":          "rule_too_strict|rule_too_permissive|rule_perm_blocked|feed_gap",
      "bucket":            "B|C|A",
      "agent":             "<agent-slug>",
      "rule_file":         "<R0N-slug.yml>  (or null if no rule fired)",
      "element_id":        "<id from project JSON>",
      "type_element":      "<type_element value>",
      "project_file":      "<project-rules-iso.json>",
      "expected":          "CONFORME|NON_CONFORME",
      "got":               "CONFORME|NON_CONFORME|unprocessed",
      "hypothesis":        "<concise one-line description>",
      "corpus_ref":        "<§N — section — document>  (or null)",
      "suggested_fix_type":"threshold|condition|exception_pattern|filtre_to_condition|new_rule|feed",
      "blocked":           false
    }
  ]
}
```

**`bucket` derivation rules** (for the webapp — derived mechanically, not from LLM judgment):

| `gap_type` | `suggested_fix_type` | `bucket` |
|---|---|---|
| `rule_too_strict` or `rule_too_permissive` or `rule_perm_blocked` | `threshold`, `condition`, `exception_pattern`, `filtre_to_condition` | `B` |
| `rule_too_strict` or `rule_too_permissive` | `new_rule` | `C` |
| `feed_gap` | `feed` | `C` |
| any | corpus ref is `null` or `unknown` | `A` |

> **`blocked` field:** set to `true` when the anti-regression guard in `chorus-fix`
> has previously flagged this gap as requiring manual verification before patching.
> On a fresh strengthen run, always set to `false` — `chorus-fix` may update this
> field in place after running the guard (the webapp reads the updated file).

**`kb_hash`:** use the same value as in `.last-check-results.json` if strengthen
was triggered from a cached result (Phase 1.1); otherwise recompute from the current
`agent/.kb-hash` file.

---

## Phase 5 — Enrichment roadmap

### 5.1 Group gaps by corrective action

Group all gaps into three buckets:

| Bucket | Content | Action |
|---|---|---|
| **A — Corpus clarification** | Gaps where the normative source is unclear or ambiguous | Need to re-read the original corpus §, possibly extract a correction text |
| **B — Rule adjustment** | Gaps where the corpus reference is known and the fix is a threshold / CONDITION change | Direct YAML edit (does not require `chorus-feed --enrich`) |
| **C — Missing coverage** | Gaps where the KB has no rule at all for this case | New rule needed → `chorus-feed --enrich` with a targeted corpus fragment |

### 5.2 Enrichment corpus recommendation

For bucket **C** (missing coverage), produce a recommendation:

```
Recommended enrichment corpus
──────────────────────────────
For each missing-coverage gap, draft the normative text fragment that covers it.
This text should be passed to:

  chorus-feed <sandbox-name> <corpus-correctif.txt> --enrich

Suggested corpus-correctif.txt content:
─────────────────────────────────────────
[Gap #N — <type>/<slot>]
<Normative extract or paraphrase covering the missing rule.
 Include: element type, triggering condition, threshold value, rejection reason.>

[Gap #M — <type>/<slot>]
<...>
─────────────────────────────────────────
After running chorus-feed --enrich, re-run:
  chorus-check <sandbox-name> --all
  chorus-strengthen <sandbox-name>   ← to verify convergence
```

### 5.3 Convergence loop reminder

```
Reinforcement loop:
  chorus-create-project <sb> --batch          ← (once, or if suite is stale)
       ↓
  chorus-stress <sb>                          ← adversarial cases (boundary/missing/edge/cascade)
       ↓
  chorus-strengthen <sb>                      ← identify gaps (typical + stress suites)
       ↓
  chorus-fix <sb> [--dry-run]                 ← apply bucket B patches + generate corpus-correctif
  chorus-feed <sb> corpus-correctif.txt --enrich  ← bucket C new rules (auto via chorus-fix --bucket-c)
       ↓
  chorus-check <sb> --all                     ← verify both suites
       ↓
  chorus-strengthen <sb>                      ← check convergence
       ↓
  ✅ CONVERGED  — all projects pass, 0 discordances, 0 unprocessed
     (typical suite: project-rules-iso / edges / cross / scale
      stress suite:  project-stress-* with _expected_uncertain=false)
```

---

## Separation of responsibilities

| | `chorus-feed` | `chorus-create-project` | `chorus-stress` | `chorus-check` | `chorus-strengthen` | `chorus-fix` |
|---|---|---|---|---|---|---|
| **Reads** | corpus | sandbox org KB | org KB + YAML CONDITIONs | org KB + YAML | pipeline output + org KB | gap report + YAML + project JSON |
| **Produces** | KB org, YAML, Helpers.pm | `project-*.json` (typical) | `project-stress-*.json` (adversarial) | Feed.pm, Agent shells, Expert.pm, run.pl | gap report + enrichment roadmap | patched YAML + `corpus-correctif.txt` |
| **Expected results** | — | LLM + KB inference | **Deterministic from threshold_registry** | — | — | — |
| **Modifies KB** | ✅ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Modifies YAML** | ✅ | ✗ | ✗ | ✗ | ✗ | **✅ (Bucket B)** |
| **Triggered by** | new standard | coverage need | after `--batch` | project to validate | failed `--all` | strengthen gap report |
