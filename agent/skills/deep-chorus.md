# Skill — deep-chorus

> **Trigger:** `deep-chorus [<focus>]`
> **Agent:** `architect`
> **Purpose:** Deep implementation analysis of the Chorus::* classes.
> Reads the actual source (not just POD), maps internal data structures,
> documents undocumented mechanisms, and identifies extension points.
> Produces a structured report in `$SESSIONS`.
>
> Optional `<focus>` narrows the analysis:
> - `backward-chaining` — focus on rule dependency graph and goal-driven inference
> - `explain` — focus on rule-firing trace and diagnostic internals
> - `planner` — focus on remediation / `Chorus::Planner` architecture
> - *(omit for full analysis)*

---

## Existing reference reports (load before reading sources)

| Report | Content |
|---|---|
| `$SESSIONS/2026-06-22-16-54-deep-analysis-chorus-1.03.md` | Full deep analysis of v1.03 — Frame internals, `%REPOSITORY`, `$SELF`, `applyrules()` |
| `$SESSIONS/2026-06-29-11-12-backward-chaining-analysis.md` | Backward-chaining gap analysis — `_PREMISSES`, `%RULE_PRODUCES`, `_MUTABLE`, `_EXPLAIN`, `Chorus::Planner` |
| `$SESSIONS/2026-06-30-18-16-chorus2-full-reference-classes-skills.md` | Full v2 reference — all classes, skills, YAML DSL |

**Rule:** read all relevant reports before reading source files — avoid re-discovering
what is already documented.

---

## Phase 1 — Source inventory

Read in order:

```
lib/Chorus/Engine.pm          # inference engine — applyrules(), addrule(), loadRules(), $ENGINE prototype
lib/Chorus/Expert.pm          # orchestrator — process(), register(), BOARD, _LOCK_UNTIL_STABLE
lib/Chorus/Engine/AIAgent.pod # AI pipeline architecture — chorus-feed / chorus-check workflow
```

For Collection (only if focus requires it):
```
lib/Chorus/Collection/List.pm
lib/Chorus/Collection/Filter.pm
```

> `Chorus::Frame` is in a separate CPAN distribution (`Chorus-Frame`).
> Its source is at `$CMS5` equivalent — use `chorus-engine.md` §Chorus::Frame
> and the deep analysis reports rather than reading it directly.

---

## Phase 2 — Internal data structures to map

### Chorus::Engine — key internals

| Structure | Location | Role |
|---|---|---|
| `$ENGINE` | `Engine.pm` — package-level Frame | Prototype — all engine methods are closures on this Frame |
| `$SELF` | `Chorus::Frame` global | Points to the currently-executing Frame (engine or rule) |
| `$_[0]->{_RULES}` | arrayref on each engine instance | Ordered list of rule Frames |
| `$_[0]->{_QUEUE}` | arrayref, rebuilt each `applyrules()` call | Working copy of `_RULES` consumed by `$apply_rec` |
| `$_[0]->{_CYCLE}` | int | Current cycle count (incremented in `loop()`) |
| `$_[0]->{_SUCCES}` | bool | True if at least one rule fired in the current `loop()` |
| `$_[0]->{_SLEEPING}` | flag | Set by `pause()`, cleared by `wakeup()` — skips `applyrules()` entirely |
| `$_[0]->{_CUT}` | flag | Set by `cut()` — exits inner scope-combination loops, cleared after each rule |
| `$_[0]->{_LAST}` | flag | Set by `last()` — exits rule queue, resets `_QUEUE` |
| `$_[0]->{_REPLAY}` | flag | Set by `replay()` — resets `_QUEUE`, re-runs current agent |
| `$_[0]->{_REPLAY_ALL}` | flag | Set by `replay_all()` — propagates to `Expert::process()` outer loop |

### Rule Frame structure (created by `addrule()`)

```perl
Chorus::Frame->new(
  _ID        => 'rule-name',          # optional — used for deduplication
  _SCOPE     => { var => sub {...} },  # combinators — re-evaluated each cycle
  _APPLY     => sub { ... },          # action — receives one scope combination
  _TERMINAL  => 'solved'|'failed',    # optional — auto-terminates engine on fire
  _PREMISSES => { slot => 'Y', ... }, # optional — metadata, NOT used by applyrules()
  _TRACE     => 1,                    # optional — logs each firing to STDERR
)
```

### `applyrules()` algorithm

```
_QUEUE ← copy of _RULES
$apply_rec = recursive sub:
  rule ← shift _QUEUE
  scope ← evaluate all _SCOPE closures → { var => [frame, ...], ... }
  generate cartesian product via nested foreach (eval'd string: JUMP: { foreach ... })
  for each combination:
    call _APPLY->(%opts)
    if fired and _TERMINAL → solved() or failed()
    break JUMP if _LAST | _CUT | _REPLAY | _REPLAY_ALL | BOARD.SOLVED | BOARD.FAILED
  clear _CUT flag
  reset _QUEUE if _LAST | _REPLAY | _REPLAY_ALL | BOARD.SOLVED | BOARD.FAILED
  clear _LAST flag
  return if _REPLAY | _REPLAY_ALL
  recurse on next rule in _QUEUE
```

**Critical detail:** `_APPLY` is called via a plain coderef
`$rule->{_APPLY}->(%opts)` — NOT via Frame dispatch (`$rule->_APPLY`).
This keeps `$SELF` pointing to the engine throughout ACTION execution,
so `$SELF->solved()`, `$SELF->cut()`, etc. work correctly inside YAML rules.

### Chorus::Expert — key internals

| Structure | Location | Role |
|---|---|---|
| `$this->{_agents}` | arrayref | Ordered agent list — iterated by `process()` |
| `$this->{_board}` | `Chorus::Frame` | Shared BOARD — injected into each agent at `register()` |
| `$this->{_MAX_ITER}` | int (default 10 000) | Outer loop guard — iterations, not cycles |
| `BOARD->{SOLVED}` | flag | Set by any agent's `solved()` — terminates `process()` with `1` |
| `BOARD->{FAILED}` | flag | Set by any agent's `failed()` — terminates `process()` with `undef` |
| `BOARD->{INPUT}` | any | Set by `process($input)` — raw pipeline input |
| `agent->{_LOCK_UNTIL_STABLE}` | flag | If set, this agent only runs when no previous agent succeeded |

**`process()` outer loop:**
```
do {
  foreach agent in _agents:
    if _LOCK_UNTIL_STABLE and any previous agent succeeded → last
    do { agent->loop() } while agent->_REPLAY
    if agent->_REPLAY_ALL → delete flag, break agent loop (restart from agent 0)
} until BOARD.SOLVED or BOARD.FAILED
```

---

## Phase 3 — Extension points (focus-specific)

### Focus: `backward-chaining`

The June 2026 analysis (`2026-06-29-11-12-backward-chaining-analysis.md`) is
authoritative. Summarise:

**What exists:**
- `_PREMISSES` on rule Frames — declared in YAML, compiled into `_PREMISSES => {...}`,
  **not consumed by `applyrules()`** — available as extension point
- `_NEEDED` on Frames — lazy slot evaluation, local to one Frame, not engine-level
- `%REPOSITORY` in `Chorus::Frame` — O(1) index Frames→slots (forward direction)
- Copy-on-Write via `Chorus::Frame::cow()` — available for simulation

**What is missing (implementation roadmap):**

| Component | Effort | Dependency |
|---|---|---|
| `PRODUCES:` key in YAML DSL + `_PRODUCES` on rule Frames | Low | — |
| `%RULE_PRODUCES` hash built at `loadRules()` | Low | `PRODUCES:` |
| `_MUTABLE` flag on Frame slots | Low | JSON project + Feed |
| `_EXPLAIN` mode in `applyrules()` — captures failed candidates | Medium | — |
| `Chorus::Planner` — goal-driven resolution via `%RULE_PRODUCES` | High | all above |

**Simulation alternative** (faster path):
Clone a non-compliant Frame via CoW, mutate mutable slots, re-run `$expert->process()`.
No `Chorus::Planner` needed — requires only `_MUTABLE` flag.
Viable because the pipeline is idempotent and stateless between runs.

### Focus: `explain`

Identify where in `applyrules()` to inject a trace for rules that were
evaluated but did not fire (condition blocked, exception triggered, scope empty).
Key insertion point: inside `$apply_rec`, after `$_af->(%opt)` returns false.

### Focus: `planner`

Architecture: new class `Chorus::Planner` in `lib/Chorus/Planner.pm`.
Inputs: non-compliant Frame + goal (`{ slot => ..., value => ... }`).
Uses `%RULE_PRODUCES` to walk the dependency graph backward.
Returns ordered list of `{ action => ..., slot => ..., from => ..., to => ... }`.

---

## Phase 4 — Output

Produce a report `$SESSIONS/YYYY-MM-DD-HH-MM-deep-chorus-<focus>.md` with:

```markdown
# Deep analysis — Chorus::* [<focus>]

## Summary
<3-5 bullet points: key findings, surprises, confirmed assumptions>

## Internal data structures
<table or annotated source excerpts>

## Extension points identified
<concrete list with file:line references>

## Implementation roadmap
<ordered steps with effort estimates>

## Open questions
<anything requiring user decision before implementation>
```

Do not commit the report — it goes to `$SESSIONS` (not versioned).
