# Chorus::Frame — Advanced Mechanisms Reference

> **Authoritative source for advanced procedural slots and Frame mechanics.**
>
> Loaded by: `chorus-feed` (§ Procedural Slots Generation)
> Scope: patterns for `_AFTER`, `_BEFORE`, `_REQUIRE`, `_NEEDED`, `_ON_DELETE`,
> Copy-on-Write, prototype selection (fselect), Frame networks (_ALTERNATIVES),
> and inheritance modes (N vs Z).

---

## Quick Navigation

| Mechanism | Use Case | Risk Level |
|---|---|---|
| **[fselect](#fselect--prototype-selection)** | Scoring-based prototype matching | 🟡 Medium |
| **[_TERMINAL_SLOTS / complete()](#_terminal_slots--frame-validation)** | Frame completeness validation | 🟢 Low |
| **[Procedural Slots — $SELF Capture](#procedural-slots--self-capture-rules)** | _AFTER, _BEFORE, _NEEDED with context | 🔴 High |
| **[get('a b c') vs ->a->b->c](#get-path-vs-autoload)** | $SELF et `_NEEDED` diffèrent selon le style d'accès | 🔴 High |
| **[Inheritance Modes N/Z](#inheritance-modes--n-vs-z)** | Valuation order across inheritance | 🟡 Medium |
| **[Copy-on-Write (CoW)](#copy-on-write-cow)** | Safe mutation of shared Frames | 🟢 Low |
| **[_ALTERNATIVES — Frame Networks](#_alternatives--frame-networks-minsky)** | Sibling prototype fallback | 🟡 Medium |
| **[_ON_DELETE — If-Removed Demon](#_on_delete--if-removed-demon)** | Cascade deletion hooks | 🟡 Medium |

---

## fselect — Prototype Selection

**Full reference:** See `Chorus::Frame` POD, fselect() function.

Selects the best-matching Frame(s) from a registry (or restricted pool) based on
observed slot/value pairs. Implements Minsky's frame-selection mechanism for diagnosis.

### Complete syntax

```perl
# Single best match (highest score)
my $proto = fselect(slot1 => val1, slot2 => val2, ...);

# All candidates ranked by descending score
my @ranked = fselect(slot1 => val1, _all => 1);

# Restrict to a seed Frame and its declared _ALTERNATIVES
my $best = fselect(slot1 => val1, _alternatives => $seed_frame);

# Restrict search space to a list of candidates
my $proto = fselect(slot1 => val1, _from => \@candidates);

# Accept zero-score matches (default: minimum score 1)
my @all_including_zero = fselect(slot1 => val1, _all => 1, _min => 0);

# Combine options
my @ranked = fselect(
    wood_class => 'oak',
    treatment  => 'treated',
    _all       => 1,
    _from      => \@normatif_catalog,
    _min       => 1
);
```

### Scoring algorithm

For each candidate Frame in the candidate pool:

1. For each observed slot/value pair: **+1 point** if the Frame provides the slot
   (directly or via inheritance) AND the resolved value (via `get()`) **matches** the observation
2. Exclude candidates scoring < `_min` (default: 1)
3. Return best candidate (scalar context), or all candidates sorted by descending score (list context)

**Example:**

```perl
my $catalog = Chorus::Frame->new(
    id => 'oak-catalog',
    _ISA => [
        Chorus::Frame->new(id => 'oak-untreated', wood_class => 'oak', treatment => undef),
        Chorus::Frame->new(id => 'oak-treated',   wood_class => 'oak', treatment => 'C24'),
    ]
);

my @ranked = fselect(
    wood_class => 'oak',
    treatment  => 'C24',
    _all => 1,
    _min => 0
);
# Result: [oak-treated (score 2), oak-untreated (score 1)]
```

### Pattern B — Automatic _ISA injection in Feed.pm

When `chorus-feed` / `chorus-check` generates a Feed.pm, the `load_projet()` subroutine
calls `fselect` to find the best-matching prototype from a static catalog, then injects
it as `_ISA`:

```perl
sub load_projet {
    my ($projet) = @_;
    
    # Build Frame from JSON
    my $frame = Chorus::Frame->new(%$projet);
    
    # Find best-matching prototype
    my $proto = fselect(
        type_element => $frame->get('type_element'),
        wood_class   => $frame->get('wood_class'),
        _from        => \@CATALOG_PROTOTYPES
    );
    
    # Inject prototype inheritance
    $frame->set('_ISA', $proto) if $proto;
    
    return $frame;
}
```

Result: the Frame inherits all normative thresholds and defaults from the matched prototype.

### Debugging — Frame not matching

If a Frame scores 0 (no matches):

1. **Check the candidate pool:** does it contain Frames with matching slots?
2. **Check slot values:** do they `eq` the observed values? (no type coercion)
3. **Check slot registration:** were they set via `set()`, not direct assignment?
4. **Re-run with `_min => 0`:** see all candidates and their scores

```perl
# Debug: list all candidates and scores
my @all = fselect(wood_class => 'oak', _all => 1, _min => 0);
for my $f (@all) {
    printf "Candidate %s (score unknown — re-compute if needed)\n", $f->get('id');
}
```

---

## _TERMINAL_SLOTS / complete() — Frame Validation

**Full reference:** See `Chorus::Frame` POD, complete() method.

Declares which slots must contain actual data (`_VALUE`) for a Frame to be
considered complete in Minsky's model. Used to validate project Frames before execution.

### Declaring terminal slots

```perl
my $proto = Chorus::Frame->new(
    _TERMINAL_SLOTS => ['color', 'size', 'weight'],
    # ... defaults for color, size, weight ...
);
```

### Checking completeness

```perl
my $instance = Chorus::Frame->new(
    _ISA   => $proto,
    color  => 'red',
    size   => 'large',
    # weight not set — will be incomplete
);

if ($instance->complete) {
    # All terminal slots have values
} else {
    # At least one terminal slot is undef
}
```

### In chorus-check — Pre-execution validation

Before launching the pipeline, validate all project Frames:

```perl
# In run.pl (generated by chorus-check)
for my $elem (@$elements) {
    unless ($elem->complete) {
        warn "Element " . $elem->get('id') . " missing terminal slot\n";
        next;  # skip or die
    }
}

# Only complete Frames reach the pipeline
my $ok = $expert->process($input);
```

### Interaction with _VALUE, _DEFAULT, _NEEDED

A slot is considered "filled" if `get()` returns a defined value, regardless of source:
- If it contains `_VALUE` → filled
- If it inherits `_DEFAULT` → filled
- If it computes via `_NEEDED` coderef → filled (lazy)
- Otherwise → unfilled

Example:

```perl
my $proto = Chorus::Frame->new(
    _TERMINAL_SLOTS => ['color', 'size'],
    size => { _DEFAULT => 'large' },  # size has a default
);

my $inst = Chorus::Frame->new(
    _ISA => $proto,
    color => 'red',  # color set explicitly
    # size not set, but inherited from proto
);

$inst->complete;  # true — both color and size are defined (color via _VALUE, size via _DEFAULT)
```

---

## Procedural Slots — $SELF Capture Rules

**Critical:** Procedural slots (coderefs) have special semantics for the `$SELF` variable.
Incorrect usage causes silent failures.

### _AFTER — Forward chaining hook

Called **after** a slot value is written (via `set()`), before the method returns.
Receives the new value as argument.

**Signature:**

```perl
_AFTER => sub {
    my ($new_value) = @_;
    # $SELF = Frame on which set() was originally called (not necessarily the frame that defines this slot)
    ...
}
```

**Use case:** Propagate a change to related slots or external systems.

### ⚠️ PITFALL: $SELF overwritten by inner set()

When `_AFTER` calls `set()` on **another Frame**, the `$SELF` context changes inside that `set()` call:

```perl
# ❌ WRONG — $SELF overwritten
_AFTER => sub {
    my ($new_val) = @_;
    $other_frame->set('x', $SELF->get('y'));  # $SELF might have changed inside set()
}

# ✅ CORRECT — capture $SELF first
_AFTER => sub {
    my ($new_val) = @_;
    my $ctx = $SELF;  # capture before any external set()
    $other_frame->set('x', $ctx->get('y'));
}
```

### _BEFORE — Pre-write hook

Called **before** a slot value is written, before validation.
Receives the new value as argument.

**Signature:**

```perl
_BEFORE => sub {
    my ($new_value) = @_;
    # $SELF = Frame on which set() was originally called (not necessarily the frame that defines this slot)
    ...
}
```

**Use case:** Normalize or sanitize the value before storage.

### _REQUIRE — Validation hook

Called to validate a new value **before** storage. Return `-1` (REQUIRE_FAILED constant)
to **block** the write. Any other return value allows the write.

**Signature:**

```perl
_REQUIRE => sub {
    my ($new_value) = @_;
    return -1 if $new_value < 0;  # reject negative values
    return 1;  # allow write
}
```

**Use case:** Enforce domain constraints (e.g., non-negative, non-empty string).

### _NEEDED — Lazy computation (backward chaining prototype)

Called when `get()` is invoked on a slot but neither `_VALUE` nor `_DEFAULT` is present.
**Called once, result is NOT cached.**

**Signature:**

```perl
_NEEDED => sub {
    # $SELF = Frame on which get() was originally called
    # (see §get-path-vs-autoload below — $SELF differs between get('a b') and ->a->b)
    # ✅ Use get() — $SELF->{other_slot} would miss _DEFAULT / _NEEDED / _ISA inheritance
    my $computed = SomeHelper->derive($SELF->get('other_slot'));
    return $computed;
}
```

**Critical limitations:**

1. **Not cached** — every `get()` re-evaluates `_NEEDED`. Use explicit `set()` if computation is
   expensive (cache the result by calling `$SELF->set('slot', $computed)` before returning).
2. **Engine methods unavailable** — `$SELF` in `_NEEDED` is a data Frame, not an Engine Frame.
   You **cannot** call `$SELF->solved()`, `cut()`, `replay()`, etc. from `_NEEDED`.
   `fmatch()` **can** be called (it is a `Chorus::Frame` utility, not an Engine method), but
   carries two risks: re-evaluation cost on every `get()` (see point 1), and circular dependency
   if the queried Frames also trigger `_NEEDED` that in turn reads back this Frame.
3. **Local to Frame** — `_NEEDED` cannot traverse outside its Frame; use `_AFTER` on a *previous* slot
   to trigger cross-Frame propagation.

**Example:**

```perl
my $f = Chorus::Frame->new(
    lac_base => 5,
    sofa_score => sub {
        my $lac = $SELF->get('lac_base');
        return undef unless defined $lac;
        return ($lac > 10 ? 3 : 0);  # simplified SOFA scoring
    },
);

my $score = $f->get('sofa_score');  # calls _NEEDED, returns 0
$f->set('lac_base', 15);
my $score2 = $f->get('sofa_score');  # calls _NEEDED again, returns 3
```

### ⚠️ get('a b c') vs ->a->b->c — Two radically different $SELF semantics {#get-path-vs-autoload}

These two access forms look equivalent but produce **different `$SELF`** inside procedural
slots, and differ in **whether `_NEEDED` fires on intermediate steps**.

#### How `get()` manages `$SELF` (source: `Frame.pm`)

`get()` calls `pushself($frame)` **once** at entry and `popself()` at exit.
The internal path traversal (`_getN` / `_getZ`) navigates recursively
**without ever updating `$SELF`**.  So `$SELF` remains the frame on which
`get()` was originally called — regardless of how deep the path goes.

For intermediate steps, `_getN` uses `_inherited($this, $step)` which returns
the **raw slot value** (the sub-Frame object), without going through `_value_N`.
This means **`_NEEDED` is NOT evaluated on intermediate steps** of a path.

#### Comparison table

| | `$f->get('foo bar baz')` | `$f->foo->bar->baz` |
|---|---|---|
| Number of `get()` calls | **1** | **3** (one per AUTOLOAD) |
| `$SELF` when `baz`'s `_NEEDED` fires | **`$f`** (root frame) | **the frame returned by `->bar`** |
| `_NEEDED` evaluated on `foo` and `bar`? | ❌ No — raw sub-frame used | ✅ Yes — each step goes through `get()` |

#### Concrete example

```perl
my $baz_frame = Chorus::Frame->new(
    _NEEDED => sub { "owner=${\ref($SELF)}, key=" . ($SELF->{_KEY} // '?') },
);

my $bar_frame = Chorus::Frame->new( baz => $baz_frame );
my $foo_frame = Chorus::Frame->new( bar => $bar_frame );
my $f         = Chorus::Frame->new( foo => $foo_frame );

# Path form — one get() call, $SELF = $f throughout
my $v1 = $f->get('foo bar baz');   # $SELF inside _NEEDED = $f

# Chained form — three get() calls, $SELF updated at each step
my $v2 = $f->foo->bar->baz;       # $SELF inside _NEEDED = $bar_frame
```

#### Practical rules

> **✅ In YAML rules (`EFFET`, `CONDITION`, `EXCEPTION`) and Helpers (`Helpers.pm`):
> always prefer `$var->get('foo bar baz')` over `$var->foo->bar->baz`.**
>
> In those contexts, `$var` is the Frame injected by the rule engine (from `_SCOPE`).
> Using the path form guarantees that **`$SELF` remains that Frame throughout the
> traversal** — which is exactly what any `_NEEDED` or `_DEFAULT` coderef in the
> sub-frame tree expects when it refers back to the domain object.
> The chained form silently shifts `$SELF` to a sub-frame at each step, which
> breaks any coderef that reads `$SELF->some_top_level_slot`.

- **Use `get('a b c')`** (preferred) when a procedural slot anywhere in the path needs
  to refer to the **root Frame** — the domain object as seen by the rule.
- **Use `->a->b->c`** only when each intermediate step must trigger its own `_NEEDED`
  evaluation (i.e. the intermediate slot is itself computed, not a stored sub-Frame),
  AND you are certain no `_NEEDED` / `_DEFAULT` in the chain reads `$SELF`.
- **Never mix the two styles** for the same path without consciously choosing which
  `$SELF` semantics you need.
- **In `_AFTER` / `_BEFORE`**: `$SELF` is the Frame on which `set()` was originally
  called — same rule applies (it is NOT necessarily the frame that defines the hook
  if inheritance is involved).

#### Impact on inheritance

If `baz` is defined on a **parent frame** (via `_ISA`) and accessed with `get('foo bar baz')`,
`$SELF` is still `$f` — not the parent that owns `baz`.
With `->foo->bar->baz`, `$SELF` is the frame on which `->baz` is called (which may itself
have inherited `baz` — `$SELF` is still the receiver, not the declaring ancestor).

---

### `$f->{slot}` vs `$f->get('slot')` — Read semantics {#hash-vs-get-reads}

> **Rule:** always use `$f->get('slot')` (or `$f->slot` via AUTOLOAD) for domain slot reads
> in ACTION/EFFET, CONDITION, Helpers.pm, and procedural slots (`_NEEDED`, `_AFTER`).
> `$f->{slot}` direct hash access is only acceptable in the three specific contexts listed below.

#### Why the difference matters

`Chorus::Frame` objects are blessed hashrefs. Their internal slot storage is:

| How slot was set | Raw storage in hash | `$f->{slot}` returns | `$f->get('slot')` returns |
|---|---|---|---|
| `new(slot => $val)` or `set('slot', $scalar)` | `$f->{slot} = $scalar` | `$scalar` ✅ | `$scalar` ✅ |
| `set('slot', { _DEFAULT => $val })` | `$f->{slot} = { _DEFAULT => $val }` | hashref ❌ | `$val` ✅ |
| `set('slot', sub { ... })` (`_NEEDED`) | `$f->{slot} = sub { ... }` | coderef ❌ | result of call ✅ |
| Slot **only on `_ISA` parent** (inherited) | key absent from frame | `undef` ❌ | traverses `_ISA` ✅ |

**`$f->{slot}` works by coincidence** for plain scalar slots — it silently breaks as soon as a
prototype provides `_DEFAULT`, a slot is lazy (`_NEEDED`), or the value lives on an `_ISA` parent.
The bug is silent: no error, just wrong or missing values in computed results.

#### Three legitimate uses of `$f->{slot}` for reads

**① EXCEPTION idempotence guards — intentionally different semantics**

```perl
EXCEPTION: defined $f->{slot_pose}   # ✅ intentional: tests "_VALUE explicitly written by set()"
```

`defined $f->{slot_pose}` = has `set()` been called on THIS frame for this slot?
`defined $f->get('slot_pose')` = is there ANY value, including inherited `_DEFAULT`?

For idempotence, we want the first form: if a prototype provides `_DEFAULT => 'pending'`,
the rule must still fire to compute and write the actual `_VALUE`. Using `->get()` would
block it silently — the rule would never fire, `_VALUE` would never be written.

> ⚠️ **Limit:** if the result slot lives ONLY on the `_ISA` parent (e.g. injected in prototype
> construction), `$f->{slot}` is always `undef` → guard always passes → rule fires on every cycle.
> In that case, add a CONDITION to route by `type_element` before the EXCEPTION fires.

**② `run.pl` display/reporting loop**

```perl
# In run.pl — $e iterates over @elements, all slots written by rules as plain scalars
printf "statut : %s\n", $e->{statut_conformite} // '(unprocessed)';
```

Rules always write result slots as plain scalars via `set()` → direct hash access is safe here.
No `_DEFAULT`/`_NEEDED` in result slots; performance is not critical.

**③ Internal Engine system slots**

```perl
$SELF->{_KEY}     # internal Frame identity — not a domain slot
$SELF->{_CYCLE}   # Engine counter — stored directly by the engine internals
```

System slots (`_KEY`, `_PARENT_KEY`, `_CYCLE`, etc.) are stored directly by the engine — not
wrapped in `_VALUE`/`_DEFAULT`. `$f->{_KEY}` is correct for these.

#### Pattern — correct reads in generated code

```perl
# ❌ WRONG — bypasses _DEFAULT, _NEEDED, _ISA inheritance
my $type = $p->{type_element};
my $val  = $w->{height_m} // 0;
my $cond = $f->{masonry_condition} // 'A';  # if _DEFAULT => 'A' on prototype → hashref, not 'A'
my $r    = SomeHelper->compute($SELF->{input_slot});  # inside _NEEDED: no chain traversal

# ✅ CORRECT — full valuation chain
my $type = $p->get('type_element');
my $val  = $w->get('height_m') // 0;
my $cond = $f->get('masonry_condition') // 'A';
my $r    = SomeHelper->compute($SELF->get('input_slot'));
```

#### Quick decision table

| Context | Form to use | Reason |
|---|---|---|
| ACTION / EFFET — read slot | `$f->get('slot')` | Full valuation chain |
| CONDITION — test slot presence | `defined $f->get('slot')` | Traverses _ISA + _DEFAULT |
| EXCEPTION — idempotence guard | `defined $f->{slot}` | Tests "_VALUE set by rule" only |
| Helpers.pm — slot argument | `$f->get('slot')` | Caller may have _DEFAULT/_NEEDED |
| `_NEEDED` coderef — read via `$SELF` | `$SELF->get('slot')` | Traverses own _ISA chain |
| `_AFTER` coderef — read captured `$ctx` | `$ctx->get('slot')` | Same rule |
| `fselect()` arguments | `$frame->get('slot')` | Slot may come from prototype |
| `run.pl` display | `$e->{slot}` | Result slots are plain scalars |
| Engine system slots | `$SELF->{_KEY}` etc. | Not domain slots, stored directly |

---

### Lifecycle order in set()

When `set('slot', $val)` is called:

1. `_REQUIRE` is called with `$val` → if returns `-1`, abort (no change)
2. `_BEFORE` is called with `$val`
3. Value is stored in `_VALUE`
4. Slot is registered in `%REPOSITORY`
5. `_AFTER` is called with `$val` (forward chaining)

```
set($slot, $val)
  ↓
  _REQUIRE($val) → return -1 to abort
  ↓ (only if allowed)
  _BEFORE($val)
  ↓
  store $val in _VALUE
  ↓
  register in %REPOSITORY
  ↓
  _AFTER($val)  ← forward chaining happens here
  ↓
  return
```

---

## Inheritance Modes — N vs Z

**Full reference:** See `Chorus::Frame` POD, setMode() function.

### Mode N (Default) — Breadth-first per valuation key

Each valuation key (`_VALUE`, `_DEFAULT`, `_NEEDED`) is searched across the
**entire inheritance tree** before moving to the next key.

**Algorithm:**

```
1. Get _VALUE on (Frame, Frame._ISA, Frame._ISA._ISA, ...)
2. If found, return. If not found, get _DEFAULT on same tree.
3. If found, return. If not found, get _NEEDED on same tree.
4. If found and coderef, call and return. If not found, return Frame itself.
```

**Implication:** A `_DEFAULT` deep in the inheritance tree is preferred over
a `_NEEDED` closer to the root.

### Mode Z — Full sequence per frame

The full sequence (`_VALUE → _DEFAULT → _NEEDED`) is tested on each Frame
before descending to parents.

**Algorithm:**

```
For each Frame in inheritance chain:
  1. Test _VALUE on this Frame
  2. If absent, test _DEFAULT on this Frame
  3. If absent, test _NEEDED on this Frame
  4. If any found, return
  5. Otherwise, continue to _ISA
```

**Implication:** A `_VALUE` on a parent is preferred over a `_DEFAULT` on a child.

### Example — Difference

```perl
my $proto = Chorus::Frame->new(
    id => 'proto',
    color => { _DEFAULT => 'gray' },
);

my $child = Chorus::Frame->new(
    id => 'child',
    _ISA => $proto,
    color => { _VALUE => 'red' },
);

my $grandchild = Chorus::Frame->new(
    id => 'grandchild',
    _ISA => $child,
);

# Mode N (default)
my $c1 = $grandchild->get('color');  # searches: _VALUE on (grandchild, child, proto)
                                     # finds 'red' on child._VALUE → returns 'red'

# Mode Z
Chorus::Frame::setMode('Z');
my $c2 = $grandchild->get('color');  # on grandchild: _VALUE? _DEFAULT? _NEEDED?
                                     # on child: _VALUE? yes → returns 'red'
```

In this case, both return `'red'`. But in deeper trees with multiple levels of defaults,
the difference becomes significant.

### Switching modes

```perl
Chorus::Frame::setMode('N');          # Mode N (default, explicit)
Chorus::Frame::setMode(GET => 'Z');   # Mode Z (verbose form)
```

Mode is a **global setting** — affects all Frame `get()` calls in the process.

### Guidance

- **Default to Mode N** — it's the standard and expected by most codebases.
- **Use Mode Z** if you have:
  - Multi-level prototypes where each level adds its own defaults
  - A DSL where shallower defaults override deeper ones
  - A specific design decision documented in your handbook

---

## Copy-on-Write (CoW)

**Full reference:** See `Chorus::Frame` POD, set() method with _PARENT_KEY.

Automatic mechanism that prevents mutation of shared sub-Frames during `set()`.

### How it works

When `set()` traverses a sub-Frame whose `_PARENT_KEY` differs from the current Frame's `_KEY`,
a "shadow" Frame is created locally before the write:

```perl
my $shared = Chorus::Frame->new(b => { _VALUE => 'old' });

my $f = Chorus::Frame->new(a => $shared);
my $g = Chorus::Frame->new(a => $shared);

# Both f and g share the same $shared Frame
$f->set('a b', 'new');

# Result:
# - f.a is now a shadow Frame inheriting from $shared, with 'b' = 'new'
# - g.a still points to original $shared, with 'b' = 'old'
```

### Transparent behavior

You don't need to do anything — CoW is automatic in `set()`.

**Don't do this:**

```perl
# ❌ WRONG — direct assignment bypasses CoW
$f->{a} = Chorus::Frame->new(...);

# ✅ CORRECT — use set(), which applies CoW if needed
$f->set('a', ...);
```

### Use case — Safe frame mutations in simulation/testing

Clone a Frame before mutation to avoid affecting shared prototypes:

```perl
my $original = Chorus::Frame->new(...);
my $simulation = Chorus::Frame->new(_ISA => $original);

# Mutate the simulation
$simulation->set('threshold', 999);

# Original is unchanged (via CoW)
```

---

## _ALTERNATIVES — Frame Networks (Minsky)

**Full reference:** See `Chorus::Frame` POD, fselect() function with _alternatives option.

Declares a list of sibling prototype Frames that should be considered as alternatives
when the primary prototype doesn't match perfectly.

### Declaring alternatives

```perl
my $Bird = Chorus::Frame->new(
    id        => 'bird',
    can_fly   => 1,
    legs      => 2,
    _ALTERNATIVES => [$Bat, $Insect],  # fallback prototypes
);
```

### Using in fselect

```perl
my $best = fselect(
    can_fly => 1,
    legs    => 6,
    _alternatives => $Bird  # search Bird + its _ALTERNATIVES
);

# Search space: [Bird, Bat, Insect]
# Returns the best match among them
```

### Pattern — Multi-level diagnosis

Useful for diagnostic systems where a primary prototype fails and fallbacks are tried:

```perl
my $Wood = Chorus::Frame->new(
    id => 'wood',
    is_organic => 1,
    _ALTERNATIVES => [$Concrete, $Steel],  # fallback materials
);

my $element = fselect(
    is_organic => 1,
    strength   => 'high',
    _alternatives => $Wood
);
# If Wood doesn't match, try Concrete, then Steel
```

---

## _ON_DELETE — If-Removed Demon

**Full reference:** See `Chorus::Frame` POD, delete() method.

Completes the Minsky triad of lifecycle demons:
- `_BEFORE` / `_AFTER` — if-added / if-changed
- `_ON_DELETE` — if-removed

Called after a slot is deleted (via `$f->delete('slot')`).

### Signature

```perl
_ON_DELETE => sub {
    my ($slot_name) = @_;
    # $SELF = Frame that owned the slot
    ...
}
```

### Use case — Cleanup and cascade

```perl
my $element = Chorus::Frame->new(
    type  => 'beam',
    _ON_DELETE => sub {
        my ($slot) = @_;
        if ($slot eq 'strength') {
            $SELF->delete('result_ok');  # cascade: clear dependent result
        }
    },
);

$element->delete('strength');  # triggers _ON_DELETE
```

### Interaction with _REQUIRE

Note: `_ON_DELETE` is called **after** deletion, not before. To **prevent** deletion,
use a `_REQUIRE` hook on a different slot that guards against invalid states.

---

## Integration Checklist

When building a complex Frame hierarchy with procedural slots:

- [ ] Every `_AFTER` that calls `set()` on another Frame: capture `$SELF` first
- [ ] Every `_NEEDED` is a **pure function** — no Engine calls, no side effects
- [ ] `_TERMINAL_SLOTS` on prototypes, checked via `complete()` before pipeline
- [ ] Mode N/Z choice documented in handbook (default: N)
- [ ] `fselect` in Feed.pm for Pattern B, with fallback (`_min => 0`) if needed
- [ ] `_ALTERNATIVES` declared on primary prototypes for multi-level diagnosis
- [ ] `_ON_DELETE` for cascade cleanup (if applicable to domain)

---

## See Also

- `chorus-engine-yaml.md` — fselect, _TERMINAL_SLOTS, Mode N/Z quick reference
- `Chorus::Frame` POD — authoritative source for all methods
- `chorus-feed.md` — KB formalization and procedural slot generation
- `chorus-check.md` — Feed.pm code generation with _NEEDED and _AFTER injection
