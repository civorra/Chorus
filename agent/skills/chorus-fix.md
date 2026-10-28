# Skill — chorus-fix

> Trigger: `chorus-fix <sandbox-name> [--bucket-b] [--bucket-c] [--dry-run] [--from <gap-report.md>]`
> Agent: `code`
>
> `<sandbox-name>`: sandbox with a KB, YAML rules, and a gap report from `chorus-strengthen`
>
> **Single responsibility: apply corrections diagnosed by `chorus-strengthen`.**
> This skill reads the gap report, patches YAML rules for Bucket B gaps, and generates
> `corpus-correctif.txt` for Bucket C gaps. It verifies the result by re-running
> `chorus-check --all` and `chorus-strengthen`.
>
> It does NOT modify KB org files, Helpers.pm, Feed.pm, or any project JSON.
>
> Options:
>
> | Option | Behaviour |
> |---|---|
> | *(none)* | Apply Bucket B YAML edits + generate `corpus-correctif.txt` for Bucket C |
> | `--bucket-b` | Bucket B only (YAML edits) |
> | `--bucket-c` | Bucket C only (generate `corpus-correctif.txt` + run `chorus-feed --enrich`) |
> | `--dry-run` | Show a diff of all planned changes — no file is written |
> | `--from <file>` | Read the gap report from `<file>` instead of re-running `chorus-strengthen` |
>
> Prerequisites:
> - `chorus-strengthen <sandbox-name>` must have been run (gap report available)
> - At least one `project-*.json` must exist in `$SANDBOX/` (for anti-regression guard)
>
> ⚠️ **Recommended first use:** always run with `--dry-run` on a new sandbox to review
> planned patches before applying them.

---

## Phase 0 — Acquire the gap report

### 0.1 — Sandbox inventory

Read the directory tree `$SANDBOX/` (max_depth=2):
- Confirm `$SANDBOX/rules/<slug>/` directories are present (YAML to patch)
- Confirm at least one `$SANDBOX/project-*.json` exists (for the anti-regression guard)
- Confirm `$SANDBOX/agent/chorus/<slug>.org` files are present

### 0.2 — Load the gap report

**If `--from <file>` is present:** read the specified file directly.

**Otherwise:**

1. Check for `$SANDBOX/.last-check-results.json`.
2. If absent → stop:
   ```
   ⛔ No gap report found. Run first:
      chorus-strengthen <sandbox-name>
   ```
3. If present: compute the current hash of `$SANDBOX/agent/chorus/*.org` and compare
   against the `kb_hash` field of `.last-check-results.json`.
   - **Match** → the KB has not changed since the last strengthen run. Use the cached report.
   - **Mismatch** → stop:
     ```
     ⛔ Gap report is stale (KB has changed since last chorus-strengthen).
        Re-run: chorus-strengthen <sandbox-name>
        Then: chorus-fix <sandbox-name>
     ```

### 0.3 — Parse gap list

From the gap report, extract the list of classified gaps. For each gap, record:

| Field | Source in the report |
|---|---|
| `gap_id` | `Gap #N` |
| `gap_type` | `rule too strict` · `rule too permissive` · `rule permanently blocked` · `feed gap` |
| `bucket` | B or C (derived from gap_type and `Suggested fix` line) |
| `element_id` | `Element:` line |
| `agent_slug` | `Agent:` line |
| `rule_file` | from `Suggested fix: → YAML: adjust … in <R0N-slug>.yml` or `add new rule` |
| `hypothesis` | `Hypothesis:` section |
| `corpus_ref` | `Corpus ref:` line |
| `suggested_fix` | `Suggested fix:` section |

Build two lists: `bucket_b_gaps[]` and `bucket_c_gaps[]`.

If both lists are empty → report:
```
✅ Gap report contains no Bucket B or C gaps.
   Bucket A items (corpus clarification) require human review.
```
and stop.

---

## Phase 1 — Bucket B: YAML patches

> Skip this phase if `--bucket-c` is present (Bucket C only mode).

For each gap in `bucket_b_gaps[]`:

### 1.1 — Read the target YAML

Read `$SANDBOX/rules/<agent_slug>/<rule_file>.yml`.

If the file does not exist → skip this gap with a warning:
```
⚠️ Gap #N: rule file not found: rules/<slug>/<rule_file>.yml — skipping.
```

### 1.2 — Compute the patch

Apply the patch formula matching the gap type:

**Rule too strict** (expected CONFORME → got NON_CONFORME):
- Threshold relaxation: identify the numeric threshold in the `CONDITION` or `ACTION`
  that rejects the failing element; adjust it in the direction that would accept
  the element (e.g. lower a minimum, raise a maximum).
- CONDITION widening: if the `CONDITION` excludes a valid subtype or class,
  add it with `||`.
- Source: use the exact value from `Hypothesis` / `Corpus ref` in the gap report.

**Rule too permissive** (expected NON_CONFORME → got CONFORME):
- Threshold tightening: adjust the threshold in the direction that would reject
  the failing element.
- Missing CONDITION: add a guard clause that catches the uncovered case.

**Rule permanently blocked** (EXCEPTION Pattern 1 → Pattern 2):
Replace:
```yaml
EXCEPTION: defined $f->{<guard_slot>}
```
with:
```yaml
EXCEPTION: '($f->{<guard_slot>} // "") eq "<veto_value>"'
```
The `<veto_value>` is derived from the hypothesis (the specific value the sibling
rule writes to `<guard_slot>` that should not block this rule).

**filtre → CONDITION migration:**
Move the cross-rule slot test from the `filtre` block into a `CONDITION` clause,
so the Frame is not permanently excluded when the prerequisite slot has not yet
been set by an upstream rule.

> ⚠️ **Exact values only:** all threshold values and condition strings must come
> from the gap report's `Hypothesis` + `Corpus ref` fields — never inferred.
> If a value is missing or ambiguous in the report → skip the gap with a warning
> and flag it for manual review.

### 1.3 — Anti-regression guard (mandatory — never skip)

Before writing any patch, verify that the change does not reclassify an existing
conforming element as non-conforming.

**Procedure:**

1. Read all `$SANDBOX/project-*.json` files.
2. For each file, collect every element whose type matches the rule's `FIND` / `CHERCHER`
   `filtre` (i.e. the `type_element` the rule targets).
3. Among those, keep only elements with an expected CONFORME result:
   - `id` contains `-OK-` or `-CONFORME-`, OR
   - `_resultats_attendus` field is `"CONFORME"`.
4. For each such element, simulate the patched CONDITION mentally:
   - Extract the slot values from the element JSON.
   - Apply the new threshold/CONDITION to those values.
   - If the patched condition would now **reject** this element → **BLOCK the patch**:
     ```
     ⚠️ Anti-regression guard triggered — Gap #N patch BLOCKED.
        Rule    : <rule_file>
        Patch   : <description of change>
        At risk : <element_id> in <project_file>
                  (slot <slot>=<value> would fail the new condition)
        Action  : Manual review required before applying this patch.
                  Check corpus §<ref> for the exact threshold.
     ```
   - Do not apply this patch. Add the gap to the residual report (Phase 4).

5. If no conforming element is at risk → the patch is safe to proceed.

### 1.4 — Apply or preview

**`--dry-run` mode:** display the diff for each safe patch:
```
── Gap #N — <gap_type> ──────────────────────────────────────────
  File : rules/<slug>/<rule_file>.yml
  --- before
  +++ after
  @@ ...
  -  CONDITION: ...
  +  CONDITION: ...
```

**Normal mode:** write the patched YAML using `eca__edit_file`.
Record the applied patch in the closure report (Phase 4).

---

## Phase 2 — Bucket C: corpus-correctif.txt

> Skip this phase if `--bucket-b` is present (Bucket B only mode).

### 2.1 — Generate the correction corpus

For each gap in `bucket_c_gaps[]`, draft a normative text fragment:

```
[Gap #N — <type_element>/<slot>]
<Normative text covering the missing rule.>
<Include: element type(s), triggering condition, threshold or criterion, rejection reason.>
<Source: corpus §<ref>.>
```

Base the text on the `Hypothesis` and `Corpus ref` fields from the gap report.
Do not invent normative content — if the corpus ref is `unknown`, mark the fragment
as `[REQUIRES MANUAL VERIFICATION]` and include it anyway for completeness.

### 2.2 — Determine the output filename

List existing `$SANDBOX/corpus-correctif-*.txt` files and pick the next counter:
- None exist → `corpus-correctif-001.txt`
- Highest existing is `corpus-correctif-002.txt` → write `corpus-correctif-003.txt`

### 2.3 — Write and optionally enrich

Write the file to `$SANDBOX/<filename>`.

**If `--bucket-c` is present:** run:
```bash
chorus-feed <sandbox-name> $SANDBOX/<filename> --enrich
```

**Otherwise:** display:
```
📄 Bucket C — corpus-correctif written: $SANDBOX/<filename>
   N fragment(s) for N rule gap(s).

   To apply:
     chorus-feed <sandbox-name> $SANDBOX/<filename> --enrich
```

---

## Phase 3 — Verification

> Skip this phase if `--dry-run` is active.

After any write (Phase 1 YAML patches or Phase 2 with `--bucket-c`):

### 3.1 — Re-run the pipeline

```bash
# chorus-check --all (fast path — reuses existing infrastructure)
```

Run `chorus-check <sandbox-name> --all` to get fresh results for all project files.

### 3.2 — Re-run strengthen

Run `chorus-strengthen <sandbox-name>` to obtain the updated gap count.

Capture:
- Total remaining gaps
- Remaining Bucket B / C / A counts
- Any new gaps introduced (regression indicator)

If the total gap count **increased** compared to Phase 0 → report a regression:
```
⚠️ Regression detected: gap count increased after patching.
   Before: N gap(s)  →  After: M gap(s)  (M > N)
   Newly appeared gaps are listed in the strengthen report above.
   Recommended action: revert the last YAML patch and review manually.
```

---

## Phase 4 — Closure report

> Also produced in `--dry-run` mode (shows what would have been done).

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-fix  <sandbox-name>  [--dry-run?]
  N gap(s) processed from the strengthen report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Bucket B — YAML patches
  ───────────────────────
  Applied    : N  (files: <list of R0N-slug.yml>)
  Blocked    : N  (anti-regression guard triggered — manual review)
  Skipped    : N  (missing rule file or ambiguous hypothesis)

  Bucket C — corpus-correctif
  ───────────────────────────
  Generated  : $SANDBOX/corpus-correctif-<NNN>.txt  (N fragment(s))
  Enrichment : [run / pending — run `chorus-feed <sandbox> ... --enrich`]

  Bucket A — corpus clarification (human required)
  ─────────────────────────────────────────────────
  N item(s) — not actionable automatically.
  See the strengthen report for corpus refs.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  After fix convergence check (Phase 3)
  Gaps before  : N
  Gaps after   : M
  Delta        : -N resolved  [+N regression?]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If gaps remain → suggest the next step:
```
Next: chorus-fix <sandbox-name>   ← another pass (remaining B/C gaps)
  or: chorus-strengthen <sandbox-name>   ← re-diagnose if KB has changed
```

### 4.1 — Write `.last-fix-history.json`

**Always write this file**, even in `--dry-run` mode (use `"dry_run": true` in that case).
This file is the machine-readable record consumed by the webapp Test tab to display the
full fix history across all `chorus-fix` runs on this sandbox.

Path: `$SANDBOX/.last-fix-history.json`

**Accumulation procedure (mandatory — never overwrite blindly):**

1. If `$SANDBOX/.last-fix-history.json` already exists, read and parse it.
2. Extract the existing top-level run fields (`timestamp`, `patches`, etc.) into a
   run object. Collect existing `previous_runs` array (default `[]`).
3. Prepend the extracted run to `previous_runs` → `[old_run, ...previous_runs]`.
4. Trim `previous_runs` to the **10 most recent entries** (drop the oldest) to
   avoid unbounded growth.
5. Write the new file with the **current run** at the top level and the accumulated
   history in `previous_runs`.

If the file does not exist yet → write with `previous_runs: []`.

Format:

```json
{
  "timestamp":       "YYYY-MM-DDTHH:MM:SSZ",
  "sandbox":         "<sandbox-name>",
  "dry_run":         false,
  "gaps_before":     N,
  "gaps_after":      M,
  "gaps_resolved":   N-M,
  "patches": [
    {
      "gap_id":         1,
      "gap_type":       "rule too strict",
      "element_id":     "AES-GCM-128-OK-001",
      "rule_file":      "R02-algo-sym.yml",
      "agent":          "crypto-mecanismes-sym",
      "change":         "CONDITION: $f->{taille_cle} >= 256  →  >= 128",
      "status":         "applied",
      "blocked_reason": null
    },
    {
      "gap_id":         3,
      "gap_type":       "rule too permissive",
      "element_id":     "RSA-1024-KO-007",
      "rule_file":      "R05-algo-asym.yml",
      "agent":          "crypto-mecanismes-asym",
      "change":         null,
      "status":         "blocked",
      "blocked_reason": "anti-regression guard: element RSA-2048-OK-001 would be rejected"
    }
  ],
  "corpus_correctif": "corpus-correctif-002.txt",
  "bucket_a_count":   N,
  "bucket_a_items": [
    {
      "gap_id":     5,
      "element_id": "DILITHIUM-KO-003",
      "hypothesis": "Corpus §4.3.2 ambiguous — manual review required"
    }
  ],
  "previous_runs": [
    {
      "timestamp":     "YYYY-MM-DDTHH:MM:SSZ",
      "dry_run":       false,
      "gaps_before":   5,
      "gaps_after":    3,
      "gaps_resolved": 2,
      "patches": [...],
      "corpus_correctif": null,
      "bucket_a_count": 1
    }
  ]
}
```

Field rules:
- `gaps_after` is `null` in `--dry-run` mode (Phase 3 not run, no new strengthen output).
- `gaps_resolved` is `null` in `--dry-run` mode.
- `corpus_correctif` is `null` if no Bucket C file was generated.
- `patches[].change` is `null` for `blocked` or `skipped` entries.
- `patches[].blocked_reason` is `null` for `applied` entries.
- `bucket_a_items` may be an empty array `[]` if no Bucket A gaps exist.
- `previous_runs` entries use the same fields as the top-level run (minus `previous_runs`
  itself — no nesting). `bucket_a_items` may be omitted in historical entries to save
  space — the webapp only uses `bucket_a_count` for historical display.
- Maximum 10 entries in `previous_runs` (oldest dropped on overflow).

> This file is **never committed** (add to `.gitignore` alongside `.last-strengthen-report.json`
> if not already covered). It is a cumulative operational artefact, updated on each
> `chorus-fix` run.

---

## Separation of responsibilities

| | `chorus-feed` | `chorus-create-project` | `chorus-stress` | `chorus-check` | `chorus-strengthen` | **`chorus-fix`** |
|---|---|---|---|---|---|---|
| **Reads** | corpus | sandbox org KB | org KB + YAML CONDITIONs | org KB + YAML | pipeline output + org KB | gap report + YAML + project JSON |
| **Produces** | KB org, YAML, Helpers.pm | `project-*.json` (typical) | `project-stress-*.json` | Feed.pm, Agent shells, Expert.pm, run.pl | gap report + enrichment roadmap | patched YAML + `corpus-correctif.txt` + `.last-fix-history.json` |
| **Modifies KB** | ✅ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Modifies YAML** | ✅ | ✗ | ✗ | ✗ | ✗ | **✅ (Bucket B)** |
| **Triggered by** | new standard | coverage need | after `--batch` | project to validate | failed `--all` | strengthen gap report |

---

## Limits and guarantees

- **chorus-fix does not validate semantic correctness** against the corpus source — it
  applies the fix described in the gap report (which was produced by LLM inference in
  `chorus-strengthen`). If the hypothesis in the gap report is wrong, the patch will
  also be wrong. The anti-regression guard catches regressions on *existing* conforming
  cases only — it does not catch cases not yet present in the project JSON files.
- **New regressions introduced on untested cases** are only detectable after a new
  `chorus-create-project --batch` run that regenerates the coverage suite.
- **Bucket A gaps** (ambiguous corpus refs) are never touched automatically — they
  require a human to re-read the normative source and clarify the intent before any
  fix can be computed.
- **`--dry-run` is strongly recommended** on the first run on any sandbox to validate
  the planned patches before committing to them.
