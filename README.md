# Chorus::Engine

[![CPAN version](https://badge.fury.io/pl/Chorus-Engine.svg)](https://metacpan.org/dist/Chorus-Engine)
[![Perl](https://img.shields.io/badge/perl-5.006%2B-blue)](https://www.perl.org/)
[![License](https://img.shields.io/badge/license-Artistic--2.0-green)](LICENSE)

> Chorus is a Perl inference engine that turns a normative corpus into a
> conformity-checking pipeline. An AI agent builds the knowledge base; the
> engine executes it deterministically and traceably — no LLM, no network,
> on any machine with Perl.

```
Normative corpus (PDF, plain text, Word, Excel)
        │
   chorus-pdf + chorus-feed   ← AI agent extracts and formalises the rules
        │
   KB: ontology · YAML rules · normative tables
        │
   chorus-check               ← generates the Perl pipeline, runs it
        │
   perl run.pl project.json   ← deterministic, reproducible, no AI agent
        ▼
  ✅ COMPLIANT / ❌ NON_COMPLIANT  (per element, per agent, with reason and reference)
```

---

## Why an LLM cannot run the verification itself

Chorus occupies a specific position in the current AI landscape. Most hybrid
systems use a language model as the decision layer and rules as guardrails.
Chorus inverts this: the LLM is an extraction tool that reads documents and
formalises rules; the inference engine handles all reasoning. The LLM never
draws a conclusion.

**1. Exhaustive corpus coverage — impossible to guarantee.**
A language model does probabilistic completion, not exhaustive enumeration.
Rare clauses, normative footnotes, and cross-references between standards are
silently omitted. The problem: the model does not know what it omits.

**2. Consistency across a full project dossier — certain degradation.**
A real project dossier includes plans, specifications, calculation notes,
product data sheets, test reports, CE attestations. On long contexts, an LLM
loses precision on items introduced early and does not reliably detect
cross-document contradictions.

**3. Reproducibility — absent by nature.**
Two runs on the same project can produce different verdicts. For a control
bureau or an insurer, this is disqualifying.

**4. Traceability — structurally absent.**
An LLM may hallucinate references, paraphrase imprecisely, or conflate two
clauses. It cannot guarantee that each assertion is anchored to a specific
article of a specific standard.

**5. Normative updates — opaque.**
When a standard is revised, there is no way to know which part of the LLM's
reasoning is affected. With an explicit rule engine, the update is surgical:
the affected YAML rules are identified, corrected, and re-tested in isolation.

### The division of labour

An LLM is an excellent extractor and translator of normative text into formal
rules. It is a poor conformity checker.

This is precisely the division of labour Chorus implements: the LLM generates
and formalises the rules (`chorus-feed`); the inference engine executes them
deterministically and traceably (`chorus-check`). Together they cover what
neither can do alone.

Running `chorus-check` twice on the same project file, on any machine, always
produces the same output — no sampling, no temperature, no randomness in the
decision layer.

> The term *neuro-symbolic* is sometimes applied to systems like Chorus.
> It is not accurate here. In neuro-symbolic systems, a neural model learns to
> simulate logical rules. In Chorus, the symbolic engine is real — frames, slots,
> inference chain — and the LLM is a preprocessing step. *Augmented symbolic*
> is a more precise label.

---

## AI-assisted pipeline — `chorus-*` commands

The `chorus-*` commands are **AI agent skills** — not shell scripts. Each is
loaded by an AI agent (Claude, Copilot, ECA…) and executed interactively in
your development environment. The Perl pipeline they produce runs entirely on
its own: no AI agent, no LLM, no network connection required at runtime.

### Pipeline overview

```
Normative corpus (PDF, plain text, Word, Excel)
        │
   chorus-pdf          ← extracts PDFs (text, hybrid, or full-vision mode)
        │
   corpus/<NNN>-<slug>.txt / -vision.md
        │
   chorus-feed         ← builds the KB: ontology, YAML rules, Helpers.pm
        │
   agent/agents/*.org · rules/**/*.yml · lib/.../Helpers.pm
        │                 ← domain expert reviews and corrects
   chorus-check        ← generates Feed.pm, Agent/*.pm, Expert.pm, run.pl
        │                   then runs: perl run.pl project.json
        ▼
  ✅ COMPLIANT / ❌ NON_COMPLIANT  (per element, per agent, with reason)
```

The project file fed to `chorus-check` can be:
- **written by hand** (if the slot vocabulary is known)
- **generated from the KB** with `chorus-create-project` (conforming + KO
  variants, optional 4-file coverage suite `--batch`)
- **aligned from engineer documents** with `chorus-import-project` (PDF, Word,
  Excel, inline table — bridges engineer terminology to KB slot names)

### Commands at a glance

| Command | Role |
|---|---|
| `chorus-quickstart` | Guided overview — start here if new to Chorus |
| `chorus-pdf` | Extract a PDF corpus (text / hybrid / full-vision mode) |
| `chorus-feed` | Build or enrich the KB from a corpus |
| `chorus-check` | Generate infrastructure + run conformity check |
| `chorus-create-project` | Generate a synthetic project JSON from the KB |
| `chorus-import-project` | Align engineer documents with KB slot names |
| `chorus-strengthen` | Identify rule gaps, produce enrichment roadmap |

### Reinforcement loop

Once the first pipeline is running, `chorus-strengthen` classifies every
discordance (rule too strict, rule too permissive, Feed targeting gap) and
recommends the corpus needed to close each gap:

```
chorus-create-project <sb> --batch          ← 4-file coverage suite
chorus-check <sb> --all                     ← synthesis table
chorus-strengthen <sb>                      ← gap report + roadmap
chorus-feed <sb> corpus-fix.txt --enrich    ← targeted enrichment
chorus-check <sb> --all                     ← verify convergence ✅
```

### Once generated, runs without an AI agent

```bash
# On any machine with Perl installed:
perl run.pl project.json

# Re-run with a different project — no regeneration:
perl run.pl other-project.json
```

> Full command reference: [`doc/en/04-chorus-commands.md`](doc/en/04-chorus-commands.md)

---

## Application domains

Chorus is not tied to any particular sector. A domain is *Chorus-compatible*
whenever three conditions hold:

1. **The project is described by typed elements** — each object to validate
   (structural member, contractual clause, software component…) has measurable
   attributes and a discriminating type.
2. **The standard states thresholds, conditions and reference tables** —
   explicit requirements, not open-ended prose.
3. **The decision must be traceable and reproducible** — audit, certification,
   regulatory filing, litigation.

| Domain | Typical corpus | Estimated onboarding |
|---|---|---|
| 🔐 **Cybersecurity / NIS2 / DORA** | SecNumCloud v3.2, NIS2 Annex II, DORA, ETSI EN 319 412 | **1–2 weeks** ⚡ |
| 🌿 **CSRD / Environment** | ESRS E1–E5, S1–S4, GHG Protocol, EU Taxonomy | 2–3 weeks ⚡ |
| 🏗️ **Construction / BIM** | Eurocodes EC2/EC3/EC5, Building Regs, DTU | 2–3 weeks |
| ⚖️ **GDPR / Public procurement** | GDPR Art. 13/14/28/30/35, NIS2, procurement code | 2–3 weeks |
| 🏦 **Finance / RegTech** | Basel IV (CRR3), MiFID II, EMIR | 3–4 weeks |
| 💊 **Pharmaceuticals / GMP** | EU GMP Annex 1, ICH Q8/Q9/Q10, European Pharmacopoeia | 3–4 weeks |
| 🏥 **Medical devices** | MDR 2017/745, ISO 13485, IEC 62304, ISO 14971 | 4–5 weeks |
| 🚗 **Automotive / ISO 26262** | ASIL A/B/C/D, ASPICE v3.1, MISRA C:2012 | 4–5 weeks |
| ✈️ **Aerospace / DO-178C** | DO-178C, ARP4754A, AMC 20-115 (EASA) | 4–6 weeks |
| ⚡ **Energy / Nuclear** | RCC-M, IEC 61511, ASN safety guide, IEC 62351 | 6–8 weeks |

⚡ *Immediate regulatory pressure: NIS2 transposed since October 2024, DORA
applicable since January 2025, CSRD rolling out 2024–2028.*

The key variable is **corpus quality**, not domain complexity. A well-structured
corpus (numbered requirements, explicit reference tables, defined hierarchy
levels) onboards in 2 to 4 weeks.

> Full domain reference: [`doc/en/03-applications.md`](doc/en/03-applications.md)

---

## What's new in 2.01

- **`chorus-*` commands** — complete corpus → KB → Perl infrastructure →
  conformity report pipeline, AI-agent-driven (`chorus-pdf`, `chorus-feed`,
  `chorus-check`, `chorus-create-project`, `chorus-import-project`, `chorus-strengthen`)
- **`TERMINAL` field in the YAML DSL** — declare `TERMINAL: solved` or
  `TERMINAL: failed` directly in a rule, without any Perl glue code
- **Engine scope/filter helpers promoted** — `setFilter`, `setScope`,
  `setCondition`, `setException`, `setEffect` are now proper engine instance
  methods (previously implicit package-level functions relying on `$SELF`)
- **`_MAX_CYCLES` guard** — `Chorus::Engine::loop()` aborts after 10 000
  cycles by default; configurable per engine instance
- **`Chorus::Frame::_reset()`** — clears the entire frame registry; designed
  for test isolation between test cases

---

## Full working example

`sandboxes/demo_en` — timber-frame construction compliance
against BS EN 338, EC5, Building Regulations Part L/B, BS EN 13501.

```sh
perl sandboxes/demo_en/run.pl sandboxes/demo_en/project-01.json
```

---

## The underlying engine

The `chorus-*` pipeline is built on a pure-Perl inference engine with no
runtime dependencies beyond standard CPAN (`YAML`, `Scalar::Util`, `Digest::MD5`).

Chorus implements the classical **recognize–act** cycle from the expert-system
tradition: at each iteration, the engine identifies which rules apply to the
current working memory, fires them, and restarts — until nothing changes or a
goal is reached.

The working memory is made up of `Chorus::Frame` objects whose properties
(slots) carry domain knowledge. `Chorus::Expert` chains multiple specialised
engines over a shared working memory.

### Direct API — ten lines

```perl
use Chorus::Engine;
use Chorus::Frame;

my $agent = Chorus::Engine->new();

Chorus::Frame->new(color => 'blue', label => 'sky');
Chorus::Frame->new(color => 'red',  label => 'fire');

$agent->addrule(
    _SCOPE => { f => sub { [ fmatch(color => 'blue') ] } },
    _APPLY => sub {
        my %o = @_;
        return if $o{f}->{tagged};
        $o{f}->set('tagged', 'yes');
        print "Tagged: ", $o{f}->label, "\n";   # → Tagged: sky
        return 1;
    },
);

$agent->loop();
```

The YAML DSL expresses the same logic without Perl boilerplate, with declarative
pipeline termination via the `TERMINAL` field.

> Full technical reference:
> `perldoc Chorus::Engine` · `perldoc Chorus::Frame` · `perldoc Chorus::Expert`

---

## Installation

```sh
cpanm Chorus::Engine
```

Or from source:

```sh
perl Makefile.PL && make && make test && make install
```

---

## Documentation

- [`doc/en/01-intro.md`](doc/en/01-intro.md) — concepts, architecture, YAML DSL
- [`doc/en/02-ai-agent.md`](doc/en/02-ai-agent.md) — LLM + Chorus pipeline, AI agent integration
- [`doc/en/03-applications.md`](doc/en/03-applications.md) — application domains (construction, CSRD, MDR, DO-178C…)
- [`doc/en/04-chorus-commands.md`](doc/en/04-chorus-commands.md) — `chorus-*` commands reference
- [`doc/fr/01-intro.md`](doc/fr/01-intro.md) — concepts, architecture, DSL YAML (fr)
- [`doc/fr/02-ai-agent.md`](doc/fr/02-ai-agent.md) — pipeline LLM + Chorus (fr)
- [`doc/fr/03-applications.md`](doc/fr/03-applications.md) — domaines d'application (fr)
- [`doc/fr/04-chorus-commands.md`](doc/fr/04-chorus-commands.md) — référence des commandes `chorus-*` (fr)

---

## Contributing

Contributions are welcome — bug reports, documentation fixes, new examples,
or rule engine improvements.

- **Bug reports / feature requests** — open an [Issue](https://github.com/maelink/Chorus-Engine/issues)
- **Pull requests** — target the `devel` branch; make sure `make test` passes
- **Good first issues** — look for the [`good first issue`](https://github.com/maelink/Chorus-Engine/issues?q=label%3A%22good+first+issue%22) label
- **Questions** — use [GitHub Discussions](https://github.com/maelink/Chorus-Engine/discussions)
  or the CPAN RT queue: <https://rt.cpan.org/Dist/Display.html?Name=Chorus-Engine>

---

## Repository

<https://github.com/maelink/Chorus-Engine>
