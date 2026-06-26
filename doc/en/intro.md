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

Picture this: you have a 150-page PDF — a construction standard, a technical
specification, a regulatory document. By the end of the session you want a
running Chorus inference pipeline that validates real projects against it. Not a
prototype: a full engine with specialised agents, idempotent YAML rules, normative
tables extracted from the document, correctly wired Perl infrastructure, and a
structured conformity report.

Without assistance: several days of expert Perl work. With ECA and its Chorus
skills, it is the work of one session.

> **ECA is a development tool, not a runtime dependency.** The pipeline it
> generates is pure Perl — `Feed.pm`, `Agent/*.pm`, `Expert.pm`, `run.pl`. It
> runs on any machine with Perl installed, without ECA, without a network
> connection. Once generated, the pipeline is entirely self-contained.

> **KB files (`.org`)** are structured plain text, readable with any editor —
> vim, VSCode, nano. Emacs gives the best rendering of tables and markup, but
> it is not required to read, edit or version these files.

**What the chain does in practice:**

```
chorus-pdf  standard.pdf --auto
    → extracts text page by page (pdfminer for text,
      LLM vision for figures and tables)
    → corpus/001-standard-vision.md

chorus-feed my-sandbox corpus/001-standard-vision.md
    → identifies specialities → agents
    → designs the slot ontology
    → writes eca/agents/<speciality>.org (KB per agent)
    → generates rules/<speciality>/R01-xxx.yml … (YAML rules)
    → generates lib/MyApp/Agent/<Speciality>/Helpers.pm (normative tables)

chorus-check my-sandbox project.json
    → reads the KB, generates Feed.pm + Agent/*.pm + Expert.pm + run.pl
    → runs perl run.pl project.json
    → prints the conformity report
```

Three commands. Everything else is handled.

**What makes this possible:**

The central mechanism is the **local knowledge base** — org-mode files produced
by ECA, one per agent, containing everything the engine needs to know: the domain
ontology, the slot dictionary, the rule catalogue with code, and Perl helpers
annotated with their normative source (`# §4.2 DTU 31.2`).

These files are readable by a domain expert without knowing any Perl. They can
correct a table, challenge a rule, refine a constraint. ECA re-reads the updated
KB and regenerates the downstream artefacts. Chorus executes the result without
involving the LLM — deterministically, identically, as many times as needed.

```
standard.pdf
    │ chorus-pdf
    ▼
corpus/
    │ chorus-feed
    ▼
eca/agents/*.org  ←──── domain expert reads, corrects, refines
rules/**/*.yml
lib/**/Helpers.pm
    │ chorus-check
    ▼
Feed.pm · Agent/*.pm · Expert.pm · run.pl
    │ perl run.pl project.json
    ▼
✅ COMPLIANT / ❌ NON_COMPLIANT  — with reason, per element, per agent
```

**When the standard changes:**

```
chorus-feed my-sandbox new-corpus.txt --enrich
chorus-check my-sandbox project.json
```

The KB is updated incrementally. The Perl infrastructure is regenerated. The
pipeline runs again — result guaranteed to conform to the rules as defined, with
no drift.

**In practice, on a real domain:**

A test sandbox for timber-frame construction (COB, DTU 31.2) was built with this
chain: 7 specialised agents, 37 YAML rules, 7 helper modules with EC5 and NF EN
338 lookup tables, a pipeline validating 210 building elements in a single pass.
The entire Perl and YAML codebase — around 2 000 lines — was generated by ECA
from the corpus. Not a single line written by hand.

> The ECA skills for Chorus (`chorus-pdf`, `chorus-feed`, `chorus-check`,
> `chorus-create-project`, `chorus-import-project`) are versioned in
> `$ENGINE/eca/skills/` and documented in the repository.

> **Explore without ECA:** the sandboxes `examples/sandboxes/cob-compliance_en`
> and `cob-compliance_fr` contain the full set of artefacts produced by the
> chain (corpus, KB org files, YAML rules, Perl infrastructure). They let you
> understand what ECA generates before installing it — and running
> `perl run.pl project-demo.json` shows the result live.

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
