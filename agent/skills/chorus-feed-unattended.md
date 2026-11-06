# Sub-skill — chorus-feed-unattended

> **Internal sub-skill** — loaded by `chorus-feed.md` when `--unattended` is present.
> Implements **Mode D — Unattended batch**: an orchestrator that processes exactly
> one corpus file per invocation (via Mode A or Mode B, depending on checkpoint
> state) and exits, so the webapp (or the operator) can re-invoke until convergence
> without ever risking a session timeout on a large corpus.
>
> **Not a 4th independent mode** — Mode D does not duplicate Mode A/Mode B logic.
> At Step 3 below, it determines which file to process this session and then
> **delegates to `chorus-feed.md § Mode A` or `§ Mode B` directly** (this same
> session, same invocation — not a separate `eca__skill` call) for the actual
> corpus analysis / KB enrichment. Mode D's own responsibility is purely the
> checkpoint lifecycle (read/write `.chorus-unattended-state.json`), file
> selection, `coverage_pct` bookkeeping, and the final report.
>
> Trigger: loaded via `eca__read_file` on `$ENGINE/agent/skills/chorus-feed-unattended.md`
> from `chorus-feed.md` when `chorus-feed <sandbox-name> --unattended [--corpus-dir <path>] [--max-passes N]`
> is the invoking command (see `chorus-feed.md § Mode Selection`).

> **One session = one file.** Each invocation processes exactly one corpus
> file (Mode A or Mode B depending on checkpoint state) and exits.
> This keeps every ECA session within timeout limits regardless of corpus size.
> The webapp (or the operator) re-invokes until `"converged": true`.

### Prerequisites check (blocking)

Before any processing, verify:

1. `SCOPING.md` exists in `$SANDBOX/` with status `CONFIRMED` or `LOCKED`.
2. `CORPUS-DIRECTIVES.md` exists in `$SANDBOX/`.
3. No `.chorus-wip.md` in `$SANDBOX/` (previous operation incomplete — stop and warn).
4. At least one supported corpus file in `--corpus-dir` (default: `$SANDBOX/corpus/`):
   `.md`, `.txt` (used as-is) or `.pdf`/`.docx`/`.xlsx`/`.csv`/`.xml`/`.html`/`.htm`
   (auto-converted by the corresponding skill before the first Mode A pass).
   Pure `.pdf`-only or `.txt`-only corpora are valid — do not require a pre-existing `.md`.

If any prerequisite is missing → stop immediately:
```
⛔ chorus-feed --unattended: prerequisite missing — <reason>
   Never create SCOPING.md or CORPUS-DIRECTIVES.md automatically.
```

### Step 0 — OOS reclassification (silent)

Read existing coverage reports (`README.org * Coverage`) across all agents.
For each `⛔ Out of scope` entry:

| Motif | Action |
|---|---|
| `informative` / out-of-domain | Keep `⛔` — truly definitive |
| `external-norm` | **Reclassify to `⏭ Deferred (external-norm)`** — the norm is absent from corpus, not out-of-domain |
| `⛔ pré-exclu (scoping)` | Keep `⛔` — managed by `chorus-corpus-scoping`, not here |

Record reclassifications for the final report.

**⏭/⛔ decision rule:**

| Pattern | Correct classification | Definitive? |
|---|---|---|
| Pure informative section (examples, rationale) | `⛔ OOS` | ✅ Yes |
| Explicit out-of-domain | `⛔ OOS` | ✅ Yes |
| External norm absent from corpus | `⏭ Deferred (external-norm)` | ⚠️ No — reopenable |
| Procedural, no threshold | `⏭-S Deferred` | ⚠️ No — reopenable |
| `⛔ pré-exclu (scoping)` | Separate category | ⚠️ No — revisable via scoping |

### Step 0.5 — Detect mode: pre-split vs single-corpus

> ⚠️ **Do not use a single regex on SCOPING.md to detect pre-split** — the
> `## Corpus reviewed` section always lists `corpus/NNN-*.md` source files,
> producing a guaranteed false positive. Use the 3-indicator logic below.

Detection requires **all 3 indicators** to be true for `mode: "presplit"`:

1. **Indicator 1 — Phase 2 section present in SCOPING.md**
   The SCOPING.md contains a line matching:
   `chorus-corpus-scoping.*Phase 2` OR `Corpus pre-split complete`
   (case-insensitive). This section is only written by `chorus-corpus-scoping`
   after Phase 2 completes — never by Phase 1 alone.

2. **Indicator 2 — Agent slugs listed in SCOPING.md**
   Extract slugs from the `## Agents` table (e.g. `` `crypto-alea` ``,
   `` `crypto-asym` ``). At least one slug must be found.

3. **Indicator 3 — Agent corpus files exist on the filesystem**
   At least one file matching `$SANDBOX/corpus/NNN-<slug>.md` exists where
   `<slug>` matches one of the slugs from Indicator 2.
   → Filesystem check, not just a regex on SCOPING.md content.

```
if indicator_1 AND indicator_2 AND indicator_3:
    mode = "presplit"
    agent_files = sorted matched files from indicator_3
else:
    mode = "single"
```

Edge case — Phase 2 planned but files not yet generated:
if Indicator 1 is true but Indicator 3 is false → `mode: "single"` (Phase 2
was scoped but corpus files were not yet produced; treat as single-corpus
until files exist).

> **Pre-split constraint:** in `presplit` mode, Phase A (Mode A × N agents)
> must be **fully completed before any Mode B** pass. Agents share SHARED/CONTEXT
> sections — enriching one agent before its dependencies are initialized produces
> incorrect Deferred counts and cascading misses.

### Step 1 — Read / initialize checkpoint

Read `$SANDBOX/.chorus-unattended-state.json` if present.

**If absent** (first run): scan `--corpus-dir` for all supported formats and
create checkpoint:
```json
{ "status": "waiting", "mode": "presplit|single", "phase": "A",
  "files_mode_a_pending": ["001-slug.md", "002-loi.txt", "003-reco.pdf", ...],
  "files_mode_b_pending": [],
  "passes_done": 0, "max_passes": 2N }
```

**Corpus scan rule (first run):** collect every file in `--corpus-dir` whose
extension (case-insensitive) is one of: `.md`, `.txt`, `.pdf`, `.docx`,
`.xlsx`, `.csv`, `.xml`, `.html`, `.htm`. Sort by filename. This list becomes
`files_mode_a_pending`.
- `.pdf`/`.docx`/`.xlsx`/`.csv`/`.xml`/`.html`/`.htm` files are listed as-is
  in the checkpoint; `chorus-feed.md § Document Format Guard` auto-converts
  them when their turn comes in Step 3.
- Pre-existing `.md`/`.txt` files are used as-is.
- Files already converted (e.g. `003-reco-text.md` exists alongside
  `003-reco.pdf`) → include only the `.md` (skip the source `.pdf`).

**If present**:
- `status: "converged"` → display convergence summary and exit.
- `status: "cancelled"` → display cancellation message and exit.
- `status: "stopped_max_passes"` → display max-passes message and exit.
- `status: "waiting"` → resume from next pending file (Phase A or B).
- `status: "running"` → previous session may have crashed; resume from `current_file`.

### Step 2 — Write "running" checkpoint

**Before processing the file**, update checkpoint:

```json
{ "status": "running", "current_file": "<NNN-slug.md>",
  "current_mode": "A|B", "last_update": "<ISO8601>" }
```

This ensures the webapp sees `status: "running"` immediately (progress bar active).

### Step 3 — Process one file

Determine which file to process this session:

**`presplit` mode:**
- If `files_mode_a_pending` is non-empty → take first file, run **Mode A**
  (`chorus-feed.md § Mode A`).
- Else if `files_mode_b_pending` is non-empty → take first file, run **Mode B
  `--enrich`** (`chorus-feed.md § Mode B`).
- Else → evaluate convergence (Step 4).

**`single` mode:**
- If `files_mode_a_pending` is non-empty → take first file, run **Mode A**
  (all agents, `chorus-feed.md § Mode A`).
- Else if `files_mode_b_pending` is non-empty → take first file, run **Mode B
  `--enrich`** (`chorus-feed.md § Mode B`).
- Else → evaluate convergence (Step 4).

After processing, remove the file from its pending list and evaluate
Mode A's own Phase 6.5 (which loads `chorus-feed-coverage.md` as usual —
nothing changes in that call chain from Mode D's perspective).
If the processed file still has Deferred after Mode A → add to `files_mode_b_pending`.

Convergence criterion:
`Deferred-S = 0 AND Deferred-C = 0 AND CORPUS:unresolved = 0`

### Step 3.5 — Compute `coverage_pct` (mechanical, mandatory)

> ⚠️ **Why this step exists.** Prior to this step's introduction, `coverage_pct`
> had no defined formula anywhere in this skill — every occurrence below used
> a bare `X` placeholder, leaving the actual number to the enriching agent's
> own judgment call each pass. This produced visibly inconsistent results: a
> pass that mechanically closed 4 entire families (`families_closed_this_pass:
> 4`, `deferred_s` dropping from 16 to 3) reported a `coverage_pct` gain of
> only 2 points — the number was an impression, not a measurement, and did not
> reflect the real progress already visible in the other structured fields
> (incident: sandbox 06-CC-3.1.5, pass 16). `coverage_pct` MUST now be computed
> mechanically from counts already produced elsewhere in this same pass —
> never estimated, never eyeballed, never carried over "by feel" from the
> previous pass's number.
>
> ⚠️ **Incremental, not a full re-scan (cost control — mandatory).** The first
> version of this step required a full re-read of `README.org § Coverage` on
> *every* pass to recompute `families_integrated`/`families_deferred`/
> `families_oos` from scratch. On a sandbox with a large README (many agents,
> many enrichment passes already recorded), this added a non-trivial amount of
> extra reading/reasoning on top of an already substantial `--unattended` pass
> (Mode B enrichment + its own coverage update via `chorus-feed-coverage.md` +
> this step), and correlated with a session ending in a "Error in input stream"
> backend timeout (incident: sandbox 06-CC-3.1.5, pass 18 — same class of
> timeout already documented for `chorus-check --summary`+`--explain` combined
> in one turn, cf. `chorus-web.js` § `openAnalyseFromReport`). The revised
> procedure below keeps the three family counters **persisted in the checkpoint
> itself** and updates them incrementally — a full `README.org § Coverage`
> re-scan is now the **exception**, not the per-pass default.

**Inputs — incremental update, not full re-derivation:**

- Read the **previous checkpoint's** `families_integrated_total` /
  `families_deferred_total` / `families_oos_total` (new persisted fields —
  see Step 4's checkpoint shape below). On the very first pass that ever
  reaches this step (fields absent), fall back once to a full
  `README.org § Coverage` scan (see "Full re-scan" below) to seed them.
- For this pass only, determine the **delta** from the agent(s)/section(s)
  actually touched this pass (already known from Phase B1.5's per-family
  tier classification and Phase B3's applied changes — no extra reading
  required beyond what this pass already did):
  - `+N` to `families_integrated_total` for each family this pass moved from
    Deferred/unscanned to `✅ Integrated` (this is exactly
    `families_closed_this_pass`, already computed — reuse it, don't recount).
  - `-N` to `families_deferred_total` for the same families (one family
    cannot be both newly-Integrated and still-Deferred after the same pass).
  - `+N` to `families_deferred_total` (and to the *_total sum, growing the
    denominator) only if this pass's own corpus reading **discovered** new
    families not previously listed anywhere in `README.org § Coverage` for
    the agent(s) touched this pass (e.g. an `≈18 families` estimate refined
    into an exact higher count for the agent processed this pass) — never
    for agents/sections this pass did not touch.
  - `families_oos_total` changes only via Step 0's OOS reclassification
    (already a mandatory, already-read step — reuse its output, don't
    re-scan for it here).

**Formula (unchanged):**
```
total     = families_integrated_total + families_deferred_total + families_oos_total
coverage_pct = round(100 × families_integrated_total / total)   (total == 0 → 100)
```

**Full re-scan — exceptional, not per-pass:**

Only perform a complete `README.org § Coverage` re-read (summing every
`** ✅ Integrated`/`** ⏭ Deferred`/`** ⛔ Out of scope` sub-heading's detail-table
row count from scratch, as the original version of this step always did) when:
- This is the very first pass to reach Step 3.5 (counters not yet persisted), OR
- The operator explicitly requests a recount (e.g. after manually editing
  `README.org`, or after suspecting drift between the persisted counters and
  the file), OR
- A `deferred_unchanged_passes` stagnation streak (≥ 3) suggests the
  incremental counters may have drifted from reality and a reset is warranted.

Document which path was taken (`incremental` vs `full re-scan`) in
`next_action`'s free text alongside the three raw counts.

**Required consistency checks before writing `coverage_pct` to the checkpoint:**

1. **Never silently reuse a stale total** — if this pass took the incremental
   path, the three `*_total` fields written to the checkpoint are the
   previous checkpoint's values plus/minus this pass's own delta only, never
   an untouched copy-paste of the previous value when a delta was computed.
2. If this pass closed `families_closed_this_pass` families (Phase B1.5), the
   new `coverage_pct` MUST be strictly greater than the previous checkpoint's
   value, unless the denominator itself grew this pass (newly-discovered
   families — document this explicitly in `next_action` if it happens, e.g.
   "coverage_pct appears to drop because N newly-identified families were
   added to the denominator this pass, not a regression").
3. Report the three raw counts (`families_integrated_total`/
   `families_deferred_total`/`families_oos_total`) in `next_action`'s free
   text alongside the computed `coverage_pct` — a bare percentage with no
   visible arithmetic behind it is exactly what this step was introduced to
   eliminate.

> **Known limitation — `≈N` estimates.** Several `README.org § Coverage`
> entries use an approximate count (`≈18 families`) for agents whose corpus
> section has been scanned at class/family-header level but not deep-read
> component by component (cf. `agent-ape-ace-ase`). Using an approximate
> number here is intentional and acceptable — the alternative (deep-reading
> every agent's full component list before the first `coverage_pct` can ever
> be computed) would defeat the purpose of an incremental, per-pass metric.
> Once an agent's families are deep-read and its Deferred entry replaced with
> an exact count, update the persisted `*_total` fields accordingly as part
> of that pass's normal delta — this is a **refinement of the denominator**,
> not an error to "fix" by keeping the old estimate.

### Step 4 — Update checkpoint ("waiting") and evaluate

After processing, update checkpoint:

```json
{
  "status": "waiting",
  "files_done": K,
  "files_pending": N-K,
  "coverage_pct": X,
  "families_integrated_total": FI,
  "families_deferred_total": FD,
  "families_oos_total": FO,
  "deferred_s": DS,
  "deferred_c": DC,
  "last_update": "<ISO8601>",
  "next_action": "chorus-feed <sandbox> --unattended",
  "new_rules_this_pass": R,
  "suggested_next_file": "<NNN-slug.md>|null",
  "deferred_unchanged_passes": U,
  "families_closed_this_pass": F,
  "unresolved_deferred_notes": [
    {"item": "<short id/section ref>", "reason": "<why genuinely non-codifiable this pass>"}
  ]
}
```

> ⚠️ **Structured fields (added alongside `next_action`, not replacing it)** —
> `next_action` remains a free-text summary for humans/ECA reading the
> checkpoint directly; the fields below exist so the webapp can render
> conditional UI (badges, stagnation warnings, priority target) **without
> parsing free text**, which would be fragile against LLM phrasing drift
> across sessions. Compute each as follows:
>
> - **`coverage_pct`** (int): **never estimated here** — computed mechanically
>   per Step 3.5 above (incremental update of the three persisted `*_total`
>   fields, full re-scan only on the exceptional paths listed there). Do not
>   recompute its formula redundantly in this step; Step 3.5 already produced
>   the final value and the three `*_total` fields below before Step 4 begins.
> - **`families_integrated_total`** / **`families_deferred_total`** /
>   **`families_oos_total`** (int each): persisted running totals maintained
>   incrementally by Step 3.5 — write them unchanged from what Step 3.5
>   computed (previous checkpoint's values ± this pass's delta). Never
>   recompute them from a fresh full `README.org` scan here "just to be safe"
>   — that defeats the cost-control purpose of Step 3.5's incremental path.
> - **`new_rules_this_pass`** (int): count of new `rules/<agent>/R<NN>-*.yml`
>   files created *during this pass only* (compare `rules/` tree before/after
>   this session's Mode A/B pass — not a cumulative sandbox-wide count).
>   `0` if this pass only closed/reconfirmed Deferred items without adding a rule.
> - **`suggested_next_file`** (string or `null`): the single file this session
>   recommends targeting next, following the same precedence as Step 3 (Mode A
>   pending first, else Mode B pending) — but informed by this pass's findings
>   (e.g. "the only remaining Mode B file carries the bulk of the backlog").
>   `null` if `files_mode_a_pending` and `files_mode_b_pending` are both empty
>   (i.e. converged or stopped_max_passes with no further file to target).
> - **`deferred_unchanged_passes`** (int): read the previous checkpoint's
>   `deferred_s`/`deferred_c` **before** overwriting it this Step. If
>   `(this pass's DS + DC) == (previous checkpoint's deferred_s + deferred_c)`
>   → increment the previous checkpoint's `deferred_unchanged_passes` by 1;
>   otherwise reset to `0`. Absent on the very first checkpoint (treat as `0`).
>   This is a **stagnation signal**: N consecutive passes with no reduction in
>   total Deferred count despite rules/notes being added, usually meaning the
>   remaining Deferred backlog needs content from another not-yet-enriched
>   agent/corpus file (as opposed to being simply unworked).
> - **`unresolved_deferred_notes`** (array, may be empty): one entry per
>   Deferred item this pass **specifically attempted** to close and could not,
>   with a short human-readable reason (e.g. "requires agent-sfr content,
>   not available from Part 1 alone"). Do not enumerate the entire residual
>   Deferred backlog here — only items this pass actively investigated and
>   explicitly reconfirmed non-codifiable (mirrors the detail already given
>   in `next_action`'s free text, structured for UI consumption).
> - **`families_closed_this_pass`** (int): count of distinct families/
>   components this pass moved from Deferred to Integrated/Promoted —
>   Simple-tier batched closures (Phase B1.5) **and** the single Complex-tier
>   closure, if any, all counted together. Distinct from `new_rules_this_pass`:
>   a pass batching 4 Simple families (no new rule needed for any of them)
>   plus 1 Complex family (1 new rule) reports `new_rules_this_pass: 1` but
>   `families_closed_this_pass: 5` — the gap between the two numbers is itself
>   informative (large gap = productive Simple-family batching happened;
>   `families_closed_this_pass == new_rules_this_pass` = no batching this
>   pass, one family needed one rule).

Determine next state:

| Condition | Next state | Action |
|---|---|---|
| All files done AND Deferred-S=0 AND Deferred-C=0 AND CORPUS:unresolved=0 | `converged` | Write final report, display ✅ |
| All files done AND Deferred remain | Re-run Mode B on Deferred files (if < max_passes) OR `stopped_max_passes` | |
| Files still pending | Process next file (Mode A) next session | |
| `passes_done ≥ max_passes` | `stopped_max_passes` | Write report, signal incomplete |

### Step 5 — Display end-of-session message

```
✅ Pass P/MAX done — <NNN-slug.md> (Mode A|B)
   Coverage: X% · Deferred-S: DS · Deferred-C: DC · CORPUS:unresolved: U
   Next: chorus-feed <sandbox> --unattended
```

If `status: "converged"`:
```
✅ Unattended run complete — full corpus coverage reached.
   Passes: P · Files: N · Final coverage: X%
   Report: $SANDBOX/agent/autofeed-report-<NNN>.md
```

### Checkpoint JSON structure (reference)

```json
{
  "sandbox": "<name>",
  "started": "<ISO8601>",
  "status": "running|waiting|converged|stopped_max_passes|cancelled",
  "mode": "presplit|single",
  "phase": "A|B",
  "files_total": N,
  "files_mode_a_pending": ["003-crypto-asym.md", "004-gestion-cles.md"],
  "files_mode_b_pending": ["001-crypto-alea.md"],
  "current_file": "<NNN-slug.md>",
  "current_mode": "A|B",
  "passes_done": P,
  "max_passes": "2N",
  "coverage_pct": X,
  "families_integrated_total": 0,
  "families_deferred_total": 0,
  "families_oos_total": 0,
  "deferred_s": DS,
  "deferred_c": DC,
  "oos_reclassified": [{"section": "§3.2", "from": "⛔ OOS", "to": "⏭ Deferred"}],
  "last_update": "<ISO8601>",
  "converged": false,
  "next_action": "chorus-feed <sandbox> --unattended",
  "new_rules_this_pass": 0,
  "suggested_next_file": "<NNN-slug.md>|null",
  "deferred_unchanged_passes": 0,
  "families_closed_this_pass": 0,
  "unresolved_deferred_notes": []
}
```

- `phase`: `"A"` while `files_mode_a_pending` is non-empty; `"B"` once Phase A is complete.
- `files_mode_a_pending`: files not yet initialized (Mode A). In `presplit` mode, each maps to one agent.
- `files_mode_b_pending`: files whose agent has residual Deferred after Mode A.
- `families_integrated_total` / `families_deferred_total` / `families_oos_total`:
  persisted running totals behind `coverage_pct` — see Step 3.5 for the
  incremental-update procedure (full re-scan is the exception, not the
  per-pass default).
- `new_rules_this_pass` / `suggested_next_file` / `deferred_unchanged_passes` /
  `families_closed_this_pass` / `unresolved_deferred_notes`: structured
  counterparts to `next_action`'s free text — see Step 4 for the exact
  computation of each. Written on every `waiting`/`stopped_max_passes`/
  `converged` checkpoint update, not only on the very first one shown above
  as a shape reference.

> **Webapp integration (WEB-004):** poll `$SANDBOX/.chorus-unattended-state.json`
> every 2s via `/api/sandbox/:id/unattended-state`. Progress bar =
> `passes_done / max_passes * 100`. Cancel by writing `status: "cancelled"`.
> The checkpoint replaces the complex real-time SSE originally planned for
> WEB-004 Phase 1 — same UX, less code.
>
> **Structured fields consumption (added alongside `next_action`):** the
> webapp's "Confirmer → Feed" button renders conditional UI from
> `new_rules_this_pass` (badge, e.g. "+1 règle"), `deferred_unchanged_passes`
> (stagnation warning past a threshold, e.g. ≥2), and `suggested_next_file`
> (explicit "→ cible : <file>" label) — all without parsing `next_action`'s
> free text, which remains reserved for the ECA session prompt context (human/
> LLM-readable summary, not meant for UI regex matching). Keep both in sync:
> any future field renamed/removed here must be mirrored in the webapp's
> `readFeedStatus()` (`chorus/scanner.js` and `server/routes/scan.js`).

### Final report (`$SANDBOX/agent/autofeed-report-<NNN>.md`)

Written at convergence or `stopped_max_passes`. Contains:

- Run summary (files, passes, duration, coverage)
- Deferred-S residuals with motif (structural/too-ambiguous — corpus revision needed)
- Deferred-C residuals with motif (contextual — dependency or external norm)
- `⛔ OOS` definitive list
- OOS reclassified to Deferred (Step 0)
- CORPUS:unresolved residuals
- **"Corpus extensions suggested"** section (if any `external-norm` Deferred):

```markdown
## Corpus extensions suggested

The following sections are blocked on an external norm absent from the corpus.
Add the listed sources and re-run --unattended.

| Blocked section | Missing norm | Deferred motif |
|---|---|---|
| §3.2 — PQC algorithms | NIST SP 800-208 | external-norm |
```
