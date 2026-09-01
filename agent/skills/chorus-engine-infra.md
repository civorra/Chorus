# Chorus::Engine — Perl Infrastructure Reference

> **Authoritative source for Perl infrastructure generation.**
> This file owns its sections — do not duplicate them in `chorus-engine.md`.
>
> Loaded by: `chorus-check` (full path only — infrastructure absent)
> For direct Perl work in `$ENGINE`: load this file + `chorus-engine-yaml.md`
> Scope: everything needed to generate Feed.pm, Agent/<Nom>.pm, Expert.pm, run.pl.
> Not covered here: YAML authoring → `chorus-engine-yaml.md`
> Not covered here: Collection::List / Collection::Filter → `chorus-engine.md`

---

## 1. Core Mechanisms

### 1.1 The Expert → Agent → Frame Chain

```
Chorus::Expert          loop orchestration + termination
  └─ Chorus::Engine     agent = Frame inheriting from $ENGINE
       └─ _RULES        list of rule-Frames
            └─ _SCOPE   addresses domain Chorus::Frames
                 └─ Chorus::Frame   knowledge + hooks
```

| Level | Responsibility |
|---|---|
| Expert | when to iterate agents, detect termination |
| Agent | which rules, in what order, flow control |
| Frame | domain knowledge, inheritance, procedural hooks |

---

### 1.2 Chorus::Frame — Essential Slots

| Slot | Role |
|---|---|
| `_ISA` | inheritance (scalar or arrayref of Frames) |
| `_VALUE` | Frame's primary value |
| `_DEFAULT` | fallback if `_VALUE` is absent |
| `_NEEDED` | last-resort coderef (backward chaining) |
| `_BEFORE` | hook before a slot is modified |
| `_AFTER` | hook after a slot is modified (forward propagation) |
| `_REQUIRE` | validation: returning `REQUIRE_FAILED` blocks `_setValue` |
| `_NOFRAME` | prevents automatic promotion of a hash to a Frame |

**Reserved system slots** — never use as domain slot names:
`_KEY` `_PARENT_KEY` `_ISA` `_VALUE` `_DEFAULT` `_NEEDED` `_BEFORE` `_AFTER` `_REQUIRE` `_NOFRAME` `_SERIALIZE`

**`get()` inheritance modes:**
- **Mode N** (default): for each valuation key, traverse the entire inheritance tree before moving to the next.
- **Mode Z**: test the full sequence `(_VALUE, _DEFAULT, _NEEDED)` on each Frame before descending into parents.

```perl
Chorus::Frame::setMode(GET => 'Z');
Chorus::Frame::setMode(GET => 'N');
```

**`$SELF`** = current context in any `sub { }` slot.

**`fmatch()`** — slot-based Frame selection via `%REPOSITORY`:

```perl
my @c = fmatch(slot => 'couleur');
my @r = fmatch(slot => ['couleur', 'score']);
my @r = fmatch(slot => 'couleur', from => \@subset);
```

> ⛔ `$f->{slot} = val` bypasses `%REPOSITORY` → `fmatch` returns 0 Frames → **silent** pipeline break.
> Always use `$f->set('slot', $val)`.

---

### 1.3 Chorus::Engine — Rule Triggering

```perl
my $agent = Chorus::Engine->new(_IDENT => 'MonAgent');

$agent->addrule(
    _ID    => 'nom-unique',
    _SCOPE => {
        var => sub { [ fmatch(slot => 'slot_cible') ] },
    },
    _APPLY => sub {
        my %opts = @_;
        return unless <condition>;
        # ... effets ...
        return 1;
    },
);
```

**Inference loop:** `loop()` → `applyrules()` as long as at least one rule returns true.
Safety: `_MAX_CYCLES` (default 10,000) → warning + stop if exceeded.

**Flow controls:**

| Method | Scope | Effect |
|---|---|---|
| `$agent->cut()` | current rule | exits scope loops → next rule |
| `$agent->last()` | current agent | exits rules loop → next agent |
| `$agent->replay()` | current agent | restarts from 1st rule |
| `$agent->replay_all()` | all agents | restarts from 1st agent |
| `$agent->solved()` | global | `BOARD->{SOLVED} = 'Y'` → stop |
| `$agent->failed()` | global | `BOARD->{FAILED} = 'Y'` → stop |
| `$agent->pause()` | agent | disabled until `wakeup()` |
| `$agent->reorder(\&fn)` | agent | re-sorts `_RULES` + `replay()` |

> ⚠️ In pure Perl `addrule()`: use `$agent` (captured as closure).
> In YAML EFFET: use `$SELF` — `$agent` is out of scope → crash.

---

### 1.4 Chorus::Expert — Orchestration

```perl
my $xprt = Chorus::Expert->new();
$xprt->register($agent1, $agent2, $agent3);
my $ok = $xprt->process($input);  # 1=solved, undef=failed
```

- `register()` injects the **shared BOARD** into each agent (`$agent->BOARD`).
- `process()`: `do { for each agent: agent->loop() } until BOARD->{SOLVED|FAILED}`
- `$input` accessible via `$agent->BOARD->INPUT`.
- Inter-agent communication: write/read slots on `$agent->BOARD`.
- `_LOCK_UNTIL_STABLE`: agent skipped if a previous agent already succeeded in the current iteration.

#### Two-level inference loop

The engine operates on **two nested loops** that must not be confused:

```
┌─── Chorus::Expert::process() — OUTER loop ──────────────────────────────┐
│                                                                          │
│  do {                                                                    │
│    for each agent in register() order:                                   │
│    │                                                                     │
│    │  ┌─── Chorus::Engine::loop() — INNER loop ────────────────────┐    │
│    │  │  applyrules() until all rules return 0 (local convergence)  │    │
│    │  │  = one agent iterates over its own rules until stable       │    │
│    │  └────────────────────────────────────────────────────────────┘    │
│    │                                                                     │
│    └─ then: next agent                                                   │
│                                                                          │
│  } until BOARD->{SOLVED} or BOARD->{FAILED}                             │
└──────────────────────────────────────────────────────────────────────────┘
```

**What this means in practice:**

- **Inner loop** (`Chorus::Engine`): one agent iterates over its own YAML rules, cycle after
  cycle, until no rule produces an effect in a full pass. This is the level described in
  `chorus-engine-yaml.md § Rule Evaluation Lifecycle`. The term "cycle" always refers to this
  inner loop.

- **Outer loop** (`Chorus::Expert`): once Agent A has converged locally (inner loop finished),
  control passes to Agent B — which runs its own inner loop. After all agents have run, the
  Expert checks `BOARD->{SOLVED|FAILED}`. If neither flag is set, it launches **another outer
  iteration**, starting again from Agent A.

**Inter-agent slot dependencies** work through the outer loop, not the inner cycle:

| Dependency type | Mechanism | Loop level |
|---|---|---|
| Rule Rxx depends on slot written by Rule Ryy **in the same agent** | `CONDITION: defined $p->{slot_from_Ryy}` | Inner loop — resolved within one agent's inference |
| Rule Rxx depends on slot written by **another agent** via BOARD | Read `$agent->BOARD->{key}` in ACTION | Outer loop — available only after the other agent's inner loop has completed |

> ⚠️ **CONDITION cannot wait for another agent's output.**
> `CONDITION: defined $p->{slot_from_agent_B}` will never be satisfied within Agent A's inner
> loop if the slot is written by Agent B — because Agent B has not yet run in this outer
> iteration. Cross-agent data must transit via **BOARD** slots, read in ACTION (not CONDITION).

**Why `N_agents` appears in the `_MAX_CYCLES` formula:**

`_MAX_CYCLES = N_frames × N_rules_total × N_agents × D × 10`

Each outer iteration runs all agents. If the Expert needs K outer iterations to converge
(e.g. because Agent B's output unlocks new rules in Agent A on the next round), the total
number of inner cycles is multiplied by N_agents × K. The `N_agents` factor approximates
this overhead assuming K ≈ 1 (single outer pass). If the pipeline requires multiple outer
rounds, increase the margin accordingly.

> ⚠️ **Known bug: `Chorus::Expert->new()` ignores its arguments.**
> Always force `_MAX_ITER` via direct assignment after `new()`:
> ```perl
> # ⛔ WRONG — _MAX_ITER ignored
> my $xprt = Chorus::Expert->new(_MAX_ITER => 50_000);
>
> # ✅ CORRECT
> my $xprt = Chorus::Expert->new();
> $xprt->{_MAX_ITER} = 50_000;
> ```
> Sizing heuristic: `N_frames × N_rules_total × D × safety_margin`
> where **D** = depth of the longest cross-rule dependency chain within one agent
> (count CONDITION guards that test a slot written by another rule — each such level = +1 cycle per Frame).
> D = 1 if all rules are independent.
> For a production pipeline (100 frames, 40 rules, D = 1): `_MAX_ITER ≥ 100_000`.
> For a pipeline with a 3-rule chain (D = 3): `_MAX_ITER ≥ 300_000`.

---

### 1.5 BOARD — Shared Publication Space

The BOARD is a single `Chorus::Frame` instance injected by `register()` into every agent.
It is the **only shared mutable state** between agents — `%REPOSITORY` (Frames) is also
shared, but agents coordinate global pipeline state exclusively through BOARD slots.

#### What belongs on the BOARD

| Put on BOARD | Keep in Frames |
|---|---|
| Global pipeline flags (`SOLVED`, `FAILED`) | Per-element classification results |
| Phase markers (`current_phase`, `pass_number`) | Inference slots computed by rules |
| Aggregate results (counts, global scores, totals) | Individual element slots (`besoin_*`, `resultat_*`) |
| Agent-to-agent signals (`agent_a_done`, `threshold_override`) | Prototype defaults (`_DEFAULT`, `_ISA`) |
| The original input (`INPUT`) | Frame relationships (`_AFTER`, `_CONTAINER`) |

> **Rule of thumb:** if the value is the same for all elements in the pipeline run → BOARD.
> If it is specific to one Frame → Frame slot.

#### Writing to the BOARD (Perl — in Agent.pm or addrule())

```perl
# In a rule closure (addrule) or Agent method:
$agent->BOARD->{phase}        = 'scoring';      # set a phase marker
$agent->BOARD->{total_ko}     = $count;         # publish an aggregate
$agent->BOARD->{agent_a_done} = 1;              # signal completion to next agent
```

#### Reading from the BOARD (Perl)

```perl
my $phase = $agent->BOARD->{phase};             # read in same or other agent
my $input = $agent->BOARD->{INPUT};             # original input passed to process()
```

#### Writing/Reading from BOARD in YAML ACTION / EFFET

```yaml
ACTION: |
  # Write to BOARD from a YAML rule:
  $SELF->BOARD->{total_ko} = ($SELF->BOARD->{total_ko} // 0) + 1;
  1

ACTION: |
  # Read a value published by a previous agent:
  my $threshold = $SELF->BOARD->{threshold_override} // 100;
  $p->set('adjusted_threshold', $threshold);
  1
```

> ⚠️ In YAML ACTION / EFFET, use **`$SELF`** (the agent) — never `$agent` (out of scope).
> `$SELF->BOARD` is identical to `$agent->BOARD` — same Frame instance.

#### Full inter-agent pattern: Agent A publishes → Agent B consumes

```
Outer iteration 1:
  Agent A (inner loop):
    R01 computes per-element scores → writes Frame slots
    R02 accumulates total → $SELF->BOARD->{global_score} = $total; return 1
    R03 signals done      → $SELF->BOARD->{scoring_done} = 1;      return 1
    (all rules return 0 → Agent A converged)

  Agent B (inner loop):
    R01 reads BOARD: my $score = $SELF->BOARD->{global_score} // 0;
        CONDITION: '$SELF->BOARD->{scoring_done}'   # ⛔ WRONG — see note below
        → correct approach: read directly in ACTION, no CONDITION guard on BOARD
    (all rules return 0 → Agent B converged)

  Expert checks BOARD → not SOLVED yet → launches outer iteration 2
  ...
```

> ⚠️ **Do not use CONDITION to wait for a BOARD slot written by another agent.**
> `CONDITION` is evaluated inside Agent B's inner loop — at that point, Agent A has
> already completed its inner loop (BOARD slot is set). So the CONDITION would actually
> be satisfied immediately. However, if Agent B runs *before* Agent A in `register()`
> order, the BOARD slot is not yet set when Agent B's inner loop starts in the first
> outer iteration. The rule will fire immediately with `undef` (or be skipped), producing
> a wrong result — not a deferred wait.
>
> **Correct pattern:** read the BOARD slot directly in ACTION with a `// default` fallback,
> and use `register()` order to guarantee Agent A runs before Agent B.

```perl
# Expert.pm — register() order = execution order within each outer iteration
$xprt->register($agent_scoring,   # 1st: computes and publishes to BOARD
                $agent_decision);  # 2nd: reads BOARD slots already set by agent_scoring
```

#### BOARD slot lifecycle

| Event | Effect on BOARD |
|---|---|
| `$xprt->register(...)` | BOARD Frame created and injected into all agents |
| `$xprt->process($input)` called | `BOARD->{INPUT} = $input` set |
| Any agent calls `solved()` | `BOARD->{SOLVED} = 'Y'` → Expert stops after current agent |
| Any agent calls `failed()` | `BOARD->{FAILED} = 'Y'` → Expert stops after current agent |
| `process()` returns | `BOARD->{SOLVED}` and `BOARD->{FAILED}` **deleted** (BOARD is reusable) |
| Custom slots (`phase`, `total_ko` …) | **Not deleted** by `process()` — persist across calls if the same Expert instance is reused |

> ⚠️ Custom BOARD slots survive `process()`. If the same `Chorus::Expert` instance
> processes multiple inputs sequentially (batch), reset custom slots explicitly before
> each call:
> ```perl
> delete $xprt->BOARD->{total_ko};
> delete $xprt->BOARD->{scoring_done};
> my $ok = $xprt->process($next_input);
> ```

#### Checklist — BOARD design

- [ ] BOARD slots used only for global / inter-agent state — per-element data stays in Frames
- [ ] `register()` order guarantees producer agents run before consumer agents
- [ ] Custom BOARD slots documented in `index.org` (key, type, written by, read by)
- [ ] Custom slots reset explicitly between `process()` calls if the Expert is reused
- [ ] YAML ACTION uses `$SELF->BOARD` — never `$agent->BOARD`
- [ ] No `CONDITION` guard on a BOARD slot written by another agent — use `register()` order + ACTION fallback

---

## 2. Multi-Specialty Pattern

### 2.1 Recommended Project Structure

```
MyExpert/
  lib/
    MyExpert/
      Agent/
        Specialite1.pm
        Specialite2.pm
      Expert.pm
  rules/
    specialite1/
      R01-xxx.yml
    specialite2/
      R01-zzz.yml
  t/
    01-pipeline.t
```

### 2.2 Agent Module with Perl Helpers

```perl
package MyExpert::Agent::Specialite1;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;
use Exporter 'import';

our @EXPORT_OK = qw($agent helper1 helper2);

sub helper1 { my ($frame) = @_; return $result; }
sub helper2 { ... }

our $agent;

sub build {
    my ($class, %opts) = @_;
    $agent = Chorus::Engine->new(_IDENT => 'Specialite1');
    $agent->loadRules($opts{rules_dir} // "rules/specialite1");
    return $agent;
}

1;
```

### 2.3 Expert Assembly

```perl
package MyExpert::Expert;

use strict;
use Chorus::Expert;
use MyExpert::Agent::Specialite1;
use MyExpert::Agent::Specialite2;

sub run {
    my ($class, $input) = @_;

    my $a1 = MyExpert::Agent::Specialite1->build();
    my $a2 = MyExpert::Agent::Specialite2->build();

    my $a_ctrl = Chorus::Engine->new(_IDENT => 'Ctrl');
    $a_ctrl->addrule(
        _SCOPE => { p => sub { [ fmatch(slot => 'slot_cle') ] } },
        _APPLY => sub {
            my @all = fmatch(slot => 'slot_cle');
            return unless @all && (grep { defined $_->{statut} } @all) == scalar(@all);
            $a_ctrl->solved();
            return 1;
        },
    );

    my $xprt = Chorus::Expert->new();
    $xprt->register($a1, $a2, $a_ctrl);
    return $xprt->process($input);
}

1;
```

### 2.4 Implicit Slot Pipeline

| Agent | `CHERCHER.attribut` | Sets the slot |
|---|---|---|
| Specialty 1 | `slot_brut` | `slot_enrichi` |
| Specialty 2 | `slot_enrichi` | `slot_calcule` |
| Ctrl | `slot_cle` (+ check `statut`) | calls `solved()` |

> **Golden rule:** each agent looks for a slot that only the previous agent can have set.

---

## 3. Inter-Frame Relationships

> **Authoritative reference.** This section is the canonical source for inter-frame
> relationship patterns in Chorus sandboxes.  Findings are derived from a complete
> reading of `Chorus::Frame` v2.0.2 source and validated in `test-11`.

Two complementary patterns exist.  Choose based on the nature of the relationship.

---

### 3.1 Pattern A — Structural links (slot → Frame)

**When to use:** a domain element *belongs to* or *is connected to* another domain element
(e.g. `buttressing_wall → external_wall`, `wall → building`).

#### JSON convention

Use a `*_ref` field containing the `id` of the target element:

```json
{ "id": "BW-01", "type_element": "buttressing_wall",
  "supports_ref": "EW-01", "buttressing_length_m": 1.0 }
```

Naming rule: `<relationship>_ref` → resolves to slot `<relationship>` on the Frame.

#### Feed.pm — 2-pass + `%REF_FIELDS`

> `%REF_FIELDS` and both passes go **inside `load_projet()`**, not at module level.
> If your sandbox also uses Pattern B (`_ISA` prototypes), see §3.5 for the complete
> skeleton combining both patterns.

```perl
sub load_projet {
    my ($fichier) = @_;
    # ... JSON loading and SLOTS_REQUIS validation (standard boilerplate) ...

    # Declare all reference fields — one line per link.  Add here to extend.
    my %REF_FIELDS = (
        supports_ref => 'supports',   # e.g. buttressing_wall → external_wall
        building_ref => 'building',   # e.g. wall → building
    );

    # Pass 1 — create frames WITHOUT *_ref fields (targets must exist first)
    my (%frames_by_id, @frames, @deferred);
    for my $elem (@elements) {
        my $type    = $elem->{type_element} or next;
        my $has_ref = grep { defined $elem->{$_} } keys %REF_FIELDS;
        if ($has_ref) { push @deferred, $elem; next; }

        my $frame = Chorus::Frame->new(%$elem);
        # Pre-populate targeting slot(s) — adapt to your sandbox
        # e.g. $frame->set('besoin_validation', 'Y') if $TYPED_FRAMES{$type};
        $frame->set('besoin_X', 'Y') if $TYPED_FRAMES{$type};
        $frames_by_id{ $elem->{id} } = $frame;
        push @frames, $frame;
    }

    # Pass 2 — create frames WITH *_ref fields (reference resolved at new() time)
    for my $elem (@deferred) {
        my $type  = $elem->{type_element};
        my %slots = %$elem;

        for my $ref_field (keys %REF_FIELDS) {
            my $slot_name = $REF_FIELDS{$ref_field};
            my $ref_id    = delete $slots{$ref_field} // next;
            $slots{$slot_name} = $frames_by_id{$ref_id}
                or die "Element '$elem->{id}': $ref_field '$ref_id' not found\n";
        }

        my $frame = Chorus::Frame->new(%slots);
        # Pre-populate targeting slot(s) — same as pass 1
        $frame->set('besoin_X', 'Y') if $TYPED_FRAMES{$type};
        $frames_by_id{ $elem->{id} } = $frame;
        push @frames, $frame;
    }

    return @frames;
}
```

> **⚠️ Why pass the reference at `new()` time, not via `set()` after:**
> `set()` calls `_setSlot()` which sets `_PARENT_KEY` on the target frame — a CoW
> side effect.  Passing at `new()` goes through `_blessToFrameRec` which skips
> already-blessed Frames.  Both work for read-only navigation, but `new()` is cleaner.

#### YAML rules — navigation with backward-compatible fallback

Two valid patterns depending on whether the link is mandatory or optional:

```perl
# ACTION / EFFET body

# ── Option A: link is OPTIONAL — fall back to direct slot (backward-compatible)
my $sup = $w->get('supports');
my $h   = $sup ? ($sup->get('height_m') // 0) : ($w->get('height_m') // 0);

# ── Option B: link is MANDATORY — hard skip if absent
my $sup = $w->get('supports')
    or do { warn "R05: no 'supports' link on $w->{id} — skipped\n"; return 0 };
my $h = $sup->get('height_m') // 0;
```

> **Use Option A** when the same rule must handle both old project files (flat slots)
> and new project files (inter-frame links).  Use Option B only when the link is
> architecturally guaranteed and its absence is a data error.

> **Never write to a linked Frame from a rule** — `$w->get('supports')->set(...)` creates
> invisible side effects on frames processed by other rules.  Read-only navigation only.

#### What `get()` returns on a Frame-valued slot

`$w->get('supports')` returns the Frame object directly when the target frame has no
`_VALUE`/`_DEFAULT`/`_NEEDED` — which is always the case for domain frames.
`$SELF` is managed correctly by `get()`'s push/pop stack.

#### `fmatch` behaviour

`$bw->set('supports', $ew)` registers `$bw` under `'supports'` in `%REPOSITORY`.
`fmatch(slot => 'supports')` → finds buttressing_wall frames.  ✅
The target frame (`$ew`) is NOT double-registered.

---

### 3.2 Pattern B — Type prototypes (`_ISA` + `fselect`)

**When to use:** a set of domain frames shares normative thresholds or default values
that come from a static catalog (e.g. masonry strength tables, section minimum tables).

> ⛔ **Never use `_ISA` for structural relationships** (Pattern A use cases).
> `_ISA` propagates ALL parent slots into `fmatch` results.  If the parent has
> `height_m`, then `fmatch(slot => 'height_m')` returns BOTH parent AND all children —
> silently injecting unwanted frames into every rule scope that targets `height_m`.
> Use Pattern A (slot→Frame) for structural links.

#### Why `_ISA` is safe for static catalogs

Prototype frames are safe when they do **not** carry the targeting slot used by YAML rules
(`besoin_X`, `needs_Y`).  Rules use `FIND: attribut: besoin_X` → `fmatch` only
finds frames that have `besoin_X` registered.  Prototypes don't → they never
appear in any rule scope.  ✅

> **Example** (ADA sandbox): rules use `FIND: attribut: besoin_masonry` — masonry spec
> prototypes carry no `besoin_masonry` slot → invisible to every masonry rule.

#### Feed.pm — `_build_*_catalog()` + `$inject_isa` closure

> **`@catalog` must be created ONCE, before both passes.**
> Creating it inside a loop would re-register duplicate frames in `%REPOSITORY`.
> The `$inject_isa` closure captures the catalog by reference.

```perl
# ── Outside or at top of load_projet() — catalog created once ────────────────

# 1. Build the prototype catalog (module-level sub or inline)
# Name the discriminator slots after YOUR domain (e.g. wood_class + treatment,
# reaction_class + group, etc. — replace masonry_* with your actual keys).
sub _build_spec_catalog {
    return (
        Chorus::Frame->new(
            spec_key_1 => 'value_A', spec_key_2 => 'value_B', spec_key_3 => 1,
            threshold_cond_A => 6.0, threshold_cond_B => 9.0, threshold_cond_C => 18.0,
        ),
        # ... one frame per combination
    );
}

# 2. Inside load_projet(), BEFORE pass 1:
my @catalog = _build_spec_catalog();   # created once, captured by $inject_isa

# 3. $inject_isa closure — called in BOTH pass 1 and pass 2
my $inject_isa = sub {
    my ($slots) = @_;
    # Replace 'spec_key_1' etc. with the actual discriminator slots for your domain
    return unless defined $slots->{spec_key_1};
    my $spec = fselect(
        spec_key_1 => $slots->{spec_key_1},
        spec_key_2 => $slots->{spec_key_2} // '',
        spec_key_3 => $slots->{spec_key_3} // 1,
        _from      => \@catalog,   # mandatory — restrict to catalog only
    );
    return unless defined $spec;
    $slots->{_ISA} = defined($slots->{_ISA})
        ? [ ref($slots->{_ISA}) eq 'ARRAY' ? @{$slots->{_ISA}} : $slots->{_ISA}, $spec ]
        : $spec;
};
# Then in pass 1: $inject_isa->(\%slots);
# And in pass 2: $inject_isa->(\%slots);   — see §3.5 for the full skeleton
```

> `_from => \@catalog` is mandatory — without it, `fselect` searches ALL registered
> frames and returns unexpected matches from the domain itself.

#### YAML rules — reading inherited thresholds

```perl
# ACTION body — no guard needed (get() returns undef if slot absent in inheritance chain)
my $min_str = $w->get("min_str_$cond");   # traverses _ISA → prototype

if (!defined $min_str) {
    $w->set('strength_ok', 'YES');   # no numeric minimum for this spec
    return 1;
}
```

Dynamic slot names (`"min_str_$cond"`) work with `get()` — it takes a plain string.
`$w->min_str_A` (AUTOLOAD) also works but only for static names.

---

### 3.3 Decision table

| Situation | Pattern | Mechanism |
|---|---|---|
| Element A belongs to / is connected to element B | **A** | `*_ref` → slot→Frame |
| Multiple elements share the same normative table | **B** | `_ISA` + `fselect` |
| Default values shared across a type | **B** | `_ISA` + `_DEFAULT` |
| Structural relationship that needs reverse lookup | **A** | slot→Frame; reverse via `fmatch(slot=>'link')` + grep |
| Structural relationship with `_ISA` | ⛔ **never** | Pollutes all `fmatch` scopes |

### 3.4 Checklist — Inter-Frame

- [ ] `*_ref` fields **OPTIONAL** in `%SLOTS_REQUIS` — never add them as required slots; rules fall back to direct slots when link is absent (backward-compatibility)
- [ ] `*_ref` fields stripped from slots hash before `Chorus::Frame->new()` (`delete $slots{ref_field}`)
- [ ] Target frame created in **pass 1** (no `*_ref` itself) — referencing frame in **pass 2**
- [ ] `_ISA` injection (`$inject_isa`) called in **both** pass 1 and pass 2 — elements without `*_ref` still need their prototypes
- [ ] `%frames_by_id` maintained throughout — die with informative message if target not found
- [ ] Guards in YAML `ACTION`: Option A (fallback) for optional links, Option B (hard skip) for mandatory — see §3.1 YAML rules
- [ ] Rules **never write** to linked frames
- [ ] Prototype catalog: `_from => \@catalog` in every `fselect` call
- [ ] `@catalog` created **once before pass 1** — never inside a loop
- [ ] Prototypes **never carry** the targeting slot (`besoin_X`) used by domain rules
- [ ] `_ISA` set at `new()` time — never via `$f->set('_ISA', ...)`
- [ ] INPUTS header in YAML documents linked slots: `link.slot_name : type — meaning`

---

### 3.5 Complete `load_projet()` skeleton — Pattern A + B combined

> Reference implementation: `test-11-construction-corpus-en-pdf-inter-frames-relations`

```perl
sub load_projet {
    my ($fichier) = @_;

    # Standard: JSON load + SLOTS_REQUIS validation (not shown)
    my @elements = ...;

    # ── Pattern B: build prototype catalog ONCE, before both passes ───────────
    my @catalog = _build_spec_catalog();   # see §3.2 for _build_*_catalog()

    # ── Pattern B: $inject_isa closure — captures @catalog ────────────────────
    my $inject_isa = sub {
        my ($slots) = @_;
        return unless defined $slots->{spec_key_1};   # your domain discriminator
        my $spec = fselect(
            spec_key_1 => $slots->{spec_key_1},
            spec_key_2 => $slots->{spec_key_2} // '',
            spec_key_3 => $slots->{spec_key_3} // 1,
            _from      => \@catalog,
        );
        return unless defined $spec;
        $slots->{_ISA} = defined($slots->{_ISA})
            ? [ ref($slots->{_ISA}) eq 'ARRAY' ? @{$slots->{_ISA}} : $slots->{_ISA}, $spec ]
            : $spec;
    };

    # ── Pattern A: *_ref → slot mapping ───────────────────────────────────────
    my %REF_FIELDS = (
        ref_field_1 => 'slot_name_1',   # e.g. supports_ref => 'supports'
        ref_field_2 => 'slot_name_2',   # e.g. building_ref => 'building'
    );

    # ── Pass 1 — frames without *_ref fields ──────────────────────────────────
    my (%frames_by_id, @frames, @deferred);
    for my $elem (@elements) {
        my $type    = $elem->{type_element} or next;
        next unless $SLOTS_REQUIS{$type};
        my $has_ref = grep { defined $elem->{$_} } keys %REF_FIELDS;
        if ($has_ref) { push @deferred, $elem; next; }

        my %slots = %$elem;
        $inject_isa->(\%slots);                      # Pattern B — BOTH passes
        my $frame = Chorus::Frame->new(%slots);
        $frame->set('targeting_slot', 'Y') if $TYPED_FRAMES{$type};
        $frames_by_id{ $elem->{id} } = $frame;
        push @frames, $frame;
    }

    # ── Pass 2 — frames with *_ref fields ─────────────────────────────────────
    for my $elem (@deferred) {
        my $type  = $elem->{type_element};
        my %slots = %$elem;

        for my $ref_field (keys %REF_FIELDS) {       # Pattern A — resolve links
            my $slot_name = $REF_FIELDS{$ref_field};
            my $ref_id    = delete $slots{$ref_field} // next;
            $slots{$slot_name} = $frames_by_id{$ref_id}
                or die "Element '$elem->{id}': $ref_field '$ref_id' not found\n";
        }

        $inject_isa->(\%slots);                      # Pattern B — BOTH passes
        my $frame = Chorus::Frame->new(%slots);
        $frame->set('targeting_slot', 'Y') if $TYPED_FRAMES{$type};
        $frames_by_id{ $elem->{id} } = $frame;
        push @frames, $frame;
    }

    return @frames;
}
```

---

## Checklist — Anti-Pitfalls

### ✅ Frames

- [ ] ⛔ **Never `$f->{slot} = $val`** — use `$f->set('slot', $val)` — bypasses `%REPOSITORY` → silent pipeline break
- [ ] Never `delete $f->{slot}` — use `$f->delete('slot')`
- [ ] In `_AFTER`: capture `$SELF` before any `set()` on another Frame:
      ```perl
      # ✅ CORRECT
      _AFTER => sub { my $ctx = $SELF; $other->set('x', $ctx->val) }
      ```

### ✅ Engine / Expert

- [ ] At least one agent or rule must call `solved()` (otherwise infinite loop)
- [ ] Calibrate `_MAX_CYCLES`: `N_frames × N_rules × N_agents × D × 10`
      where D = depth of the longest intra-agent cross-rule dependency chain
      (D = 1 if all rules are independent; D = N for a chain R01→R02→…→R0N)
- [ ] **`Chorus::Expert->new()` ignores its arguments** — always force `_MAX_ITER` after `new()` (see §1.4)
- [ ] Termination agent registered **last** in `register()`
- [ ] Deduplicate `_ID`s: two rules with the same `REGLE` → 2nd silently ignored
- [ ] ⛔ **Never termination via global `fmatch` in a YAML EFFET** → guaranteed infinite loop → use pure Perl `addrule()` with `$agent` closure
- [ ] ⚠️ In pure Perl `addrule()` → `$agent->solved()` (closure). In YAML EFFET → `$SELF->solved()`. Never mix.

### ✅ Multi-Specialty Architecture

- [ ] **1 specialty = 1 agent = 1 YAML directory = 1 optional Perl module**
- [ ] **Perl helpers — mandatory typeglob injection before `loadRules()`**:
      ```perl
      use MyAgent::Helpers qw(mon_helper);
      { no strict 'refs'; *{'Chorus::Engine::mon_helper'} = \&mon_helper; }
      $agent->loadRules("$base/rules/mon-agent");
      ```
      Without this: `Undefined subroutine &Chorus::Engine::mon_helper`.
- [ ] BOARD inter-agent keys documented in `index.org`

---

## Quick Reference

### Internal Engine Slots

```
_RULES  _SCOPE  _APPLY  _ID  _TERMINAL  _PREMISSES
_CUT  _LAST  _REPLAY  _REPLAY_ALL  _SLEEPING  _SUCCES
_MAX_CYCLES  _LOCK_UNTIL_STABLE  _IDENT
```

### BOARD Slots (Expert)

```
SOLVED   FAILED   INPUT   <custom inter-agent slots>
```

> Reserved slots: `SOLVED`, `FAILED` (deleted by `process()` on return), `INPUT` (set by `process()`).
> Custom slots (phase markers, aggregates, agent signals): see `§1.5 BOARD — Shared Publication Space`.

### Exported Symbols

```perl
use Chorus::Frame;                              # $SELF, &fmatch, &setMode, REQUIRE_FAILED
use Chorus::Collection::List qw($LIST);
use Chorus::Collection::Filter qw($FILTER @_VFILTER);
```
