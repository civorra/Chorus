# Skill — Chorus::Engine

> Automatically loaded for any Perl code created or modified in `$ENGINE`.
> Reference: report `$SESSIONS/2026-06-22-16-54-deep-analysis-engine.md`

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

**Design principle:** each level has a single responsibility.

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
- **Mode N** (default): for each valuation key (`_VALUE`, `_DEFAULT`, `_NEEDED`), traverse the entire tree before moving to the next.
- **Mode Z**: test the full sequence `(_VALUE, _DEFAULT, _NEEDED)` on each Frame before descending into parents.

```perl
Chorus::Frame::setMode(GET => 'Z');   # passe en mode Z
Chorus::Frame::setMode(GET => 'N');   # retour au mode N
```

**`$SELF`** = current context, available in any slot of type `sub { }`:

```perl
my $f = Chorus::Frame->new(
    label => sub { "Je suis " . $SELF->name },
    name  => 'Chorus',
);
```

**`fmatch()`** — efficient slot-based selection via `%REPOSITORY` + `%INSTANCES`:

```perl
# tous les Frames ayant le slot 'couleur'
my @c = fmatch(slot => 'couleur');

# intersection de slots
my @r = fmatch(slot => ['couleur', 'score']);

# espace de recherche restreint
my @r = fmatch(slot => 'couleur', from => \@subset);
```

---

### 1.3 Chorus::Engine — Rule Triggering

An agent is **itself a Frame** inheriting from the internal `$ENGINE` prototype.

```perl
my $agent = Chorus::Engine->new(_IDENT => 'MonAgent');
```

**Rule structure:**

```perl
$agent->addrule(
    _ID    => 'nom-unique',         # optionnel — déduplication
    _SCOPE => {
        var => sub { [ fmatch(slot => 'slot_cible') ] },
        # ou: var => [liste_statique]
    },
    _APPLY => sub {
        my %opts = @_;
        # $opts{var} = un Frame de la combinaison courante
        return unless <condition>;  # règle ne s'applique pas
        # ... effets ...
        return 1;                   # règle s'est appliquée
    },
);
```

**Inference loop:**
- `loop()` calls `applyrules()` in a loop as long as at least one rule returns true.
- For each rule: `_SCOPE` expansion → cartesian product → `_APPLY(%opts)` call.
- Safety: `_MAX_CYCLES` (default 10,000) → warning + stop if exceeded.

**Flow controls:**

| Method | Scope | Effect |
|---|---|---|
| `$agent->cut()` | current rule | exits scope loops → next rule (same agent) |
| `$agent->last()` | current agent | exits the rules loop → next agent |
| `$agent->replay()` | current agent | restarts from the 1st rule of this agent |
| `$agent->replay_all()` | all agents | restarts from the 1st agent (bubbles up to Expert) |
| `$agent->solved()` | global | `BOARD->{SOLVED} = 'Y'` → immediate stop |
| `$agent->failed()` | global | `BOARD->{FAILED} = 'Y'` → immediate stop |
| `$agent->pause()` | agent | disabled until `wakeup()` |
| `$agent->reorder(\&fn)` | agent | re-sorts `_RULES` + `replay()` |

---

### 1.4 Chorus::Expert — Orchestration

```perl
my $xprt = Chorus::Expert->new();
$xprt->register($agent1, $agent2, $agent3);
my $ok = $xprt->process($input);  # 1=solved, undef=failed
```

- `register()` injects the **shared BOARD** into each agent (`$agent->BOARD`).
- `process()` : `do { for each agent: agent->loop() } until BOARD->{SOLVED|FAILED}`
- `$input` accessible via `$agent->BOARD->INPUT`.
- Inter-agent communication: write/read slots on `$agent->BOARD`.
- `_LOCK_UNTIL_STABLE` on an agent: it is skipped if a previous agent already succeeded in the current iteration.

> ⚠️ **Known bug: `Chorus::Expert->new()` ignores its arguments:**
> Arguments passed to `new()` (e.g. `_MAX_ITER => 50_000`) are silently
> ignored — the value stays at its internal default.
> **Required pattern: assign directly after `new()`**:
>
> ```perl
> # ⛔ FAUX — _MAX_ITER ignoré
> my $xprt = Chorus::Expert->new(_MAX_ITER => 50_000);
>
> # ✅ CORRECT — affectation directe post-new
> my $xprt = Chorus::Expert->new();
> $xprt->{_MAX_ITER} = 50_000;   # obligatoire pour les pipelines longs
> ```
>
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
        Specialite1.pm     # constructeur agent + helpers Perl
        Specialite2.pm
        Specialite3.pm
      Expert.pm            # assembly + process()
  rules/
    specialite1/           # règles YAML de l'agent 1
      R01-xxx.yml
      R02-yyy.yml
    specialite2/
      R01-zzz.yml
    specialite3/
      R01-www.yml
  t/
    01-pipeline.t
```

### 2.2 Agent Template with Perl Helpers

```perl
package MyExpert::Agent::Specialite1;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;
use Exporter 'import';

our @EXPORT_OK = qw($agent helper1 helper2);

# -- Helpers Perl appelables depuis les règles YAML --

sub helper1 {
    my ($frame) = @_;
    # ...
    return $result;
}

sub helper2 { ... }

# -- Constructeur de l'agent --

our $agent;

sub build {
    my ($class, %opts) = @_;
    $agent = Chorus::Engine->new(_IDENT => 'Specialite1');
    $agent->loadRules($opts{rules_dir} // "rules/specialite1");
    return $agent;
}

1;
```

### 2.3 Expert Assembly Template

```perl
package MyExpert::Expert;

use strict;
use Chorus::Expert;
use MyExpert::Agent::Specialite1;
use MyExpert::Agent::Specialite2;
use MyExpert::Agent::Specialite3;

sub run {
    my ($class, $input) = @_;

    my $a1 = MyExpert::Agent::Specialite1->build();
    my $a2 = MyExpert::Agent::Specialite2->build();
    my $a3 = MyExpert::Agent::Specialite3->build();

    # Agent de contrôle (terminaison) — règle Perl pur
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
    $xprt->register($a1, $a2, $a3, $a_ctrl);
    return $xprt->process($input);
}

1;
```

### 2.4 Implicit Slot Pipeline

Agent chaining is done via the slot targeted in `CHERCHER`:

| Agent | `CHERCHER.attribut` | Sets the slot |
|---|---|---|
| Specialty 1 | `slot_brut` | `slot_enrichi` |
| Specialty 2 | `slot_enrichi` | `slot_calcule` |
| Specialty 3 | `slot_calcule` | `statut` |
| Ctrl | `slot_cle` (+ check `statut`) | calls `solved()` |

> **Golden rule:** each agent looks for a slot that only the previous agent can have set.
> This guarantees execution order without explicit coupling.

---

## 3. Complete YAML Guide

### 3.1 Complete Rule Structure

```yaml
REGLE: nom-de-la-regle          # obligatoire — devient _ID (déduplication)
TERMINAL: solved                 # optionnel — 'solved' ou 'failed'
PREMISSES:                       # optionnel — métadonnées pour reorder()
  - slot-prerequis
  - autre-slot
CHERCHER:                        # obligatoire — définit _SCOPE
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

### 3.2 CHERCHER — Variable Scope

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
- **`filtre`**: Perl expression on `$_` (the current Frame) — narrows the space before `_APPLY`.
- The filter is evaluated **before** the combinatorial loop → critical optimization.

### 3.3 CONDITION vs EXCEPTION

| Key | Semantics | Generated code |
|---|---|---|
| `CONDITION` | The rule **must** be true to fire | `return unless <CONDITION>;` |
| `EXCEPTION` | The rule **must not** fire if true | `return if <EXCEPTION>;` |

> **Idempotence convention:** always add `EXCEPTION: defined $var->{slot_pose}`
> to prevent a rule from firing repeatedly on the same Frame.

```yaml
EXCEPTION: defined $p->{fm_d}    # ne s'applique pas si fm_d déjà calculé
```

### 3.4 EFFET — Syntaxes

**Single-instruction block:**
```yaml
EFFET: "$frame->increase; 1"
```

**Multi-line block (YAML block scalar `|`):**
```yaml
EFFET: |
  my $W = $p->{largeur} * $p->{hauteur} ** 2 / 6;
  my $M = $p->{q_lineique} * $p->{portee} ** 2 / 8;
  $p->set('sigma_m', $M / $W);
  1
```

**Sequential effect list:**
```yaml
EFFET:
  - '$p->set("step1", "y")'
  - '$p->set("done", "y"); 1'
```

> ⚠️ The **last instruction must return a truthy value** for the rule to be considered
> as having "fired". End with `1` or a truthy expression.

> ⚠️ Use `|` (newlines preserved) and not `>` (newlines folded) for multi-line blocks.

### 3.5 TERMINAL — Automatic Termination

```yaml
REGLE: tout-est-traite
CHERCHER:
  p:
    attribut: statut
TERMINAL: solved
EXCEPTION: '$p->{statut} ne "FINAL"'
EFFET: "1"
```

When the rule fires **and** `_TERMINAL => 'solved'`, the engine automatically calls `solved()`.

### 3.6 Loading Order

`loadRules($dir)` loads `*.yml` files in **alphabetical order**.

```
R01-etape-un.yml      → chargée en premier
R02-etape-deux.yml
R10-etape-finale.yml
```

Multiple directories = multiple `loadRules()` calls:
```perl
$agent->loadRules("$RULES/phase1");
$agent->loadRules("$RULES/phase2");
```

### 3.7 PREMISSES — for reorder()

`PREMISSES` is a list of slots required by the rule. Not used directly by the engine, but accessible via `$rule->_PREMISSES` to dynamically sort rules:

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

## 4. Chorus::Collection

### 4.1 Collection::List — Ordered Frame Sequences

```perl
use Chorus::Collection::List qw($LIST);

my $sequence = Chorus::Frame->new(_ISA => $LIST);
$sequence->build($f1, $f2, $f3);   # initialise _ITEMS, pose _CONTAINER sur chaque item

$sequence->push_items($f4);         # ajout à droite
$sequence->unshift_items($f0);      # ajout à gauche
$sequence->first_item;              # $f0
$sequence->last_item;               # $f4
$sequence->length;                  # 5

$sequence->HAS('slot');             # premier item ayant le slot truthy
$sequence->HAS_NO('slot');          # vrai si aucun item n'a ce slot
$sequence->STARTS_WITH('slot');     # teste le premier item
$sequence->ENDS_WITH('slot');       # teste le dernier item
```

**Bidirectional prev/succ chaining:**
```perl
$f2->connect_left($f1);    # $f2->prev = $f1, $f1->succ = $f2
$f2->connect_right($f3);   # $f2->succ = $f3, $f3->prev = $f2
```

**List merging:**
```perl
$target->merge_left($list_a, $list_b);   # déplace les items à gauche
$target->merge_right($list_c);           # déplace les items à droite
# les listes sources sont vidées après merge
```

**Container name:** `_CONTAINER` by default, customizable:
```perl
$sequence->set_container_name('_PHRASE');
# chaque item aura un slot _PHRASE → $item->_PHRASE == $sequence
```

### 4.2 Collection::Filter — Pattern Matching on Sequences

```perl
use Chorus::Collection::Filter qw($FILTER @_VFILTER);

my $filtre = Chorus::Frame->new(_ISA => $FILTER);

# Définir le test par nœud (obligatoire pour comparer des valeurs de slots)
$filtre->set_node_test(sub {
    my ($frame) = @_;
    return $frame->categorie;    # retourne la valeur à comparer au motif
});

# Compiler le motif
$filtre->set_filter('^NOM (ADJ+) !PONCT*$');

# Tester une séquence
if ($filtre->check(@tokens)) {
    my ($adjectifs) = @_VFILTER;   # capture du groupe (ADJ+)
}
```

**Pattern syntax:**

| Token | Meaning |
|---|---|
| `^` | sequence start anchor |
| `$` | sequence end anchor |
| `X` | exactly token X |
| `[A B C]` | OR: A or B or C |
| `!X` | NOT: is not X |
| `.` | ANYTHING: any token |
| `X+` | 1 or more |
| `X*` | 0 or more (greedy) |
| `X?` | 0 or 1 (lazy) |
| `X{m,n}` | between m and n occurrences |
| `(...)` | capture group → `@_VFILTER` |

> `@_VFILTER` is reset on each `check()` call. Capture immediately after.

---

## 5. Checklist — Anti-Pitfalls

### ✅ YAML Rules

- [ ] **Always** end `EFFET` with a truthy value (`1` or truthy expression)
- [ ] **Conditional EFFET without `else` pitfall**: if the `if` modifies nothing and the rule returns `1`,
      the engine thinks it did work → `applyrules()` returns true → infinite loop until `_MAX_CYCLES`.
      **Rule:** return `0` (or `return 0`) when no slot has been modified.
      ```yaml
      # FAUX — boucle infinie si la condition n'est jamais vraie
      EFFET: |
        if ($p->{val} > 5) { $p->set('flag', 'KO') }
        1
      # CORRECT
      EFFET: |
        if ($p->{val} > 5) { $p->set('flag', 'KO'); return 1 }
        0
      ```
      Construction domain example — moisture/wood class:
      ```yaml
      # DANGEREUX à l'échelle — retourne 1 même si rien n'est modifié
      EFFET: |
        if ($p->{humidite_pct} > 18) { $p->set('alerte_humidite', 'KO') }
        1
      # CORRECT — le moteur sait qu'il n'a pas travaillé
      EFFET: |
        if ($p->{humidite_pct} > 18) { $p->set('alerte_humidite', 'KO'); return 1 }
        0
      ```
      > This pitfall is invisible on a sandbox (6 frames) and critical at real scale
      > (300 frames × 40 rules = explosion up to `_MAX_CYCLES` with a warning).
      > Systematically check every YAML whose EFFET contains an `if` without `else`.
- [ ] **Always** add `EXCEPTION: defined $var->{slot_pose}` for idempotence
- [ ] Use `|` (block scalar) for multi-line `EFFET`, never `>`
- [ ] Name files with prefix `R01-`, `R02-` to control loading order
- [ ] `filtre` in `CHERCHER` to narrow the scope **before** `_APPLY`

### ✅ Frames

- [ ] Never use `$f->{slot}` to read a value — use `$f->slot` or `$f->get('slot')`
- [ ] ⛔ **Never use `$f->{slot} = $val` to write** — use `$f->set('slot', $val)`

  **Critical pitfall `$f->{slot} = val`:** direct assignment bypasses `_setSlot`
  → `_registerSlot` → `%REPOSITORY` **is not updated** → `fmatch(slot => 'slot')`
  returns 0 Frames → subsequent agents never find the Frame.
  This bug is **silent**: no error, the slot exists on the Frame,
  but it is invisible to any `fmatch` targeting.

  ```perl
  # ⛔ FAUX — slot créé mais invisible à fmatch (pipeline silencieusement cassé)
  $f->{besoin_conformite} = 1;

  # ✅ CORRECT — slot enregistré dans %REPOSITORY → visible par fmatch
  $f->set('besoin_conformite', 1);
  ```

  At-risk cases: LLM-generated YAML EFFET, copy from a plain Perl hash,
  code from a Perl tutorial without knowledge of the Chorus engine.

- [ ] Never use `delete $f->{slot}` — use `$f->delete('slot')`
- [ ] Never name a domain slot with a `_UPPERCASE` prefix (reserved for the system)
- [ ] In `_AFTER`: capture `$SELF` **before** any call to `set()` on another Frame

```perl
# FAUX — $SELF sera écrasé par le set() interne
_AFTER => sub { $other->set('x', $SELF->val) }

# CORRECT
_AFTER => sub { my $ctx = $SELF; $other->set('x', $ctx->val) }
```

### ✅ Engine / Expert

- [ ] At least one agent or rule must call `solved()` (otherwise infinite loop)
- [ ] Check `_MAX_CYCLES` if the pipeline is long
- [ ] **`Chorus::Expert->new()` ignores its arguments** — always force `_MAX_ITER` via direct assignment:
      `$xprt->{_MAX_ITER} = N;` immediately after `new()` (see §1.4)
- [ ] The termination agent must be registered **last** in `register()`
- [ ] Deduplicate `_ID`s: two rules with the same `REGLE` in the same agent → the 2nd is silently ignored
- [ ] `addrule()` is called with `$SELF` as context during `loadRules()` — do not call from another Frame context

### ✅ Collection::Filter

- [ ] Always call `set_node_test()` before `check()` (the default returns the raw Frame)
- [ ] `@_VFILTER` is a shared global — capture immediately after `check()`
- [ ] A pattern with `^` and `$` must cover **exactly** the entire sequence

### ✅ Multi-Specialty Architecture

- [ ] **1 specialty = 1 agent = 1 YAML directory = 1 optional Perl module**
- [ ] The implicit pipeline: each agent reads the slot set by the previous one
- [ ] **Perl helpers — mandatory injection into `Chorus::Engine` before `loadRules()`**:
      YAML EFFETs are eval'd in `Chorus::Engine` — a `use Module qw(fn)` in the
      Agent module does NOT make `fn` visible in EFFETs.
      Required pattern:
      ```perl
      use MyAgent::Helpers qw(mon_helper);
      # ...
      { no strict 'refs'; *{'Chorus::Engine::mon_helper'} = \&mon_helper; }
      $agent->loadRules("$base/rules/mon-agent");
      ```
      Without this typeglob, the error is: `Undefined subroutine &Chorus::Engine::mon_helper`.
- [ ] `eca/` never committed to the Engine git repository

---

## 6. Quick Reference

### Exported Symbols

```perl
# Chorus::Frame
use Chorus::Frame;           # $SELF, &fmatch, &setMode, REQUIRE_FAILED

# Chorus::Collection::List
use Chorus::Collection::List qw($LIST);

# Chorus::Collection::Filter
use Chorus::Collection::Filter qw($FILTER @_VFILTER);
```

### YAML DSL Keys

```
REGLE       → _ID
TERMINAL    → 'solved' | 'failed'
PREMISSES   → [slot, ...]
CHERCHER    → _SCOPE (attribut + filtre optionnel)
CONDITION   → return unless ...
EXCEPTION   → return if ...
EFFET       → corps _APPLY (doit retourner vrai)
```

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
