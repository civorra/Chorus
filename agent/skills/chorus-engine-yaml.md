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

> ⛔ **Never dereference `fmatch()` as an arrayref** — `fmatch()` returns a **list**,
> not a list reference. Using `@{ fmatch(...) }` or `@{ fmatch(...) // [] }` forces
> `fmatch()` into **scalar context** (via the `//` operator or the `@{}` deref
> expectation), which returns the **count** of matching Frames as an integer (e.g. `53`).
> `@{ 53 }` then crashes with `Can't use string ("53") as an ARRAY ref`. Use `fmatch()`
> in list context directly — as the argument to `grep`, `map`, or a plain list assignment.
> ```perl
> # ⛔ WRONG — fmatch() forced into scalar context → returns count → crash
> my @pending = grep { !defined $_->{ok} } @{ fmatch(slot => 'type_element') // [] };
>
> # ✅ CORRECT — fmatch() in list context, as argument to grep
> my @pending = grep { !defined $_->{ok} } fmatch(slot => 'type_element');
> ```

### Reading and writing slots

```perl
$f->get('slot')        # read — traverses inheritance chain (_VALUE → _DEFAULT → _NEEDED → _ISA)
$f->slot               # shorthand read (AUTOLOAD — equivalent to get())
$f->set('slot', $val)  # write — registers in %REPOSITORY → visible to fmatch
$f->delete('slot')     # delete — unregisters from %REPOSITORY
```

> ⛔ **READS — golden rule:** always use `$f->get('slot')` or `$f->slot` in ACTION/EFFET,
> CONDITION, Helpers.pm, and procedural slots (`_NEEDED`, `_AFTER`).
> **Never** use `$f->{slot}` for reads in those contexts — it bypasses `_DEFAULT`, `_NEEDED`,
> and `_ISA` inheritance, producing silently wrong values whenever a prototype is involved.
>
> **Three legitimate exceptions for `$f->{slot}` reads:**
> 1. `EXCEPTION: defined $f->{slot}` — idempotence guard (intentional: tests "_VALUE set by set()", not "_DEFAULT exists")
> 2. `run.pl` display — result slots are plain scalars written by rules
> 3. Engine system slots (`$SELF->{_KEY}`, `$agent->{_CYCLE}`) — not domain slots
>
> → Full semantics and decision table: `chorus-frame-advanced.md § $f->{slot} vs $f->get('slot') — Read semantics`

### Reserved system slots — never use as domain slot names

`_KEY` `_PARENT_KEY` `_ISA` `_VALUE` `_DEFAULT` `_NEEDED` `_BEFORE` `_AFTER` `_REQUIRE` `_NOFRAME` `_SERIALIZE`

> **⚠️ Language rule — domain slot names:** all domain slot names (i.e. all slots **except**
> reserved system slots above and the invariant `type_element`) must be named in the **corpus language**.
> French corpus → `montant_porteur`, `classe_bois`, `besoin_conformite`.
> English corpus → `bearing_member`, `wood_class`, `conformance_need`.
> This applies to `FIND`/`CHERCHER` `attribut:` values, `ACTION`/`EFFET` slot reads/writes,
> and `PREMISES`/`PREMISSES` entries.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

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

**Flow controls in YAML ACTION — use `$SELF` (never `$agent`):**

| `$SELF->method()` | Effect |
|---|---|
| `$SELF->cut()` | exits scope loops → next rule (same agent) |
| `$SELF->last()` | exits rules loop → next agent |
| `$SELF->replay()` | restarts from 1st rule of this agent |
| `$SELF->replay_all()` | restarts from 1st agent |
| `$SELF->solved()` | `BOARD->{SOLVED} = 'Y'` → immediate stop |
| `$SELF->failed()` | `BOARD->{FAILED} = 'Y'` → immediate stop |

> ⛔ `$agent` is **not** in scope inside a YAML ACTION eval → `Global symbol "$agent"` crash.
> Always use `$SELF` for flow control in `.yml` files.
>
> ⚠️ `$agent` is **not** in scope in a YAML ACTION — use `$SELF` for flow control.

---

## Implicit Slot Pipeline

Agent chaining via the slot targeted in `FIND`:

| Agent | `FIND.attribut` | Sets the slot |
|---|---|---|
| Specialty 1 | `slot_brut` | `slot_enrichi` |
| Specialty 2 | `slot_enrichi` | `slot_calcule` |
| Specialty 3 | `slot_calcule` | `statut` |
| Ctrl | `slot_cle` (+ check `statut`) | calls `solved()` |

> **Golden rule:** each agent looks for a slot that only the previous agent can have set.
> This guarantees execution order without explicit coupling.

---

## Inter-Frame Navigation in ACTION / EFFET

> **See also:** `chorus-engine-infra.md § 3. Inter-Frame Relationships` for the
> full Feed.pm implementation (2-pass, `%REF_FIELDS`, prototype catalogs).
> This section covers the YAML-side conventions only.

### Navigating a slot→Frame link

When a frame carries a slot that holds a reference to another Frame (Pattern A —
structural link), two patterns depending on whether the link is optional.

> **`$SELF` rule for inter-frame reads:**
> Always use `$w->get('link_slot remote_slot')` (path form) rather than
> `$w->get('link_slot')->get('remote_slot')` (chained form).
> The path form keeps `$SELF = $w` throughout — any `_NEEDED` or `_DEFAULT`
> coderef on `remote_slot` that reads `$SELF` will correctly see the rule-Frame.
> The chained form shifts `$SELF` to the linked sub-frame after the first `get()`.
> → Full explanation: `chorus-frame-advanced.md § get('a b c') vs ->a->b->c`

```yaml
ACTION: |
  # ── Option A: link optional — fallback to direct slot (backward-compatible)
  # Use when the same rule must work on project files with and without the link.
  # Replace 'link_slot', 'remote_slot', 'local_fallback_slot' with actual names.
  # Path form keeps $SELF = $w when remote_slot's _NEEDED fires.
  my $val = $w->get('link_slot remote_slot') // $w->get('local_fallback_slot') // 0;
  # e.g.: my $h = $w->get('supports height_m') // $w->get('height_m') // 0;
  1
```

```yaml
ACTION: |
  # ── Option B: link mandatory — hard skip if absent
  # Use only when the link is architecturally guaranteed.
  my $h = $w->get('supports height_m');
  unless (defined $h) {
      warn "R05: no 'supports' or missing 'height_m' on $w->{id}\n";
      return 0;
  }
  # ... checks using $h
  1
```

> ⛔ **Never write to a linked Frame from a rule:**
> `$w->get('supports')->set('slot', val)` creates side effects on frames
> processed by other agents — invisible and hard to debug.  Read only.

### Reading inherited thresholds via `_ISA`

When a frame inherits from a prototype (Pattern B — `_ISA`), read thresholds
directly via `get()` — the inheritance chain is traversed transparently:

```yaml
ACTION: |
  my $cond    = $w->get('masonry_condition') // 'A';   # ✅ get() — _DEFAULT on prototype is common here
  my $min_str = $w->get("min_str_$cond");   # traverses _ISA → prototype

  unless (defined $min_str) {
      $w->set('strength_ok', 'YES');   # no numeric minimum for this spec
      return 1;
  }
  # ... comparison
  1
```

Dynamic slot names (`"min_str_$cond"`) work with `get()` as a plain string argument.

### INPUTS header convention for Frame-linked slots

Replace `<link_slot>`, `<target_type>`, `<remote_slot>`, `<threshold_slot>` with your
domain's actual slot names.

```yaml
##
# INPUTS  (slots read)
#   besoin_X           : targeting slot (your sandbox's targeting slot name)
#                        — Frame-local (every targeted Frame carries its own
#                          copy, written by a dedicated rule) OR BOARD-global
#                          (pipeline-wide gate, read via $SELF->BOARD->{besoin_X},
#                          never replicated per-Frame) — state which, explicitly,
#                          see ⛔ note below. Never leave this ambiguous.
#   <link_slot>        : Frame ref — <target_type> this frame is linked to
#                        (resolved from <link_slot>_ref by Feed.pm at load time)
#   <link_slot>.<remote_slot> : <type> — <description> (read via inter-frame link)
#   _ISA → <spec_type> prototype (injected by Feed.pm via fselect)
#     <threshold_slot>_A / _B / _C : normative thresholds (inherited via _ISA)
##
```

> **Example** (ADA sandbox):
> ```yaml
> #   besoin_wall        : targeting slot — Frame-local (written on every
> #                        `wall` Frame by agent-wall-init R01, one rule
> #                        instance per targeted Frame; NOT a BOARD slot)
> #   supports           : Frame ref — external_wall this wall buttresses
> #                        (resolved from supports_ref by Feed.pm)
> #   supports.height_m  : float — height of supported wall (via link)
> #   _ISA → masonry_spec prototype
> #     min_str_A / min_str_B / min_str_C : Table 6 thresholds (via _ISA)
> ```

> ⛔ **MANDATORY distinction — Frame-local targeting slot vs. BOARD-global ordering
> gate. Confusing the two causes a pipeline that silently never converges.**
>
> A "targeting slot" referenced in an `INPUTS`/`CONDITION`/`EXCEPTION` clause is
> **one of exactly two different things** — never assume, always verify which:
>
> | Kind | How it is published | How every consuming rule must read it | Typical use |
> |---|---|---|---|
> | **Frame-local targeting slot** | A dedicated rule's `ACTION` calls `$w->set('slot', 1)` **once per targeted Frame instance** — the rule's own `FIND` targets the *same Frame type* as every rule that later reads this slot. | `CONDITION: defined $e->{slot}` / `$e->get('slot')` — reading the Frame's own copy. | A per-element flag computed by an earlier rule on the *same* Frame (e.g. `dependency_catalog_ok` written by R04, read by R05 on the *same* component Frame). |
> | **BOARD-global ordering gate** | A rule (anywhere in the pipeline, typically the very first agent) calls `$SELF->BOARD->{slot} = 1` **exactly once, pipeline-wide** — never replicated onto any individual Frame. | `CONDITION: defined $SELF->BOARD->{slot}` — **never** `$e->{slot}` or `$w->{slot}`, since the slot does not exist on element Frames at all. | A pipeline-wide "upstream phase N is done, phase N+1 may now target any Frame" gate shared across many *different* Frame types/agents (e.g. `besoin_conformite` set once by `toe-structure` on the `ST`/`PP`/`TOE` Frame, meant to unblock 11 *different* SFR class agents whose own Frames — `FAU_GEN.1`, `FCO_NRO.1`, etc. — never carry this slot themselves). |
>
> **Decision rule when authoring any `CONDITION`/`EXCEPTION` referencing a
> cross-agent targeting slot:** before writing `defined $e->{slot}`, ask —
> *does the rule that publishes this slot target the same Frame type as the
> rule reading it?* If yes → Frame-local, `$e->{slot}` is correct. If the
> publishing rule targets a **different** Frame type (e.g. `ST`/`PP`/`TOE`
> publishing, `FAU_*` reading) → it is a pipeline-wide gate and **must** go
> through `$SELF->BOARD->{slot}`, never a per-Frame copy — unless an explicit,
> separate propagation rule is authored to copy the value onto every target
> Frame type (rare, and must be documented as such in both agents' KB org).
> **Never assume — always check the publishing agent's own Slot dictionary /
> Frame catalog to see which mechanism it actually uses**, especially when the
> publishing and consuming agents were authored in separate `chorus-feed`
> passes or by separate delegated sub-agents (see `chorus-feed.md` § BOARD —
> inter-agent coordination, and § Multi-agent Mode A sequencing, for the
> matching authoring-time safeguard).

### Checklist — Inter-Frame YAML

- [ ] **Guard on every `get('link')` call** — Option A (fallback) or Option B (hard skip) — see § Navigating a slot→Frame link above
- [ ] `$_->{link_slot}` in `filtre` is the **Frame object** — use `$_->get('link_slot')` there
      if you need to inspect the linked frame inside a `filtre` expression
- [ ] **Never use `$_->{slot}` direct access in `filtre` for inherited slots** —
      `$_->{slot}` only sees direct slots; use `$_->get('slot')` to traverse `_ISA`
- [ ] `$w->get("slot_$dynamic")` — dynamic slot names work, document the possible values
- [ ] INPUTS header: document linked Frame slots as `link.slot_name : type — meaning`

---

## Complete YAML Guide

> **Language rule:** use English keywords by default (`RULE`, `FIND`, `ACTION`, `PREMISES`).
> Switch to French keywords (`REGLE`, `CHERCHER`, `EFFET`, `PREMISSES`) only when the corpus
> processed by `chorus-feed` is in French.
> Sub-keys `attribut` and `filtre` are invariant — no English alias exists in the engine.

---

### Rule Evaluation Lifecycle

**Every cycle, for every rule, the engine executes the following sequence in strict order:**

```
① fmatch(attribut)
      ↓  builds the pool of candidate Frames from %REPOSITORY
      ↓  (one pool per FIND variable)

② filtre  [optional, per variable]
      ↓  grep { <expr on $_> } pool
      ↓  Frames that fail filtre are EXCLUDED from the scope
      ↓  they never reach EXCEPTION / CONDITION / ACTION this cycle

③ Cartesian product
      ↓  var1_pool × var2_pool × …
      ↓  each combination binds the scope variables ($f, $p, $w …)

④ EXCEPTION  [optional]
      ↓  return if <EXCEPTION>
      ↓  evaluated on the bound combination
      ↓  if true → skip this combination (see permanence below)

⑤ CONDITION  [optional]
      ↓  return unless <CONDITION>
      ↓  evaluated on the bound combination
      ↓  if false → skip this combination this cycle; retry next cycle

⑥ ACTION
      ↓  business logic
      ↓  return 0 → "nothing done" (does not count as a productive step)
      ↓  return 1 → "something done" (engine schedules a new cycle)
```

**Who decides to bypass — synthesis table:**

| Mechanism | Operates on | Scope vars available? | Bypass permanence | Decision owner |
|---|---|---|---|---|
| `attribut` absent | Individual Frame | ❌ | Permanent — Frame invisible to this rule | Frame (missing slot) |
| `filtre` = false | Individual Frame | ❌ (`$_` only) | Quasi-permanent — until the Frame's slots change | Frame (slot value at scope-build time) |
| `EXCEPTION` = true | Scope combination | ✅ | **Permanent** (Pattern 1) / **Transient** (Pattern 2) | Rule (idempotence guard) |
| `CONDITION` = false | Scope combination | ✅ | **Always transient** — retried next cycle | Rule (prerequisite not yet met) |
| `ACTION` returns 0 | Scope combination | ✅ | Transient — retried next cycle | Business logic |

> **Key distinction — `filtre` vs `CONDITION`:**
> `filtre` is a **structural eligibility criterion**: it determines which Frames can
> participate in the rule at all. A Frame excluded by `filtre` never sees `EXCEPTION`,
> `CONDITION`, or `ACTION`. It is not an optimisation — it is a scope definition.
> `CONDITION` is a **temporal prerequisite**: it delays the rule's application until
> the required data is available. The Frame is in scope; the rule simply waits.
> Replacing one with the other produces incorrect behaviour.

> **Multi-variable FIND:** `EXCEPTION` and `CONDITION` apply to the **bound combination
> (var1, var2, …)**, not to individual Frames. The same Frame may participate in several
> combinations with different results for each.

> **Dependency direction is independent of rule numbering:**
> The engine does not fire rules in alphabetical order — it retries **all** rules every
> cycle until no further progress is possible. A rule R01 that reads a slot written by R02
> is perfectly valid: R01's `CONDITION: defined $p->{slot_from_r02}` will simply be false
> in cycle 1 (R02 has not yet fired), and the engine will retry R01 in cycle 2 after R02
> has run. The dependency chain R03→R02→R01 (where R03 provides data to R02, which provides
> data to R01) gives the same D = 3 and requires the same number of cycles as the
> "natural order" chain R01→R02→R03. Rule numbers reflect load order only — never assume
> that a lower-numbered rule fires first.

> **`return 0` vs `return 1` — convergence mechanism:**
> `return 1` signals "this rule produced an effect". The engine counts it as a productive
> step and schedules a new cycle. `return 0` signals "nothing was done this time". If
> **all** rules return 0 in a cycle, the engine stops (no progress possible). A rule that
> unconditionally returns 1 without writing any slot causes an infinite loop until
> `_MAX_CYCLES` is reached. This is the root cause of the "conditional ACTION without
> else" pitfall.

> **Scope of "cycle" — inner loop only:**
> Every occurrence of "cycle" in this section refers to the **inner inference loop of a
> single agent** (`Chorus::Engine::loop()`). The lifecycle above (steps ①–⑥) is replayed
> by one agent on its own rules until local convergence (all rules return 0).
>
> A multi-agent pipeline adds an **outer loop** (`Chorus::Expert::process()`): once Agent A
> has converged locally, the Expert hands control to Agent B, then Agent C, etc. After all
> agents have run, the Expert checks `BOARD->{SOLVED|FAILED}` and, if neither is set,
> starts a new outer iteration from Agent A. Agent A may then fire new rules based on slots
> written to BOARD by Agent B or C during the previous outer round.
>
> **Consequence for CONDITION guards:**
> - `CONDITION: defined $p->{slot_from_other_rule}` → intra-agent dependency → resolved
>   within the inner loop (the slot will be written by another rule in the same agent on a
>   later inner cycle).
> - A slot written by **another agent** is available only after the outer loop hands control
>   back to this agent. It must be read from `$SELF->BOARD` in ACTION — **not** via
>   CONDITION, which operates inside the inner loop where the other agent has not yet run.
>   ⛔ **Never `$agent->BOARD` inside a YAML ACTION** — `$agent` is out of scope in the
>   Engine's `eval` and crashes with `Global symbol "$agent" requires explicit package name`.
>   `$agent` is only valid inside a pure-Perl `addrule()` closure (`Agent/<Nom>.pm`), never
>   inside a `.yml` rule's `ACTION`/`EFFET`/`EXCEPTION` block.
>
> Full two-level loop diagram: `chorus-engine-infra.md § Two-level inference loop`.

---

### Rule Structure

```yaml
RULE: rule-name                  # mandatory — becomes _ID (deduplication)
TERMINAL: solved                 # optional — 'solved' or 'failed'
PREMISES:                        # optional — metadata for reorder()
  - slot-prerequisite
  - another-slot
FIND:                            # mandatory — defines _SCOPE
  var1:
    attribut: slot-name          # → fmatch(slot => 'slot-name')
    filtre: '$_->prop > 0'       # optional → grep { ... }
  var2:
    attribut: another-slot
CONDITION: '$var1->ok'           # optional — return unless CONDITION
EXCEPTION: 'defined $var1->{r}' # optional — return if EXCEPTION
ACTION: |                        # mandatory — body of _APPLY
  $var1->set('result', $var2->value);
  1
```

> French equivalent (corpus in French): `REGLE` / `CHERCHER` / `EFFET` / `PREMISSES`

### FIND — Variable Scope

```yaml
FIND:
  p:
    attribut: classe_bois
# → _SCOPE => { p => sub { [ fmatch(slot => 'classe_bois') ] } }

  p:
    attribut: level
    filtre: '$_->level < 5'
# → _SCOPE => { p => sub { [ grep { $_->level < 5 } fmatch(slot => 'level') ] } }
```

- **`attribut`**: slot passed to `fmatch` — **eligibility criterion**: any Frame that does not
  carry this slot is invisible to the rule. It never reaches `EXCEPTION`, `CONDITION`, or
  `ACTION`, in this cycle or any subsequent one (unless the slot is later added via `set()`).

- **`filtre`**: Perl expression on **`$_`** (the iterated Frame) — **structural scope definition**,
  evaluated before the Cartesian product is built.
  A Frame that fails `filtre` is **excluded from the rule's scope entirely**: it is never bound
  to a scope variable, never evaluated by `EXCEPTION` or `CONDITION`, and never processed by
  `ACTION`. This exclusion persists across cycles as long as the Frame's slots remain unchanged.
  > ⚠️ `filtre` is **not** an optimisation of `CONDITION`. They have different semantics:
  > - `filtre` = "which Frames are eligible to participate in this rule at all"
  > - `CONDITION` = "when (in which cycle) should the rule fire for an eligible Frame"
  > Using `filtre` where `CONDITION` is needed creates a **quasi-permanent** exclusion instead
  > of a temporary wait: the Frame is re-evaluated by `filtre` each cycle, but only after its
  > slots change — and by the time the prerequisite slot is written by another rule, the
  > EXCEPTION guard (Pattern 1) may already have been set by a sibling rule, permanently
  > blocking the dependent rule anyway. In typical classification pipelines this is
  > functionally equivalent to a permanent exclusion.
  >
  > **Practical rule:** use `filtre` only for stable, structural criteria (element type, static
  > threshold, slot presence guaranteed at Feed time). Use `CONDITION` for anything that depends
  > on slots written by other rules during the inference cycle.

> ⛔ **`filtre` MUST be a Perl string expression — never a YAML structure (mapping or sequence).**
> Two common broken forms exist:
>
> **Form 1 — YAML mapping** (key: value pairs) → parsed as **hashref** → `grep { HASH(0x...) }` —
> constant truthy, matches every Frame. No error raised.
> ```yaml
> # ⛔ WRONG — filtre as YAML mapping → HASH(0x...) in grep, filters nothing
> FIND:
>   e:
>     attribut: type_element
>     filtre:
>       type_element: use_of_work
>       besoin_permitted_use: 1
> ```
>
> **Form 2 — YAML sequence** (- item) → parsed as **arrayref of barewords** →
> `grep { use_of_work }` — constant truthy (non-empty string), matches every Frame.
> This is the most insidious form: the YAML looks intuitive ("a list of allowed values")
> but `setFilter()` expects Perl expressions, not literal values to match against.
> No error raised; `loadRules()` emits `[Chorus::Engine] FILTRE-SEQUENCE-LITERAL` warn (`_check_filtre_not_string()`, ENG-050).
> ```yaml
> # ⛔ WRONG — filtre as YAML sequence → arrayref of barewords → constant truthy
> FIND:
>   e:
>     attribut: type_element
>     filtre:
>       - use_of_work
>       - broadcast
> ```
>
> **Correct form — always a quoted Perl string on `$_`:**
> ```yaml
> # ✅ CORRECT — single value
> FIND:
>   e:
>     attribut: type_element
>     filtre: '$_->{type_element} eq "use_of_work"'
>
> # ✅ CORRECT — multiple values
> FIND:
>   e:
>     attribut: type_element
>     filtre: '$_->{type_element} =~ /^(use_of_work|broadcast)$/'
>
> # ✅ CORRECT — combined criteria (AND — same as YAML sequence of Perl expressions)
> FIND:
>   e:
>     attribut: type_element
>     filtre: '$_->{type_element} eq "use_of_work" && $_->{besoin_permitted_use}'
> ```

> Multiple `filtre` expressions (YAML list) are joined with **implicit AND** (`setFilter()`: `join(' and ', ...)`):
> all expressions must be true for a candidate to enter scope. This is the opposite of `CONDITION` list (implicit OR).
> See **ADR-002** (`agent/kb/decisions/ADR-002.org`) — intentional, coherent asymmetry.

> ⛔ **Never use `return` inside `filtre`** — `filtre` is compiled as the
> predicate of a `grep {}` block. In Perl, `return` inside a `grep {}` does **not**
> skip the current element — it **exits the entire enclosing `_SCOPE` closure**,
> returning a scalar (`0`) instead of an arrayref. The engine then does
> `@{ 0 }` → crash, or silently produces an empty scope set. Use a pure boolean
> expression instead.
> ```yaml
> # ⛔ WRONG — `return 0` exits the scope closure, not just the grep predicate
>     filtre: |
>       return 0 unless $SELF->BOARD->{rights_established};
>       $_->{rightholder_category} eq 'performer'
>
> # ✅ CORRECT — pure boolean expression
>     filtre: |
>       ($SELF->BOARD && $SELF->BOARD->{rights_established})
>       && $_->{rightholder_category} eq 'performer'
> ```

> ⛔ **`$SELF->BOARD->{flag}` requires a null-check in `filtre` (and in `CONDITION`)**
> — `$SELF->BOARD` is `undef` during the first engine cycles, before any agent has
> published a BOARD slot. A bare `$SELF->BOARD->{flag}` dereference crashes with
> `Can't use an undefined value as a HASH reference`. Always guard with
> `($SELF->BOARD && $SELF->BOARD->{flag})`, or use `($SELF->BOARD->{flag} // 0)` only
> after confirming BOARD is always initialized before this rule can fire (via a
> `CONDITION: defined $SELF->BOARD->{upstream_flag}` on the same rule).
> ```yaml
> # ⛔ WRONG — crashes if BOARD not yet initialized
>     filtre: '$SELF->BOARD->{rights_established} && $_->{act_type} eq "broadcast"'
>
> # ✅ CORRECT — null-safe
>     filtre: '($SELF->BOARD && $SELF->BOARD->{rights_established}) && $_->{act_type} eq "broadcast"'
> ```

> ⛔ **`$f` is not defined inside `filtre`** — `$f` (or any scope variable) only exists inside `ACTION`/`EFFET`, after `my $f = $opts{f}` is executed by `_APPLY`. Using `$f->` in a `filtre` expression causes `Global symbol "$f" requires explicit package name` at rule compilation time.
> ```yaml
> # ⛔ WRONG — $f not in scope here
> FIND:
>   f:
>     attribut: type_element
>     filtre: "defined $f->{type_element} && defined $f->{classe_bois}"
>
> # ✅ CORRECT — use $_ (the iterated Frame)
> FIND:
>   f:
>     attribut: type_element
>     filtre: "defined $_->{type_element} && defined $_->{classe_bois}"
> ```
> Multi-line block scalars (`|`) follow the same rule — every line uses `$_`:
> ```yaml
>     filtre: |
>       defined $_->{type_element}
>       && defined $_->{classe_bois}
> ```

### CONDITION vs EXCEPTION

> **Evaluation order within `_APPLY`:** `EXCEPTION` is evaluated **first** (step ④ in the
> lifecycle), then `CONDITION` (step ⑤). If `EXCEPTION` triggers, `CONDITION` is never reached.
> Both operate on the **bound scope combination** (var1, var2, …), not on individual Frames.
> A Frame that participates in N combinations may be bypassed by some and processed by others.

| Key | Semantics | Generated code | Bypass scope | Permanence |
|---|---|---|---|---|
| `EXCEPTION` = true | rule **must not** fire | `return if <EXCEPTION>;` | Scope combination | **Permanent** (P1) / Transient (P2) |
| `CONDITION` = false | rule **must** wait | `return unless <CONDITION>;` | Scope combination | **Always transient** — retry next cycle |

> A `CONDITION` given as a YAML list uses **implicit OR** (`setCondition()`: `join("or", ...)`):
> the rule fires if *any one* condition holds. This is the opposite of `filtre` list (implicit AND).
> See **ADR-002** (`agent/kb/decisions/ADR-002.org`) — intentional, coherent asymmetry.

> **`CONDITION` — transience rule:**
> When `CONDITION` is false, the engine skips the current combination for this cycle and retries
> it in the next. `CONDITION` is the correct mechanism for cross-rule slot dependencies:
> if R03 requires a slot written by R01, guard it with `CONDITION: defined $p->{slot_from_r01}`.
> The engine will retry R03 every cycle until R01 has fired and written the slot.
> ⚠️ Never use `filtre` for this purpose — a Frame excluded by `filtre` is permanently out of
> scope and will not be retried even after R01 fires.

> **⚠️ `$var->{slot}` in EXCEPTION — the sole legitimate hash-access for domain slots:**
> `EXCEPTION: defined $var->{slot}` intentionally uses `$var->{slot}` (not `$var->get('slot')`).
> It tests "has `set()` explicitly written `_VALUE` on this Frame?" — bypassing `_DEFAULT` and `_ISA`
> on purpose. Using `$var->get('slot')` instead would trigger the rule's idempotence guard even when
> the slot value comes from a prototype `_DEFAULT`, preventing the rule from ever computing and
> writing the actual `_VALUE`.
> **Outside EXCEPTION guards, `$var->{slot}` is strictly forbidden for domain slot reads** —
> always use `$var->get('slot')` (traverses `_VALUE → _DEFAULT → _NEEDED → _ISA`).
> → Authoritative rule: `chorus-engine.md § Rule 1 — Always use $f->get('slot') for domain reads`.

> **Idempotence — two patterns depending on rule semantics:**
>
> **Pattern 1 — "first writer wins" (default):** classification rules that must fire exactly once.
> ```yaml
> EXCEPTION: defined $var->{slot_pose}
> ```
> Once any rule writes `slot_pose`, all rules sharing this guard are **permanently blocked** on
> this Frame for the remainder of the inference (all future cycles). This is intentional for
> classification rules where only one sibling should fire.
> Use for: R01–R0N classification rules within the same agent when only one must fire.
>
> **Pattern 2 — "veto / override" rules:** rules that must be able to *overwrite* a value
> already set by a sibling rule (e.g. exclusion, priority qualification, emergency short-circuit).
> ```yaml
> EXCEPTION: '($var->{slot_pose} // "") eq "<veto_value>"'
> ```
> The rule re-evaluates every cycle until it either fires (and writes `<veto_value>`) or its
> CONDITION is not met. Idempotence is still guaranteed: once `<veto_value>` is written, the
> rule stops.
> Use for: exclusion rules (`hors_champ`), priority overrides, hard short-circuits that must
> take precedence over any earlier classification.
>
> ⚠️ **Never use Pattern 1 (`defined`) for a veto rule** — if a sibling rule fires first in
> an earlier cycle, the veto rule will be permanently blocked and the exclusion never applied,
> even though the engine replays all rules in subsequent cycles.

### ACTION — Syntaxes

```yaml
# Single instruction
ACTION: "$frame->increase; 1"

# Multi-line (use | not >)
ACTION: |
  my $W = $p->get('width') * $p->get('height') ** 2 / 6;
  $p->set('sigma_m', $M / $W);
  1

# Sequential list
ACTION:
  - '$p->set("step1", "y")'
  - '$p->set("done", "y"); 1'
```

> **`return 0` vs `return 1` — engine convergence mechanism:**
> - `return 1` (or any truthy value) → "this rule produced an effect this cycle". The engine
>   records a productive step and schedules a new cycle after all rules have been tried.
> - `return 0` (or any falsy value) → "nothing was done this time". The rule does not
>   contribute to cycle productivity. If **all** rules return 0 in a cycle, the engine stops
>   (convergence: no further progress is possible).
>
> This is the root cause of the **"conditional ACTION without else" pitfall**:
> ```yaml
> # ⛔ WRONG — always returns 1, even when nothing was written → infinite loop
> ACTION: |
>   if ($p->get('val') > 5) { $p->set('flag', 'KO') }
>   1
>
> # ✅ CORRECT — returns 1 only when a slot was actually written
> ACTION: |
>   if ($p->get('val') > 5) { $p->set('flag', 'KO'); return 1 }
>   0
> ```
> A rule that unconditionally returns `1` without writing any slot keeps the engine cycling
> indefinitely until `_MAX_CYCLES` is reached — with no meaningful output.

> ⚠️ Last instruction must return a truthy value **only when the rule has done useful work**.
> Use `|` (newlines preserved), never `>`.

### Convention — Motif pour CONFORME (règles numériques) (ENG-063)

> **Règle obligatoire** : toute règle dont l'EFFET compare une valeur déclarée à un seuil
> réglementaire (`$val >= $seuil`, `$val <= $seuil`) **doit** renseigner son slot `motif_*`
> pour **tous** les verdicts, y compris CONFORME.

**Pourquoi :** un rapport avec MOTIF vide sur les éléments CONFORME n'est pas traçable —
l'instructeur ne peut pas vérifier quelle valeur a été prise en compte ni quel seuil a été appliqué.

**Pattern de référence :**

```perl
# ✅ CORRECT — motif renseigné pour tous les verdicts
if ($val <= $seuil) {
  $f->set('verdict_X', 'CONFORME');
  $f->set('motif_X',
    sprintf("val = %.1f unité ≤ %d unité requis (%s)", $val, $seuil, $corpus_ref));
} else {
  $f->set('verdict_X', 'NON_CONFORME');
  $f->set('motif_X',
    sprintf("val = %.1f > %d exigé par %s — dépassement de %.1f", $val, $seuil, $corpus_ref, $val - $seuil));
}

# ✅ CORRECT — règle multi-critères (accumulator @non_confs)
# Construire @conf_items en parallèle pour le motif CONFORME
my @conf_items;
if (defined $largeur && $largeur >= $seuil_larg) {
  push @conf_items, sprintf("largeur %.2f m ≥ %.2f m", $largeur, $seuil_larg);
}
# ... autres critères ...
if (@non_confs) {
  $f->set('verdict_X', 'NON_CONFORME');
  $f->set('motif_X', join('; ', @non_confs));
} else {
  $f->set('verdict_X', 'CONFORME');
  $f->set('motif_X',
    (@conf_items ? join('; ', @conf_items) . " ($corpus_ref)"
                 : "$corpus_ref — critères vérifiés satisfaits"));
}
```

**Règles de référence (pattern déjà correct) :**
`R04-equipements`, `R02-isolement-aerien`, `R03-bruits-choc`, `R05-isolement-exterieur`
(sandbox `03b-contruction-bois-HABITATION`).

**Exceptions légitimes** (motif CONFORME non requis) :

| Cas | Raison |
|---|---|
| Règles de lookup / classification (Euroclass → M, etc.) | Pas de valeur mesurée vs seuil |
| Règles d'agrégation (`R06-finalisation-verdict`, `worst-verdict`) | Pas de comparaison directe sur Frame |
| Règles de publication BOARD | Pas de verdict sur Frame |
| Règles de ciblage / gate | Ne produisent pas de verdict final |

> **Détection automatique :** `chorus-audit-rules Phase 3.23` signale en 🟡 MINOR
> les règles numériques sans motif CONFORME. `chorus-feed` Phase 5 inclut ce point
> dans sa checklist de génération.

### Convention — `caveat_motif` pour réserve non bloquante sur CONFORME (ENG-071)

> **Règle obligatoire** : toute règle qui qualifie un verdict **CONFORME** par une
> **réserve non bloquante** (recommandation non suivie, condition optimale non remplie,
> amélioration possible mais non exigée pour la conformité) **doit** écrire cette réserve
> dans un slot dédié `caveat_motif` (ou `caveat_motif_<aspect>` si plusieurs réserves
> distinctes coexistent sur le même Frame) — **jamais** la concaténer dans `motif`/`motif_<aspect>`.

**Pourquoi :** `motif`/`motif_*` est lu par le webapp (`elementMotif()`) comme la
**justification du verdict**. Une réserve textuelle appendue au même champ
(`"... — RègleX non satisfaite sans Y déclaré"`) est indiscernable, à la lecture, d'une
raison d'échec réelle — alors que l'élément reste CONFORME. Ce défaut de présentation a
été identifié sur `08-ANSSI-PG-083-CENTRIC` (R06/R07 `crypto-mecanismes-asym` —
`RèglePQSécuAsym non satisfaite sans hybridation post-quantique déclarée` appendue au
motif d'éléments verdict=CONFORME) et corrigé côté webapp par une heuristique
(`splitMotifCaveat`, ENG-071-webapp) — mais cette heuristique est un filet de sécurité
pour le contenu legacy déjà écrit, pas une excuse pour continuer à écrire des réserves
de cette façon dans les nouvelles règles.

**Distinction avec ENG-063 :** ENG-063 impose qu'un `motif_*` existe sur CONFORME
(traçabilité valeur/seuil). ENG-071 impose que, si ce motif CONFORME doit en plus porter
une réserve non bloquante, cette réserve aille dans un slot séparé — les deux conventions
sont cumulatives, pas substituables.

**Pattern de référence :**

```perl
# ⛔ WRONG — réserve concaténée au motif principal
if ($conforme && $entry->{necessite_hybridation_pq} && !$f->{hybridation_pq_associee}) {
  $motif .= ' — RèglePQSécuAsym non satisfaite sans hybridation post-quantique déclarée';
}
$f->set('motif', $motif);

# ✅ CORRECT — réserve isolée dans son propre slot
$f->set('motif', $motif);   # justification pure du verdict CONFORME
if ($conforme && $entry->{necessite_hybridation_pq} && !$f->{hybridation_pq_associee}) {
  $f->set('caveat_motif',
    'RèglePQSécuAsym non satisfaite sans hybridation post-quantique déclarée');
}
```

**Côté webapp (contrat) :** `caveat_motif` (et toute variante `caveat_motif_<aspect>`)
est affiché séparément du motif principal, visuellement atténué (badge `⚠️ réserve`),
jamais fusionné dans la colonne MOTIF comme texte de justification.

**Détection automatique :** `chorus-audit-rules` devrait signaler (checklist à
compléter — non encore implémenté au moment de la rédaction de cette convention) tout
`motif`/`motif_*` dont le texte, sur une branche verdict CONFORME, contient un pattern
de réserve textuelle (`non satisf`, `non respect`, `requise? pour`, `non conforme`) sans
`caveat_motif` renseigné en parallèle.

### TERMINAL — Automatic Termination

```yaml
RULE: all-processed
FIND:
  p:
    attribut: status
TERMINAL: solved
EXCEPTION: '$p->{status} ne "FINAL"'
ACTION: "1"
```

- `TERMINAL: solved` — fires when the rule matches and `_APPLY` returns true → reliable, idiomatic.
- `$SELF->solved()` in ACTION — also valid: `$SELF` inside a YAML ACTION is the agent (Engine), so `$SELF->solved()` correctly sets `BOARD->{SOLVED}`. Can be combined with `TERMINAL: solved` or used alone.
- ⛔ **Never** use a global `fmatch` in a YAML `FIND`/`CHERCHER` block for a termination rule → guaranteed infinite loop. Use `fmatch` in `EXCEPTION`/`CONDITION` only (safe — not bound).

### Pattern TERMINAL multi-agent — CONDITION groupe vide (ENG-055)

Dans un pipeline multi-agents, la règle TERMINAL doit pouvoir traiter des **projets
partiels** (ne contenant pas tous les types d'éléments). La CONDITION doit être satisfaite
même si un groupe de types est absent du projet — sinon la règle attend indéfiniment un
BOARD verdict qui ne sera jamais publié (aucun élément de ce type → aucune règle ne se
déclenche pour ce groupe → son BOARD verdict reste undef → TERMINAL bloqué).

**Pattern canonique — CONDITION groupe vide :**

```yaml
REGLE: r-termination-pipeline

CHERCHER:
  tout:
    attribut: type_element

EXCEPTION: '($SELF->BOARD && defined $SELF->BOARD->{pipeline_solved})'

CONDITION: |
  do {
    my $b   = $SELF->BOARD // {};
    my @all = Chorus::Frame::fmatch(slot => 'type_element');

    # Pour chaque groupe d'agents : vrai si groupe VIDE ou si BOARD verdict défini.
    # Un groupe vide signifie qu'aucun élément de ce type n'est présent dans le projet
    # → la condition est satisfaite sans attendre un verdict qui ne viendra jamais.
    my @grp1 = grep { ($_->get('type_element') // '') =~ /^(type_a|type_b)$/ } @all;
    my @grp2 = grep { ($_->get('type_element') // '') =~ /^(type_c|type_d)$/ } @all;
    # ... un groupe par agent/domaine ...

    (!@grp1 || defined $b->{verdict_agent_1})
    && (!@grp2 || defined $b->{verdict_agent_2})
    # ... && pour chaque groupe ...
  }

EFFET: |
  my $trace = $tout->get('_rule_trace') // [];
  unless (grep { ($_->{rule_id} // '') eq 'r-termination-pipeline' } @$trace) {
    push @$trace, {
      rule_id    => 'r-termination-pipeline',
      corpus_ref => 'pipeline — agrégation finale tous agents'
    };
    $tout->set('_rule_trace', $trace);
  }
  $SELF->BOARD->{pipeline_solved} = 1;
  $SELF->solved();
  1
```

**Propriétés du pattern :**

| Propriété | Mécanisme |
|---|---|
| **Idempotence** | `EXCEPTION: defined $SELF->BOARD->{pipeline_solved}` — ne se déclenche qu'une fois |
| **Projet partiel** | `!@grp || defined $b->{verdict}` — groupe vide → condition vraie sans attendre |
| **Traceability** | `_rule_trace` push avec guard `unless grep` — évite le flood si la règle tentait de refirer |
| **Un seul déclenchement** | BOARD `pipeline_solved` + `$SELF->solved()` — arrêt immédiat après le premier appel |

> **Placement :** cette règle doit être dans le répertoire du **dernier agent**
> (`#+PIPELINE_POS` le plus élevé dans `index.org`), numérotée en dernier
> (ex. `R06-termination-pipeline.yml` si R05 est la dernière règle métier).

> **Génération automatique :** `chorus-feed` Phase 5.9 génère cette règle automatiquement
> à la fin de chaque Mode A ou Mode B si aucun `->solved()` ni `TERMINAL: solved` n'est
> présent dans le sandbox (ENG-055). Vérifier via `chorus-check Step 5f` après génération.

### ⛔ Pitfall — BOARD-publishing rule must guard against self-refiring

> Any rule whose `ACTION` publishes a BOARD flag (`$SELF->BOARD->{<flag>} = 1`
> or `$SELF->BOARD->set('<flag>', 1)`) — typically a "mark phase done" rule
> aggregating many Frames, used **without** the literal `TERMINAL:` key (e.g.
> it only marks a phase done for other agents to consume, it does not itself
> terminate the whole pipeline) — **must** include a guard in its
> `EXCEPTION`/`CONDITION` testing whether the flag has already been published,
> in addition to the aggregation condition itself:

```yaml
RULE: mark-phase-done
FIND:
  e:
    attribut: type_element
EXCEPTION: |
  defined $SELF->BOARD->{phase_done}
  || scalar(grep { !defined $_->{status} } Chorus::Frame::fmatch(slot => 'type_element')) > 0
ACTION: "$SELF->BOARD->{phase_done} = 1;"
```

- Without the `defined $SELF->BOARD->{phase_done} ||` short-circuit, once the
  aggregation condition becomes permanently true (the expected, normal
  mid-pipeline state), the `ACTION` **re-fires on every single engine cycle,
  forever** — burning CPU/memory until `_MAX_CYCLES` (default 10000) per such
  rule. Across a multi-agent pipeline this multiplies: N agents with this bug
  ≈ N × up-to-10000 wasted cycles.
- This degrades **100% silently**: no crash, no `loadRules()` warning (the
  flag genuinely is a valid BOARD write), no stderr — the only symptom is a
  hung/slow pipeline with climbing memory and no progression in the output.
- Distinct from a genuine `TERMINAL: solved`/`failed` rule (which the Engine's
  own `applyrules()` stops re-evaluating once fired) — this guard is only
  needed for BOARD-publishing rules that are **not** the pipeline's literal
  termination rule.
- `chorus-check.md § Step 5i` scans for this mechanically — but the guard
  should be authored correctly from the start by `chorus-feed`, not left to
  be caught/retrofitted at check time.

> **Incident:** a batch of `mark-phase-done-and-terminate`
> rules (one per SFR/SAR class agent) were generated without this guard —
> each re-fired every cycle once its aggregation condition stabilized,
> producing a cumulative 13+ minute hang on `chorus-check`'s own smoke test.
> Fixed by adding the `defined $SELF->BOARD->{<flag>} ||` short-circuit to all
> 19 `EXCEPTION` blocks. See `chorus-check.md § Step 5i` for the full writeup
> and the mechanical scan now guarding against recurrence.

### ⛔ Pitfall — Worst-verdict BOARD : initialisation bloquée par `// 'CONFORME'` (ENG-053)

> **Symptôme :** un slot BOARD (ex. `verdict_acoustique`, `verdict_facades`) n'est
> jamais initialisé malgré le traitement correct de toutes les Frames du groupe.
> La règle TERMINAL attend ce BOARD slot → pipeline timeout à `_MAX_ITER` sans SOLVED.
> Le bug ne se manifeste que lorsque **tous** les verdicts du groupe sont CONFORME —
> cas courant sur les premiers projets de test ou les sandboxes neufs.

**Cause :** le défaut `// 'CONFORME'` dans la comparaison worst-verdict initialise
`$board_verdict` à 'CONFORME' (priorité 0) même quand le BOARD n'est pas encore défini.
Un verdict CONFORME (priorité 0) ne satisfait jamais `0 > 0` → le BOARD n'est jamais écrit.

```perl
# ⛔ CASSÉ — BOARD jamais initialisé si tous les verdicts sont CONFORME
my $board_verdict = $SELF->BOARD->{verdict_xxx} // 'CONFORME';   # ← défaut erroné
my %prio = (NON_CONFORME => 2, _a_confirmer => 1, CONFORME => 0);
if (($prio{$verdict} // 0) > ($prio{$board_verdict} // 0)) {
    $SELF->BOARD->{verdict_xxx} = $verdict;
}
# → quand verdict='CONFORME' : (0 > 0) = FALSE → BOARD jamais écrit

# ✅ CORRECT — initialise si absent, upgrade si verdict plus mauvais
my %prio = (NON_CONFORME => 2, _a_confirmer => 1, CONFORME => 0);
if (!defined $SELF->BOARD->{verdict_xxx}
    || ($prio{$verdict} // 0) > ($prio{$SELF->BOARD->{verdict_xxx}} // 0)) {
    $SELF->BOARD->{verdict_xxx} = $verdict;
}
```

**Pattern affecté (récurrent dans les règles publication-board) :**

Toute règle qui accumule un verdict "pire-cas" sur BOARD (un résultat global issu
de N Frames individuelles) doit utiliser ce pattern. La distinction est :

| Situation | Test correct |
|---|---|
| Premier Frame du groupe | `!defined $SELF->BOARD->{slot}` → toujours initialiser |
| Frames suivantes | `> (priorité du BOARD existant)` → upgrade si pire |

> `chorus-check.md § Step 5o` scanne `// 'CONFORME'` dans les comparaisons BOARD
> pour détecter ce pattern mécaniquement.

> **Incident :** session 2026-11-14, sandbox `03b-contruction-bois-HABITATION` —
> `BOARD:verdict_acoustique` jamais initialisé malgré 2 Frames acoustiques CONFORME
> traitées. Pipeline FAILED/TIMEOUT à `_MAX_ITER=200`. Découvert par inspection
> directe du BOARD après ajout d'instrumentation.

### ⛔ Pitfall — multi-line `EXCEPTION`/`CONDITION` must be a single expression (wrap in `do {}`)

> `Chorus::Engine::codeRule()` compiles a rule's `EXCEPTION` field into
> **exactly one Perl statement**: `return if <EXCEPTION_TEXT>;` (symmetrically,
> `CONDITION` becomes `return unless <CONDITION_TEXT>;`). If the YAML
> `EXCEPTION`/`CONDITION` block spans multiple logical Perl statements — most
> commonly an intermediate `my @var = ...;` assignment on its own line,
> followed by the real boolean test on subsequent lines — **only the FIRST
> statement is ever actually guarded**. Perl parses `return if my @var = grep
> {...}` as the complete guarded expression (the assignment's own truthiness,
> which is simply "is @var non-empty?" — almost always true), and every
> following line becomes an orphaned, unguarded statement whose result is
> silently discarded.

```yaml
# ⛔ WRONG — the assignment line is the ONLY thing `return if` actually tests;
# the real boolean test below it is evaluated but discarded, every time:
EXCEPTION: |
  my @targets = grep { ($_->{type_element} // '') eq 'evaluation_class' }
                Chorus::Frame::fmatch(slot => 'type_element');
  scalar(@targets) == 0
  || scalar(grep { !defined $_->get('_verdict_processed') } @targets) > 0

# ✅ CORRECT — wrap the whole computation in `do { ... }`, whose own
# last-expression-returns-value semantics make it a single statement:
EXCEPTION: |
  do {
    my @targets = grep { ($_->{type_element} // '') eq 'evaluation_class' }
                  Chorus::Frame::fmatch(slot => 'type_element');
    scalar(@targets) == 0
    || scalar(grep { !defined $_->get('_verdict_processed') } @targets) > 0
  }
```

- **Symptom:** a Perl warning `Useless use of numeric gt (>) in void context`
  (or similar "useless use of X in void context" for whichever comparison/
  expression sits on the orphaned line) printed once per rule load — easy to
  miss among dozens of harmless `redefined`-style warnings on a multi-agent
  pipeline. The rule itself never crashes and never reports an error — it
  simply never fires its intended guard logic.
- **For a `TERMINAL: solved`/`failed` rule specifically**, this is catastrophic:
  the termination condition can never become false (the bogus "guard" — the
  bare assignment — is true as soon as the target Frame set is non-empty,
  regardless of whether every Frame has actually been processed), so the rule
  silently refuses to ever `return if` *correctly* and its `ACTION`/`TERMINAL`
  never fires — the whole pipeline loops until `Chorus::Expert`'s
  `_MAX_ITER` ceiling, reported as `process() reached max iterations without
  SOLVED or FAILED`, with every downstream agent showing "LOOPING" every
  cycle with no visible progress.
- **Rule of thumb:** any `EXCEPTION`/`CONDITION` body that needs an
  intermediate variable before its final boolean test **must** be wrapped in
  a single `do { ... }` block, with the boolean test as the block's last
  expression. Never leave a leading `my $var = ...;` (or any other complete
  statement) as a bare top-level line before the real test — only the first
  statement in a multi-line `EXCEPTION`/`CONDITION` is ever actually guarded.
- `chorus-feed` should author multi-line `EXCEPTION`/`CONDITION` bodies with
  this `do {}` wrapper from the start whenever more than one logical
  statement is needed — do not rely on a later `chorus-check`/manual-review
  pass to catch it; unlike the missing-guard pitfall above, this failure mode
  produces **no loadRules() warning that names the rule** (only a generic,
  easy-to-miss Perl `void context` warning at compile time), making it
  significantly harder to retrofit-detect mechanically.

> **Incident:** sandbox `06-CC-3.1.5`, `R11-pipeline-termination.yml`
> (`agent-ate-ava-aco`) — the rule's `EXCEPTION` started with
> `my @targets = grep {...};` as its own line, followed by the real
> `scalar(@targets) == 0 || scalar(grep {...}) > 0` test. Every project file
> containing at least one `evaluation_class` Frame (`project-cross.json`,
> `project-edges.json`, `project-rules-iso.json`) hung at
> `Chorus::Expert`'s 200-iteration ceiling — `TERMINAL: solved` never fired
> despite every `evaluation_class` Frame genuinely reaching
> `_verdict_processed = 1`. Fixed by wrapping the EXCEPTION body in `do {}`
> (2026-11-06) — see `.last-fix-history.json § engine_infra_fix_detail` in
> that sandbox for the full investigation writeup.

> **Applies equally to `CONDITION`** — `codeRule()` compiles it into the
> symmetric single statement `return unless <CONDITION_TEXT>;`, via the exact
> same `setCondition()`/`join("\n      or ", ...)` mechanism as `EXCEPTION`'s
> `setException()`. A `CONDITION` block with a bare `my @var = ...;` line
> followed by the real boolean test suffers the identical silent-discard
> failure mode. **Does not apply to `ACTION`/`EFFET`**: `setEffect()` joins
> each statement explicitly with `;\n` (`# ET séquentiel` in `Engine.pm`), so
> a multi-line `ACTION` is compiled as genuinely sequential Perl statements —
> no `do {}` wrapper needed there.

> **Mechanical guard (added 2026-11-06, `Chorus::Engine::_check_multistatement_guard()`,
> called from `loadRules()` alongside the existing `_check_guard_coherence()`):**
> any `EXCEPTION`/`CONDITION` body containing an internal `;` (i.e. more than
> just a single optional trailing one) and not already wrapped in a top-level
> `do { ... }` now emits a `warn` at load time:
> ```
> [Chorus::Engine] MULTI-STATEMENT GUARD in rule '<name>' (<file>.yml)
>   EXCEPTION spans multiple Perl statements but is not wrapped in do { ... }
>   ...
> ```
> This is a regex heuristic (not a true Perl parse), but it mirrors exactly
> the shape of the real incident and is tuned to zero false positives across
> the 52 production rules in sandbox `06-CC-3.1.5` (including the now-fixed
> `R11-pipeline-termination.yml` and every idempotence-guard one-liner). Like
> `_check_guard_coherence()`, it only `warn`s — it never blocks `loadRules()`.
> Treat any occurrence of this warning as a build-breaking issue to fix
> immediately, the same way `GUARD MISMATCH` warnings are treated.

### ⛔ Pitfall — `CONDITION: do {` sans `|` : YAML plain scalar tronqué (ENG-051)

> **Symptôme :** règle chargée par `loadRules()` (comptée dans `_RULES`), aucun message
> d'erreur, mais ne se déclenchant **jamais**. Le seul indice visible est un warning
> `Use of uninitialized value in concatenation (.) or string at Chorus/Engine.pm line 620`
> passé inaperçu parmi d'autres warnings de chargement.

**Cause :** en YAML, un scalaire brut multi-lignes (`CONDITION: do {`) dont la ligne
de fermeture `}` est à indentation zéro est **tronqué** par le parser — le `}` fermant
n'est pas inclus dans la valeur. `codeRule()` reçoit un bloc `do {` incomplet, génère
du Perl syntaxiquement invalide, retourne `undef`, et l'eval produit `$SELF->addrule()`
sans arguments — une règle vide qui ne s'applique à aucun Frame.

```yaml
# ⛔ CASSÉ — YAML plain scalar tronqué (closing } absent → Perl syntax error)
CONDITION: do {
  defined $f->get('nb_niveaux')
    || defined $f->get('hauteur_plancher_bas_m')
}
# Le parser YAML lit : "do {\n  defined $f->get('nb_niveaux')\n    || ..."
# La ligne "}" seule à colonne 0 termine le scalaire AVANT d'être incluse.

# ✅ CORRECT — indicateur | (literal block scalar) oblige le parser à tout inclure
CONDITION: |
  do {
    defined $f->get('nb_niveaux')
      || defined $f->get('hauteur_plancher_bas_m')
  }
```

**Formes autorisées pour `CONDITION` et `EXCEPTION` :**

| Cas | Forme correcte | Exemple |
|---|---|---|
| Expression courte (1 ligne) | Quoted scalar `'...'` | `CONDITION: 'defined $f->{slot}'` |
| Bloc multi-lignes avec `do {}` | Literal block `\|` | `CONDITION: \|` + bloc indenté |
| Expression longue sans `do {}` | Literal block `\|` | `CONDITION: \|` + expression |

> ⛔ **Règle stricte :** toute `CONDITION:` ou `EXCEPTION:` dont la valeur contient un
> `do {`, un `if (`, ou tout autre bloc Perl multi-lignes **DOIT** utiliser `|` comme
> indicateur de scalaire. Ne jamais écrire `CONDITION: do {` sans `|`.
>
> **Détection :** `chorus-check Phase 1.5 Step 5n` (ENG-051) scanne
> `^CONDITION: [^|'"]` dans tous les fichiers `.yml` — toute correspondance est un bug.

> **Incident :** session 2026-11-14, sandbox `03b-contruction-bois-HABITATION` —
> 5 règles brisées silencieusement (R01/R02/R06/R07 agent-securite-incendie-facades,
> R03 agent-reaction-feu), l'agent entier ne produisant aucun résultat. Découvert
> uniquement par debuggage exhaustif après constat que `famille_resolue` restait
> `undef` malgré le feed correct.

### ⛔ Pitfall — Helper namespace collision via glob-aliasing (`Chorus::Engine`)

Each `AgentXxx.pm` injects its Helpers into the shared `Chorus::Engine` package:
```perl
{ no strict 'refs'; *{'Chorus::Engine::my_helper'} = \&my_helper; }
```
This design is **intentional** — any agent can expose functions to YAML rules without
modifying `Chorus::Engine.pm`. However, Perl overwrites a typeglob silently: if two
agents both inject a function under the same name, the second agent's closure **replaces**
the first's with no warning. The displaced agent then calls the wrong closure — one that
references internal data structures (lookup tables, `%FAMILY_MAP`) from the other agent —
producing silently wrong verdicts and an undiagnosable `process() reached max iterations`
stall (identical symptom to a broken `TERMINAL: solved` rule, with no stack trace and
no warning pointing to the collision).

**Rule — ENG-032 (option 2):** every Helper function name MUST be **prefixed with the
agent slug** to guarantee global uniqueness across the whole sandbox:

```
⛔  WRONG : class_family_completion_status($class_type, $e)
✅  CORRECT: adv_agd_alc_family_completion_status($class_type, $e)
            ^^^^^^^^^^^^^^^^^^ agent slug prefix
```

The prefix is derived mechanically from the agent's directory slug (the base name of its
`rules/<slug>/` directory, with hyphens replaced by underscores). No other agent will ever
define a function with the same prefix — uniqueness is structural, not relying on review.

**Checklist** (see `### ✅ Multi-Specialty Architecture` below):
- Every sub in `Helpers.pm` is prefixed `<slug>_`.
- The corresponding YAML `ACTION` calls match — `<slug>_my_helper(...)`.
- `chorus-check` Step 5m (pre-Phase 2) scans for unqualified names shared between agents.

> **Incident:** sandbox `06-CC-3.1.5` (2026-11-06) — `chorus-feed --enrich` Gap #2
> added `class_family_completion_status()` independently to two agents in the same
> pass. The second agent's closure silently replaced the first's; every
> `evaluation_class` Frame in the displaced agent received a spurious `(\@pending=[],
> \@failed=[])` verdict, stalling `Chorus::Expert` at `_MAX_ITER`. Retrospective fix:
> renamed to `adv_agd_alc_family_completion_status()` and
> `ate_ava_aco_family_completion_status()`.

> **No mechanical guard exists in the engine** for this failure class (unlike
> `_check_multistatement_guard()` / `_check_guard_coherence()` which catch YAML rule
> bugs at `loadRules()` time — see pitfall above). Prevention is entirely at the
> authoring / generation level (option 2) and at the pre-build scan level (option 3
> via Step 5m in `chorus-check.md`).

---

### Loading Order

`loadRules($dir)` loads `*.yml` files in **alphabetical order** → name files `R01-`, `R02-`, etc.

Multiple directories = multiple `loadRules()` calls.

### PREMISES — for reorder()

> ⛔ **`PREMISES` values MUST be simple Perl identifiers (slot names) — never natural language.**
> `loadRules()` compiles each PREMISES list item as a **bare Perl hash key**:
> `_PREMISSES => { item1 => 'Y', item2 => 'Y' }`.
> A multi-word phrase like `"protection_pipeline_done is set on BOARD by agent-scope R05"`
> produces `Bareword "is" not allowed` / `syntax error` at eval time — silent rule load failure,
> that rule is simply skipped with a warning.
>
> **⛔ WRONG — natural language descriptions (bareword compile error):**
> ```yaml
> PREMISES:
>   - protection_pipeline_done is set on BOARD by agent-scope R05
>   - this rule gates the entire agent-permitted-use processing
> ```
> **✅ CORRECT — simple slot names only (or omit PREMISES entirely):**
> ```yaml
> PREMISES:
>   - protection_pipeline_done
>   - besoin_permitted_use
> ```
> **Preferred when no `reorder()` is needed: omit `PREMISES` entirely.**
> `PREMISES` is metadata for `reorder()` only — `applyrules()` ignores it at runtime.
> Write the actual prerequisite logic in `CONDITION`, not in `PREMISES`.
> See **ADR-001** (`agent/kb/decisions/ADR-001.org`) for the full rationale.

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

## Rule Documentation Standard

> **Mandatory for every generated YAML rule.**
> The header language must match the corpus language:
> English header for an English corpus, French header for a French corpus.
> Adapt the field labels accordingly (see both templates below).

### Header template — English corpus

```yaml
##
# RULE: <R0N-rule-slug>
# AGENT: <Namespace>::Agent::<Name>  (pos. N / total)
# CORPUS: §<N> — <standard/document> — <section title>
#
# PURPOSE
#   <One or two sentences describing what this rule checks and why.>
#   <Mention element types in scope if the rule is type-restricted.>
#
# INPUTS  (slots read)
#   <targeting_slot>  : targeting slot — set by <feed | previous agent RNN>
#   <slot_a>          : <type and meaning, e.g. "float — measured deflection in mm">
#   <slot_b>          : <allowed values or range>
#
# OUTPUTS (slots written)
#   <result_slot>     : <"OUI"/"NON", "OK"/"KO", or any domain value> — result of this rule
#   <targeting_slot>  : deleted after processing (consumed targeting slot)
#
# HELPERS  (omit section if none)
#   <helper_name>(<args>)  → <return type and meaning>
#
# GUARD — EXCEPTION: defined $<var>->{<slot_set>}
#   Idempotence — prevents re-processing a Frame already handled in a previous cycle.
##
```

### Header template — French corpus

```yaml
##
# REGLE: <R0N-slug-regle>
# AGENT: <Namespace>::Agent::<Nom>  (pos. N / total)
# CORPUS: §<N> — <norme/document> — <titre section>
#
# OBJECTIF
#   <Une ou deux phrases décrivant ce que vérifie cette règle et pourquoi.>
#   <Mentionner les types d'éléments en scope si la règle est restreinte par type.>
#
# ENTRÉES  (slots lus)
#   <slot_ciblage>    : slot de ciblage — posé par <feed | agent précédent RNN>
#   <slot_a>          : <type et signification, ex. "float — flèche mesurée en mm">
#   <slot_b>          : <valeurs admises ou plage>
#
# SORTIES  (slots écrits)
#   <slot_resultat>   : <"OUI"/"NON", "OK"/"KO", ou valeur domaine> — résultat de la règle
#   <slot_ciblage>    : supprimé après traitement (slot de ciblage consommé)
#
# HELPERS  (supprimer la section si aucun)
#   <nom_helper>(<args>)  → <type retour et signification>
#
# GARDE — EXCEPTION: defined $<var>->{<slot_pose>}
#   Idempotence — évite de retraiter un Frame déjà traité lors d'un cycle précédent.
##
```

### Inline comment rules (ACTION / EFFET body)

- **Group** the code into logical blocks with a one-line comment per block.
- **Annotate every early `return`**: explain *why* the Frame is skipped (out-of-scope type, missing data, etc.).
- **Mark slot writes** that produce the targeting slot for the next agent.
- **Reference the corpus** (§N) on the line that encodes a normative threshold.

```yaml
# English example
ACTION: |
  # Read input slots
  my $val  = $p->get('measured_value');
  return 0 unless defined $val;      # slot absent → frame out of scope, skip silently

  # Normative check — §4.2
  my $min = _min_required($p->get('element_type'));
  return 0 unless defined $min;      # element type not covered by this rule → skip

  # Write result
  if ($val < $min) {
    $p->set('result_ok', 'NON');
    $p->set('rejection_reason', "value $val < min $min (§4.2)");
    return 1;
  }
  $p->set('result_ok', 'OUI');
  return 1;
```

```yaml
# French example
EFFET: |
  # Lecture des slots d'entrée
  my $val  = $p->get('valeur_mesuree');
  return 0 unless defined $val;      # slot absent → frame hors scope, ignoré silencieusement

  # Vérification normative — §4.2
  my $min = _seuil_min($p->get('type_element'));
  return 0 unless defined $min;      # type non couvert par cette règle → ignoré

  # Écriture du résultat
  if ($val < $min) {
    $p->set('resultat_ok', 'NON');
    $p->set('motif_refus', "valeur $val < min $min (§4.2)");
    return 1;
  }
  $p->set('resultat_ok', 'OUI');
  return 1;
```

> **⚠️ Language rule — inline comments:** all comments inside `ACTION`/`EFFET` blocks must be
> written in the **corpus language** (English for an English corpus, French for a French corpus).
> The two examples above illustrate this rule — the English and French blocks are mutually exclusive
> depending on the corpus language; never mix languages within a single sandbox.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

> **CORPUS line:** when the rule encodes a single standard article, one `CORPUS:` line suffices.

> **Aggregation rules without a named normative reference:** some rules aggregate
> sub-verdicts (e.g. `aggregate-verdict`, `publish-taille-min`) without a
> single normative article to cite. In this case, the `CORPUS:` header **must**
> carry an explicit justification comment rather than being left vague or omitted:
>
> ```yaml
> # CORPUS: agrégation interne — pas de règle normative nommée
> #         (synthèse des verdicts R01-R04, aucun §-ref direct dans le corpus)
> ```
>
> This annotation is mandatory for diagnosability: without it, a
> `chorus-strengthen` gap on this rule cannot be traced back to a corpus
> section — the analyst has no starting point to determine whether the
> aggregation logic is correct. A vague `# CORPUS: §2.1 — agrégation` that
> cites a section but claims no named rule is equivalent to an absent reference
> and must be replaced with the explicit form above.

> When the rule combines several articles, list them all:
> ```yaml
> # CORPUS: §4.2 — NF DTU 31.2 — Section minimale montant porteur
> #          §A.2 — NF DTU 31.2 — Annexe A — Tableaux dimensionnels
> ```

---

## Advanced Mechanisms — See also

For advanced patterns using procedural slots (_AFTER, _BEFORE, _NEEDED, _REQUIRE),
prototype selection (fselect), and inheritance modes, see **`chorus-frame-advanced.md`**.

This section covers the most important cases:

- **§ fselect — Prototype Selection** — scoring-based Frame matching for Pattern B (_ISA via prototypes)
- **§ _TERMINAL_SLOTS / complete()** — Frame validation before pipeline execution
- **§ Inheritance Modes N vs Z** — default behavior and implications for _DEFAULT/_NEEDED resolution

---

## fselect — Prototype Selection (Pattern B)

> See also: `chorus-frame-advanced.md § fselect`.

**Use case:** Select the best-matching Frame from a catalog of prototypes based on observed properties.
This implements Minsky's frame-selection mechanism for domain diagnosis.

### Basic syntax

```perl
# Best match (highest score)
my $proto = fselect(wood_class => 'oak', hardness => 'high');

# All candidates ranked by descending score
my @ranked = fselect(wood_class => 'oak', _all => 1);

# Restrict to a prototype and its declared _ALTERNATIVES (frame network)
my $proto = fselect(wood_class => 'oak', _alternatives => $Bird);

# Restrict search space to a subset of Frames
my $proto = fselect(wood_class => 'oak', _from => \@candidates);

# Accept zero-score matches
my @all = fselect(wood_class => 'oak', _all => 1, _min => 0);
```

### Pattern B in Feed.pm — Automatic _ISA injection

When `chorus-feed` builds a project Frame from JSON, it calls `fselect` to find
the best-matching prototype from a static catalog and injects it via `_ISA`:

```perl
# In chorus-check → Feed.pm load_projet()
my $proto = fselect(
    wood_class => $project_frame->get('wood_class'),
    treatment  => $project_frame->get('treatment'),
    _from      => \@normatif_catalog
);
$project_frame->set('_ISA', $proto) if $proto;
```

Result: the project Frame inherits all normative thresholds from its matched prototype.

### Scoring rules

For each candidate Frame in the pool:
- **+1 point** for each slot where the Frame provides the slot AND the resolved value matches the observation
- **Score < 1** (no matches): excluded by default (pass `_min => 0` to include)
- **Best candidate** returned by default; use `_all => 1` to get all ranked candidates

### Common pitfall — unreachable prototypes

If all prototypes score 0, the Frame inherits nothing. To debug:

```perl
# Log the scores for all candidates
my @ranked = fselect(wood_class => 'oak', _all => 1, _min => 0);
for my $proto (@ranked) {
    my $score = ...;  # score not directly accessible — check by re-running with test values
    print "Proto " . $proto->get('id') . " scored $score\n";
}
```

---

## _TERMINAL_SLOTS / complete() — Frame Validation

> See also: `chorus-frame-advanced.md § _TERMINAL_SLOTS / complete()`.

**Use case:** Declare which slots must contain actual data (`_VALUE`) for a Frame
to be considered "complete" in the sense of Minsky's frame model.
Used to validate that a project Frame has been sufficiently populated before execution.

### Basic syntax

Declare terminal slots on a prototype:

```perl
my $proto = Chorus::Frame->new(
    _TERMINAL_SLOTS => ['color', 'size', 'weight'],
);
```

Check if an instance is complete:

```perl
my $instance = Chorus::Frame->new(
    _ISA   => $proto,
    color  => 'red',
    size   => 'large',
    weight => '500g',
);

if ($instance->complete) {
    print "Frame is complete\n";
} else {
    print "Frame is incomplete — missing a terminal slot\n";
}
```

### In chorus-check

Before calling `$expert->process()`, validate all project Frames:

```perl
# In run.pl or chorus-check generated code
for my $elem (@$elements) {
    unless ($elem->complete) {
        warn "Element " . $elem->get('id') . " is incomplete\n";
        next;  # skip or die, depending on policy
    }
}
my $ok = $expert->process($input);
```

---

## Inheritance Modes — N vs Z

> See also: `chorus-frame-advanced.md § Inheritance Modes (N vs Z)`.

Chorus supports two modes for resolving `_VALUE`, `_DEFAULT`, and `_NEEDED` across the inheritance tree.
The default is **Mode N**.

### Mode N (Default) — Breadth-first per valuation key

Each key is searched across the **entire inheritance tree** before moving to the next key:

```
1. Look for _VALUE on (Frame, Frame._ISA, Frame._ISA._ISA, ...)
2. If not found, look for _DEFAULT on the same tree
3. If not found, look for _NEEDED on the same tree
4. If still not found, return the Frame itself
```

**Example:**

```perl
Frame A:
  ├─ _VALUE = 'v1'

Frame B (_ISA => A):
  ├─ _DEFAULT = 'v2'

Frame C (_ISA => B):
  (no _VALUE, _DEFAULT, _NEEDED)

C->get('slot') [Mode N]:
  1. search _VALUE: C (no), B (no), A (yes!) → return 'v1'
```

### Mode Z — Full sequence per frame

Each Frame tests the **full sequence** (`_VALUE → _DEFAULT → _NEEDED`) before descending to parents:

```
1. On Frame: _VALUE? _DEFAULT? _NEEDED?
2. If all absent, on Frame._ISA: _VALUE? _DEFAULT? _NEEDED?
3. Continue up the chain
```

**Example (same Frame structure):**

```perl
C->get('slot') [Mode Z]:
  1. on C: _VALUE? (no) _DEFAULT? (no) _NEEDED? (no)
  2. on B: _VALUE? (no) _DEFAULT? (yes!) → return 'v2'
```

Note the difference: **Mode N returns 'v1', Mode Z returns 'v2'** from the same Frame tree.

### Switching modes

```perl
Chorus::Frame::setMode(GET => 'N');   # Mode N (default)
Chorus::Frame::setMode(GET => 'Z');   # Mode Z
Chorus::Frame::setMode('N');          # short form
```

The mode is a **global setting** — affects all Frame `get()` calls in the application.

### When to use Mode Z

**Mode Z** is useful when:
- You have **multi-level prototypes** where each level adds a new _DEFAULT
- You want **shallower defaults** (nearest ancestor) to take precedence
- You're implementing a **DSL** where each Frame layer defines its own defaults

**Default (Mode N)** is suitable for most use cases — it prioritizes finding the _VALUE
across the full tree before falling back to _DEFAULT.

---

## Checklist — Anti-Pitfalls

> **Full checklist** (YAML rules, Frames, Multi-Specialty Architecture — with
> `# ⛔ WRONG` / `# ✅ CORRECT` patterns and incident references) — load on demand:
> `eca__read_file("$ENGINE/agent/skills/chorus-engine-yaml-pitfalls.md")`
>
> Load after YAML rule generation (`chorus-feed` Phase 4) or before a
> `chorus-audit-rules` run. Never pre-load speculatively — it is a
> post-generation reference, not a pre-generation guide.
