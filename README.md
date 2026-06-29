# Chorus::Engine

[![CPAN version](https://badge.fury.io/pl/Chorus-Engine.svg)](https://metacpan.org/dist/Chorus-Engine)
[![Perl](https://img.shields.io/badge/perl-5.006%2B-blue)](https://www.perl.org/)
[![License](https://img.shields.io/badge/license-Artistic--2.0-green)](LICENSE)

> A pure-Perl inference engine. No runtime dependencies beyond standard CPAN.
> Runs on Perl 5.006+.

Chorus implements the classical **recognize–act** cycle from the expert-system
tradition (CLIPS, OPS5, OPS83): at each iteration, the engine identifies which
rules apply to the current working memory, fires them, and restarts — until
nothing changes or a goal is reached.

The working memory is made up of `Chorus::Frame` objects — Perl objects whose
properties (slots) carry domain knowledge, drawing from the
slot / default / procedural-attachment model introduced by Minsky (1974).

---

## Ten lines, running output

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

---

## Key properties

- **Zero runtime dependency** — only standard CPAN (`YAML`, `Scalar::Util`, `Digest::MD5`)
- **Pure Perl 5.006+** — runs anywhere, readable, auditable
- **Frames with slots** — inheritance, procedural attachments (`_NEEDED`, `_AFTER`),
  backward and forward chaining
- **YAML rules** — business logic without Perl boilerplate; supports declarative
  pipeline termination via the `TERMINAL` field (`solved`/`failed` callable from pure YAML)
- **Infinite-loop guard** — `_MAX_CYCLES` (default 10 000) prevents runaway inference loops
- **Multi-agent orchestration** — `Chorus::Expert` chains specialized engines over
  a shared working memory
- **AI agent integration** — generate a full pipeline from a plain-text corpus
  (`chorus-feed` → `chorus-check`). Compatible with any AI agent (Claude, Copilot, ECA…) running natively on **Neovim, VS Code,
  IntelliJ and Emacs** — no editor lock-in.

---

## Design note

Chorus occupies a specific position in the current AI landscape.
Most hybrid systems use a language model as the decision layer and rules as
guardrails. Chorus inverts this: the LLM is an extraction tool that reads
documents and populates structured frames; the rule engine handles all reasoning.
The LLM never draws a conclusion.

This means every result is reproducible. Running `chorus-check` twice on the
same project file, on any machine, always produces the same output — no
sampling, no temperature, no randomness in the decision layer. This is not a
claim about AI architecture; it is a description of how the pipeline is wired.

> The term *neuro-symbolic* is sometimes applied to systems like Chorus.
> It is not accurate here. In neuro-symbolic systems, a neural model learns to
> simulate logical rules. In Chorus, the symbolic engine is real — frames, slots,
> inference chain — and the LLM is a preprocessing step. *Augmented symbolic*
> is a more precise label.

---

## What's new in 2.01

- **`TERMINAL` field in the YAML DSL** — declare `TERMINAL: solved` or
  `TERMINAL: failed` directly in a rule, without any Perl glue code
- **Engine scope/filter helpers promoted** — `setFilter`, `setScope`,
  `setCondition`, `setException`, `setEffect` are now proper engine instance
  methods (previously implicit package-level functions relying on `$SELF`)
- **`_MAX_CYCLES` guard** — `Chorus::Engine::loop()` aborts after 10 000
  cycles by default; configurable per engine instance
- **`Chorus::Frame::_reset()`** — clears the entire frame registry
  (`%FMAP`, `%REPOSITORY`, `%INSTANCES`, `%SERIAL`, `@Heap`…); designed
  for test isolation between test cases

---

## Full working example

`sandboxes/demo_en` — timber-frame construction compliance
against BS EN 338, EC5, Building Regulations Part L/B, BS EN 13501.

Run it in one line:

```sh
perl sandboxes/demo_en/run.pl sandboxes/demo_en/project-01.json
```

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
- [`doc/en/02-ai-agent.md`](doc/en/02-ai-agent.md) — LLM + Chorus pipeline (AI agent integration)
- [`doc/en/03-applications.md`](doc/en/03-applications.md) — application domains (construction, CSRD, MDR, DO-178C…)
- [`doc/en/04-chorus-commands.md`](doc/en/04-chorus-commands.md) — `chorus-*` commands reference (AI-assisted workflow)
- [`doc/fr/01-intro.md`](doc/fr/01-intro.md) — concepts, architecture, DSL YAML (fr)
- [`doc/fr/02-ai-agent.md`](doc/fr/02-ai-agent.md) — pipeline LLM + Chorus, intégration agent IA (fr)
- [`doc/fr/03-applications.md`](doc/fr/03-applications.md) — domaines d'application (fr)
- [`doc/fr/04-chorus-commands.md`](doc/fr/04-chorus-commands.md) — référence des commandes `chorus-*` (fr)
- `perldoc Chorus::Engine` — rules, inference loop, YAML DSL, flow control
- `perldoc Chorus::Frame` — slots, inheritance, `fmatch`, `get`, `set`, `delete`
- `perldoc Chorus::Expert` — multi-agent orchestration, shared BOARD
- `perldoc Chorus::Collection::List` — ordered frame sequences
- `perldoc Chorus::Collection::Filter` — pattern matching on sequences

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
