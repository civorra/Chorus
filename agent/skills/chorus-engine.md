# Skill — Chorus::Engine

> Automatically loaded for any Perl code created or modified in `$ENGINE`.
> Reference: report `$SESSIONS/2026-06-30-18-16-chorus2-full-reference-classes-skills.md`

---

## Sub-skills

All domain knowledge is split into two **authoritative** sub-skills — no duplication.

| Sub-skill | Authoritative content | Load when |
|---|---|---|
| `chorus-engine-yaml.md` | Frame essentials for YAML (`$SELF`, `fmatch`, `set`), §Engine rule triggering, §Implicit pipeline, §Complete YAML guide (REGLE/CHERCHER/CONDITION/EXCEPTION/EFFET/TERMINAL/PREMISSES), §Checklists YAML + Frames + Multi-Specialty, §YAML DSL quick ref | Writing or reviewing YAML rules — loaded by `chorus-feed` |
| `chorus-engine-infra.md` | §1 Core Mechanisms (Expert→Agent→Frame chain, Frame slots, Engine rule triggering, Expert orchestration), §2 Multi-Specialty Pattern (project structure, agent template, Expert assembly, implicit pipeline), §Checklists Engine/Expert + Multi-Specialty, §Quick ref (Engine slots, BOARD) | Generating Perl infrastructure (Feed, Agent, Expert, run.pl) — loaded by `chorus-check` (full path) |

**For direct Perl work in `$ENGINE`** (auto Perl trigger):
→ load **both** sub-skills: `chorus-engine-yaml.md` + `chorus-engine-infra.md`

---

## ⛔ Critical rules — Frame slot access

> These two rules were added to the sub-skills after the last audit of this file.
> They are reproduced here so that this index exposes them immediately without requiring the sub-skills to be loaded first.
> **Authoritative reference:** `chorus-frame-advanced.md §hash-vs-get-reads` and `§get-path-vs-autoload`.

### Rule 1 — Always use `$f->get('slot')` for domain reads

```perl
$f->get('slot')   # ✅ traverses _VALUE → _DEFAULT → _NEEDED → _ISA
$f->slot          # ✅ AUTOLOAD shorthand — equivalent
$f->{slot}        # ⛔ bypasses _DEFAULT, _NEEDED, _ISA — silently wrong with prototypes
```

**Never** use `$f->{slot}` for reads in ACTION/EFFET, CONDITION, Helpers.pm, or procedural slots (`_NEEDED`, `_AFTER`).

**Three legitimate exceptions:**
1. `EXCEPTION: defined $f->{slot}` — idempotence guard (tests "_VALUE set by set()", not "_DEFAULT exists")
2. `run.pl` display loop — result slots are plain scalars written by rules
3. Engine system slots (`$SELF->{_KEY}`, `$agent->{_CYCLE}`) — not domain slots

### Rule 2 — `$f->get('a b c')` vs `$f->a->b->c` — two different `$SELF` semantics

| | `$f->get('a b c')` | `$f->a->b->c` |
|---|---|---|
| `$SELF` when `c`'s `_NEEDED` fires | **`$f`** (root frame, unchanged) | frame returned by `->b` |
| `_NEEDED` evaluated on `a` and `b`? | ❌ No — raw sub-frame used | ✅ Yes — each step goes through `get()` |

**Practical rule:** in YAML rules and Helpers.pm, always prefer `$var->get('a b c')` — it guarantees `$SELF` remains the domain object bound by the rule engine, which is what any `_NEEDED`/`_DEFAULT` coderef in the sub-frame tree expects.

Use `->a->b->c` only when each intermediate step must trigger its own `_NEEDED` and no `_NEEDED` in the chain reads `$SELF`.

---

## Chorus::Engine — Rule-Firing Log (`_LOG` / `_TRACE`)

> **New in v2.0.2.** Not in either sub-skill — documented here as the canonical reference.

A logging wrapper is injected **inside `addrule()`** around every `_APPLY` closure.
It fires after `_APPLY` returns a truthy value (rule fired), and is a no-op otherwise.

### Activation

| Mechanism | Set on | Scope | Behaviour |
|---|---|---|---|
| `_LOG => 1` | engine instance | all rules of this engine | Default STDERR output (see below) |
| `_LOG => \&my_fn` | engine instance | all rules of this engine | Calls `$my_fn->($engine, $rule_id, \%opts)` |
| `_TRACE => 1` | rule frame / `TRACE: 1` in YAML | that rule only | STDERR output, even without `_LOG` on the engine |

```perl
# Enable logging on an agent (set BEFORE or AFTER addrule — evaluated at fire time)
$agent->set('_LOG', 1);              # default STDERR handler
$agent->set('_LOG', \&my_handler);   # custom handler

# Custom handler signature:
sub my_handler {
    my ($engine, $rule_id, $opts) = @_;
    printf "fired: %s  cycle=%s\n", $rule_id, $engine->{_CYCLE};
}

# Per-rule trace (YAML):
TRACE: 1

# Per-rule trace (Perl):
$agent->addrule( _ID => 'my-rule', _TRACE => 1, _SCOPE => ..., _APPLY => ... );
```

### Default STDERR format

```
[cycle   3]  MyAgent / check-dimensions  fired
             scope: p=<frame-_KEY>
```

The scope line shows each variable name and the `id` slot of the bound Frame
(falls back to `_KEY` if `id` is absent, then to the stringified scalar).

### Important details

- `_LOG` is read **at fire time** — setting `$agent->set('_LOG', 0)` mid-run silently
  disables logging for all subsequent firings without touching `_RULES`.
- `_TRACE` is captured at `addrule()` time (closure) — changing it afterwards on the
  rule Frame has no effect.
- The internal function `_log_fire($engine, $rule_id, \%opts, $log_target)` is not
  exported and should not be called directly.

---

## Chorus::Engine — Internal counter semantics

> Precision details not in either sub-skill, useful when debugging infinite loops
> or calibrating `_MAX_CYCLES`.

### `_CYCLE` and `_SUCCES` — reset on every `loop()` call

Both counters are **reset to `0` at the start of every `loop()` call**:

```perl
loop => sub {
    $SELF->{_SUCCES} = 0;   # reset each loop() call
    $SELF->{_CYCLE}  = 0;   # reset each loop() call
    ...
    while ( applyrules() ) {
        ++$SELF->{_CYCLE};   # incremented after each pass that fired ≥ 1 rule
        ...
    }
}
```

- `_CYCLE` = **number of successful `applyrules()` passes in the current `loop()` call**
  (not a cumulative counter across `loop()` calls).
- `_SUCCES` = `1` if at least one rule fired in the **most recent `applyrules()` pass**;
  reset to `0` at the top of every `loop()` call. `Chorus::Expert` reads
  `$agent->_SUCCES` after `loop()` to drive `_LOCK_UNTIL_STABLE` logic.
- The internal `$cycles` variable (used for the `_MAX_CYCLES` guard) tracks the same
  count as `_CYCLE`, but is local — it exists only to avoid a race if `_CYCLE` were
  modified externally.

### `_KEY` is excluded from YAML scope variables

Inside `applyrules()`, scope variable names are filtered:

```perl
grep { $_ ne '_KEY' } keys(%{$rule->{_SCOPE}})
```

**You cannot name a `CHERCHER:` variable `_KEY`** — it would be silently ignored.
Reserve all `_UPPERCASE` names for system slots.

---

## ⚠️ Canonical Language Rule — All Generated Artefacts

> **Every artefact generated by the Chorus pipeline must be written in the same language as the corpus.**
>
> This rule applies unconditionally to **all** output types:
>
> | Artefact | Rule |
> |---|---|
> | **KB org files** (`.org`) | Section headings, slot descriptions, comments, free text → corpus language |
> | **Frame slot names** | Named in corpus language (e.g. French corpus → `montant_porteur`, `classe_bois`; English corpus → `bearing_member`, `wood_class`) |
> | **Perl comments** (`Feed.pm`, `Agent/*.pm`, `Expert.pm`, `Helpers.pm`, `run.pl`) | All inline and block comments → corpus language |
> | **YAML keywords** | Use French keywords (`REGLE`, `CHERCHER`, `EFFET`, `PREMISSES`) for French corpus, English keywords (`RULE`, `FIND`, `ACTION`, `PREMISES`) for English corpus — see `chorus-engine-yaml.md` |
> | **YAML headers and inline comments** | Corpus language — see `chorus-engine-yaml.md § Rule Documentation Standard` |
> | **JSON fields** (project files) | Technical structural keys (e.g. `"elements"`, `"type_element"`, `"id"`) are invariant; **user-facing values** (`"description"`, `"_note_calc"`, annotation strings) → corpus language |
> | **Reports and org outputs** (`import-report`, `thesaurus`, gap reports) | All section headings, column labels, and content → corpus language |
>
> ⚠️ **Mixing languages within a single sandbox is forbidden**, even if it seems "conventional" to use English for technical names.
> The only exceptions are: Perl reserved words, CPAN module names, fixed DSL keys (`attribut`, `filtre`), and internal engine slot names — these always remain in English regardless of the corpus language.
> Full list of reserved system slots (from `chorus-engine-yaml.md § Reserved system slots`):
> `_KEY` `_PARENT_KEY` `_ISA` `_VALUE` `_DEFAULT` `_NEEDED` `_BEFORE` `_AFTER` `_REQUIRE` `_NOFRAME` `_SERIALIZE`
> Additional runtime slots (`_SELF` `_ITEMS` `_CONTAINER` `_SCOPE` `_MAX_ITER` `_LOCK_UNTIL_STABLE`):
> → see `chorus-engine-yaml.md § Reserved system slots` (already loaded in this context).
>
> **This section is the single authoritative reference.** All skills (`chorus-feed`, `chorus-check`, `chorus-engine-yaml`, `chorus-create-project`, `chorus-import-project`, `chorus-strengthen`) defer to this rule.

---

## Chorus::Expert — Lesser-known behaviours

> Not in `chorus-engine-infra.md` — documented here as the canonical reference.

### `debug($level)` — verbose process loop tracing

```perl
my $xprt = Chorus::Expert->new();
$xprt->debug(1);   # enable verbose STDERR output
$xprt->debug(0);   # disable
```

When active, `process()` prints to STDERR at each key decision point:

```
Chorus::Expert - LOOPING ON AGENT Enrich NOW.
Chorus::Expert - Agent Validate is tagged with LOCK_UNTIL_STABLE
Chorus::Expert - None of agents [Enrich] have succeeded
Chorus::Expert - REPLAYING AGENT Enrich NOW.
Chorus::Expert - WILL REPLAY ALL AGENTS NOW.
```

Useful to diagnose infinite loops and unexpected LOCK_UNTIL_STABLE skips.

### BOARD cleanup after `process()`

`process()` **deletes** `SOLVED` and `FAILED` from the BOARD before returning:

```perl
($board->delete('SOLVED'), return 1) if $board->{SOLVED};
($board->delete('FAILED'), return  ) if $board->{FAILED};
```

Consequence: **the same `Chorus::Expert` instance can be called again** with
`process($new_input)` after a previous run — the BOARD is clean.
This also means you cannot read `$board->{SOLVED}` after `process()` returns;
test the return value of `process()` instead (`1` = solved, `undef` = failed).

---

## Chorus::Collection

> This section lives here only — it is not in either sub-skill.
> Load this file (or this section) when working with `Collection::List` or `Collection::Filter`.

### Collection::List — Ordered Frame Sequences

```perl
use Chorus::Collection::List qw($LIST);

my $sequence = Chorus::Frame->new(_ISA => $LIST);
$sequence->build($f1, $f2, $f3);   # initialise _ITEMS, pose _CONTAINER sur chaque item

$sequence->push_items($f4);         # append to the right
$sequence->unshift_items($f0);      # prepend to the left
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
$target->merge_left($list_a, $list_b);   # moves items to the left
$target->merge_right($list_c);           # moves items to the right
# source lists are emptied after merge
```

**Container name:** `_CONTAINER` by default, customizable:
```perl
$sequence->set_container_name('_PHRASE');
# chaque item aura un slot _PHRASE → $item->_PHRASE == $sequence
```

### Collection::Filter — Pattern Matching on Sequences

```perl
use Chorus::Collection::Filter qw($FILTER @_VFILTER);

my $filtre = Chorus::Frame->new(_ISA => $FILTER);

$filtre->set_node_test(sub {
    my ($frame) = @_;
    return $frame->categorie;
});

$filtre->set_filter('^NOM (ADJ+) !PONCT*$');

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

**Checklist:**
- [ ] Always call `set_node_test()` before `check()` (the default returns the raw Frame)
- [ ] `@_VFILTER` is a shared global — capture immediately after `check()`
- [ ] A pattern with `^` and `$` must cover **exactly** the entire sequence

### Exported Symbols

```perl
use Chorus::Collection::List qw($LIST);
use Chorus::Collection::Filter qw($FILTER @_VFILTER);
```
