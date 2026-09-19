# chorus-corpus-scoping

> Trigger: `chorus-corpus-scoping <sandbox-name> [--corpus <file(s)>]`
> Agent: `architect`
>
> Also loads **automatically** as a gate inside `chorus-feed <sandbox> <corpus>`
> **Mode A** (first initialization), before any KB/YAML/Helpers.pm is written —
> see "Integration with `chorus-feed`" below for the exact trigger condition.

## Purpose

Generic, domain-agnostic skill that produces a **structural scoping pass** —
agents, Frames, inter-Frame relationships, control slots, BOARD slots, pipeline
order — as a standalone, human-reviewable artefact **before** any KB org file,
YAML rule, or Helper is generated.

It contains **no domain knowledge** — only the analytical method already used
internally by `chorus-feed` §1.1–1.3 (agents, Frames, relationships, control
slots, pipeline ordering), extracted into an explicit gate with a persistent
artefact and a validation checkpoint. Applicable to any corpus, any sector.

## Why a separate gate

`chorus-feed` Mode A already performs this analysis internally (§1.1 Corpus
Analysis), but as an in-flight step immediately followed by generation — there
is no persistent artefact and no pause for human validation before KB/YAML/
Helpers.pm are written. On a large or structurally complex corpus, a scoping
error (wrong agent split, missed Frame relationship, wrong control-slot choice)
is expensive to unwind once artefacts already exist. This skill inserts a
checkpoint: produce the scoping decisions, write them down, let a human confirm
them, **then** run `chorus-feed` for actual generation.

## When this skill loads

- **On demand:** `chorus-corpus-scoping <sandbox-name> [--corpus <file(s)>]` —
  run standalone, any time, on any sandbox.
- **Automatically, inside `chorus-feed <sandbox> <corpus>` Mode A only**, when
  the corpus crosses a complexity threshold (see below) and no `SCOPING.md`
  exists yet in the sandbox. `chorus-feed` **pauses after generating
  `SCOPING.md`** and waits for explicit human confirmation before proceeding
  to KB/YAML/Helpers.pm generation.
- **Never triggers on `--enrich` runs** — scoping is a Mode A (initialization)
  concern only. Enrichment works within an already-scoped structure.

### Standalone invocation — decision table

When called as `chorus-corpus-scoping <sandbox-name> [--split]`, apply this
decision table **before doing anything else**. Never re-run Phase 1 if
`SCOPING.md` already exists — re-analysis wastes tokens and risks overwriting
a previously confirmed structure.

| `SCOPING.md` state | `--split` flag | Agent files present? | Action |
|---|---|---|---|
| **Absent** | any | — | Run Phase 1 — analyse corpus, write `SCOPING.md` as `DRAFT`, stop and ask for confirmation |
| **`DRAFT`** | any | — | Display existing `SCOPING.md`, ask operator to confirm or revise. Do NOT re-run Phase 1. |
| **`CONFIRMED`** | absent | **absent** | Run Phase 2 automatically — same as `--split`. Display Phase 2 summary, ask review before proceeding to `chorus-feed`. |
| **`CONFIRMED`** | absent | **present** | Check idempotence (Step 6): if source corpus unchanged → display "Agent files up to date", suggest `chorus-feed` next step. If changed → re-run Phase 2. |
| **`CONFIRMED`** | `--split` | absent | Run Phase 2 — explicit trigger, same as automatic above. |
| **`CONFIRMED`** | `--split` | present | Force re-run Phase 2 (override idempotence check) — operator explicitly requested regeneration. |

> **Key rule:** `--split` is **never needed to trigger Phase 2** when `SCOPING.md`
> is `CONFIRMED` and no agent files exist — Phase 2 runs automatically. `--split`
> is useful only to **force regeneration** when agent files already exist (e.g.
> after manually editing `SCOPING.md ## Corpus section assignment`).
>
> **Never re-run Phase 1** on a `CONFIRMED` or `DRAFT` `SCOPING.md` unless the
> operator explicitly requests it with `--rescan`. Re-running Phase 1 silently
> overwrites the confirmed structure and resets the status to `DRAFT`.

### Auto-trigger threshold (inside `chorus-feed` Mode A)

| Condition | Action |
|---|---|
| Corpus ≤ 2 files **and** ≤ ~50 pages (or equivalent plain-text size) | Skip — proceed directly to `chorus-feed` §1.1 inline, no gate, no `SCOPING.md` required |
| Corpus > 2 files, **or** > ~50 pages, **or** operator explicitly requests it | Run this skill first — block generation until `SCOPING.md` exists and is confirmed |
| `SCOPING.md` exists with status `DRAFT` | Stop — display it, ask operator to confirm |
| `SCOPING.md` exists with status `CONFIRMED`, no agent files | Run Phase 2 then stop — present split summary before proceeding to generation |
| `SCOPING.md` exists with status `CONFIRMED`, agent files present | Load agent files directly — skip Phase 1 and Phase 2, proceed to `chorus-feed` generation |

> The threshold is deliberately approximate — when in doubt, run the gate.
> The cost of an unnecessary scoping pass on a small corpus is low; the cost of
> skipping it on a large one is high (KB/YAML/Helpers.pm rework).

## The five structuring questions

These are the same analytical questions as `chorus-feed.md` §1.1–1.3, made
explicit and given a persistent, reviewable form. No domain vocabulary is
prescribed here — only the structural questions to answer using the actual
corpus's own vocabulary.

### 1. Agents (specialties)

Group rules by coherent theme. Criteria:
- Rules concerning the same types of Frames.
- Same incoming/outgoing slots.
- Orderable sequentially without cyclic dependencies.

Result: an ordered list of agents (slug + intent + pipeline position).

### 2. Domain Frames

For each persistent concept in the corpus (≥ 2 slots, stable identity) →
candidate Frame. Intermediate calculations remain plain slots, not Frames.

> ⛔ The slot identifying an element's type must always be named
> `type_element` (engine-wide convention — not a scoping decision, a hard
> constraint). All other slot names use the corpus's own language and
> vocabulary — never translate or normalize into a different language than
> the source corpus.

### 3. Inter-Frame relationships

Examine whether any Frame *belongs to* or *depends on* another Frame for key
properties. Signs of a relationship:
- A slot on Frame A duplicates a property of Frame B.
- A rule would need a cross-product scope (`FIND: var1 / var2`) to relate two
  Frame types — this usually signals a missing structural link.
- Multiple Frames of type A share the same normative thresholds coming from a
  static catalog indexed by some key tuple.

For each relationship found, classify it:

| Relationship type | Pattern |
|---|---|
| Element A structurally belongs to / is connected to B | **slot→Frame** (`*_ref` field, resolved at load time) |
| Multiple Frames share a normative threshold catalog | **`_ISA` prototype** (shared catalog + inheritance) |

### 4. Control slots (only if the corpus explicitly signals them)

Do **not** add these speculatively — only when a corpus pattern explicitly
motivates each one:

| Control slot | Corpus signal that motivates it |
|---|---|
| `_DEFAULT` | "default value X unless otherwise specified", "applies if not stated" |
| `_NEEDED` | An explicit derivation formula ("= sum of", "= computed from") for a slot not always supplied |
| `_AFTER` | An explicit stated dependency: "when X changes on A, Y on B must be re-evaluated" — last resort, strict guardrails (see `chorus-feed.md` §1.2c) |
| `_BEFORE` | Explicit need to normalize inconsistent input formats before storage |
| `_REQUIRE` | Explicit hard domain constraints (min/max, enum, non-empty) stated as "must never" |

### 5. BOARD slots and pipeline order

- **BOARD slots:** results global to the pipeline run (totals, phase flags,
  cross-agent signals) rather than specific to one Frame element. List each
  with its producer agent, consumer agent(s), and type.
- **Pipeline order:** order agents by data dependency — agent N sets slot X,
  agent N+1 consumes X, so N+1 runs after N. `register()` order in the
  generated shell Agent must respect this.

## Mandatory pre-checks before finalizing the scoping

Two discipline checks from `chorus-feed.md` apply during scoping, not only
during rule authoring — flag any suspect section now, before generation:

- **Rotated-header matrix tables** (`chorus-pdf.md` §1.4c / `chorus-feed.md`
  §1.3b): if any table earmarked for a Frame catalog or threshold source shows
  the flattened-row-label-plus-column-tokens symptom, do not use it as a
  scoping source — verify independently via `pdftotext -layout` first, or mark
  the concept `⛔ Out of scope (pending table verification)`.
- **Grammar/identifier rules spanning multiple forms** (`chorus-feed.md`
  §1.3c): if scoping identifies a Frame whose type-identifying slot has a
  documented "well-formed identifier" shape, note whether the corpus has
  alternate/extended forms to search for — so the eventual rule-authoring
  pass in `chorus-feed` knows to check before finalizing.

## Output — `SCOPING.md`

Written at the sandbox root: `sandboxes/<sandbox-name>/SCOPING.md`.

```markdown
# Corpus scoping — <sandbox-name>

## Corpus reviewed
| File | Pages / size | Notes |
|---|---|---|
| corpus/<file> | <n> | <one-line content summary> |

## Agents (proposed pipeline order)
| # | Slug | Intent | Consumes (slots) | Produces (slots) |
|---|---|---|---|---|
| 1 | <slug> | <intent> | — | <slot, slot> |
| 2 | <slug> | <intent> | <slot> | <slot> |

## Domain Frames
| Frame | Key slots | Notes |
|---|---|---|
| <frame_type> | <slot, slot, type_element> | <persistent concept, stable identity> |

## Inter-Frame relationships
| From | To | Pattern | Notes |
|---|---|---|---|
| <frame_a>.<slot> | <frame_b> | slot→Frame / _ISA prototype | <justification> |

## Control slots
| Frame.slot | Control slot | Corpus justification |
|---|---|---|
| <frame>.<slot> | _DEFAULT / _NEEDED / _AFTER / _BEFORE / _REQUIRE | <quoted or paraphrased corpus signal> |

## BOARD slots
| BOARD slot | Written by | Read by | Type |
|---|---|---|---|
| <slot> | <agent> | <agent> | flag / count / … |

## Pre-checks performed
- [ ] Rotated-header matrix table scan — <result: none found / N flagged, see below>
- [ ] Grammar/identifier alternate-form search — <result per identifier family>

## Corpus section assignment
  Filled by Phase 2 (corpus pre-split) after operator confirms `CONFIRMED` status.
  Each corpus section maps to one primary agent (generates rules) and zero or more
  context agents (section included for context, `no_auto_rules` for those agents).

  | Section corpus | Agent primaire | Agents contexte | Statut |
  |---|---|---|---|
  | <§N — title> | <slug> | <slug, slug> | PRIMARY / SHARED / CONTEXT-ONLY |

  Statut values:
  - `PRIMARY`      — section generates YAML rules for the primary agent
  - `SHARED`       — section included in all agents as context (e.g. intro, glossary,
                     composition tables) — `no_auto_rules` everywhere
  - `CONTEXT-ONLY` — section has no primary agent (cross-cutting, procedural) but
                     is included as context in the listed agents

## Open questions for the operator
- <anything the agent could not resolve unambiguously from the corpus alone>

## Status
`DRAFT` — awaiting operator confirmation
`CONFIRMED — <date>` — cleared for Phase 2 corpus pre-split and `chorus-feed` generation
```

## Phase 2 — Corpus pre-split (multi-target extraction)

> **Trigger:** runs automatically immediately after the operator sets
> `SCOPING.md` status to `CONFIRMED`, before any `chorus-feed` invocation.
> Can also be run standalone: `chorus-corpus-scoping <sandbox-name> --split`.
>
> **Prerequisite:** `SCOPING.md` must have status `CONFIRMED` and a non-empty
> `## Agents` table. If status is `DRAFT`, stop and ask the operator to confirm first.
>
> **Single responsibility:** produce one corpus file per agent, each containing
> all sections relevant to that agent (primary + context), assembled from the
> original normalized corpus `.md` file(s) in `$SANDBOX/corpus/`. Never modifies
> the original corpus files — only creates new derived files alongside them.

### Step 1 — Build section inventory

Re-read the corpus `.md` file(s) identified in `## Corpus reviewed` (SCOPING.md).
Extract every section heading (any Markdown `#` level, or equivalent structural
marker such as class/family/component identifiers in normative standards).

For each section, record:
- its heading text and anchor identifier (e.g. `§ADV_ARC.1`, `Table EAL-1`)
- its page range estimate (character offset in the `.md` file — used only for
  ordering within agent files, not for classification)
- its full text block (heading + all content until the next same-level heading)
- its **pre-annotation** (see below) — checked before any keyword scoring

#### Pre-annotation convention — `CHORUS:no_auto_rules`

Any section in a corpus `.md` file may carry a pre-annotation marker placed
on the line immediately following its heading:

```markdown
## Foreword
<!-- CHORUS:no_auto_rules — informative, no codifiable requirement -->

## Annex A (informative) — Glossary
<!-- CHORUS:no_auto_rules — definitions only, fed to thesaurus -->
```

**Effect in Phase 2:** a section bearing this marker is **immediately and
unconditionally** classified `OUT-OF-SCOPE` (if no agent would benefit from
it as context) or `CONTEXT-ONLY` (if it contains definitions/glossary material
useful for cross-reference). The keyword scoring algorithm (Step 2) is skipped
entirely for these sections — no scoring needed, no risk of misclassification.

**Who writes these markers:**
- `chorus-pdf`, `chorus-word`, `chorus-excel` — auto-detect common doctrinal
  patterns during extraction and insert the marker automatically (see each
  skill's § Auto-annotation step).
- The operator — can add markers manually to the `.md` before running
  `chorus-corpus-scoping --split`, with zero domain knowledge required:
  the heading text is sufficient to identify intro/foreword/annex sections.

**Priority rule:** a `CHORUS:no_auto_rules` marker always wins over any
keyword score. A section cannot be promoted to PRIMARY by the scoring
algorithm if it carries this marker.

### Step 2 — Classify sections against agents

For each section S, determine its **primary agent** and **context agents** using
the `## Agents` intent descriptions from `SCOPING.md`:

**Classification algorithm:**

```
PRIMARY match (one agent only):
  Score each agent A for section S:
    score(A, S) = count of distinct intent keywords of A found in S's heading + first paragraph
  Primary agent = argmax score(A, S)   if max_score > 0
               = none                   if max_score = 0 (→ CONTEXT-ONLY or SHARED)

SHARED flag:
  A section is SHARED if it matches ≥ 3 agents with score > 0 AND no single agent
  dominates (max_score < 2 × second_score) — typically: intro, glossary, definition
  sections, composition/dependency tables that are referenced across all agents.

CONTEXT-ONLY flag:
  A section with max_score = 0 but whose content is referenced (by §-number) from
  at least one agent's primary sections → CONTEXT-ONLY for those referencing agents.
  A section with max_score = 0 and no cross-references → OUT-OF-SCOPE (not included
  in any agent file; marked ⛔ in the corpus section assignment table).

CONTEXT agents (secondary):
  For every non-primary agent B where score(B, S) > 0, or where S is SHARED:
    add B to S's context agents list.
```

> ⚠️ **Keyword extraction from intent:** the `Intent` column of the `## Agents`
> table uses natural language (e.g. "Development assurance families — ADV_ARC,
> ADV_FSP, ADV_TDS"). Extract both the free-text words AND any explicit identifiers
> (e.g. `ADV_ARC`, `ADV_FSP`) as matching tokens — identifier matching takes
> precedence over keyword matching (exact prefix match on section heading beats
> keyword frequency).

### Step 3 — Assemble agent corpus files

For each agent A in pipeline order:

1. Collect all sections where A is primary agent OR A is in context agents OR section
   is SHARED.
2. Sort collected sections by their original document order (preserves narrative flow
   and cross-reference context).
3. Write `$SANDBOX/corpus/<NNN>-<slug-A>.md` where `<NNN>` follows the existing
   numbering (next available after the source file(s)).

Each agent corpus file opens with a mandatory header block:

```markdown
# SPLIT FROM: corpus/<original-file.md>
# AGENT: <slug-A>
# GENERATED BY: chorus-corpus-scoping Phase 2 — <YYYY-MM-DD>
# SECTIONS: <N_primary> PRIMARY + <N_context> CONTEXT + <N_shared> SHARED
```

Each section within the file is preceded by a one-line marker:

```markdown
<!-- SECTION: §<ref> | STATUS: PRIMARY | AGENT: <slug-A> -->
<!-- SECTION: §<ref> | STATUS: SHARED -->
<!-- SECTION: §<ref> | STATUS: CONTEXT | PRIMARY-AGENT: <slug-B> -->
```

These markers are read by `chorus-feed` Phase -0.5 to apply `no_auto_rules`
on non-PRIMARY sections — never visible in the final KB artefacts.

Also write `$SANDBOX/corpus/<NNN>-no-auto-rules.md` containing all OUT-OF-SCOPE
sections (informative, procedural, unmatched) — available as reference but never
fed to `chorus-feed`.

### Step 4 — Update `## Corpus section assignment` in SCOPING.md

For each section classified in Steps 1–2, append a row to the
`## Corpus section assignment` table (replacing the placeholder row).

### Step 5 — Display split summary and ask confirmation

```
[chorus-corpus-scoping — Phase 2] Corpus pre-split complete
  Source file(s)  : corpus/<original>.md  (<N> sections found)
  Agent files     : <N_agents> files written
  ─────────────────────────────────────────────────────────────
  Agent            File                        PRIMARY  CONTEXT  SHARED
  <slug-A>         corpus/<NNN>-<slug-A>.md      <n>      <n>     <n>
  <slug-B>         corpus/<NNN>-<slug-B>.md      <n>      <n>     <n>
  no-auto-rules    corpus/<NNN>-no-auto-rules.md  —        —      <n>
  ─────────────────────────────────────────────────────────────
  Sections unmatched (⛔ out-of-scope) : <n>

⚠️  Review the ## Corpus section assignment table in SCOPING.md.
    Correct any misclassified section by editing the table directly,
    then re-run chorus-corpus-scoping --split to regenerate agent files.
    When satisfied, proceed with:
    chorus-feed <sandbox-name> corpus/<NNN>-<first-agent>.md
```

> **Operator review is structural, not normative:** the operator only needs to
> verify that each section heading landed in the right agent file — not to
> understand the normative content of the section itself. E.g. "ADV_ARC.1 is
> in agent-adv" is verifiable from the section title alone, with zero domain
> knowledge of what ADV_ARC.1 requires.

### Step 6 — Idempotence

If agent corpus files already exist (from a previous Phase 2 run):
- Check whether the source corpus `.md` has changed (compare file mtime or content hash).
- If unchanged → skip re-generation and display: `[Phase 2] Agent files already up to date.`
- If changed → delete old agent files and regenerate from scratch (never partially update).

---

## Integration with `chorus-feed`

`chorus-feed.md` Mode A, Phase 1 (Corpus Analysis) is amended as follows:

```
Before Phase 1 (Corpus Analysis):
  1. Check the auto-trigger threshold (see above).
  2. If threshold crossed and sandboxes/<sandbox-name>/SCOPING.md absent:
     → run chorus-corpus-scoping, write SCOPING.md with status DRAFT.
     → STOP. Do not proceed to KB/YAML/Helpers.pm generation.
     → Present SCOPING.md to the operator, request confirmation.
  3. If SCOPING.md exists with status CONFIRMED:
     → skip §1.1–1.3 inline analysis — use SCOPING.md's decisions directly
       as the basis for KB org / YAML / Helpers.pm generation.
  4. If SCOPING.md exists with status DRAFT (unconfirmed from a prior run):
     → STOP. Do not proceed. Ask the operator to confirm or revise it first.
```

This does not change `chorus-feed`'s single responsibility (it still never
generates infrastructure code) — it only relocates *when* the structural
decisions of §1.1–1.3 are made and gives them a persistent, confirmable form.

## Relationship to other skills

- **`chorus-corpus-directives.md`** — orthogonal, not overlapping. Directives
  settle **inter-source** structuring (version pinning, `no_auto_rules` scope,
  thesaurus seed, cross-reference format) for corpora combining ≥2
  independently-versioned sources. Scoping settles **intra-domain** structuring
  (agents, Frames, relationships) for any corpus, single- or multi-source.
  When both apply (a large multi-source corpus), run directives first (source
  boundaries and rule-generation eligibility), then scoping (internal
  structure) — in that order, since scoping's agent/Frame analysis benefits
  from already knowing which sources are `no_auto_rules`.
- **`chorus-feed.md`** — consumes `SCOPING.md` when present and confirmed;
  otherwise performs its own inline §1.1–1.3 analysis for small corpora that
  did not cross the auto-trigger threshold.
- **`chorus-engine-infra.md` §1.5, §3** — full technical reference for BOARD
  and inter-Frame relationship *implementation* (this skill only decides
  *what* relationships/slots exist, not their Perl implementation).

## Output guarantees

- Creates or updates `sandboxes/<sandbox-name>/SCOPING.md` only.
- Never touches `KB/`, `rules/`, `lib/`, or `agent/chorus/` — pre-flight
  analysis only, no generation.
- Never reads another sandbox's `SCOPING.md` or KB (strict sandbox isolation,
  same rule as every other skill in this repository).
