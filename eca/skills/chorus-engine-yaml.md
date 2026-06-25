# Chorus::Engine — YAML Authoring Reference

> **Authoritative source for YAML authoring.**
> This file owns its sections — do not duplicate them in `chorus-engine.md`.
>
> Loaded by: `chorus-feed` (§0 Prerequisites)
> For direct Perl work in `$ENGINE`: load this file + `chorus-engine-infra.md`
> Scope: everything needed to write correct YAML rules and Helpers.pm.
> Not covered here: Perl infrastructure (Feed, Agent, Expert, run.pl) → `chorus-engine-infra.md`
> Not covered here: Collection::List / Collection::Filter → `chorus-engine.md`

---

## Frame essentials for YAML authors

### `$SELF` and `fmatch()`

**`$SELF`** = current context, available in any slot of type `sub { }` and in YAML EFFETs:

```perl
# In a Perl frame:
my $f = Chorus::Frame->new(
    label => sub { "I am " . $SELF->name },
    name  => 'Chorus',
);
```

**`fmatch()`** — slot-based Frame selection via `%REPOSITORY`:

```perl
my @c = fmatch(slot => 'couleur');                        # all Frames with slot 'couleur'
my @r = fmatch(slot => ['couleur', 'score']);             # intersection
my @r = fmatch(slot => 'couleur', from => \@subset);      # restricted search space
```

> ⛔ A Frame is only visible to `fmatch` if its slot was registered via `$f->set('slot', val)`.
> Direct assignment `$f->{slot} = val` bypasses registration → `fmatch` returns 0 Frames → **silent pipeline break**.

### Reading and writing slots

```perl
$f->get('slot')        # read — traverses inheritance chain
$f->slot               # shorthand read
$f->set('slot', $val)  # write — registers in %REPOSITORY → visible to fmatch
$f->delete('slot')     # delete — unregisters from %REPOSITORY
```

### Reserved system slots — never use as domain slot names

`_KEY` `_PARENT_KEY` `_ISA` `_VALUE` `_DEFAULT` `_NEEDED` `_BEFORE` `_AFTER` `_REQUIRE` `_NOFRAME` `_SERIALIZE`

---

## Engine — Rule triggering

**Rule structure (pure Perl — what YAML compiles to):**

```perl
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

**Inference loop:** `loop()` calls `applyrules()` as long as at least one rule returns true.
Safety: `_MAX_CYCLES` (default 10,000) → warning + stop if exceeded.

**Flow controls in YAML EFFET — use `$SELF` (never `$agent`):**

| `$SELF->method()` | Effect |
|---|---|
| `$SELF->cut()` | exits scope loops → next rule (same agent) |
| `$SELF->last()` | exits rules loop → next agent |
| `$SELF->replay()` | restarts from 1st rule of this agent |
| `$SELF->replay_all()` | restarts from 1st agent |
| `$SELF->solved()` | `BOARD->{SOLVED} = 'Y'` → immediate stop |
| `$SELF->failed()` | `BOARD->{FAILED} = 'Y'` → immediate stop |

> ⛔ `$agent` is **not** in scope inside a YAML EFFET eval → `Global symbol "$agent"` crash.
> Always use `$SELF` for flow control in `.yml` files.

---

## Implicit Slot Pipeline

Agent chaining via the slot targeted in `CHERCHER`:

| Agent | `CHERCHER.attribut` | Sets the slot |
|---|---|---|
| Specialty 1 | `slot_brut` | `slot_enrichi` |
| Specialty 2 | `slot_enrichi` | `slot_calcule` |
| Specialty 3 | `slot_calcule` | `statut` |
| Ctrl | `slot_cle` (+ check `statut`) | calls `solved()` |

> **Golden rule:** each agent looks for a slot that only the previous agent can have set.
> This guarantees execution order without explicit coupling.

---

## Complete YAML Guide

### Rule Structure

```yaml
REGLE: nom-de-la-regle          # mandatory — becomes _ID (deduplication)
TERMINAL: solved                 # optional — 'solved' or 'failed'
PREMISSES:                       # optional — metadata for reorder()
  - slot-prerequis
  - autre-slot
CHERCHER:                        # mandatory — defines _SCOPE
  var1:
    attribut: nom-du-slot        # → fmatch(slot => 'nom-du-slot')
    filtre: '$_->prop > 0'       # optionnel → grep { ... }
  var2:
    attribut: autre-slot
CONDITION: '$var1->ok'           # optionnel — return unless CONDITION
EXCEPTION: 'defined $var1->{r}' # optionnel — return if EXCEPTION
EFFET: |                         # obligatoire — corps de _APPLY
  $var1->set('result', $var2->value);
  1
```

### CHERCHER — Variable Scope

```yaml
CHERCHER:
  p:
    attribut: classe_bois
# → _SCOPE => { p => sub { [ fmatch(slot => 'classe_bois') ] } }

  p:
    attribut: level
    filtre: '$_->level < 5'
# → _SCOPE => { p => sub { [ grep { $_->level < 5 } fmatch(slot => 'level') ] } }
```

- **`attribut`**: slot passed to `fmatch` — defines the search space.
- **`filtre`**: Perl expression on `$_` — narrows the space **before** the combinatorial loop → critical optimization.

### CONDITION vs EXCEPTION

| Key | Semantics | Generated code |
|---|---|---|
| `CONDITION` | rule **must** be true to fire | `return unless <CONDITION>;` |
| `EXCEPTION` | rule **must not** fire if true | `return if <EXCEPTION>;` |

> **Idempotence:** always add `EXCEPTION: defined $var->{slot_pose}` to prevent re-firing on the same Frame.

### EFFET — Syntaxes

```yaml
# Single instruction
EFFET: "$frame->increase; 1"

# Multi-line (use | not >)
EFFET: |
  my $W = $p->{largeur} * $p->{hauteur} ** 2 / 6;
  $p->set('sigma_m', $M / $W);
  1

# Sequential list
EFFET:
  - '$p->set("step1", "y")'
  - '$p->set("done", "y"); 1'
```

> ⚠️ Last instruction must return a truthy value. Use `|` (newlines preserved), never `>`.

### TERMINAL — Automatic Termination

```yaml
REGLE: tout-est-traite
CHERCHER:
  p:
    attribut: statut
TERMINAL: solved
EXCEPTION: '$p->{statut} ne "FINAL"'
EFFET: "1"
```

- `TERMINAL: solved` — rule fires on ONE Frame and that is sufficient to terminate.
- `$SELF->solved()` in EFFET — when a condition must be checked before concluding.
- ⛔ **Never** termination via global `fmatch` in a YAML EFFET → guaranteed infinite loop → use pure Perl `addrule()` (see `chorus-check.md` Phase 3).

### Loading Order

`loadRules($dir)` loads `*.yml` files in **alphabetical order** → name files `R01-`, `R02-`, etc.

Multiple directories = multiple `loadRules()` calls.

### PREMISSES — for reorder()

```perl
sub sort_by_interest {
    my ($r1, $r2) = @_;
    return 1  if $r1->_PREMISSES->{CAT_NOM};
    return -1 if $r2->_PREMISSES->{CAT_NOM};
    return 0;
}
$agent->reorder(\&sort_by_interest);
```

---

## Checklist — Anti-Pitfalls

### ✅ YAML Rules

- [ ] **Always** end `EFFET` with a truthy value (`1` or truthy expression)
- [ ] **Conditional EFFET without `else`**: if the `if` modifies nothing and returns `1` → infinite loop until `_MAX_CYCLES`.
      ```yaml
      # ⛔ WRONG — infinite loop if condition never true
      EFFET: |
        if ($p->{val} > 5) { $p->set('flag', 'KO') }
        1
      # ✅ CORRECT
      EFFET: |
        if ($p->{val} > 5) { $p->set('flag', 'KO'); return 1 }
        0
      ```
      > Invisible on a sandbox (6 frames), critical at real scale (300 frames × 40 rules).
- [ ] **Always** add `EXCEPTION: defined $var->{slot_pose}` for idempotence
- [ ] Use `|` (block scalar) for multi-line `EFFET`, never `>`
- [ ] Name files `R01-`, `R02-` to control loading order
- [ ] `filtre` in `CHERCHER` to narrow scope **before** `_APPLY`

### ✅ Frames

- [ ] ⛔ **Never `$f->{slot} = $val`** — use `$f->set('slot', $val)` — direct assignment bypasses `%REPOSITORY` → `fmatch` returns 0 Frames → **silent** pipeline break
      ```perl
      # ⛔ WRONG — slot invisible to fmatch (pipeline silently broken)
      $f->{besoin_conformite} = 1;
      # ✅ CORRECT
      $f->set('besoin_conformite', 1);
      ```
- [ ] Never use `delete $f->{slot}` — use `$f->delete('slot')`
- [ ] Never name a domain slot with a `_UPPERCASE` prefix (reserved for the system)
- [ ] In `_AFTER`: capture `$SELF` **before** any call to `set()` on another Frame:
      ```perl
      # ⛔ WRONG — $SELF overwritten by internal set()
      _AFTER => sub { $other->set('x', $SELF->val) }
      # ✅ CORRECT
      _AFTER => sub { my $ctx = $SELF; $other->set('x', $ctx->val) }
      ```

### ✅ Multi-Specialty Architecture

- [ ] **1 specialty = 1 agent = 1 YAML directory = 1 optional Perl module**
- [ ] The implicit pipeline: each agent reads the slot set by the previous one
- [ ] **Perl helpers — mandatory typeglob injection into `Chorus::Engine` before `loadRules()`**:
      ```perl
      use MyAgent::Helpers qw(mon_helper);
      { no strict 'refs'; *{'Chorus::Engine::mon_helper'} = \&mon_helper; }
      $agent->loadRules("$base/rules/mon-agent");
      ```
      Without this: `Undefined subroutine &Chorus::Engine::mon_helper`.

---

## Quick Reference — YAML DSL Keys

```
REGLE       → _ID
TERMINAL    → 'solved' | 'failed'
PREMISSES   → [slot, ...]
CHERCHER    → _SCOPE (attribut + filtre optionnel)
CONDITION   → return unless ...
EXCEPTION   → return if ...
EFFET       → corps _APPLY (doit retourner vrai)
```
