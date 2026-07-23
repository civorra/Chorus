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
> Sizing heuristic: `N_frames × N_rules_total × safety_margin`.
> For a production pipeline (100 frames, 40 rules): `_MAX_ITER ≥ 100_000`.

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

```perl
# Declare all reference fields once — add a line to extend
my %REF_FIELDS = (
    supports_ref => 'supports',   # buttressing_wall → external_wall
    building_ref => 'building',   # wall → building
);

# Pass 1 — create frames without references (targets must exist first)
my (%frames_by_id, @deferred);
for my $elem (@elements) {
    my $has_ref = grep { defined $elem->{$_} } keys %REF_FIELDS;
    if ($has_ref) { push @deferred, $elem; next; }
    $frames_by_id{$elem->{id}} = Chorus::Frame->new(%$elem);
}

# Pass 2 — create frames with references (pass ref at new() time)
for my $elem (@deferred) {
    my %slots = %$elem;
    for my $ref_field (keys %REF_FIELDS) {
        my $slot_name = $REF_FIELDS{$ref_field};
        my $ref_id    = delete $slots{$ref_field} // next;
        $slots{$slot_name} = $frames_by_id{$ref_id}
            or die "Element '$elem->{id}': $ref_field '$ref_id' not found\n";
    }
    $frames_by_id{$elem->{id}} = Chorus::Frame->new(%slots);
}
```

> **⚠️ Why pass the reference at `new()` time, not via `set()` after:**
> `set()` calls `_setSlot()` which sets `_PARENT_KEY` on the target frame — a CoW
> side effect.  Passing at `new()` goes through `_blessToFrameRec` which skips
> already-blessed Frames.  Both work for read-only navigation, but `new()` is cleaner.

#### YAML rules — navigation with mandatory guard

```perl
# ACTION / EFFET body
my $sup = $w->get('supports')
    or do { warn "R05: no 'supports' link — skipped\n"; return 0 };

my $h = $sup->get('height_m') // 0;   # read from linked Frame
```

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
(`besoin_X`, `needs_Y`).  Rules use `FIND: attribut: besoin_masonry` → `fmatch` only
finds frames that have `besoin_masonry` registered.  Prototypes don't → they never
appear in any rule scope.  ✅

#### Feed.pm — `_build_*_catalog()` + `fselect`

```perl
sub _build_masonry_catalog {
    return (
        Chorus::Frame->new(
            masonry_unit_type => 'brick', masonry_material => 'clay', masonry_group => 1,
            min_str_A =>  6.0, min_str_B =>  9.0, min_str_C => 18.0,
        ),
        Chorus::Frame->new(
            masonry_unit_type => 'brick', masonry_material => 'clay', masonry_group => 2,
            min_str_A =>  9.0, min_str_B => 13.0, min_str_C => 25.0,
        ),
        # ... full catalog
    );
}

# In load_projet(), after resolving *_ref fields (pass 2):
my @catalog = _build_masonry_catalog();
if (defined $slots{masonry_unit_type}) {
    my $spec = fselect(
        masonry_unit_type => $slots{masonry_unit_type},
        masonry_material  => $slots{masonry_material}  // '',
        masonry_group     => $slots{masonry_group}     // 1,
        _from             => \@catalog,   # restrict to catalog only
    );
    $slots{_ISA} = $spec if defined $spec;
}
my $frame = Chorus::Frame->new(%slots);   # _ISA injected at construction time
```

> `_from => \@catalog` is mandatory — without it, `fselect` searches all registered
> frames and returns unexpected matches.

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

- [ ] `*_ref` fields stripped from slots hash before `Chorus::Frame->new()` (`delete $slots{ref_field}`)
- [ ] Target frame created in **pass 1** (no `*_ref` itself) — referencing frame in **pass 2**
- [ ] `%frames_by_id` maintained throughout — die with informative message if target not found
- [ ] Guards in YAML `ACTION`: `my $link = $w->get('slot') or return 0`
- [ ] Rules **never write** to linked frames
- [ ] Prototype catalog: `_from => \@catalog` in every `fselect` call
- [ ] Prototypes **never carry** the targeting slot (`besoin_X`) used by domain rules
- [ ] `_ISA` set at `new()` time — never via `$f->set('_ISA', ...)`
- [ ] INPUTS header in YAML documents linked slots: `link.slot_name : type — meaning`

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
- [ ] Calibrate `_MAX_CYCLES`: `N_frames × N_rules × N_agents × 10`
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
SOLVED   FAILED   INPUT
```

### Exported Symbols

```perl
use Chorus::Frame;                              # $SELF, &fmatch, &setMode, REQUIRE_FAILED
use Chorus::Collection::List qw($LIST);
use Chorus::Collection::Filter qw($FILTER @_VFILTER);
```
