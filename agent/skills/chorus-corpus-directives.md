# chorus-corpus-directives

chorus-corpus-directives <sandbox-name> [--init]

## Purpose

Generic, domain-agnostic skill that governs the structuring decisions any
multi-source normative corpus needs settled *before* a first `chorus-feed`,
and re-checked whenever `chorus-feed --enrich` introduces a source not yet
covered. It contains no domain knowledge itself — only the questions to
settle and the format the answers must take.

Typical trigger case: a sandbox where a binding regulatory text (a law, a
CIR, a standard's normative body) references one or more independently
versioned technical documents (a toolbox, an implementation framework, a
referenced standard) — e.g. a CIR referencing an ARF, or Common Criteria
referencing ETSI TS 119 312 for cryptographic thresholds.

## When this skill loads

- Automatically, as the first step of `chorus-feed <sandbox> <corpus>` —
  **but only if the sandbox involves ≥2 independently-versioned normative
  sources** (e.g. a binding text referencing a separately-versioned
  technical toolbox or external standard). Single-source sandboxes (a
  standard's own parts/volumes sharing one version and publication date,
  e.g. Common Criteria Part 1/2/3) skip this gate entirely.
- Automatically, as a step of `chorus-feed <sandbox> <corpus> --enrich`,
  only if the corpus's declared source is not already listed in the
  sandbox's `CORPUS-DIRECTIVES.md` (or the file doesn't exist yet and the
  new corpus genuinely introduces a second independently-versioned source).
- On demand, via `chorus-corpus-directives <sandbox-name> --init`, to
  bootstrap or edit the file directly with the operator.

## Step 0.0 — Corpus conversion gate (ENG-077)

> **Applies always** — before any detection logic or operator-instructions read.
> `chorus-corpus-directives` governs the normative structure of the corpus; it is
> meaningless if the corpus itself is not yet in a validated Markdown form.

```
SANDBOX = $SANDBOXES/<sandbox-name>
```

### Source file scan

Scan for document source files (not yet converted or converted but not validated):

```python
import os, glob, json

SOURCE_EXTS = {'.pdf', '.docx', '.xlsx', '.csv', '.xml', '.html', '.htm'}

# Check corpus/sources/ first, then corpus/ root (non-recursive)
source_files = []
for base in [os.path.join(SANDBOX, 'corpus', 'sources'),
             os.path.join(SANDBOX, 'corpus')]:
    if os.path.isdir(base):
        for f in sorted(os.listdir(base)):
            if os.path.splitext(f)[1].lower() in SOURCE_EXTS:
                source_files.append(os.path.join(base, f))
        if base.endswith('sources'):
            break   # prefer corpus/sources/ if it exists
```

**If no source files found → gate passes trivially.** The sandbox either has no
document corpus yet (called with `--init` before depositing files) or uses only
plain-text/Markdown corpus directly — no validation required.

### Validate against `.corpus-ready.json`

```python
corpus_ready_path = os.path.join(SANDBOX, '.corpus-ready.json')
if os.path.exists(corpus_ready_path):
    with open(corpus_ready_path) as f:
        corpus_ready = json.load(f)
    validated_sources = {
        e['source'] for e in corpus_ready.get('validated', [])
        if e.get('status') == 'ok'
    }
else:
    validated_sources = set()

missing = []
for src in source_files:
    rel = os.path.relpath(src, SANDBOX)   # e.g. "corpus/sources/NIST.FIPS.186-5.pdf"
    if rel not in validated_sources:
        missing.append(rel)
```

### HARD STOP if any source is unvalidated

```
If missing is non-empty:

⛔ Corpus conversion gate — chorus-corpus-directives cannot proceed.
   N source file(s) have no validated Markdown equivalent in .corpus-ready.json:

   For each missing file, run:
     1. <skill> <sandbox> <file>              ← chorus-pdf / chorus-word / chorus-excel
     2. chorus-markdown <sandbox> <file> <output.md> --report

   Missing:
     - corpus/sources/document.pdf
       → chorus-pdf <sandbox> corpus/sources/document.pdf
       → chorus-markdown <sandbox> corpus/sources/document.pdf corpus/NNN-document-text.md --report
     ...

   Then re-run: chorus-corpus-directives <sandbox>
```

> **Never bypass this gate** by proceeding to Step 0 (operator instructions) while
> source files are unvalidated — the directives (version pinning, `no_auto_rules`
> scope) depend on reading the actual corpus content, which is not yet in a trusted form.

## Detection logic (followed by the agent)

0. **Pre-load operator instructions** — check for
   `sandboxes/<sandbox-name>/instructions-directives.md` at the sandbox root.
   - If the file exists: read it fully into context. Display:
     ```
     [chorus-corpus-directives] ✅ instructions-directives.md chargé —
       sources déclarées : <N> (liste des slugs)
       Réponses pré-remplies pour les 4 questions structurantes.
     ```
     The answers from that file (sources table, no_auto_rules justifications,
     version pinning, thesaurus seed, cross-reference format) are used
     **directly** to populate `CORPUS-DIRECTIVES.md` without asking the
     operator interactively — the skill proceeds as if the operator had
     provided those answers in the conversation.
     Open questions marked with `> ⚠️ **Point de décision**` in the
     instructions file are surfaced for explicit confirmation before
     the file is written.
   - If the file is absent: proceed normally (interactive mode — ask the
     operator the four questions in sequence).

1. Look for `sandboxes/<sandbox-name>/CORPUS-DIRECTIVES.md`.
2. If absent — bootstrap it from the template below. All four sections
   must be filled, together with the human operator, before `chorus-feed`
   is allowed to proceed on this sandbox.
3. If present — load it fully into context before touching the corpus.
4. On `--enrich` — compare the corpus file's declared source (from its
   header, or an explicit statement from the operator) against the
   `Sources` table already present in `CORPUS-DIRECTIVES.md`.
   - Match found: proceed directly to `chorus-feed`, no update needed.
   - No match: pause, classify the new source against the four questions
     below, append it to the file, then proceed.

## The four structuring questions

### 1. Version pinning

For every source with independent versioning (a binding text vs. a
referenced technical toolbox or standard), record which version of each
was current when the other was adopted, or which version is intended to
apply. Never let an import silently follow a toolbox's "latest" when its
binding counterpart references a fixed version at a fixed date.

### 2. `no_auto_rules` scope

Classify every declared source as either:

- **rule-generating** — its text directly yields `FIND`/`EXCEPTION`/
  `CONDITION`/`ACTION` rules, article by article, opposable in a
  conformity verdict.
- **`no_auto_rules: true`** — doctrine, context, or technical-reference
  material: feeds the thesaurus and is available for cross-reference at
  check time, but never auto-generates a rule on its own.

Record the classification per source, with a one-line justification.

### 3. Thesaurus seed

Before the first `chorus-feed` / `chorus-import-project` pass, list known
synonym or near-synonym pairs across the declared sources (differing
terms for the same concept, e.g. `Wallet Solution` / `Wallet Instance`).
Seed `KB/terminologie.yaml` with these before ingestion rather than
discovering them mid-run.

### 4. Cross-reference format

Fix, once per sandbox, the notation used to record "clause X of source A
⇒ section Y of source B" links, so cross-references stay consistent
across every later `chorus-feed --enrich` pass.

## Template — `CORPUS-DIRECTIVES.md`

```markdown
# Corpus directives — <sandbox-name>

## Sources
| Source | Type | Version pinned | no_auto_rules |
|---|---|---|---|
| <name> | binding / technical-reference / doctrine | <version @ date> | true / false |

## Version pinning notes
- <binding source> references <technical source> at version <X>, as adopted
  on <date>. Do not follow the technical source's live/latest version.

## no_auto_rules justification
- <source>: <one-line reason>

## Thesaurus seed
| Term A | Term B | Same concept? |
|---|---|---|
| ... | ... | ... |

## Cross-reference format
<binding-source-ref> ⇒ <technical-reference-ref>
Example: `Art. 5a(23) CIR 2024/2982 ⇒ ARF v1.x §6.6.3`
```

## Output

- Creates or updates `sandboxes/<sandbox-name>/CORPUS-DIRECTIVES.md`.
- Blocks progression to `chorus-feed` until the four sections are
  non-empty for every declared source.
- Does not touch `KB/`, `rules/`, or `agent/agents/` — this is a
  pre-flight gate, not a KB-building step.

## Relationship to other skills

- **Upstream of `chorus-feed`** — first call on a sandbox, and any
  `--enrich` call introducing a source not yet declared.
- **Independent of `chorus-fit-assessment`** — that skill is the earlier
  go/no-go decision (four-axis grid) on whether a domain deserves Chorus
  at all; this skill assumes the answer is already yes and is not
  domain-specific.
- **Independent of `chorus-import-project`** — that skill aligns an
  engineer's project/dossier data against an existing KB (Phase B
  instance data); this skill governs corpus/KB construction (Phase A).
