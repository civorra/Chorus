# Skill — chorus-feed

> Trigger: `chorus-feed <sandbox-name> <corpus> [--enrich]`
> Agent: `architect`
>
> `<sandbox-name>`: name of the sandbox directory under `$SANDBOXES/`
> `<corpus>`: plain-text file (`.txt`), Markdown file (`.md`), or inline content — **never a PDF**
> `--enrich`: activates Mode B (incremental enrichment) — absent by default
>
> **Single responsibility: enrich knowledge.**
> This skill never generates infrastructure code (Feed, shell Agent, Expert, run.pl).
> It produces:
>   - KB org-mode files per agent (`eca/agents/<slug>.org`)
>   - YAML rule files (`rules/<slug>/R<NN>-xxx.yml`)
>   - Business knowledge Perl helpers (`lib/<Namespace>/Agent/<Slug>/Helpers.pm`)
>   - Pipeline index (`eca/agents/index.org`)
>
> To validate a project based on this knowledge → use `chorus-check`.

---

## ⛔ Strict sandbox isolation

**Never read any file, KB, YAML, or artifact from a sandbox other than `<sandbox-name>`.**

This applies regardless of context: even if another sandbox appears to contain similar
or related knowledge, it must be completely ignored. Each sandbox is an independent,
self-contained unit. Cross-sandbox reads are forbidden in all modes (A and B).

---

## 0. Prerequisites

Load: `chorus-engine-yaml.md` — YAML authoring reference (Frame essentials, Engine rule triggering, YAML guide, checklists)

### ⛔ PDF input guard

**Before doing anything else**, check the `<corpus>` argument.
If it ends in `.pdf` (case-insensitive) → **stop immediately** and output:

```
⛔ The corpus provided is a PDF file.
   chorus-feed requires a plain-text or Markdown file as input.

   Run first:
     chorus-pdf <sandbox-name> <file.pdf>           (text only, no API key)
     chorus-pdf <sandbox-name> <file.pdf> --auto    (recommended — pdfminer + vision)
     chorus-pdf <sandbox-name> <file.pdf> --images  (full vision — scanned PDFs)

   Then re-run:
     chorus-feed <sandbox-name> corpus/<NNN>-<slug>-text.txt
     (or: corpus/<NNN>-<slug>-vision.md)

   chorus-pdf extracts text, tables, figures and diagrams and produces
   a .txt (text mode) or .md (auto/images mode) file ready for chorus-feed.
```

Do not proceed past this point if the input is a PDF.
Inline content (no file extension) is always accepted as-is.

---

## Mode Selection

**Default: Mode A — always, regardless of the sandbox state.**

The `--enrich` flag is required to activate Mode B.

| Condition | Mode |
|---|---|
| No `--enrich` flag | **Mode A** — ignore any existing KB in the sandbox |
| `--enrich` flag present | **Mode B** — read existing KB and enrich |

> ⚠ Without `--enrich`, **never** read `eca/agents/`, existing YAMLs, or
> any other KB artifact from the sandbox — even if the `<sandbox-name>` directory already exists.
> The provided corpus is treated as a fresh source, independent of any existing context.

---

## Mode A — Initialization (new corpus, fresh base)

Used when `<sandbox-name>` does not yet exist or does not contain a KB.

### Phase 0 — Sandbox Initialization

Create the directory structure:

```bash
SANDBOX="$SANDBOXES/<sandbox-name>"
mkdir -p "$SANDBOX/eca/agents"
mkdir -p "$SANDBOX/corpus"
mkdir -p "$SANDBOX/rules"
mkdir -p "$SANDBOX/lib"
```

Save the corpus in `corpus/001-<slug-source>.txt`
(convention: numbered to allow incremental enrichment).

Create `README.org`:

```org
#+TITLE: Sandbox <sandbox-name>
#+DATE: <date>
#+STATUS: draft

* Corpus
  | Num | Fichier                    | Source              | Date       |
  |-----+----------------------------+---------------------+------------|
  | 001 | corpus/001-<slug>.txt      | <origine>           | <date>     |

* Identified pipeline
  (filled in during Phase 1)

* Agent status
  | Agent | KB | YAML | Helpers | Enrichments |
  |-------+----+------+---------+-------------|

* Session notes
```

### Phase 1 — Corpus Analysis

**1.1 Identify specialties**

Read the corpus in full. Group rules by coherent theme.
Each group = one agent. Criteria:
- rules concerning the same types of Frames
- same incoming/outgoing slots
- orderable sequentially without cyclic dependencies

Result: ordered list of agents (slug + intent + pipeline position).

**1.2 Identify domain Frames**

For each persistent concept in the corpus (≥ 2 slots, stable identity) → Frame.
Intermediate calculations remain as slots, not Frames.

**1.3 Identify the pipeline**

Order agents by data dependency:
agent N sets slot X → agent N+1 consumes X → N+1 after N.

### Phase 2 — Targeting Strategy (_SCOPE)

**Do not skip this phase.**

**2.1 Reminder**

`_SCOPE` → Cartesian product. `fmatch(slot => 'X')` returns all Frames
carrying X. The `filtre` reduces **before** the combinatorial loop.
A Frame is invisible to an agent if it does not carry the targeted slot.

**2.2 Rule A vs B**

```
Volume Frames < 50  AND  discriminating slots well distributed → Strategy A
Otherwise                                                       → Strategy B
```
When in doubt → prefer B (always more efficient).

> ⚠️ **Scalability — volume rule:** if the expected number of Frames exceeds 100,
> **always force Strategy B** (presence slot + `EXCEPTION` on each rule).
> Strategy A without `filtre` on a scope of > 100 Frames risks O(N²)
> as soon as `FIND` has multiple variables (unreduced Cartesian product).

**2.3 `_MAX_CYCLES` sizing**

Document in the `Constraints & Pitfalls` section of each agent KB:

```
_MAX_CYCLES recommended: N_frames × N_rules_agent × N_agents × 10
```

Example for a real construction pipeline (300 elements, 5 agents, 8 rules/agent):

```perl
_MAX_CYCLES => 300 * 8 * 5 * 10,   # = 120 000
```

The engine's default value (`10 000`) is a safeguard against infinite loops
— it must be calibrated to the expected volume, not used as-is.

**2.3 Strategy B — presence slot**
- Name: `besoin_<slug_underscore>` (convention)
- Set by: initial feed (agent 1) or agent N-1 in its ACTION (subsequent agents)

**2.4 Strategy A — discriminating slot**
- Identify the common slot + filter value
- If `fmatch` returns > 100 Frames before `grep` → reconsider B

### Phase 3 — Fill the KB per agent

Create `$SANDBOX/eca/agents/<slug>.org` from `_template.org`.
Mandatory fill order:

1. Header (`#+AGENT`, `#+PIPELINE_POS`, `#+RULES_DIR`)
2. Domain
3. **Targeting slots** — strategy + table + pre-population contract
4. Pipeline I/O (incoming / outgoing slots)
5. Ontology
6. Frame catalog
7. Slot dictionary
8. Rule catalog
9. **Perl Helpers** — signatures + complete business logic code
10. Constraints & Pitfalls

> **Helpers rule:** a helper belongs to `chorus-feed` (and therefore to the KB)
> if it encodes **knowledge extracted from the corpus**: value tables,
> normalized calculations, regulatory thresholds. It does NOT belong to `chorus-feed`
> if it relates to infrastructure (file access, parsing, networking).

> ⚠️ **Normative tables — externalize into Helpers, not inline in YAMLs.**
> For domains with dense corpora (standards, DTU, EC5, NF EN…), normative
> values (resistances, exposure classes, regulatory thresholds…) must
> be centralized in `Helpers.pm` rather than coded as scalars in YAML `ACTION`s.
> Advantages: updates during a normative revision without touching the YAMLs;
> traceability to the source (comment `Source corpus: §<N> — <title>`);
> unit tests independent of the rules.
>
> **Traceability rule:** each threshold or normative table in `Helpers.pm`
> must be annotated with its corpus source:
> ```perl
> # Source corpus: §5.3 tab. 1 — NF EN 338:2016 — Bending resistance by class
> my %FM_PAR_CLASSE = (C14 => 14, C16 => 16, C18 => 18, C24 => 24, C30 => 30);
> ```
> If the source is not identifiable → document the uncertainty in a `# TODO` comment.

Points to watch:
- Idempotence: `EXCEPTION: defined $var->{<slot_pose>}` on every rule that sets a slot
- Termination: document in which rule and under what condition `solved()` is called
- Naming: `R<NN>-<slug>.yml` — alphabetical order = load order

### Phase 4 — Create `eca/agents/index.org`

```org
#+TITLE: Pipeline — <sandbox-name>

* Pipeline global
  | Pos | Agent (module Perl)     | Slug    | KB                 | Statut |
  |-----+-------------------------+---------+--------------------+--------|
  |   1 | <Namespace>::Agent::Xxx | <slug>  | eca/agents/x.org   | draft  |

* Pipeline consistency
  - Agent 1 targeting slot: set by → initial feed
  - Agent 2 targeting slot: set by → agent 1 (R<NN>-xxx.yml, ACTION)
  - Termination agent: <Name> pos <N> → rule <Rxx> → solved()

* Integrated corpus
  | Num | Fichier              | Agents affected     |
  |-----+----------------------+---------------------|
  | 001 | corpus/001-xxx.txt   | all (initialization)|
```

### Phase 5 — Generate YAML files

> **Language rule:** use English keywords by default (`RULE`, `FIND`, `ACTION`, `PREMISES`).
> Use French keywords (`REGLE`, `CHERCHER`, `EFFET`, `PREMISSES`) only when the corpus is in French.

For each rule in the `Rule catalog` of each KB:

```yaml
RULE: <kebab-case-name>          # mandatory — becomes _ID (deduplication)
TERMINAL: solved                 # optional — 'solved' or 'failed'
                                 # when the rule fires AND TERMINAL is present →
                                 # the engine calls solved()/failed() automatically
PREMISES:                        # optional — prerequisite slots for reorder()
  - <slot-prerequisite>          # used by $agent->reorder(\&fn) to sort
  - <another-slot>               # rules by relevance dynamically
FIND:                            # mandatory — defines _SCOPE
  <var>:
    attribut: <targeting-slot>
    filtre: '<expression for strategy A>'
EXCEPTION: defined $<var>->{<slot_set>}    # idempotence — return if
CONDITION: '<optional-guard>'              # return unless
ACTION: |
  # ⚠️ Flow controls in ACTION: use $SELF (not $agent) → chorus-engine §1.3
  <Perl code>
  1
```

**When to use `TERMINAL` vs `$SELF->solved()` in ACTION:**
- `TERMINAL: solved` — the rule fires on ONE Frame and that alone is sufficient to terminate
- `$SELF->solved()` in ACTION — when the rule must check a condition before concluding.
  ⚠️ `$agent` is **not** available in a YAML ACTION (error `Global symbol "$agent"`) —
  use **exclusively `$SELF`** for flow control in ACTIONs.

> ⚠️ **Critical antipattern — YAML termination + global fmatch = infinite loop:**
> A YAML rule with a global `fmatch` in the ACTION (without an `EXCEPTION` covering the final slot)
> never converges: it fires on every Frame, returns 0 indefinitely, and
> `applyrules()` can never conclude. `_MAX_CYCLES` will be reached on every run.
>
> ```yaml
> # ⛔ ANTIPATTERN — guaranteed infinite loop
> RULE: termination
> FIND:
>   p:
>     attribut: needs_check
> ACTION: |
>   my @pending = grep { !defined $_->{status} }
>                 Chorus::Frame::fmatch(slot => 'needs_check');
>   if (@pending == 0) { $SELF->solved(); return 1 }
>   0
> ```
>
> **Solution**: global termination rule → **pure Perl `addrule()`** in the shell Agent,
> with `$agent` captured in a closure (see `chorus-check.md`, Phase 3, termination rule).
> Never code a termination via global `fmatch` in a YAML.

**When to document `PREMISES`:**
Always document if the agent is likely to use `reorder()` to
optimize rule order at runtime. PREMISES declare
the slots the rule needs — the sorting code consults them via `$rule->_PREMISSES`.

YAML Checklist:
- [ ] Slot names = Slot dictionary from the KB
- [ ] **`CHERCHER`/`FIND` has a named scope variable** — the scope key must be a variable name (`f:`, `e:`, `p:` …), not directly `attribut:`. Without it the engine treats `attribut` itself as the variable name → runtime crash.
      ```yaml
      # ⛔ WRONG — no scope variable; engine crashes at rule compilation
      CHERCHER:
        attribut: type_element
        filtre: "defined $_->{type_element}"
      # ✅ CORRECT
      CHERCHER:
        f:
          attribut: type_element
          filtre: "defined $_->{type_element}"
      ```
- [ ] **`filtre` uses `$_`, not `$f`** — see `chorus-engine-yaml.md` checklist.
- [ ] **`CONDITION` tests data presence, not conformance** — see `chorus-engine-yaml.md` checklist.
- [ ] Every rule that sets a slot has its idempotence `EXCEPTION: defined $var->{slot_set}`
- [ ] `ACTION` ends with `1` or a truthy expression
- [ ] ⛔ **`$f->{slot} = val` in ACTION** → silent pipeline break (`fmatch` returns 0 Frames downstream) — always use `$f->set('slot', val)` → `chorus-engine §5`
- [ ] ⛔ **CONDITION too restrictive on `type_element`** → silently excludes Frames of other types — prefer testing slot presence → `chorus-engine §5`
- [ ] ⛔ **Conditional ACTION without `else`** → returns `1` even when nothing modified → infinite loop at scale — always `return 1` inside the `if`, `0` as fallback → `chorus-engine §5`
- [ ] Use `|` (block scalar) for multi-line `ACTION` — never `>`
- [ ] Files named `R<NN>-<slug>.yml` (alphabetical = load order)
- [ ] ⛔ **Termination via global `fmatch` in YAML** → guaranteed infinite loop — use pure Perl `addrule()` instead (see `chorus-check.md` Phase 3)
- [ ] If `PREMISES` present: consistent with the KB `Slot dictionary`

### Phase 5.5 — Generate Perl Helpers

For each agent whose KB contains a non-empty `Perl Helpers` section,
create `$SANDBOX/lib/<Namespace>/Agent/<Slug>/Helpers.pm`.

**Criteria for including a helper here:**
The code encodes knowledge extracted from the corpus:
- normative value tables (e.g. resistances by class NF EN 338)
- regulatory calculations (e.g. EC5 §6.3 formula)
- threshold or range from a standard article

**What is NOT a knowledge helper** (→ stays in `chorus-check`):
- file parsing, database access, network calls
- orchestration logic (loops over agents, error handling)

#### Template `Helpers.pm`

```perl
package <Namespace>::Agent::<Slug>::Helpers;

use strict;
use warnings;
use Exporter 'import';

# Exhaustive list of exported helpers — chorus-check imports them all
our @EXPORT_OK = qw(
    <helper1>
    <helper2>
);

# -------------------------------------------------------
# <helper1>
# Source corpus : §<N> — <titre section>
# -------------------------------------------------------
# Signature : <helper1>(<args>) → <type retour>
# Called by: R<NN>-<slug>.yml (ACTION)
sub <helper1> {
    my (<args>) = @_;
    # <corps extrait du corpus>
}

# -------------------------------------------------------
# <helper2>
# Source corpus : §<N> — <titre section>
# -------------------------------------------------------
sub <helper2> {
    my (<args>) = @_;
    # <corps extrait du corpus>
}

1;
```

#### Generation rules

- **One `Helpers.pm` file per agent** — even if there is only one helper.
- **Exhaustive `@EXPORT_OK`** — all helpers listed, none missing.
  `chorus-check` does a full `use ... qw(...)` to make them available
  in the namespace before `loadRules()`.
- **`Source corpus` comment** on each helper — traceability to the standard.
- If a helper is **shared between multiple agents** → place it in
  `lib/<Namespace>/Helpers/Shared.pm` and document it in the KB of
  both agents involved.
- **No side effects** in a helper: no slot writes, no call to
  `$SELF`, no `fmatch`. Helpers compute and return a value —
  the YAML calls `$frame->set()`.
- **Out-of-scope types — defensive fallback:** when a helper is a table lookup
  (section minimums, resistances, thresholds…) and the `type_element` is outside
  the perimeter of the rule (e.g. `chevron` passed to a helper designed for
  `montant_porteur`), always return a neutral value that makes the downstream
  `is_xxx_suffisante` check pass rather than fail:
  ```perl
  sub section_min_requise {
    my (undef, $type, ...) = @_;
    # types outside ossature perimeter → no constraint
    unless ($type =~ /^(montant_porteur|montant_non_porteur|lisse_basse|lisse_haute)$/) {
      return (0, 0);   # (0, 0) → any section satisfies b >= 0 && h >= 0
    }
    ...
  }
  ```
  Returning the maximum sentinel (`(63, 220)`, `9999`…) as fallback causes false
  negatives on out-of-scope elements — they fail a check that was never meant
  for them, producing silently incorrect `NON` verdicts.
  Document out-of-scope handling with a `# types outside perimeter → neutral value` comment.
- **`$SELF` pitfall**: in an `_AFTER` hook or a closure that calls `set()`
  on another Frame, capture `$SELF` **before** any call to `set()`:
  ```perl
  # WRONG — $SELF will be overwritten by the internal set()
  _AFTER => sub { $other->set('x', $SELF->val) }
  # CORRECT
  _AFTER => sub { my $ctx = $SELF; $other->set('x', $ctx->val) }
  ```
  This pitfall concerns helpers called from an `_AFTER` or a procedural slot —
  not pure helpers (compute → return value).

#### Helpers Checklist

- [ ] Every helper referenced in a YAML ACTION has its implementation in `Helpers.pm`
- [ ] `@EXPORT_OK` covers all helpers in the file
- [ ] Every helper has its `Source corpus` comment
- [ ] No side effects (no `set`, no `fmatch`, no I/O)
- [ ] Shared helpers are in `Shared.pm` and documented in both KBs
- [ ] Any helper called from an `_AFTER` or procedural slot: capture `$SELF`
      before any `set()` on another Frame (`my $ctx = $SELF; ...`)

### Phase 6 — Closing

Update `README.org`:
- `Agent status` section: KB ✓, YAML ✓, Helpers ✓ (or `-` if none)
- `Identified pipeline` section: complete table

Invalidate the infrastructure hash so the next `chorus-check` triggers a
full regeneration:

```bash
rm -f $SANDBOX/eca/.kb-hash
```

---

## Mode B — Incremental Enrichment (`--enrich` required)

Used **only** when `--enrich` is present in the command.
`<sandbox-name>` must exist and contain a KB.

### Phase B0 — Read existing KB

1. Read `eca/agents/index.org` → current pipeline, known agents
2. Read each `eca/agents/<slug>.org` → Slot dictionary, Rule catalog
3. Read existing YAML files → already codified rules

### Phase B1 — Analyze the new corpus

Classify each rule/prescription from the new corpus into **3 categories**:

| Category | Criterion | Action |
|---|---|---|
| **Refinement** | Concerns a Frame and slots already known | Add rule to an existing agent |
| **Extension** | Concerns new slots of a known Frame | Extend existing agent KB + new YAML rules |
| **New domain** | Concerns Frames or concepts absent from the KB | Create a new agent |

### Phase B2 — Save the new corpus

Number incrementally: `corpus/002-<slug-source>.txt`, `003-...`
Update the `Integrated corpus` table in `index.org`.

### Phase B3 — Apply changes

**Refinement case:**
- Open `eca/agents/<slug>.org`
- Add the rule to `Rule catalog`
- Update `Slot dictionary` if new slots
- Generate the corresponding YAML file in `rules/<slug>/`
- If the rule requires a helper: add the helper to `Helpers.pm`
  and update `@EXPORT_OK`
- Verify idempotence and order of R<NN> files

**Extension case:**
- Update `Frame catalog` (new slots)
- Update `Slot dictionary`
- Add rules to `Rule catalog`
- Generate the new YAML files
- Add required helpers to `Helpers.pm`
- Verify that new slots do not conflict with those
  of other agents (Slot dictionary of the index)

**New domain case:**
- Apply Mode A (Phases 1 to 5.5) on the fragment only
- Determine the position of the new agent in the pipeline:
  - Does it read a slot set by an existing agent? → after it
  - Does it set a slot consumed by an existing agent? → before it
- Update `index.org`: insert the new agent at the correct position
- ⚠ Verify that the insertion does not break the chain of targeting slots

### Phase B4 — Enrichment closing

Update `README.org`:
- Add the row in `Corpus` (number + file + source + date)
- Update `Agent status` (KB, YAML, Helpers — new or enriched)
- Increment the enrichment counter of each modified agent

Invalidate the infrastructure hash so the next `chorus-check` triggers a
full regeneration:

```bash
rm -f $SANDBOX/eca/.kb-hash
```

---

## Quick Reference — Naming Conventions

| Artifact          | Convention                              | Example                           |
|-------------------|-----------------------------------------|-----------------------------------|
| Sandbox           | `test-<NNN>` or `test-<slug>`           | `test-01`, `test-norme-ec5`       |
| Agent slug        | kebab-case                              | `conformite-fiscale`              |
| KB file           | `<slug>.org`                            | `conformite-fiscale.org`          |
| YAML directory    | `rules/<slug>/`                         | `rules/conformite-fiscale/`       |
| YAML files        | `R<NN>-<slug-rule>.yml`                 | `R01-verif-montant.yml`           |
| Agent helpers     | `lib/<Namespace>/Agent/<Slug>/Helpers.pm` | `lib/CB/Agent/Ossature/Helpers.pm` |
| Shared helpers    | `lib/<Namespace>/Helpers/Shared.pm`     | `lib/CB/Helpers/Shared.pm`        |
| Initial corpus    | `corpus/001-<slug-source>.txt`          | `corpus/001-dtu-31-2.txt`         |
| Enrichment corpus | `corpus/<NNN>-<slug>.txt`               | `corpus/002-ec5-sect3.txt`        |
| Project namespace | CamelCase, defined at startup           | `MonProjet`                       |

> ⚠ `chorus-feed` never generates: `Feed.pm`, shell Agent module (`build()`),
> `Expert.pm`, `run.pl`. These artifacts are the exclusive responsibility of `chorus-check`.
