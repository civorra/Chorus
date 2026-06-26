# Chorus in the age of LLMs

Large language models (GPT, Claude, Gemini…) now achieve remarkable performance
on comprehension, generation, and general reasoning tasks. This raises a
legitimate question: what is a rule engine like Chorus still good for?

The answer is one word: **control**.

---

## What LLMs do not provide

An LLM "knows" things, but that knowledge is implicit, distributed across
billions of parameters, and fundamentally opaque. You cannot:

- **point to** the rule that produced a particular result,
- **surgically fix** an error without retraining the model,
- **guarantee** that a business constraint will always be respected,
- **read or hand over** the modelled knowledge to a human expert.

For many use cases this opacity is acceptable. For others — regulated domains,
certifiable systems, auditable expertise — it is a showstopper.

---

## What Chorus provides

With Chorus, knowledge is an **explicit artefact**: readable frames, versioned
YAML rules that can be discussed and challenged. A domain expert can read them,
contest them, refine them. Every conclusion has a traceable justification.

---

## Complementarity rather than competition

| Task | Right tool |
|---|---|
| Free-text understanding, extraction, generation | LLM |
| Strict business constraint validation | Chorus |
| Decision justification and traceability | Chorus |
| Fast adaptation to a new domain | LLM |
| Guaranteed compliance with a standard | Chorus |

A LLM can extract and structure the input data; Chorus applies the business rules
and certifies the result. The two complement each other without competing.

---

## Coupling with an LLM tool — the ECA architecture

Picture this: you have a 150-page PDF — a construction standard, a technical
specification, a regulatory document. By the end of the session you want a
running Chorus inference pipeline that validates real projects against it. Not a
prototype: a full engine with specialised agents, idempotent YAML rules, normative
tables extracted from the document, correctly wired Perl infrastructure, and a
structured conformity report.

Without assistance: several days of expert Perl work. With ECA and its Chorus
skills, it is the work of one session.

> **ECA is not an execution dependency.** The pipeline it generates is pure
> Perl — `Feed.pm`, `Agent/*.pm`, `Expert.pm`, `run.pl`. It runs on any machine
> with Perl installed, without ECA, without a network connection. Once generated,
> the pipeline is entirely self-contained for execution.
>
> **ECA is a project dependency.** Adapting a sandbox to a new project —
> aligning engineer documents with KB slots and producing a valid project JSON —
> requires `chorus-create-project` or `chorus-import-project`, both ECA skills.
> The dependency is real and by design: the LLM reads the KB and handles the
> terminology gap that no static script can cover generically. ECA is also
> needed when the normative corpus changes — to re-run `chorus-feed --enrich`
> and `chorus-check`.

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

> **Explore the sandbox without ECA:** the sandboxes `examples/sandboxes/cob-compliance_en`
> and `cob-compliance_fr` contain the full set of artefacts produced by the
> chain (corpus, KB org files, YAML rules, Perl infrastructure). They let you
> understand what ECA generates and run `perl run.pl project-demo.json` live —
> but they use a pre-built project JSON. Adapting to a new project requires ECA.

---

## In summary

LLMs excel at what is **vast and ambiguous**.
Chorus excels at what is **precise and certifiable**.

For a developer or domain expert who needs to *master* the knowledge they model —
not just use it — Chorus remains an irreplaceable tool, precisely because it
solves a problem that LLMs cannot solve by construction.

---

## The `chorus-*` commands

> See [`04-chorus-commands.md`](04-chorus-commands.md) — complete reference for
> `chorus-pdf`, `chorus-feed`, `chorus-check`, `chorus-create-project`,
> `chorus-import-project`: syntax, modes, prerequisites, outputs, end-to-end
> workflow and quick-reference table.

## Application domains

> See [`03-applications.md`](03-applications.md) — sector-by-sector analysis,
> compatibility pattern, estimated onboarding time per domain.
