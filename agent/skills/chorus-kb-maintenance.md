# Skill — chorus-kb-maintenance

> Trigger: `chorus-kb-maintenance <sandbox-name> [--since <date|sha>] [--patch] [--report]`
> Agent: `architect`
>
> `<sandbox-name>` : sandbox whose KB (org + YAML rules + README) is audited
> `--since <date|sha>` : override the auto-detected engine-side analysis window
>                        (default: derived from the sandbox's own git history — see Phase 0.2)
> `--patch`        : apply the **mechanically safe** corrections found in Phase 3
>                    (pitfall fixes). Semantic findings from Phase 2 and 4 are
>                    **never auto-patched** — always reported for operator review.
> `--report`       : write `$SANDBOX/$WORKSPACE/reports/kb-audit-<slug>-<NNN>.md`
>                    (default when no flag given: report only, no file written —
>                    findings printed inline)
>
> **Purpose:** detect drift between (1) the engine's own skills/templates that
> *generate* rules and KB org definitions, (2) the sandbox's actual YAML rules,
> (3) their corresponding `.org` Rule Catalog entries, and (4) the sandbox's
> `README.org` — accumulated silently over a sandbox's lifetime as `chorus-feed`,
> `chorus-fix`, and direct edits each touch only part of this chain (see
> `AGENTS.md § KB org ↔ YAML sync`).
>
> **Not a replacement for:**
> - `chorus-review-kb` — corpus coverage (article → rule → Helper traceability)
> - `chorus-check` Phase 0 — `.kb-hash`/`.template-hash` staleness gate before running a pipeline
> - `chorus-audit-import` — imported project JSON fidelity
>
> `chorus-kb-maintenance` is specifically about **drift introduced by the passage
> of time**: engine conventions evolving after the sandbox's KB was generated,
> and the sandbox's own YAML/org/README falling out of sync with each other.
>
> Prerequisites: the sandbox must be a git repository (`git -C $SANDBOX rev-parse
> --is-inside-work-tree`). If not, **stop and report** — Phase 1/2 depend entirely
> on sandbox git history; there is no meaningful fallback.


## Phase 0 — Resolve scope and analysis window

### 0.1 Resolve paths

```
SANDBOX = $SANDBOXES/<sandbox-name>/
ENGINE  = $ENGINE   (this repository root)
```

Read `$SANDBOX/agent/chorus/index.org` → namespace, agent slugs, pipeline order,
list of expected `.org` files and `rules/<slug>/` directories.

Verify sandbox is a git repo:
```bash
git -C $SANDBOX rev-parse --is-inside-work-tree
```
If this fails → **stop**, report: `❌ <sandbox-name> is not a git repository —
chorus-kb-maintenance requires sandbox-local git history (Phase 1/2). Run
\`git init\` + an initial commit in the sandbox before retrying.`

### 0.2 Determine the analysis window

If `--since` is given, use it verbatim for both engine-side and sandbox-side
`git log --since=...`.

Otherwise, auto-detect the sandbox's KB creation point:
```bash
git -C $SANDBOX log --follow --diff-filter=A --format=%aI -- agent/.kb-hash | tail -1
```
If `agent/.kb-hash` was never added (predates ENG-041 hash tracking), fall back to
the first commit that added any `agent/chorus/*.org` file:
```bash
git -C $SANDBOX log --diff-filter=A --format=%aI -- 'agent/chorus/*.org' | tail -1
```
If neither exists → **stop**, report: `❌ cannot determine KB creation date —
no agent/.kb-hash or agent/chorus/*.org found in sandbox git history. Use
--since explicitly.`

Store as `SINCE_DATE`. Print:
```
[kb-maintenance] Analysis window: SINCE_DATE → HEAD
[kb-maintenance] Sandbox git: <N> commits touching agent/chorus/ or rules/ in window
```

### 0.3 Check for uncommitted sandbox drift (pre-flight)

```bash
git -C $SANDBOX status --porcelain -- agent/chorus/ rules/
```
If non-empty → **warn, do not stop**: `⚠️ uncommitted changes in agent/chorus/ or
rules/ — Phase 2's commit-correlation will not see these. Consider committing
or stashing before running chorus-kb-maintenance for a clean baseline.` Continue
regardless — this is advisory, matching the `.chorus-wip.md` posture (surface,
never silently skip).


## Phase 1 — Engine-side drift: skills & templates vs. SINCE_DATE

**Goal:** identify which engine conventions that generate rules/org content have
changed since this sandbox's KB was created, so Phase 2/3 know what to check for
— this is a scoping step, not itself a finding.

```bash
git -C $ENGINE log --since="$SINCE_DATE" --format='%h %aI %s' -- \
  agent/skills/chorus-engine-yaml.md \
  agent/skills/chorus-feed.md \
  agent/skills/chorus-feed-coverage.md \
  agent/skills/chorus-templates.md \
  agent/org/agents/_template.org \
  agent/org/agents/index.org
```

For each matching commit, read the diff (`git -C $ENGINE show <sha> -- <path>`)
and classify its relevance:

| Change type | Relevance for this skill |
|---|---|
| New/changed pitfall checklist item (`chorus-engine-yaml.md § Pitfalls`) | ✅ feeds Phase 3 checklist |
| New/changed Rule Catalog / org template structure (`_template.org`) | ✅ feeds Phase 4 README/org-shape check |
| New `_rule_trace`/`non_conformity_motif` convention (ENG-038-style) | ✅ feeds Phase 3 checklist |
| Pure prose/doc clarification, no behavioural change | ℹ️ note only, no downstream check |
| Unrelated skill section (e.g. `chorus-pdf` extraction logic) | excluded by the path filter above — should not appear |

Build **ENGINE_DELTA**: the list of concrete, mechanically-checkable rules that
postdate this sandbox's KB creation. This list is the input to Phase 3 — do not
hardcode a fixed checklist in this skill; re-derive it from `chorus-engine-yaml.md`'s
current `§ Pitfalls` section every run, since the engine file is the source of truth
and evolves independently of this skill.

Print: `[kb-maintenance] ENGINE_DELTA: <N> engine conventions postdating KB creation`


## Phase 2 — Sandbox-side drift: YAML rules touched since creation vs. their `.org` definition

**Goal:** for every `.yml` rule modified in the sandbox since `SINCE_DATE`, verify
its FIND/CONDITION/EXCEPTION/ACTION still matches what the corresponding `.org`
Rule Catalog entry describes.

### 2.1 List touched rule files

```bash
git -C $SANDBOX log --since="$SINCE_DATE" --name-only --format='%h %aI' -- \
  'rules/*/R*.yml' | awk 'NF'
```
Build **TOUCHED_RULES**: `{file, slug, rule_id, first_commit_in_window, last_commit}`.
`slug` = parent directory name under `rules/`; `rule_id` = filename without
extension (e.g. `R04-foo-bar`).

### 2.2 For each touched rule — pull both sides

For each entry in TOUCHED_RULES:
1. Read the current YAML (`rules/<slug>/<rule_id>.yml`): `RULE`, `FIND`,
   `EXCEPTION`, `CONDITION`, `ACTION`/`EFFET`, output slots written.
2. Read the corresponding Rule Catalog row in `agent/chorus/<slug>.org` for this
   `rule_id` — plus the Slot dictionary entries for any slot the rule reads/writes,
   plus the Outgoing table entries if the rule writes a new output slot.
3. Also diff the YAML against its state **just before** `first_commit_in_window`
   (`git -C $SANDBOX show <first_commit_in_window>^:rules/<slug>/<rule_id>.yml`)
   to see exactly what changed — this scopes the comparison to the actual delta,
   not the whole rule.

### 2.3 Classify each touched rule

| Finding | Meaning |
|---|---|
| ✅ Aligned | `.org` Rule Catalog entry (CONDITION/EXCEPTION prose, Outgoing slots, Constraints & Pitfalls) still accurately describes the current YAML |
| ⚠️ Org stale — description drift | YAML logic changed (new guard, new threshold, new slot) but `.org` prose/table was not updated to match |
| ⚠️ Org stale — missing slot | YAML now writes a slot absent from the Outgoing table / Slot dictionary |
| 🔴 Org contradicts YAML | `.org` explicitly describes behaviour the current YAML no longer has (worse than simply missing — actively misleading) |
| ❌ Rule Catalog row missing entirely | `.yml` file exists, touched since window start, but has no row at all in `agent/chorus/<slug>.org` |

This phase is **semantic** (requires comparing prose intent to code logic) — never
auto-patch under `--patch`. Always produce a finding row with a suggested `.org`
text update for the operator to apply.

Print: `[kb-maintenance] TOUCHED_RULES: <N> — Aligned: <a> / Stale: <s> / Contradicts: <c> / Missing row: <m>`


## Phase 3 — Mechanical pitfall compliance (ENGINE_DELTA + full pitfall checklist)

**Goal:** scan every `.yml` in the sandbox (not just TOUCHED_RULES — pitfalls can
predate this sandbox's creation too) against the mechanically-detectable rules in
`chorus-engine-yaml.md § Pitfalls`. Unlike Phase 2, these checks are syntactic/
structural, not semantic — safe to auto-fix under `--patch`.

### 3.1 Checklist (re-derive from `chorus-engine-yaml.md` each run — do not hardcode
a stale copy; the table below reflects the checklist as of this skill's authoring
and must be reconciled against the live file every invocation)

| # | Check | Detection | Auto-fixable under `--patch`? |
|---|---|---|---|
| P1 | Multi-statement `EXCEPTION`/`CONDITION` not wrapped in `do { ... }` | Parse the block; if it contains more than one top-level `;`-terminated statement and does not start with `do {` | ✅ yes — wrap mechanically, make the boolean test the block's last statement |
| P2 | `filtre` written as a YAML mapping instead of a quoted Perl string | YAML type of `filtre:` value is a mapping/dict | ⚠️ flag only — cannot safely infer the intended Perl expression |
| P3 | `return` used inside `filtre` | `filtre` string contains `\breturn\b` | ⚠️ flag only — requires rewriting as a boolean expression |
| P4 | `$f->` (scope var) referenced inside `filtre` | `filtre` string matches `\$\w+->` where `$\w+` is not `$_` | ⚠️ flag only — needs the author to rewrite using `$_` |
| P5 | `$SELF->BOARD->{flag}` read without a null-check in `filtre`/`CONDITION` | string contains `$SELF->BOARD->{\w+}` not preceded by `defined` or `&&.*BOARD &&` pattern | ⚠️ flag only — null-check placement is context-sensitive |
| P6 | Multi-line `ACTION` using folded scalar `>` instead of literal `|` | YAML scalar style of `ACTION`/`EFFET` value is folded (`>`) and content spans >1 line | ✅ yes — rewrite the YAML node style to `|` (content unchanged, only the block-scalar indicator) |
| P7 | `use Module qw(...)` inside `ACTION`/`EFFET` | ACTION/EFFET text matches `^\s*use\s+\w` | ⚠️ flag only — requires moving the helper injection to Agent `build()` |
| P8 | `---` document separator inside a rule file (multiple YAML docs in one file) | `YAML::LoadFile`-equivalent: file contains a line matching `^---\s*$` after the first doc | ⚠️ flag only — requires splitting into separate `R0N-*.yml` files, renumbering |
| P9 | Direct slot read via `$f->{slot}` in `ACTION`/`EFFET`/`CONDITION` (not an `EXCEPTION` idempotence guard) | regex scan for `\$\w+->\{(?!_)\w+\}` outside an `EXCEPTION:` block, excluding known-safe `type_element` reads | ⚠️ flag only — needs `.get('slot')` substitution reviewed per occurrence (risk of false positive on legitimate `type_element` access) |
| P10 | Direct slot write via `$f->{slot} = ...` instead of `$f->set('slot', ...)` | regex `\$\w+->\{\w+\}\s*=(?!=)` | ✅ yes — mechanical rewrite to `->set('slot', value)` is unambiguous |
| P11 | `delete $f->{slot}` instead of `$f->delete('slot')` | regex `delete\s+\$\w+->\{\w+\}` | ✅ yes |
| P12 | Failing/uncertain verdict slot set without a matching `non_conformity_motif` write in the same branch (ENG-038) | for each `ACTION` setting a slot to a known-failing value (`'NO'`, `'NON'`, `'NON_CONFORME'`, `'_a_confirmer'`), check the same `if`/branch also sets `non_conformity_motif`/`motif_*` | ⚠️ flag only — the actual motif text requires domain knowledge |
| P13 | `fmatch(slot => 'type_element')` used in a pipeline-done/EXCEPTION gate instead of the agent's own output slot | regex `fmatch\(\s*slot\s*=>\s*['"]type_element['"]\s*\)` inside EXCEPTION/ACTION of a rule whose RULE name matches `*done*`/`*terminate*`/`*phase*` | ⚠️ flag only — needs the correct agent-specific slot name |
| P14 | Unfiltered `fmatch(slot => '<slot>')` inside `EXCEPTION` (no preceding `grep` narrowing to the agent's own Frame family) | structural: `fmatch(` call inside EXCEPTION not wrapped in an outer `grep { ... type_element =~ ... }` | ⚠️ flag only |
| P15 | Aggregate rule's `!@elements`/`!@expected` branch applies the same bounded-wait `return 0` pattern used for the "pending" branch | structural: both the `if (!@elements)` and `if ($pending && $waited < MAX)` branches contain `return 0` | ⚠️ flag only — needs branch-specific rewrite (immediate `return 1` + set on `!@elements`) |
| P16 | `CONDITION` tests a business/conformance result rather than data presence | heuristic: `CONDITION` string calls a `Helper->is_valid`/`->check`-style method, or compares a `_ok`/`_conforme` slot to a literal | ⚠️ flag only — requires moving the test into `ACTION` |

> Checks marked ✅ are purely syntactic/mechanical — zero semantic ambiguity,
> safe under `--patch`. Checks marked ⚠️ are surfaced as findings regardless of
> `--patch`, never auto-applied — the underlying fix requires domain reasoning
> (choosing the right slot name, writing the right motif text, etc.) that risks
> silently introducing a *different* bug if guessed.

### 3.2 Apply fixes (only if `--patch`)

For each ✅-fixable finding (P1, P6, P10, P11): apply the mechanical rewrite,
preserving all other YAML formatting/comments. After any `.yml` edit:
```bash
# Regenerate per AGENTS.md § KB org ↔ YAML sync — V4 rule
```
Immediately update the corresponding `agent/chorus/<slug>.org` entry if the fix
changes anything externally observable (it generally doesn't for P1/P6 — pure
syntax; P10/P11 don't change semantics either) — but still regenerate
`agent/.kb-hash` since YAML file content changed (see `chorus-check.md § Phase 0`).

Print a per-file fix log:
```
[kb-maintenance] PATCHED rules/<slug>/<rule_id>.yml — P1 (wrapped EXCEPTION in do{})
[kb-maintenance] agent/.kb-hash regenerated
```


## Phase 4 — README.org consistency

Read `$SANDBOX/README.org` (or `index.org` if that is the sandbox's canonical
entry point — check `agent/chorus/index.org` for the convention actually used).

Cross-check against ground truth:

| README claim | Ground truth source | Check |
|---|---|---|
| List of agents / `.org` files | `ls $SANDBOX/agent/chorus/*.org` | every file listed exists; every existing file is listed (unless explicitly marked sub-skill/internal) |
| List of `rules/<slug>/` rule counts | `ls $SANDBOX/rules/<slug>/*.yml \| wc -l` per slug | counts match, or README uses a non-numeric qualitative claim that is not contradicted |
| Pipeline order described | `agent/chorus/index.org` pipeline order section | same sequence |
| Last-updated / last-feed date mentioned | `git -C $SANDBOX log -1 --format=%aI -- agent/chorus/` | not stale by more than one `chorus-feed`/`chorus-fix` cycle — flag if README date predates the latest KB-touching commit |
| Links to `agent/chorus/*.org` (if README uses relative links/references) | file existence | no dangling reference |
| Coverage/stability-point claims (SP1/SP2, Deferred=0, etc.) | latest `chorus-review-kb` org report if present (`agent/review-kb-*.org`) | claim not contradicted by the latest report on file |

Classify each check: ✅ consistent / ⚠️ stale (outdated but not wrong) / 🔴 incorrect
(actively contradicts ground truth). README fixes are **never** auto-patched even
under `--patch` — prose rewrite is always surfaced for operator review, with the
proposed replacement text given in the finding.


## Phase 5 — Supplementary consistency checks

Run these regardless of Phase 1–4 findings — they catch drift classes outside the
4-point brief but within the same "KB internal consistency" scope:

### 5.1 `.kb-hash` / `.template-hash` freshness
Recompute both hashes exactly as `chorus-check.md § Phase 0` does
(`sha256sum agent/chorus/*.org` + `# rules` section over `rules/*/*.yml`) and
diff against the stored `agent/.kb-hash`. A mismatch here means Phase 0 of the
*next* `chorus-check` run will trigger a FULL PATH regeneration — report this
proactively rather than letting the operator discover it mid-pipeline-run.

### 5.2 Rule Catalog ↔ YAML file bijection
For each `<slug>.org`, extract every `rule_id` referenced in its Rule Catalog
table. For each `rules/<slug>/`, list every `R*.yml` file present.
- **Orphan catalog row**: `rule_id` in the `.org` table with no matching `.yml` file.
- **Undocumented rule file**: `.yml` file present with no matching Rule Catalog row.
Both are reported — never silently assumed to be intentional.

### 5.3 BOARD-global vs. Frame-local slot confusion
For each slot read via `defined $e->{slot}` / `$e->get('slot')` somewhere in the
sandbox's rules, check whether that same slot name is *ever* written via
`$SELF->BOARD->{slot} = ...` anywhere in the sandbox. If a slot is **only** ever
written at BOARD level but read via `$e->{slot}`/`$e->get('slot')` on an element
Frame (never via `$SELF->BOARD->{slot}` or `$e->BOARD->{slot}`), flag it — this is
the exact silent-permanent-false pattern documented in `chorus-engine-yaml.md`'s
BOARD-global vs. Frame-local decision table.

### 5.4 `_rule_trace` / `non_conformity_motif` traceability spot-check
Sample a handful of rules writing failing/uncertain verdicts (reuse the P12 scan
from Phase 3) and confirm `_rule_trace` entries are pushed where the KB convention
requires it (per ENG-038/`_rule_trace` checklist items in `chorus-engine-yaml.md`).

### 5.5 Residual `.chorus-wip.md`
```bash
test -f $SANDBOX/.chorus-wip.md && echo "⚠️ WIP checkpoint present"
```
If present, read its content and report the interrupted operation — never delete
it automatically (same rule as `AGENTS.md § .chorus-wip.md convention`).

### 5.6 Sandbox git cleanliness (post-run)
Re-run the Phase 0.3 check after all Phase 3 patches (if `--patch` was used) —
confirm the patch set is exactly what was intended before suggesting a commit;
never commit automatically on behalf of the operator.

### 5.7 Thesaurus consistency (only if `agent/thesaurus/` exists)
For each alias entry in `agent/thesaurus/global.org` (and any `<client>.org`
shard), confirm the target slot/value it maps to still exists in the current KB
(Slot dictionary across all `<slug>.org` files). Flag orphaned aliases pointing to
slots removed since the thesaurus entry was created.


## Phase 6 — Report

### 6.1 Console summary (always printed)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🧹  chorus-kb-maintenance — <sandbox-name>

  Window: <SINCE_DATE> → HEAD (<N> commits)

  Phase 1 — Engine delta:        <N> conventions postdating KB creation
  Phase 2 — Touched rules:       <N> total — ✅<a> ⚠️<s> 🔴<c> ❌<m>
  Phase 3 — Pitfall compliance:  <N> findings — <F> auto-fixed (--patch) / <F> flagged
  Phase 4 — README.org:          ✅<a> ⚠️<s> 🔴<c>
  Phase 5 — Supplementary:       <N> findings (.kb-hash / catalog bijection / BOARD / WIP / thesaurus)

  <if --patch not given and any ✅-fixable P-check found>
  ℹ️  <N> mechanical fixes available — re-run with --patch to apply
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 6.2 `--report` file

If `--report` given, write `$SANDBOX/$WORKSPACE/reports/kb-audit-<slug>-<NNN>.md`
(auto-increment `<NNN>` like `chorus-check --explain`'s numbering convention) with:
- Full findings table per phase (rule_id, finding class, suggested fix text)
- The ENGINE_DELTA list from Phase 1 (so the operator can see exactly which engine
  conventions motivated each Phase 3 check this run)
- A "Recommended next actions" section, ordered by severity (🔴 first, then ⚠️, then ✅ already-patched log)

### 6.3 Never auto-commit
This skill never commits to either the engine or the sandbox repo. If Phase 3
applied `--patch` fixes, end the response by explicitly prompting the operator
to review and commit the sandbox changes — do not fold this into any
pre-approved auto-commit convention (unlike `update-knowledge`-style KB org
commits in other projects' `AGENTS.md` — no equivalent rule exists for Chorus).


## Checklist (pre-flight for this skill's own correctness)

- [ ] Sandbox git-repo check done before anything else (Phase 0) — hard stop if absent
- [ ] `SINCE_DATE` resolution never silently defaults to "beginning of time" — explicit
      stop-and-ask if neither `.kb-hash` nor `agent/chorus/*.org` creation commit found
- [ ] Phase 3's checklist (§ 3.1) is explicitly re-validated against the live
      `chorus-engine-yaml.md § Pitfalls` section each run — if that file has pitfall
      items not reflected in the table above, note the gap in the report rather than
      silently using a stale table
- [ ] Phase 2 findings are never auto-patched, regardless of `--patch`
- [ ] Phase 4 README findings are never auto-patched, regardless of `--patch`
- [ ] `.kb-hash` regenerated after any Phase 3 `--patch` YAML edit
- [ ] `.chorus-wip.md` presence surfaced, never deleted
- [ ] No automatic git commit in either repo
