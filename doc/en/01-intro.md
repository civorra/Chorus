# Introduction to Chorus

## What is Chorus?

**Chorus** is an inference engine written in pure Perl. It rests on three
fundamental concepts: a **working memory** populated with frames, an **inference
cycle** that applies rules in a loop until a fixed point, and a **multi-agent
orchestration** layer that breaks complex problems into independent specialities.

**The working memory** is made up of `Chorus::Frame` objects — Perl objects whose
properties (*slots*) represent domain knowledge. All frames are indexed in a
global registry; the `fmatch()` function queries that registry in constant time.
Every rule operates on this shared memory.

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
| **3 — ECA** | Pipeline generated from a corpus | Perl 5 + ECA | Normative domains, large corpora |

Levels 1 and 2 are **100 % self-contained**: pure Perl, no external dependency,
no third-party tool. Level 3 adds ECA as a *development* tool — not as a
*runtime* dependency. A pipeline generated at level 3 runs exactly like one
written by hand at level 1.

> **Starting point:** the examples in `examples/sandboxes/cob-compliance_en`
> (or `_fr`) are fully functional without ECA. They show the complete structure
> of a Chorus project — corpus, KB, YAML rules, Perl infrastructure — and run
> with `perl run.pl project-demo.json`.

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

> See [`02-eca.md`](02-eca.md) — LLM vs Chorus positioning, ECA architecture,
> `chorus-pdf` → `chorus-feed` → `chorus-check` pipeline.

---

## Further reading

- `perldoc Chorus::Expert` — multi-agent orchestration, shared BOARD, `_MAX_ITER`
- `perldoc Chorus::Engine` — rules, inference loop, YAML DSL, flow control
- `perldoc Chorus::Frame` — slots, inheritance, `fmatch`, `get`, `set`, `delete`
- `perldoc Chorus::Collection::List` — ordered frame sequences
- `perldoc Chorus::Collection::Filter` — pattern matching on sequences
