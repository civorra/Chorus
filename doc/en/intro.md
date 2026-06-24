# Introduction to Chorus

## What is Chorus?

**Chorus** is a lightweight inference framework written in pure Perl.
It lets you model a problem as **knowledge** (objects) and **rules**
(conditions + actions), then lets the engine figure out how to apply them
to solve the problem.

The core idea: instead of writing an algorithm that says *how* to solve a
problem step by step, you declare *what you know* and *what you are looking for*,
and Chorus takes care of the rest — deterministically and traceably.

The framework is organized in three nested layers:

```
Chorus::Expert      coordinates agents, detects completion
  └─ Chorus::Engine   one agent = a set of rules
       └─ Chorus::Frame   knowledge = objects with slots
```

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

## Why this model?

The advantage of an explicit rule system is **traceability**: every result can be
justified by a specific rule. Knowledge is separated from the engine and can be
read, modified, or extended independently without touching the inference code.

This is what sets Chorus apart from purely algorithmic approaches: you describe
the **what**, not the **how**.

---

## Chorus in the age of LLMs

Large language models (GPT, Claude, Gemini…) now achieve remarkable performance
on comprehension, generation, and general reasoning tasks. This raises a
legitimate question: what is a rule engine like Chorus still good for?

The answer is one word: **control**.

### What LLMs do not provide

An LLM "knows" things, but that knowledge is implicit, distributed across
billions of parameters, and fundamentally opaque. You cannot:

- **point to** the rule that produced a particular result,
- **surgically fix** an error without retraining the model,
- **guarantee** that a business constraint will always be respected,
- **read or hand over** the modelled knowledge to a human expert.

For many use cases this opacity is acceptable. For others — regulated domains,
certifiable systems, auditable expertise — it is a showstopper.

### What Chorus provides

With Chorus, knowledge is an **explicit artefact**: readable frames, versioned
YAML rules that can be discussed and challenged. A domain expert can read them,
contest them, refine them. Every conclusion has a traceable justification.

### Complementarity rather than competition

| Task | Right tool |
|---|---|
| Free-text understanding, extraction, generation | LLM |
| Strict business constraint validation | Chorus |
| Decision justification and traceability | Chorus |
| Fast adaptation to a new domain | LLM |
| Guaranteed compliance with a standard | Chorus |

A LLM can extract and structure the input data; Chorus applies the business rules
and certifies the result. The two complement each other without competing.

### Coupling with an LLM tool — the ECA architecture

An AI assistant like **[ECA](https://eca.dev/)** can integrate directly into the
Chorus development loop, acting as a *knowledge generator* where the engine acts
as a *certifiable executor*.

The architecture rests on three layers that communicate through plain-text files
readable by humans **and** by the LLM:

```
Raw corpus (PDFs, standards, technical docs…)
        │
        ▼  ECA reads, extracts, structures
┌───────────────────────────────────┐
│  Knowledge base  (org-mode)       │  ← read and maintained by ECA
│  eca/agents/qualification.org     │    • domain, ontology
│  eca/agents/framing.org           │    • slot dictionary
│  eca/agents/thermal.org  …        │    • rule catalogue
└───────────────────────────────────┘
        │
        ▼  ECA generates / refines
┌──────────────────────┐   ┌──────────────────────────┐
│  YAML rules          │   │  Perl helpers             │
│  rules/qualification │   │  lib/COB/Agent/           │
│  rules/framing  …    │   │  Qualification/Helpers.pm │
└──────────────────────┘   └──────────────────────────┘
        │                           │
        └──────────┬────────────────┘
                   ▼  Chorus runs (rules + Frames)
        ┌──────────────────────────────────┐
        │  Chorus::Expert                  │
        │    Agent::Qualification          │
        │    Agent::Framing                │
        │    Agent::Thermal  …             │
        │    Agent::Control  (termination) │
        └──────────────────────────────────┘
                   │
                   ▼
        Certifiable + traceable result
```

**The role of each layer:**

- **The corpus** (standards PDF, technical documents) is the domain source of
  truth. ECA reads it and extracts structured knowledge.

- **The org-mode files** (`eca/agents/*.org`) are the local knowledge base: one
  file per agent, with its domain, ontology, slot dictionary, rule catalogue and
  constraints. This is the collaboration interface between the human, the LLM,
  and the engine.

- **ECA** reads these org files through its skills and generates or refines YAML
  rules and Perl helpers from them — without hallucinating, because the knowledge
  is explicitly grounded in the local KB.

- **Chorus** executes the result deterministically, without any LLM, on the set
  of Frames built from the real project data.

**Update cycle when a standard changes:**

1. ECA reads the new corpus and updates the org files;
2. ECA generates the corresponding YAML rules and Perl helpers;
3. Chorus runs the updated pipeline — result guaranteed to conform to the rules
   as defined, with no stochastic drift.

Knowledge remains readable and auditable at every step. The human stays in
control: org files can be edited directly, YAML rules can be reviewed, and
generated Perl code can be validated before integration.

### In summary

LLMs excel at what is **vast and ambiguous**.
Chorus excels at what is **precise and certifiable**.

For a developer or domain expert who needs to *master* the knowledge they model —
not just use it — Chorus remains an irreplaceable tool, precisely because it
solves a problem that LLMs cannot solve by construction.

---

## Further reading

- `perldoc Chorus::Expert` — multi-agent orchestration, shared BOARD, `_MAX_ITER`
- `perldoc Chorus::Engine` — rules, inference loop, YAML DSL, flow control
- `perldoc Chorus::Frame` — slots, inheritance, `fmatch`, `get`, `set`, `delete`
- `perldoc Chorus::Collection::List` — ordered frame sequences
- `perldoc Chorus::Collection::Filter` — pattern matching on sequences
