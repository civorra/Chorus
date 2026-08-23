# Skill — chorus-review-kb

> **Trigger:** `chorus-review-kb <sandbox-name> [--agent <slug>] [--format html|org] [--decisions <file>] [--min-coverage N]`
> **Agent:** `architect`
>
> `<sandbox-name>` : sandbox with a KB produced by `chorus-feed`
> `--agent <slug>` : restrict the review to one agent (default: all agents in pipeline order)
> `--format html|org` : controls which artifacts are generated:
>   - `html` *(default)* — generates **both** `kb-review-<NNN>.html` (interactive viewer) **and**
>     `kb-review-<NNN>.org` (machine-readable report). Use for standard review sessions.
>   - `org` — generates **only** `kb-review-<NNN>.org`, skipping the HTML entirely.
>     Use when the corpus is large (HTML timeout risk), when the expert prefers the org format,
>     or when running in a CI/automated context.
>   The `.org` file is **always** generated regardless of `--format` — it is the canonical
>   machine-readable output. The HTML is optional and generated on top of it.
> `--decisions <file>` : path to a `kb-review-<NNN>-decisions.json` exported from the HTML viewer.
>   When present, the skill runs Phase 4b instead of Phases 1–5: it loads expert decisions,
>   updates the org report, and produces a `corpus-correctif.txt` for `chorus-feed --enrich`.
>   *(See Phase 4b below.)*
>
> **Single responsibility: produce a corpus-coverage review artifact that allows a
> domain expert — without Perl or YAML knowledge — to verify article by article that
> every normative requirement in the corpus is represented by at least one YAML rule.**
>
> This skill produces two artifacts:
> - `kb-review-<NNN>.html` — an interactive viewer (HTML + CSS + JS, zero dependencies,
>   opens in any browser) showing the corpus article → rule → Helper mapping, with
>   Validate / Flag / Missing buttons for the expert
> - `kb-review-<NNN>.org` — a structured report of the same information, readable by
>   the agent and loadable as input for `chorus-feed --enrich` (gaps) and
>   `chorus-strengthen` (roadmap)
>
> It does NOT modify any KB, YAML, or Helper file.
>
> Prerequisites:
> - `chorus-feed <sandbox-name>` must have been run (org KB + YAML rules present)
> - The corpus source file(s) must be accessible in `$SANDBOX/corpus/`
>   (the text extracted by `chorus-pdf`/`chorus-word`/`chorus-xml` — not the original PDF)
>
> **Relationship with `chorus-feed` Phase 6.5 coverage report:**
> `chorus-feed` Mode A already generates a coverage report in `README.org` (Phase 6.5),
> classifying corpus sections as ✅ Integrated / ⏭ Deferred / ⛔ Out of scope.
> `chorus-review-kb` is **not a replacement** for that report — it is a complementary,
> independent verification:
>
> | | `chorus-feed` Phase 6.5 | `chorus-review-kb` |
> |---|---|---|
> | **Moment** | At encoding time (inline) | Post-encoding (regenerable anytime) |
> | **Source** | LLM analysis of corpus text | Mechanical cross-reference of `CORPUS:` fields |
> | **Audience** | Agent / developer | Domain expert (no Perl/YAML required) |
> | **Classification** | ✅ / ⏭ / ⛔ (LLM-inferred) | Covered / Uncovered / Orphan / No-CORPUS |
> | **Expert decisions** | Not captured | Captured via HTML export → `decisions.json` |
>
> When both reports exist, divergences are expected and informative:
> - An article ⏭ Deferred in Phase 6.5 but Uncovered here → confirm it was intentionally skipped
> - An article ✅ Integrated in Phase 6.5 but Orphan here → the `CORPUS:` field may reference a wrong §
> - Phase 6.5 is the LLM's self-assessment; `chorus-review-kb` is the **expert's independent audit**
>   and is authoritative for certification purposes.

> ⚠️ **Sources — strict order:**
> 1. `$SANDBOX/agent/chorus/index.org` → agents, pipeline, namespace
> 2. `$SANDBOX/agent/chorus/<slug>.org` → Rule Catalogue (`CORPUS:` field), Helpers section
> 3. `$SANDBOX/rules/<slug>/*.yml` → `CORPUS:` header field in each rule
> 4. `$SANDBOX/corpus/*.txt` or `*.md` → corpus text (for article extraction and display)
>
> ⛔ **Never read** `Helpers.pm`, `Feed.pm`, `Agent/*.pm`, `Expert.pm`, `run.pl`
> ⛔ **Never invent coverage claims** — only report what is explicitly linked via `CORPUS:` fields

---

## Phase 0 — Sandbox inventory (first tool call — token keepalive)

Read `$SANDBOX/` directory tree (max_depth=3) before any file read.

Confirm:
- `$SANDBOX/.chorus-wip.md` → **if present, stop immediately**:
  ```
  ⛔ A previous chorus-review-kb run was interrupted ($SANDBOX/.chorus-wip.md present).
     Review or delete the file manually, then re-run chorus-review-kb.
  ```
- `$SANDBOX/agent/chorus/*.org` → KB files present
- `$SANDBOX/rules/` → YAML rules present
- `$SANDBOX/corpus/*.{txt,md}` → corpus source files accessible
- Any existing `kb-review-*.{html,org}` → compute next sequence number NNN:
  ```bash
  ls $SANDBOX/kb-review-*.org 2>/dev/null | sort | tail -1
  # extract NNN from the last filename, then NNN = last + 1, zero-padded to 3 digits
  # if no file exists → NNN = 001
  ```
  > **Anti-collision rule:** always use the `.org` file as the canonical sequence source
  > (it is always written, unlike `.html` which depends on `--format`).
  > If two agents start simultaneously, both will read the same last NNN and produce
  > the same filename — this is safe: the second write overwrites the first cleanly
  > (no partial state). Do not use timestamps or random suffixes — NNN must be stable
  > and deterministic so that `decisions.json` filenames reliably resolve back to their org.

> ⛔ **Review artefacts — never commit:**
> `kb-review-*.html`, `kb-review-*.org`, `kb-review-*-decisions.json`,
> and `corpus-correctif-*.txt` are local review artefacts — not versioned KB, not
> generated infrastructure. They must not be staged or committed.
> (Same policy as `agent/sessions/`, `.kb-hash`, `.last-check-results.json`.)

If KB or corpus absent → stop with explicit message:
```
⛔ Cannot produce a coverage review without both the KB (chorus-feed) and the
   corpus source files ($SANDBOX/corpus/*.txt or *.md).
   If the corpus source was extracted to a different location, pass it explicitly.
```

> **`--decisions` fast path:** if `--decisions <file>` is present → skip Phases 1–5 entirely.
> Go directly to **Phase 4b**.

---

## Phase 1 — Extract the CORPUS map from YAML rules

### 1.1 Per-agent rule inventory

For each agent (or the specified `--agent`), read all YAML files in `$SANDBOX/rules/<slug>/`.

From each rule, extract the `CORPUS:` header field:

```yaml
##
# RULE: classify-gfr-stage
# CORPUS: §1 — KDIGO 2024 — Table 2 — GFR Categories (p. S137)
# ...
```

Build a map:
```
rule_corpus_map[rule_id] = {
  agent:         '<slug>',
  file:          'R01-classify-gfr.yml',
  corpus_ref:    '§1 — KDIGO 2024 — Table 2 — GFR Categories (p. S137)',
  parsed_article: '§1',          # extracted section/article number
  parsed_source:  'KDIGO 2024',  # document name
  parsed_title:   'Table 2 — GFR Categories',
}
```

Flag rules where `CORPUS:` is absent or contains `TODO`:
```
⚠️ Missing CORPUS reference:
   Agent: <slug>, Rule: <R-file>
   → This rule cannot be mapped to a corpus article.
   → Add a CORPUS: field to the rule header before running chorus-review-kb.
```

### 1.2 Per-agent KB rule catalogue cross-check

Read `$SANDBOX/agent/chorus/<slug>.org` Rule Catalogue section.

For each rule listed in the catalogue, verify it has a corresponding `.yml` file.
Flag catalogue entries without a YAML file as `catalogue_only` (documented but not implemented).

---

## Phase 2 — Extract articles from the corpus

### 2.1 Corpus file inventory

List all files in `$SANDBOX/corpus/`. For each file, identify:
- Extraction format: text (`.txt`) or hybrid (`.md` — contains `[FIGURE N]` and `=== PAGE N ===` markers)
- Estimated article count (count `§` or numbered section patterns)

**Multi-corpus handling:** if more than one corpus file is present, article references may
collide (e.g. `§1` exists in both `kdigo2024.txt` and `kdigo2012.txt`).

| Situation | Strategy |
|---|---|
| Single corpus file | Use bare ref as key: `§1` |
| Multiple corpus files | Qualify the key with a short source tag: `§1@kdigo2024`, `§1@kdigo2012` |
| Multiple files, same numbering scheme | Detect collisions; qualify all refs from the collision point onward |

Source tag derivation: take the corpus filename stem, strip leading digits and separators,
truncate to 12 chars (e.g. `001-kdigo-2024-exec.txt` → tag `kdigo-2024`).

When qualified keys are used, the `CORPUS:` field in YAML rules must also include the
source tag for matching to succeed (e.g. `CORPUS: §1@kdigo2024 — …`).
If existing YAML rules use bare refs and multiple corpus files are present → warn:
```
⚠️ Multi-corpus sandbox: CORPUS: fields use bare §-refs but N corpus files are present.
   Cross-reference accuracy may be reduced. Consider qualifying CORPUS: fields.
```

### 2.2 Article extraction

Parse each corpus file to extract identifiable normative units:

```
Article patterns (tried in order):
  1. Numbered section:    §N.N.N, Article N, Section N, Recommendation N.N
  2. Practice Points:     Practice Point N.N.N.N
  3. Table references:    Table N — <title>
  4. Named clause:        Chapter N — <title>
  5. Fallback:            any line starting with a number followed by a title pattern
```

For each extracted article, record:
```
article_map['§1'] = {
  ref:         '§1',
  title:       'Definition and Classification of CKD',
  source_file: '001-kdigo-exec-summary-text.txt',
  page_hint:   'p. S137',    # extracted from PAGE markers if hybrid
  excerpt:     '<first 200 chars of the article body>',
  has_rule:    false,        # filled in Phase 3
  rules:       [],           # filled in Phase 3
}
```

> ⚠️ Article extraction is heuristic — not all corpus documents have
> consistent section numbering. Flag articles that could not be parsed with
> `extraction_confidence: low`.
>
> **`extraction_confidence: low` — counting rule:**
> These articles **are included** in `total_articles` and in the coverage percentage
> denominator — omitting them would silently inflate the coverage rate.
> They are tagged `(low)` in all tables (org and HTML) and listed in a dedicated
> "Extraction warnings" section so the expert can review them.
> The coverage summary displays a footnote:
> `Coverage N% includes N article(s) with low extraction confidence — verify manually.`

---

## Phase 3 — Build the coverage matrix

### 3.1 Cross-reference rules → articles

For each entry in `rule_corpus_map`, match `parsed_article` against `article_map`:

```
article_map['§1'].has_rule = true
article_map['§1'].rules.push({
  rule_id: 'classify-gfr-stage',
  file:    'R01-classify-gfr.yml',
  agent:   'staging',
})
```

Unmatched `parsed_article` values (rule references an article not found in corpus) →
flag as `orphan_reference`:
```
⚠️ Orphan rule reference:
   Rule R01 references §42, but §42 was not found in the corpus text.
   → Either the article number is wrong in the CORPUS: field, or the
     corpus extraction missed this section.
```

### 3.2 Compute coverage statistics

```
total_articles:      N   (all articles in article_map)
covered_articles:    N   (has_rule == true)
uncovered_articles:  N   (has_rule == false)
orphan_references:   N   (rules pointing to non-existent articles)
missing_corpus_refs: N   (rules without CORPUS: field)
coverage_pct:        N%  (covered / total × 100)
```

Coverage levels (default thresholds — overridable):
```
≥ 80% → 🟢 Good coverage
60–79% → 🟡 Moderate — recommend chorus-feed --enrich before pilot
< 60%  → 🔴 Low — significant normative gaps, not ready for production use
```

> **Configurable thresholds:** read `#+MIN_COVERAGE` from `$SANDBOX/agent/chorus/index.org`
> if present (format: `#+MIN_COVERAGE: 75` — integer percentage). If absent, apply the
> defaults above. The `--min-coverage N` flag overrides both, taking highest precedence.
> Use lower thresholds for exploratory sandboxes; raise them for production certification.

---

## Phase 4 — Generate `kb-review-<NNN>.html`

> **Skip this phase entirely if `--format org` was specified.** Go directly to Phase 5.

### 4.0 — WIP checkpoint + chunking strategy

**Before writing any file**, create `$SANDBOX/.chorus-wip.md`:

```markdown
# chorus-review-kb WIP checkpoint
sandbox: <name>
review:  kb-review-<NNN>.html
started: <YYYY-MM-DD>
status:  IN_PROGRESS
```

**Anti-timeout rule — generate the HTML in multiple passes:**

> ⚠️ A self-contained HTML file with N article panels can easily exceed 500 lines.
> Generating it in a single `eca__write_file` call risks `java.net.ConnectException`.
> Always use the chunked approach below — even for small corpora.

| Pass | Tool | Content |
|---|---|---|
| **Pass 1** | `eca__write_file` | Full HTML shell: `<html>`, `<head>`, inline `<style>` (CSS), inline `<script>` (JS: `filter()`, `search()`, `mark()`, `exportValidatedReport()`), summary bar, filter bar, empty `<div id="articles">`, uncovered section placeholder, export button, `</body></html>` |
| **Pass 2…N** | `eca__edit_file` (append before `</div>`) | Article panels in batches of **20–25 panels per pass** — append into `<div id="articles">` |
| **Pass N+1** | `eca__edit_file` | Fill the uncovered articles section (Phase 4.5) |

Generate a self-contained HTML file (`$SANDBOX/kb-review-<NNN>.html`)
with no external dependencies (all CSS and JS inline).

### 4.1 Header section

```html
<!-- Coverage summary bar -->
<div class="summary">
  <span class="stat">Articles: N total</span>
  <span class="stat covered">N covered ✅</span>
  <span class="stat uncovered">N uncovered ⚠️</span>
  <span class="stat pct">Coverage: N%</span>
</div>

<!-- Filter bar -->
<div class="filters">
  <button onclick="filter('all')">All</button>
  <button onclick="filter('covered')">Covered ✅</button>
  <button onclick="filter('uncovered')">Uncovered ⚠️</button>
  <button onclick="filter('flagged')">Flagged ❌</button>
  <button onclick="filter('validated')">Validated ✓</button>
  <input  type="text" placeholder="Search article..." oninput="search(this.value)">
</div>
```

### 4.2 Article panels (one per article in corpus order)

Each panel has three columns:

```html
<div class="article" id="art-§1" data-status="covered">

  <!-- Left: corpus excerpt -->
  <div class="corpus-text">
    <span class="art-ref">§1</span>
    <span class="art-title">Definition and Classification of CKD</span>
    <span class="art-source">KDIGO 2024 — p. S137</span>
    <blockquote class="excerpt">
      CKD is defined as abnormalities of kidney structure or function, present
      for more than 3 months, with implications for health…
    </blockquote>
  </div>

  <!-- Centre: rules mapped to this article -->
  <div class="rules-mapped">
    <div class="rule-chip" onclick="toggleRule('R01-classify-gfr')">
      <span class="agent-tag">staging</span>
      <span class="rule-id">R01 — classify-gfr-stage</span>
      <span class="confidence">✅</span>
    </div>
    <!-- OR if uncovered: -->
    <div class="rule-chip missing">
      <span class="missing-label">⚠️ No rule mapped to this article</span>
    </div>
  </div>

  <!-- Right: expert decision -->
  <div class="decision">
    <button class="btn-validate" onclick="mark('§1','validated')">✅ Correct</button>
    <button class="btn-flag"     onclick="mark('§1','flagged')">❌ Rule missing / wrong</button>
    <textarea class="comment" placeholder="Expert note…"></textarea>
  </div>

</div>
```

### 4.3 Rule detail panel (expandable on click)

When a rule chip is clicked, expand to show:
```html
<div class="rule-detail" id="detail-R01-classify-gfr">
  <div class="rule-meta">
    <b>File:</b> rules/staging/R01-classify-gfr.yml<br>
    <b>Agent:</b> staging (pos. 1 / 3)<br>
    <b>CORPUS:</b> §1 — KDIGO 2024 — Table 2 — GFR Categories<br>
  </div>
  <div class="rule-slots">
    <b>Inputs:</b>  eGFR_mL_min (float)<br>
    <b>Outputs:</b> ckd_stage (enum: G1 G2 G3a G3b G4 G5)<br>
  </div>
  <!-- Helper values relevant to this rule, from org KB Helpers section -->
  <div class="helper-values">
    <b>Thresholds (from org KB):</b>
    <table>
      <tr><th>Stage</th><th>eGFR range</th><th>Source</th></tr>
      <tr><td>G1</td><td>≥ 90</td><td>Table 2 §S137</td></tr>
      <tr><td>G2</td><td>60 – 89</td><td>Table 2 §S137</td></tr>
      <!-- ... -->
    </table>
  </div>
</div>
```

### 4.4 Export function

```javascript
function exportValidatedReport() {
  // Collect all article decisions (validated / flagged / comment)
  const data = { review: REVIEW_ID, sandbox: SANDBOX_NAME, exported: new Date().toISOString(), decisions: [] };
  document.querySelectorAll('.article').forEach(el => {
    const decision = el.dataset.decision || 'pending';
    if (decision !== 'pending') {
      data.decisions.push({
        article_ref: el.id.replace('art-', ''),
        decision:    decision,
        note:        el.querySelector('.comment').value || ''
      });
    }
  });
  const json = JSON.stringify(data, null, 2);

  // Primary: trigger browser download
  try {
    const blob = new Blob([json], { type: 'application/json' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href     = url;
    a.download = REVIEW_ID + '-decisions.json';
    a.click();
    URL.revokeObjectURL(url);
  } catch (e) {
    // Fallback for browsers that block file:/// downloads (security policy)
    document.getElementById('export-fallback').style.display = 'block';
    document.getElementById('export-textarea').value = json;
  }
}
```

> ⚠️ **`file:///` security:** some browsers block JS-triggered downloads when the HTML
> is opened as a local file (`file:///` scheme). The export function includes a **fallback**:
> if the download fails, a `<textarea>` containing the full JSON appears on the page.
> The expert copies the content and saves it manually as `kb-review-<NNN>-decisions.json`.

The HTML must include the fallback elements (hidden by default):
```html
<div id="export-fallback" style="display:none">
  <p>⚠️ Automatic download blocked by browser. Copy the JSON below and save as
     <code>kb-review-<NNN>-decisions.json</code>:</p>
  <textarea id="export-textarea" rows="20" style="width:100%;font-family:monospace"></textarea>
</div>
```

A "Export report" button at the bottom of the page triggers `exportValidatedReport()`.
The exported (or copy-pasted) JSON is the input for Phase 4b (`--decisions`).

### 4.5 Uncovered articles section

A dedicated collapsible section at the bottom lists all uncovered articles
in corpus order, with their excerpt and a direct "Flag as gap" button.
This section is the primary input for the expert's review session.

---

## Phase 5 — Generate `kb-review-<NNN>.org`

> **After writing the org file**, delete `$SANDBOX/.chorus-wip.md`.
> (If `--format org` was used, create and delete `.chorus-wip.md` around Phase 5 only.)

Write `$SANDBOX/kb-review-<NNN>.org` regardless of `--format`:

```org
#+TITLE: KB Coverage Review — <sandbox-name>
#+GENERATED: <ISO-date>
#+CORPUS: <list of corpus files used>
#+COVERAGE: N% (N/N articles)

* Coverage summary
  | Status    | Count | Pct |
  |-----------+-------+-----|
  | Covered   |     N | N%  |
  | Uncovered |     N | N%  |
  | Orphan    |     N | N%  |
  | No CORPUS |     N | N%  |

* Covered articles (validated rules)
  | Article ref | Title | Rules | Agents | Status |
  |-------------+-------+-------+--------+--------|
  | §1          | ...   | R01   | staging| ✅     |

* Uncovered articles (gaps → candidates for chorus-feed --enrich)
  | Article ref | Title | Excerpt (100 chars) | Priority |
  |-------------+-------+---------------------+----------|
  | §7.3        | Deformation criteria | ... | HIGH |

  Priority heuristic (⚠️ LLM-inferred from article text — not deterministic):
    HIGH   → article contains numeric thresholds (likely encodable as a YAML rule)
    MEDIUM → article contains conditional requirements (encodable with effort)
    LOW    → article is narrative/explanatory (difficult to encode as a binary rule)

  Treat these priorities as suggestions for triage, not as objective classifications.
  A domain expert may re-prioritize any article during the HTML review session.

* Orphan rule references (rules pointing to non-existent corpus articles)
  | Rule | Agent | CORPUS field | Issue |
  |------+-------+-------------+-------|
  |      |       |              |       |

* Rules without CORPUS reference (traceability gap)
  | Rule | Agent | File |
  |------+-------+------|
  |      |       |      |

* Expert decisions (populated after HTML review)
  (this section is filled when kb-review-<NNN>-decisions.json is loaded)
  | Article ref | Decision | Expert note |
  |-------------+----------+-------------|
  |             |          |             |

* Next steps
  #+BEGIN_EXAMPLE
  # If uncovered articles exist:
  chorus-feed <sandbox-name> <new-corpus-extract> --enrich

  # If orphan references exist:
  # Fix CORPUS: fields in the listed YAML rules

  # If rules without CORPUS exist:
  # Add CORPUS: header to each listed rule (see chorus-engine-yaml.md)
  #+END_EXAMPLE
```

---

## Phase 4b — Load expert decisions (`--decisions <file>` mode)

> **This phase replaces Phases 1–5** when `--decisions <file>` is present.
> The HTML review and org generation are already done — this phase closes the loop
> by integrating expert annotations back into the agent workflow.

### 4b.0 — Locate the existing org report

```bash
ls $SANDBOX/kb-review-*.org   # find the matching NNN from the decisions filename
```

The `decisions.json` filename encodes the NNN (`kb-review-<NNN>-decisions.json`).
Read the corresponding `$SANDBOX/kb-review-<NNN>.org` as the base to update.

### 4b.1 — Parse the decisions file

Expected JSON structure (produced by `exportValidatedReport()` in the HTML viewer):

```json
{
  "review":    "kb-review-<NNN>",
  "sandbox":   "<sandbox-name>",
  "exported":  "<ISO-date>",
  "decisions": [
    {
      "article_ref": "§1",
      "decision":    "validated",
      "note":        "Rule R01 correctly encodes Table 2 threshold."
    },
    {
      "article_ref": "§7.3",
      "decision":    "flagged",
      "note":        "Rule missing — article defines minimum deflection not covered."
    },
    {
      "article_ref": "§12",
      "decision":    "missing",
      "note":        "Not in corpus extraction — article cut off at page boundary."
    }
  ]
}
```

Decision values:
| Value | Meaning |
|---|---|
| `validated` | Expert confirms the mapped rule(s) correctly encode this article |
| `flagged` | Expert identifies a gap — rule is wrong, missing, or incomplete |
| `missing` | Article was not visible to the expert (extraction issue, not a rule gap) |

### 4b.2 — Update the org report

Populate the `* Expert decisions` section of `$SANDBOX/kb-review-<NNN>.org`:

```org
* Expert decisions
  #+REVIEWED: <ISO-date>
  #+REVIEWER: <if known from decisions.json, else "anonymous">

  | Article ref | Decision  | Expert note                                                  |
  |-------------+-----------+--------------------------------------------------------------|
  | §1          | validated | Rule R01 correctly encodes Table 2 threshold.                |
  | §7.3        | flagged   | Rule missing — minimum deflection not covered.               |
  | §12         | missing   | Not in corpus extraction — page boundary cut.                |

** Flagged gaps (→ candidates for chorus-feed --enrich)
   | Article ref | Title | Expert note | Priority |
   |-------------+-------+-------------+----------|
   | §7.3        | ...   | ...         | HIGH     |

** Coverage with expert review
   | Metric                          | Count | Pct |
   |---------------------------------+-------+-----|
   | Validated (confirmed covered)   |     N | N%  |
   | Flagged (confirmed gaps)        |     N | N%  |
   | Missing (extraction issue)      |     N | N%  |
   | Not reviewed                    |     N | N%  |
```

### 4b.3 — Generate `corpus-correctif.txt`

For each `flagged` decision, extract the article excerpt from `$SANDBOX/corpus/*.{txt,md}`
and write a ready-to-use corpus file for `chorus-feed --enrich`:

```
$SANDBOX/corpus-correctif-<NNN>.txt
```

Format:
```
[Expert review — kb-review-<NNN> — §7.3]
<corpus excerpt for §7.3, 200–500 chars>
Expert note: Rule missing — minimum deflection not covered.

[Expert review — kb-review-<NNN> — §12.1]
...
```

> This file is a **direct input** for `chorus-feed <sandbox-name> corpus-correctif-<NNN>.txt --enrich`.
> It is the concrete mechanism that connects the expert review loop to the KB enrichment pipeline.

### 4b.4 — Display Phase 4b summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-review-kb --decisions  <sandbox-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Expert decisions loaded : N
    Validated             : N  (confirmed covered)
    Flagged               : N  (confirmed gaps)
    Missing               : N  (extraction issue — not a rule gap)
    Not reviewed          : N
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Updated : $SANDBOX/kb-review-<NNN>.org
  Created : $SANDBOX/corpus-correctif-<NNN>.txt  (N flagged articles)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Next steps:
    chorus-feed <sandbox-name> corpus-correctif-<NNN>.txt --enrich
    chorus-check <sandbox-name> --all
    chorus-strengthen <sandbox-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 6 — Display generation report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-review-kb  <sandbox-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Corpus articles found  : N
  Covered by ≥1 rule     : N  (N%)  🟢|🟡|🔴
  Uncovered (gap)        : N
  Orphan rule references : N
  Rules without CORPUS   : N
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Outputs:
    $SANDBOX/kb-review-<NNN>.html   ← open in browser for expert review  [--format html only]
    $SANDBOX/kb-review-<NNN>.org    ← machine-readable report  [always]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Next steps:
    1. Open kb-review-<NNN>.html in a browser
    2. Review uncovered articles with a domain expert
    3. Click "Export report" → save kb-review-<NNN>-decisions.json
    4. chorus-review-kb <sandbox-name> --decisions kb-review-<NNN>-decisions.json
       → produces corpus-correctif-<NNN>.txt
    5. chorus-feed <sandbox-name> corpus-correctif-<NNN>.txt --enrich
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## What `chorus-review-kb` covers that no other skill covers

| Gap type | Detected by `chorus-stress` | Detected by `chorus-strengthen` | Detected by `chorus-review-kb` |
|---|---|---|---|
| Rule encodes wrong threshold | ✅ (boundary family) | ✅ (discordance) | ✅ (Helper values visible) |
| Rule covers wrong article | ❌ | ❌ | ✅ (orphan reference) |
| Article has no rule at all | ❌ | ❌ | ✅ (uncovered article) |
| Rule has no corpus traceability | ❌ | ❌ | ✅ (missing CORPUS field) |
| Helper value visible to domain expert | ❌ | ❌ | ✅ (shown in rule detail panel) |

**This skill closes the corpus coverage gap** — the one gap that neither
automated testing nor convergence checking can detect, because it requires
a domain expert to verify that what was encoded *corresponds to what the
corpus actually requires*.

---

## Separation of responsibilities

| | `chorus-feed` | `chorus-review-kb` | `chorus-stress` | `chorus-strengthen` |
|---|---|---|---|---|
| **Reads** | corpus → generates KB | KB + corpus text | KB + YAML | pipeline output |
| **Produces** | KB (org, YAML, Helpers) | HTML viewer + org report | Stress project JSON | Gap report |
| **Validates** | (via LLM) | **Human expert + corpus** | Deterministic thresholds | Rule behavior |
| **Detects** | — | Article coverage gaps | Threshold precision bugs | Rule logic gaps |
| **Triggered** | New corpus | After `chorus-feed`, before pilot | After `--batch` | After failed `--all` |

---

## Integration in the KB certification chain

```
chorus-feed <sb> <corpus>                        ← LLM generates KB from corpus (Phase 6.5: README.org coverage)
    ↓
chorus-review-kb <sb>                            ← generates HTML viewer + org report  ← THIS SKILL
    ↓  [expert reviews in browser, clicks Validate/Flag]
    ↓  [clicks "Export report" → kb-review-<NNN>-decisions.json]
    ↓
chorus-review-kb <sb> --decisions kb-review-<NNN>-decisions.json
    ↓  → updates org + produces corpus-correctif-<NNN>.txt
    ↓
[chorus-feed <sb> corpus-correctif-<NNN>.txt --enrich   ← fill expert-identified gaps]
    ↓
chorus-check <sb> <project>            ← generate infrastructure
    ↓
chorus-create-project <sb> --batch     ← typical test cases
chorus-stress <sb>                     ← boundary/edge/cascade test cases
    ↓
chorus-check <sb> --all                ← automated validation
chorus-strengthen <sb>                 ← gap diagnosis
    ↓
✅ CERTIFIED KB:
   - Corpus coverage validated by domain expert  (chorus-review-kb)
   - Rule behavior validated by deterministic tests  (chorus-stress + chorus-check --all)
   - Traceability: every verdict → rule → corpus article
```
