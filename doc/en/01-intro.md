# Introduction to Chorus

## What is Chorus?

**Chorus** is an inference engine written in pure Perl. It rests on three
fundamental concepts: a **working memory** populated with frames, an **inference
cycle** that applies rules in a loop until a fixed point, and a **multi-agent
orchestration** layer that breaks complex problems into independent specialities.

**The working memory** is made up of `Chorus::Frame` objects — Perl objects whose
properties (*slots*) represent domain knowledge, drawing from the
slot / default / procedural-attachment model introduced by Minsky (1974).
All frames are indexed in a global registry; the `fmatch()` function queries
that registry in constant time. Every rule operates on this shared memory.

**The inference cycle** is handled by `Chorus::Engine`. An agent holds a set of
rules; each rule declares which frames it applies to (`_SCOPE`) and what effect
it produces (`_APPLY`). The engine fires rules in a loop as long as at least one
of them had an effect — it stops at the fixed point, when nothing changes any
more, or as soon as a goal is reached. Rules can be written in Perl or loaded
from YAML files.

**The orchestration** is handled by `Chorus::Expert`. Several specialised agents
are registered and share a common dashboard (`BOARD`). The Expert runs them
cooperatively in a loop until one declares the problem solved. Each agent ignores
the others and handles only its own scope; their chaining produces the global
result.

```
Chorus::Expert      coordinates agents, detects completion
  └─ Chorus::Engine   one agent = a set of rules + inference loop
       └─ Chorus::Frame   working memory = indexed objects with slots
```

The core idea: instead of writing an algorithm that says *how* to solve a
problem step by step, you declare *what you know* (the frames) and *what you
know how to do* (the rules), and Chorus takes care of the rest — deterministically
and traceably.

---

## Usage levels

Chorus is designed to be adopted gradually. You do not have to use the full
chain from the start.

| Level | What you use | Prerequisites | Who it is for |
|---|---|---|---|
| **1 — Pure Perl** | `addrule()`, `loop()` in Perl | Perl 5 | Discovery, prototyping, small projects |
| **2 — YAML** | YAML DSL rules, `loadRules()` | Perl 5 | Maintainable projects, rich business logic |
| **3 — AI agent** | Pipeline generated from a corpus | Perl 5 + AI agent | Normative domains, large corpora |

Levels 1 and 2 are **100 % self-contained**: pure Perl, no external dependency,
no third-party tool. Level 3 adds an AI agent as a *development* tool — not as a
*runtime* dependency. A pipeline generated at level 3 runs exactly like one
written by hand at level 1.

> **Starting point:** the example sandbox `sandboxes/demo_en`
> is fully functional without an AI agent. It shows the complete structure
> of a Chorus project — corpus, KB, YAML rules, Perl infrastructure — and runs
> with `perl sandboxes/demo_en/run.pl sandboxes/demo_en/project-01.json`.

---

## Chorus::Expert — orchestration

`Chorus::Expert` is the conductor. It registers several specialized agents
(`Chorus::Engine`), provides them with a **shared dashboard** (`BOARD`) to
communicate, and runs them in a loop until one of them declares the work done.

```perl
use Chorus::Expert;

my $xprt = Chorus::Expert->new();

$xprt->register($agent_analyse, $agent_compute, $agent_control);

my $ok = $xprt->process($data);   # 1 = success, undef = failure or timeout
```

The Expert ensures that agents run in registration order and restarts the loop
as long as at least one of them produced an effect. It stops as soon as an agent
calls `solved()` — or when `_MAX_ITER` cycles are reached without convergence.

> **Common pattern:** register a control agent last. Its sole role is to check
> that all objects have been processed, then call `$agent->solved()`.

---

## Chorus::Engine — rules

`Chorus::Engine` is the inference engine. Each instance is an **agent** holding
a list of rules. A rule declares:

- its **scope** (`_SCOPE`): how to find the objects it applies to;
- its **action** (`_APPLY`): what it does when the scope is satisfied.

```perl
use Chorus::Engine;
use Chorus::Frame;   # for fmatch()

my $agent = Chorus::Engine->new();

$agent->addrule(
    _SCOPE => {
        animal => sub { [ fmatch(slot => 'cry') ] },
    },
    _APPLY => sub {
        my %opts = @_;
        return if defined $opts{animal}->{known_cry};   # already processed
        $opts{animal}->set('known_cry', $opts{animal}->cry);
        return 1;   # the rule had an effect
    },
);

$agent->loop();   # standalone loop (without Expert)
```

The engine applies rules in a loop as long as at least one of them produces an
effect. It stops when nothing changes anymore, or when `solved()` is called.

---

## Chorus::Frame — knowledge

`Chorus::Frame` is the basic building block: a Perl object whose properties are
called **slots**. Frames can inherit from each other via the `_ISA` slot, exactly
like prototypes. A slot can hold a scalar value or a function computed on the fly.

```perl
use Chorus::Frame;

my $animal = Chorus::Frame->new(
    type => 'unknown',
    cry  => sub { "..." },
);

my $cat = Chorus::Frame->new(
    _ISA => $animal,
    type => 'feline',
    cry  => sub { "meow" },
);

print $cat->type;   # "feline"
print $cat->cry;    # "meow"
```

All frames are automatically indexed in a global registry. The `fmatch()`
function lets you retrieve them quickly by slot:

```perl
my @with_cry = fmatch(slot => 'cry');    # all frames that have a 'cry' slot
my @felines  = fmatch(type => 'feline'); # by slot value
```

> **Pitfall:** always use `$f->set('slot', $val)` and `$f->delete('slot')`
> — never `$f->{slot} = $val` or `delete $f->{slot}`, which bypass the index
> and make frames invisible to `fmatch()`.

### Frame selection with `fselect()`

`fmatch()` answers the question *"which frames have this slot?"* — the engine
reaches into the working memory and pulls frames out.

`fselect()` inverts the direction, following Minsky's original intent: given a
set of observed properties, *which prototype fits this situation best?*  Each
candidate frame is awarded one point per slot/value pair it matches; the
highest-scoring frame wins.

```perl
# Three prototypes in working memory
my $bird = Chorus::Frame->new(type => 'animal', can_fly => 1,  legs => 2);
my $fish = Chorus::Frame->new(type => 'animal', can_fly => 0,  legs => 0);
my $bat  = Chorus::Frame->new(type => 'animal', can_fly => 1,  legs => 2, nocturnal => 1);

# Observed situation: something that flies and has two legs
my $proto = fselect(can_fly => 1, legs => 2);
# → $bird and $bat both score 2; one of them is returned

# All candidates ranked best-first
my @ranked = fselect(can_fly => 1, legs => 2, _all => 1);

# Restrict the search to a known subset
my $best = fselect(can_fly => 1, _from => [$bird, $fish]);

# Instantiate from the selected prototype
my $instance = Chorus::Frame->new(_ISA => $proto, %observed);
```

**Options:**

| Option | Default | Effect |
|---|---|---|
| `_all` | — | Return all candidates ranked by score (list or arrayref) |
| `_from` | all frames | Restrict the candidate pool |
| `_min` | `1` | Minimum score to be included; `0` to allow zero-match candidates |

> **Relationship to `fmatch`:** the two functions are complementary. `fmatch`
> is the engine's primary tool — it drives the inference rules. `fselect` is a
> higher-level primitive for situation recognition: choose a frame *type* from
> context, then use `fmatch` to operate on instances of that type.

### The complete Minsky triad — `_NEEDED` / `_AFTER` / `_ON_DELETE`

Minsky defined three *procedural demons* that fire when a slot is touched.
`Chorus::Frame` now implements all three:

| Demon | Slot | When it fires | Chaining direction |
|---|---|---|---|
| if-needed | `_NEEDED` | `get()` cannot resolve the slot | Backward |
| if-added | `_AFTER` | a value is written via `set()` | Forward |
| if-removed | `_ON_DELETE` | a slot is erased via `delete()` | Side-effect |

```perl
my $f = Chorus::Frame->new(
    budget     => 1000,
    _AFTER     => sub { print "budget changed to $_[0]\n" },
    _ON_DELETE => sub { print "slot '$_[0]' removed\n" },
    _NEEDED    => sub { 0 },   # backward: produce a default when unresolved
);

$f->set('budget', 500);    # → "budget changed to 500"
$f->delete('budget');      # → "slot 'budget' removed"
```

`_ON_DELETE` receives the name of the deleted slot as its argument.  `$SELF`
is set to the frame at the time of the call, so the hook can inspect the
frame's remaining state.

### Terminal slots and `complete()`

Minsky distinguished *terminal nodes* — slots that must be grounded in actual
observed data — from non-terminal slots that may remain procedural. The
`_TERMINAL_SLOTS` slot and the `complete()` method implement this distinction.

```perl
my $Vehicle = Chorus::Frame->new(
    _TERMINAL_SLOTS => ['color', 'nb_wheels'],
    nb_wheels       => sub { 4 },   # non-terminal: has a default
);

my $car  = Chorus::Frame->new(_ISA => $Vehicle, color => 'red', nb_wheels => 4);
my $bike = Chorus::Frame->new(_ISA => $Vehicle, color => 'blue');

$car->complete;    # 1  — all terminal slots filled
$bike->complete;   # undef — nb_wheels not explicitly set on $bike
                   #         (the procedural default on the prototype does count)
```

`_TERMINAL_SLOTS` is inherited: a child frame that does not redeclare it uses
its parent's list. Each slot is resolved via `get()`, so `_DEFAULT` and
procedural slots count as filled.

> **Practical use:** call `complete()` inside a control agent's rule to check
> that all domain objects have been fully processed before calling `solved()`.

### Frame networks and `_ALTERNATIVES`

Minsky's frames were organised into *networks of alternative frames*:
when one prototype fails to fit a situation, the system tries its declared
siblings. The `_ALTERNATIVES` slot and the `_alternatives` option of
`fselect()` implement this.

```perl
my $Bat    = Chorus::Frame->new(can_fly => 1, legs => 2, nocturnal => 1);
my $Insect = Chorus::Frame->new(can_fly => 1, legs => 6);
my $Bird   = Chorus::Frame->new(can_fly => 1, legs => 2,
                                _ALTERNATIVES => [$Bat, $Insect]);

# Observed: something that flies, has 6 legs → Insect wins
my $match = fselect(can_fly => 1, legs => 6, _alternatives => $Bird);
# → $Insect (score 2) beats $Bird and $Bat (score 1 each)
```

`_alternatives` restricts the candidate pool to the seed frame plus all
frames in its `_ALTERNATIVES` list, keeping the search local to a declared
neighbourhood rather than scanning all registered frames.

### Chorus and Minsky's model — compatibility summary

`Chorus::Frame` implements the core of Minsky's frame model (1974):

| Concept | Chorus | Notes |
|---|---|---|
| Named slots + default values | ✅ `_DEFAULT` | Direct |
| Procedural slots | ✅ `sub {}` | Evaluated lazily via `get()` |
| Single and multiple inheritance | ✅ `_ISA` | Direct |
| *if-needed* demon | ✅ `_NEEDED` | Backward chaining |
| *if-added* demon | ✅ `_AFTER` | Forward chaining |
| *if-removed* demon | ✅ `_ON_DELETE` | Side-effect on `delete()` |
| Terminal nodes | ✅ `_TERMINAL_SLOTS` + `complete()` | Without active questioning |
| Frame selection | ✅ `fselect()` | Explicit call, not perception-driven |
| Frame networks | ✅ `_ALTERNATIVES` | Declarative neighbourhood |
| Automatic perception-driven selection | ⚠️ | Structurally absent — see below |
| Spreading activation (markers) | ❌ | Not implemented |

**The main remaining divergence:** in Minsky's original model, frame selection
is triggered *automatically* by perceptual input — the system chooses the best
prototype without an explicit call. In Chorus, `fselect()` must be called
explicitly from a rule or from Perl code. This reflects a deliberate
architectural choice: Chorus is a rule-driven inference engine, not a
perceptual system. The selection mechanism is available and correct; its
activation is under the developer's control.

**On spreading activation:** Minsky envisioned marker propagation through the
frame network to pre-activate candidate frames in parallel before explicit
selection. `fselect()` scores candidates linearly — this is sequentially
correct but not propagative. It is sufficient for rule-based domains and adds
no practical limitation in the contexts where Chorus is used.

---

> **Terminology note:** the term *neuro-symbolic* is sometimes applied to systems
> like Chorus. It is not accurate here. In neuro-symbolic systems, a neural model
> *learns* to simulate logical rules. In Chorus, the symbolic engine is real —
> frames, slots, inference chain — and the LLM is a preprocessing step.
> *Augmented symbolic* is a more precise label.

---

## Rules in YAML

For projects with many rules, Chorus provides a YAML DSL that avoids writing
Perl code by hand:

```yaml
RULE: compute-known-cry
FIND:
  animal:
    attribut: cry
EXCEPTION: defined $animal->{known_cry}
ACTION: |
  $animal->set('known_cry', $animal->cry);
  1
```

## Chorus as an inference engine

This model is directly inspired by the expert-system tradition of the 1980s–90s.
CLIPS, OPS5 and their predecessors all share the same recognize–act loop, the
same working memory, and the same forward-chaining mechanism. Chorus is a modern,
minimal Perl implementation of that lineage — without the weight of a dedicated
runtime.

Chorus implements the classical *recognize–act* cycle: at each iteration, the
engine searches the working memory for rules whose conditions are satisfied, fires
them, and starts again — until the **fixed point** (no rule can fire any more) or
until an explicit goal is reached.

This mechanism expresses itself at every layer of the architecture.

### The working memory

The `%FMAP`, `%REPOSITORY` and `%INSTANCES` registries in `Chorus::Frame`
constitute the working memory. The `fmatch()` function queries it in constant
time to retrieve all frames that provide a given slot, with optional filtering.

### The recognize–act cycle

`applyrules()` evaluates each rule's `_SCOPE` to identify candidate frames
(the *recognize* phase), then calls `_APPLY` for every combination (the *act*
phase). It tracks `$stillworking` — true if at least one rule produced an effect.
`loop()` repeats this cycle until the fixed point.

### Forward chaining

At two levels:
- **At the frame level**: the `_AFTER` slot fires side-effects as soon as a value
  changes, immediately propagating consequences within the knowledge structure.
- **At the engine level**: rules enrich frames by adding new slots, which makes
  other rules eligible in the next cycle.

### Backward chaining

When `get()` cannot resolve a slot, it invokes the `_NEEDED` coderef to *produce*
the value on demand. The slot is computed only when something needs it — this is
backward chaining at the knowledge-representation level.

### Goal-directed termination

`solved()` / `failed()`, `_TERMINAL`, `_MAX_CYCLES`: the engine reasons until an
explicit terminal state is reached or all possibilities are exhausted. The
`replay_all()` call restarts the entire agent pipeline from scratch, allowing the
system to reason over states that evolve during processing.

---

## Why this model?

The advantage of an explicit rule system is **traceability**: every result can be
justified by a specific rule. Knowledge is separated from the engine and can be
read, modified, or extended independently without touching the inference code.

This is what sets Chorus apart from purely algorithmic approaches: you describe
the **what**, not the **how**.

---

## Chorus in the age of LLMs

> See [`02-ai-agent.md`](02-ai-agent.md) — LLM vs Chorus positioning, AI agent architecture,
> `chorus-pdf` → `chorus-feed` → `chorus-check` pipeline.

---

## Further reading

- `perldoc Chorus::Expert` — multi-agent orchestration, shared BOARD, `_MAX_ITER`
- `perldoc Chorus::Engine` — rules, inference loop, YAML DSL, flow control
- `perldoc Chorus::Frame` — slots, inheritance, `fmatch`, `get`, `set`, `delete`
- `perldoc Chorus::Collection::List` — ordered frame sequences
- `perldoc Chorus::Collection::Filter` — pattern matching on sequences
- [CLIPS](https://www.clipsrules.net/), [OPS5](https://en.wikipedia.org/wiki/OPS5) — the expert-system tradition Chorus draws from
- Minsky, M. (1974). *A Framework for Representing Knowledge* — the frame model behind `Chorus::Frame`
