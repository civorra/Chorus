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
  └─ Chorus::Engine     agent = Frame héritant de $ENGINE
       └─ _RULES        liste de Frames-règles
            └─ _SCOPE   adresse des Chorus::Frame du domaine
                 └─ Chorus::Frame   connaissance + hooks
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
> # ⛔ FAUX — _MAX_ITER ignoré
> my $xprt = Chorus::Expert->new(_MAX_ITER => 50_000);
>
> # ✅ CORRECT
> my $xprt = Chorus::Expert->new();
> $xprt->{_MAX_ITER} = 50_000;
> ```
> Sizing heuristic: `N_frames × N_règles_total × marge_sécurité`.
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
