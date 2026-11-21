# Skill — chorus-markdown

> Trigger: `chorus-markdown <sandbox> <source> <output.md> [--strict] [--report]`
> Agent: `code`
>
> `<sandbox>`: name of the sandbox directory under `$SANDBOXES/`
> `<source>`: original document (PDF, DOCX, XLSX, or plain-text corpus) used as
>   the fidelity reference — resolved absolute, or relative to `$SANDBOX/corpus/`
> `<output.md>`: Markdown (or `.txt`) file to validate — resolved absolute, or
>   relative to `$SANDBOX/corpus/`
> `--strict`: any anomaly blocks the pipeline (non-zero exit code)
> `--report`: produce a validation report at
>   `$SANDBOX/workspace/reports/markdown-check-<slug>.md`
>
> **Single responsibility: verify that a Markdown/text file produced by a
> conversion or alignment skill is faithful to its source document.**
> This skill never modifies `<output.md>` — it only inspects it and reports.
>
> Callable by any skill producing Markdown from a document: `chorus-pdf`,
> `chorus-word`, `chorus-excel`, `chorus-import-project`, optionally
> `chorus-feed` (enriched corpus check).

## ⛔ Strict sandbox isolation

Never read any KB, YAML, or artifact from a sandbox other than `<sandbox>`.
This skill operates exclusively on `<source>` and `<output.md>` as given —
no inference from other files in the sandbox.

## Overview

`chorus-pdf`, `chorus-word`, and `chorus-excel` all convert a source document
into an enriched Markdown/text corpus file. Each of these skills previously
defined its own ad hoc fidelity checks (or none at all), leading to silent
loss of structure that propagates downstream: `chorus-feed` ingests a
degraded corpus, generated rules may be wrong, and `chorus-import-project`
aligns values against mis-extracted terms.

This skill centralises fidelity validation in **one place**, with controls
derived directly from concrete failure patterns observed in production
(see `agent/kb/pitfalls.org` § extraction, and audit referenced in
`todo-history/TODO.org` § ENGINE `[#J]`).

> ⛔ **This skill does not fix anomalies.** It only detects and reports them.
> Fixing a detected anomaly (e.g. re-running `chorus-pdf --hybrid` on a
> flagged page, manually reconstructing a borderless table) remains the
> responsibility of the calling skill or a human operator.

## Known failure patterns this skill targets

Derived from a cold re-conversion audit of `chorus-pdf` in text-only mode
(no vision fallback) on two real normative documents (Common Criteria Part 2,
ANSSI crypto guide) — see `todo-history/TODO.org` § `[#J]` for full detail:

| Pattern | Symptom | Silent? |
|---|---|---|
| Borderless table flattening | Whitespace-only tables collapse into isolated `X`/`-` lines, losing row/column structure | ✅ yes — extraction log's table counter does not detect it |
| Rotated-header matrix | Column headers printed one character per line (90° rotation) become stacks of single-char lines | ✅ yes — output looks like normal text, no visible failure signal |
| Table-count log unreliability | Extraction log reports N tables found, but the source document contains many more (not just the ones with drawn borders) | ✅ yes — the only visible signal (log) is misleading |
| Legislative two-column table (ENG-075) | Tables *Disposition / Rédaction résultant de* in legal/regulatory corpora have no `Table N` label and no numeric content — both §2.3a and §2.3b miss them; two columns appear as alternating text lines | ✅ yes — §2.3a needs `Table N` proximity; §2.3b needs ≥60% numeric lines; §2.2 scores 0 vs 0 (no `Table N` in source) |
| Ambiguous flattened exponents | `2^128` becomes `2128`, visually indistinguishable from a 4-digit integer | ✅ yes — no character is lost, only semantics |
| Mid-formula text-block splitting | A formula mixed with prose gets split across two text blocks by `pdfminer` layout analysis | ⚠️ partial — content preserved, but sentence/section segmentation downstream may be affected |
| No formula placeholder in text mode | Unlike `[FIGURE — not extracted]`, formulas are never flagged, correctly rendered or not | ✅ yes — no way to locate risk zones without reading the whole document |

## Phase 0 — Resolve inputs

### 0.1 Resolve the sandbox path

```
SANDBOX = $SANDBOXES/<sandbox>
```

Verify that `$SANDBOX/corpus/` exists. If not, abort with:
```
⛔ Sandbox '<sandbox>' not found or has no corpus/ directory.
```

### 0.2 Resolve `<source>` and `<output.md>`

Both accept an absolute path or a path relative to `$SANDBOX/corpus/`.
Abort with a clear message if either file does not exist.

### 0.3 Detect source type

Detect `<source>` type by extension: `.pdf`, `.docx`, `.xlsx`/`.csv`, or
plain text/Markdown (treated as "already-text" reference — word-count
checks only, no table/figure-count extraction needed).

## Phase 1 — Build the reference signal from `<source>`

This phase extracts **lightweight structural counts** from the original
document — never a full re-conversion (that would duplicate `chorus-pdf`/
`chorus-word`/`chorus-excel` work). Goal: cheap counters to compare against
`<output.md>`, not a parallel extraction pipeline.

> ⚠️ **Mandatory environment diagnostic.** The generated
> `agent/validate-markdown-<slug>.py` script must log, in its first lines of
> execution, the actually-installed versions of every optional dependency it
> ends up using (mirrors the requirement in `chorus-pdf.md` Phase 0.0/Phase 2):
> ```python
> import sys, importlib.metadata as _ilmd
> _pkgs = ("pdfminer.six", "python-docx", "openpyxl")
> _parts = []
> for _pkg in _pkgs:
>     try:
>         _parts.append(f"{_pkg}=={_ilmd.version(_pkg)}")
>     except _ilmd.PackageNotFoundError:
>         _parts.append(f"{_pkg}==<not installed>")
> print(f"[chorus-markdown] Environment: {', '.join(_parts)} (interpreter: {sys.executable})",
>       file=sys.stderr)
> ```
> This script has no `os.execv()` bootstrap (unlike `chorus-pdf`'s pdfplumber
> re-exec), so `sys.executable` always reflects the launching interpreter —
> still worth logging for cross-checking against the other skills' scripts.

### 1.1 PDF source

Use `pdfminer.six` (already a dependency of `chorus-pdf`) in a minimal pass:
- Count headings matching `Table \d+`, `Tableau \d+`, `Figure \d+` in the
  raw text layer (regex on concatenated page text).
- Count total words (whitespace-split) across all pages — reference word
  count for the length-ratio check (§1.5).
- Run `pdftotext -layout <source> -` (same tool already used as the
  comparison baseline in `chorus-pdf`'s own blind-spot documentation,
  §1.4c/§1.4d) on pages where a `Table N` heading was found, to produce a
  layout-preserving reference snippet usable in the report (§ Phase 3).

> ⚠️ `pdfminer.six` is a hard dependency for this branch. Abort with
> `⛔ pdfminer.six not installed. Run: pip install pdfminer.six` on
> `ImportError`. On success, log:
> `[chorus-markdown] Reference extraction: pdfminer.six active (N heading(s), M word(s) counted)`


> ⚠️ **`pdftotext` (poppler-utils) is an optional dependency for this
> sub-step only.** If `subprocess.run(["pdftotext", ...])` raises
> `FileNotFoundError` (binary absent), the script must emit an explicit
> warning — not silently drop the layout-preserving snippet from the
> report:
> ```python
> try:
>     result = subprocess.run(["pdftotext", "-layout", source_pdf, "-"],
>                              capture_output=True, text=True, check=False)
>     pdftotext_available = True
> except FileNotFoundError:
>     pdftotext_available = False
>     print("[chorus-markdown] ⚠️  pdftotext not found (poppler-utils) — "
>           "report will omit layout-preserving reference snippets for "
>           "Table N localisation (degraded report detail, not a validation "
>           "failure). Install: sudo apt install poppler-utils",
>           file=sys.stderr)
> ```
> This is distinct from `chorus-pdf.md` §1.4c/§1.4d (which use the same
> binary as a *fallback extraction strategy*): here `pdftotext` absence only
> degrades report readability (no snippet to show next to a `❌`/`⚠️` row),
> it never changes a control's pass/fail outcome.


### 1.2 DOCX source

Use `python-docx` (dependency of `chorus-word`): count `document.tables`
(native table objects — DOCX tables are structural, not whitespace-based,
so this count is exact, unlike the PDF case) and total paragraph word count.

> ⚠️ `python-docx` is a hard dependency for this branch (no graceful
> fallback possible — DOCX structure cannot be approximated otherwise).
> If `import docx` raises `ImportError`, abort immediately with
> `⛔ python-docx not installed. Run: pip install python-docx` rather than
> silently skipping the DOCX reference extraction.
> On success, log the usage explicitly:
> `[chorus-markdown] Reference extraction: python-docx active (N table(s), M paragraph(s) counted)`

### 1.3 XLSX/CSV source

Use `openpyxl` (dependency of `chorus-excel`): count non-empty cells per
sheet, sheet count, and total textual cell content word count.

> ⚠️ `openpyxl` is a hard dependency for this branch — same rationale as
> §1.2. Abort with `⛔ openpyxl not installed. Run: pip install openpyxl`
> on `ImportError`. On success, log:
> `[chorus-markdown] Reference extraction: openpyxl active (N sheet(s), M non-empty cell(s) counted)`


### 1.4 Plain-text/Markdown source

No extraction needed — the source file itself is both reference and
word-count baseline (used only when `<output.md>` is a second-pass file,
e.g. `chorus-import-project` alignment output derived from another `.md`).

## Phase 2 — Validate `<output.md>` against the reference

Each control below produces one row of the validation table (§ Phase 3).
Severity: `❌` (fails `--strict`), `⚠️` (warning, does not fail `--strict`
unless escalated by a specific rule noted below).

### 2.1 Complétude sections

Count headings (`#`, `##`, …, or `Table N`/`Figure N` style markers) in
`<output.md>`. Compare against the heading/table/figure count from Phase 1.
- `❌` if the output has **strictly fewer** structural markers than the
  source reference count (indicates dropped sections).
- `⚠️` if counts match but order cannot be verified cheaply (no strict
  ordering check in this skill — out of scope, see § Out of scope).

### 2.2 Tableaux — syntactic validity and count mismatch

- For every Markdown pipe table block (`| ... | ... |` followed by a
  `|---|---|` separator line) in `<output.md>`: verify column count is
  consistent across all rows of that block. `❌` on mismatch (malformed
  table — a conversion artifact, not a source defect).
  > ⚠️ **Separator-first tables (`--auto` mode blind spot):** Claude vision
  > occasionally generates tables **without a header row**, starting directly
  > with the separator `|---|...|`. The detection logic uses `block[0]` as
  > reference — if `block[0]` is a separator with M cols and data rows have
  > N≠M cols, the table is correctly flagged `❌`. Fix: use `pdftotext -layout
  > -f <page> -l <page> <pdf>` to verify the real column count; regenerate
  > the separator with the data rows' majority column count. See
  > `chorus-pdf.md § "Auto mode — separator-first table fix"` for the full
  > repair procedure.
- **Table-count mismatch** (the audit's #1 finding — T1/T3): compare the
  number of `Table N`/`Tableau N` headings found in `<output.md>` against
  the number found in the source reference (§1.1/§1.2/§1.3). `❌` if the
  output count is **lower** than the source count — this is the primary
  signal against the known "table count in extraction log is not a
  reliable completeness indicator" blind spot. Report exactly which
  `Table N` labels are present in the source but absent as a pipe-table
  block in the output.

### 2.3 Détection de cellules concaténées sans séparateur (borderless flattening)

Two independent sub-heuristics, both `⚠️` by default:

**§2.3a — Standard pattern (normative documents with `Table N` labels):**
Scan for runs of **≥ 4 consecutive short lines** (each ≤ 3 non-whitespace
characters, e.g. `X`, `-`, `O`, a bare digit) occurring within 15 lines of
a `Table N`/`Tableau N` heading, with **no** `|` pipe character anywhere in
that span. `⚠️` (false-positive risk on short list items; escalate to `❌`
under `--strict` only when combined with a confirmed table-count mismatch
from §2.2 on the same `Table N`).

**§2.3b — Unlabelled numeric table (CCTP / commercial documents):**
Scan the full output independently of any `Table N` proximity for a
**`=== PAGE N ===` block** that simultaneously satisfies **all three**
conditions:
1. Contains **≥ 5 consecutive non-empty lines** with **no** `|` pipe
   character and no `#` heading marker.
2. At least **60 %** of those lines match the pattern of an isolated
   dimensional value: `^\s*\d[\d\s]*(\s*(mm|cm|m|kg|N|%))?\s*$` — i.e.
   a number optionally followed by a unit, possibly with spacing artifacts
   from `pdfminer` layout analysis (e.g. `1 350`, `60`, `1 490`).
3. The page does **not** already contain a pipe table block covering
   the same content (no `| --- |` separator within the same page block).

`⚠️` on match. Report: page number, number of matching lines, sample values.
Escalate to `❌` under `--strict`.

> **Rationale (incident 01-PMR, 2026-11-01):** the dimensional table
> GAINE/PYLONE (Largeur/Profondeur/Ht Fosse) in an Etna France CCTP was
> completely flattened — each cell on its own line, column structure lost.
> §2.3a missed it because (a) no `Table N` label, (b) values like `1 350`
> exceed the 3-char threshold. §2.3b covers this class of document.
>
> **False-positive guard:** condition 2 (≥ 60 % numeric lines) distinguishes
> a flattened dimensional table from a normal bulleted list, which typically
> contains only 0–1 numeric lines in a 5-line run.

**§2.3c — Tableaux législatifs textuels (corpus droit / réglementation) :**
Scan du fichier output pour des blocs vérifiant **simultanément** :

1. **≥ 4 paires** de lignes consécutives alternant :
   - Ligne impaire (disposition) : correspond à
     `^\s*(Articles?\s+[A-Z]\.\s*\d[\d\s\-à]+(-\d+)?|[A-Z]\w[\w\s]+\s+[A-Z]\.\s*\d[\d\s\-à]+)`
     — ex. `Article L. 411-1`, `Articles R. 611-1 à R. 611-8`
   - Ligne paire (source) : contient
     `(Loi|Ordonnance|D[eé]cret|Arr[eê]t[eé])\s+n[o°]`
     — ex. `Loi n° 92-597 du 1er juillet 1992`, `Ordonnance n° 2021-1518`
2. **Aucun** caractère `|` dans le bloc (structure tabulaire perdue)
3. *(Optionnel, renforce la confiance)* : un titre `DISPOSITIONS\s+APPLICABLES`
   ou `DANS\s+LEUR\s+R[EÉ]DACTION` présent dans les 5 lignes précédant le bloc

`⚠️` sur toute correspondance. Rapport : numéro de page (`=== PAGE N ===`
englobant), nombre de paires détectées, 2 lignes d'exemple.
Escalade en `❌` sous `--strict`.

> **Rationale (ENG-075, 2026-11-21) :** les tableaux législatifs à deux
> colonnes *Disposition / Rédaction résultant de* (ex. Code de la propriété
> intellectuelle, pages 300 et 634) n'ont pas de label `Table N` → §2.3a
> aveugle ; leur contenu est purement textuel → §2.3b aveugle ; pdfminer
> ne compte aucun `Table N` dans le PDF source → §2.2 triviallement ✅.
> Ce pattern est fréquent dans tout corpus de droit public français
> (codes, ordonnances, décrets d'applicabilité outre-mer).

### 2.4 Détection de colonnes mono-caractère empilées (rotated-header pattern)

Heuristic for pattern T2. Reuse the detection logic already sketched in
`chorus-pdf.md` §1.4c (`detect_rotated_headers()`) as a **post-hoc**
validator here rather than only as a pre-filter in the extraction skill
itself: a run of **≥ 6 consecutive lines of 1–2 characters** within a
`Table N` span. `⚠️` — this pattern is visually indistinguishable from
normal prose without the positional context, so it is reported for human
review rather than auto-failed even under `--strict`.

> 🔍 **Triage de tout `⚠️`/`❌` (§2.2 à §2.7) :** avant de conclure à un
> défaut du PDF source, appliquer la procédure de comparaison croisée
> `pdftotext -layout` vs `pdfminer`/`pdfplumber` documentée dans
> `chorus-pdf.md` § "Cross-tool comparison — standard triage procedure for
> suspect pages" (`pdftotext -layout -f <page> -l <page> <pdf> -`). Si
> `pdftotext -layout` reconstruit une structure cohérente que `pdfminer`
> a ratée, le défaut vient de l'heuristique de layout — pas du contenu du
> PDF (cf. findings T1/T2 de l'audit `[#J]`, qui ont justement été établis
> via cette méthode sur les patterns détectés en §2.3/§2.4 ci-dessus).

### 2.5 Formules — placeholder presence

- Search `<output.md>` for `[FORMULA: ...]` placeholders (the convention
  documented in `chorus-pdf.md` §3 "Formulas", to be introduced by
  `[#K]`). Report the count found.
- **Not a failing condition today**: as of this skill's first version,
  `chorus-pdf` text mode does not yet emit this placeholder (confirmed
  gap — see audit `[#J]` § F3). This control is therefore informational
  (`ℹ️`) until `[#K]` ships the placeholder in `chorus-pdf`'s extraction
  script. Re-classify as `⚠️`/`❌` once `[#K]` is delivered.
- **Ambiguous-exponent heuristic** (pattern F1): flag occurrences of
  `\b2\d{2,3}\b`-style digit runs immediately preceded by `2` with no `^`
  or Unicode superscript, **only** when occurring within a paragraph
  containing at least one of the context keywords `bits`, `calculs`,
  `opérations`, `complexité`, `collision` (French corpus) or `bits`,
  `operations`, `complexity`, `collision` (English corpus) — to limit
  false positives on years/identifiers. `⚠️` only (never `❌` — high
  false-positive risk, human judgment required).

### 2.6 Longueur — ratio mots source / mots `.md`

Compare total word count of `<output.md>` against the Phase 1 reference
word count. `❌` if ratio falls outside **[0.70, 1.30]** (±30%). A ratio
far below 0.70 is a strong secondary signal of silent content loss
(correlates with §2.2/§2.3 findings); a ratio far above 1.30 suggests
duplication or runaway vision-mode hallucination.

### 2.7 Encodage — residual replacement characters

Search `<output.md>` for `\uFFFD` (Unicode replacement character) and the
literal substring `(cid:` (pdfminer's raw glyph-ID fallback when a font's
character mapping is missing — never a semantically interpretable
sequence). `❌` on any occurrence — this is always a defect, never a
false positive.

### 2.8 XREF — cross-reference presence

If the source reference (§Phase 1) contains tagged cross-references
(`[FIG-N]`, `[TABLE-N]` convention from `chorus-word`'s XREF pass, or
figure/table numbering from `chorus-pdf`), verify each one referenced in
prose also has a corresponding block/heading in `<output.md>`, and
vice-versa (orphan detection — a block present without any in-text
reference to it, or a reference with no matching block). `⚠️` — reported
for review, not auto-failed.

## Phase 3 — Report generation (`--report`)

Written to `$SANDBOX/workspace/reports/markdown-check-<slug>.md`
(`<slug>` derived from `<output.md>`'s filename stem). Directory created
if absent.

Structure:

```markdown
# Markdown fidelity check — <output.md>

Source: <source>
Checked: <date>
Mode: --strict / (none)

## Synthèse

| Contrôle | Statut | Détail |
|---|---|---|
| Complétude sections | ✅ | 12/12 headings matched |
| Tableaux — validité syntaxique | ✅ | 4 pipe tables, all consistent |
| Tableaux — comptage vs source | ❌ | Source: 9 "Table N" headings — Output: 3 pipe tables. Missing: Table 1, Table 4, Table 5, Table 6, Table 7, Table 8, Table 9 |
| Cellules concaténées (borderless) | ⚠️ | 2 suspect zones near "Table 1" (page unknown — source is PDF, no page anchor in output) |
| Colonnes mono-caractère (rotated header) | ⚠️ | 1 suspect zone near "Table 3" |
| Formules — placeholder | ℹ️ | 0 `[FORMULA: ...]` found (not yet emitted by chorus-pdf — see [#K]) |
| Formules — exposants ambigus | ⚠️ | 2 occurrences: "2128" (context: "opérations"), "263" (context: "calculs") |
| Longueur — ratio mots | ❌ | ratio 0.41 (source: 18420 words, output: 7552 words) |
| Encodage | ✅ | no U+FFFD, no (cid:...) |
| XREF | ⚠️ | 1 orphan reference: "[TABLE-5]" cited in text, no matching block |

## Détail des anomalies

### ❌ Tableaux — comptage vs source
...

### ❌ Longueur — ratio mots
...
```

Every `❌`/`⚠️` row must include enough localisation (heading name, nearby
line number in `<output.md>`, or page/section hint from the source) for a
human operator to find the anomaly without re-reading the whole document.

## Phase 4 — Exit behaviour

| Condition | `--strict` absent | `--strict` present |
|---|---|---|
| Only `✅`/`ℹ️` rows | exit 0 | exit 0 |
| At least one `⚠️` row | exit 0 (warning printed to stderr) | exit 0 (unless escalated per §2.3 rule) |
| At least one `❌` row | exit 0 (warning printed to stderr) | **exit 1** |

Without `--strict`, this skill never blocks the calling pipeline — it is
purely advisory unless the caller explicitly opts into hard failure.

## Integration

```
chorus-pdf        ──┐
chorus-word       ──┼──► chorus-markdown (validation post-extraction)
chorus-excel      ──┘

chorus-import-project ──► chorus-markdown (validation du .md d'alignement, optionnel)
chorus-feed           ──► chorus-markdown (validation du corpus enrichi, optionnel)
```

Each calling skill documents, in its own "Post-processing" / "Integration"
section, when and how to invoke `chorus-markdown`, with recommended flags.
As of this skill's first version: `chorus-word.md`, `chorus-excel.md`, and
`chorus-import-project.md` invoke it (see their respective Integration
sections). `chorus-pdf.md` invocation is deferred to `[#K]` (TODO.org),
which also introduces the `[FORMULA: ...]` placeholder this skill's §2.5
control depends on for full (non-informational) severity.

## Out of scope (first version)

- **Section ordering verification** — only counts are compared, not
  sequence (would require a much heavier diff-style alignment; deferred).
- **Automatic fixing** — this skill never edits `<output.md>`.
- **Full re-extraction as ground truth** — Phase 1 uses lightweight
  counters, not a parallel full conversion (would duplicate `chorus-pdf`/
  `chorus-word`/`chorus-excel` and defeat the purpose of a fast check).
- **Formula content fidelity** — only placeholder *presence* is checked
  (§2.5), never whether a transcribed formula is mathematically correct.

## Dependencies

| Package | Install | Used for |
|---------|---------|----------|
| `pdfminer.six` | `pip install pdfminer.six` | PDF source reference extraction (§1.1) |
| `python-docx` | `pip install python-docx` | DOCX source reference extraction (§1.2) |
| `openpyxl` | `pip install openpyxl` | XLSX source reference extraction (§1.3) |
| `pdftotext` (poppler-utils) | system package | Layout-preserving snippet for report localisation (§1.1) |

> ℹ️ No `ANTHROPIC_API_KEY` dependency — this skill performs no LLM calls,
> only deterministic structural counting and regex heuristics.

## Quick Reference — Naming Conventions

| Artifact | Convention | Example |
|----------|-----------|---------|
| Validation script | `agent/validate-markdown-<slug>.py` | `agent/validate-markdown-cctp-structure.py` |
| Report (`--report`) | `workspace/reports/markdown-check-<slug>.md` | `workspace/reports/markdown-check-cctp-structure.md` |

## Phase 5 — Update `.corpus-ready.json` (after successful validation)

When `chorus-markdown` exits with code 0 (validation passed — no `❌` row,
or `--strict` absent), update the sandbox root's `.corpus-ready.json` marker
file to record this source/`.md` pair as validated. This file is consumed by
the corpus conversion gate in `chorus-corpus-directives`, `chorus-corpus-scoping`,
`chorus-feed`, and `chorus-feed-unattended` to verify that all source documents
are converted and validated before the pipeline starts.

> **`.corpus-ready.json` is never committed** (like `.chorus-wip.md`). Add it to
> `.gitignore` if not already excluded. It is a transient validation marker — it
> can always be regenerated by re-running `chorus-markdown` on each source/`.md` pair.

### 5.1 Read or initialize

```python
import json, os, datetime

corpus_ready_path = os.path.join(SANDBOX, '.corpus-ready.json')

if os.path.exists(corpus_ready_path):
    with open(corpus_ready_path) as f:
        corpus_ready = json.load(f)
else:
    corpus_ready = {"validated": [], "pending": []}
```

### 5.2 Build the entry

```python
entry = {
    "source": os.path.relpath(source_abs, SANDBOX),    # e.g. "corpus/sources/NIST.FIPS.186-5.pdf"
    "md":     os.path.relpath(output_md_abs, SANDBOX),  # e.g. "corpus/021-fips186-5-dss.md"
    "report": f"workspace/reports/markdown-check-{slug}.md" if report_flag else None,
    "date":   datetime.date.today().isoformat(),
    "status": "ok"
}
```

Where `source_abs` is the absolute path of `<source>` (Phase 0.2) and `output_md_abs`
is the absolute path of `<output.md>`. `slug` is derived from `<output.md>`'s filename
stem (same convention as Phase 3's report filename).

### 5.3 Upsert by source path

Remove any existing entry for the same `source` path, then append the new entry:

```python
corpus_ready["validated"] = [
    e for e in corpus_ready["validated"]
    if e.get("source") != entry["source"]
]
corpus_ready["validated"].append(entry)
# Remove from pending if previously failed
corpus_ready["pending"] = [
    e for e in corpus_ready.get("pending", [])
    if e.get("source") != entry["source"]
]
```

### 5.4 Write

```python
with open(corpus_ready_path, 'w') as f:
    json.dump(corpus_ready, f, indent=2, ensure_ascii=False)
print(f"[chorus-markdown] ✅ .corpus-ready.json updated — "
      f"{entry['source']} → {entry['md']}", file=sys.stderr)
```

### 5.5 Failure case — `--strict` exit-1

When `--strict` is active and at least one `❌` row exists (exit code 1),
`.corpus-ready.json` is **not** updated with `status: "ok"`. Instead, write a
`"failed"` entry in `pending` to signal "conversion done but validation failed":

```python
# Only on --strict exit-1 failure
failed_entry = {
    "source": entry["source"], "md": entry["md"],
    "date":   entry["date"],   "status": "failed"
}
corpus_ready["pending"] = [
    e for e in corpus_ready.get("pending", [])
    if e.get("source") != entry["source"]
]
corpus_ready["pending"].append(failed_entry)
# Write (pending section only updated — validated section unchanged)
with open(corpus_ready_path, 'w') as f:
    json.dump(corpus_ready, f, indent=2, ensure_ascii=False)
print(f"[chorus-markdown] ⛔ .corpus-ready.json — "
      f"{entry['source']} marked failed (--strict, ❌ present)", file=sys.stderr)
```

A source file in `pending` is treated the same as a missing entry by the
corpus conversion gate: the pipeline cannot proceed until `chorus-markdown`
runs again and exits 0 for that source.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `⛔ Sandbox '<sandbox>' not found` | Wrong sandbox name or missing `corpus/` | Verify `$SANDBOXES/<sandbox>/corpus/` exists |
| All rows `ℹ️`/`✅` but output "feels" incomplete | Lightweight counters (Phase 1) do not catch every pattern — see § Out of scope | Combine with manual spot-check per `chorus-pdf.md` §1.4g checklist |
| Table-count mismatch (§2.2) reports 0 missing but output is visibly truncated | Source document uses non-standard table numbering (not `Table N`/`Tableau N`) | Manual review required — this heuristic depends on conventional numbering |
