# Skill — chorus-complete-report

> Trigger: `chorus-complete-report [<sandbox-name>] [<entity>] [--slug <slug>] [--source <file>]`
> Agent: `architect`
>
> All four arguments are **optional when already available from context**
> (e.g. when invoked from a chorus-web ECA terminal that already knows the
> current sandbox and entity).
>
> `<sandbox-name>` : sandbox containing the reports to enrich.
>                    Default: current sandbox from context.
>
> `<entity>`       : entity sub-folder under `workspace/` (e.g. `test-1`, `eviden`).
>                    Default: current entity from context.
>
> `--slug <slug>`  : timestamp slug of the run-report to process,
>                    i.e. the `YYYYMMDD-HHMMSS` part of
>                    `workspace/<entity>/reports/run-report-<slug>.json`.
>                    Default: most recent `run-report-*.json` for the entity.
>                    Example: `--slug 20261002-110429`
>
> `--source <file>`: filename of the original source document to cross-check against,
>                    looked up in `workspace/<entity>/sources/<file>`.
>                    **Optional** — auto-resolved from `_import.source_file` in the
>                    project JSON (see Phase C0 step 4) when not provided explicitly.
>                    Example: `--source cbom-01.json`
>
> **Full example:** `chorus-complete-report 08-ANSSI-PG-083_MULTI-SOURCES test-1 --slug 20261002-110429 --source cbom-01.json`
>
> **Single responsibility:** for every element left uncertain (`❓ incertain` /
> `_a_confirmer`) by a prior `chorus-check --explain`/`--summary` run, go back to the
> **original source document** (whatever its format) and determine whether the
> uncertainty reflects a genuine limitation of the source data itself, or an
> artefact/approximation introduced by the import pipeline (`chorus-import-project`
> and its extensions). Patch the existing `explain-*`/`synthese-*` reports with the
> outcome — **never** re-run the compliance pipeline, **never** change any verdict.
>
> Prerequisite: `chorus-check <sandbox-name> <fichier-project> --explain --summary`
> must have already produced `$WORKSPACE/reports/explain-<slug>-NNN.md` (and, if
> `--summary` was used, `$WORKSPACE/reports/synthese-<slug>-NNN.md`) — resolved as
> `$SANDBOX/workspace/<entity>/reports/`.
>
> ⚠️ **This skill is domain- and format-agnostic.** It must never hardcode assumptions
> about a specific source format (JSON schema, PDF structure, spreadsheet layout, or
> any particular standard/tool). All format-specific extraction logic is described
> generically below (Phase C2) and must be re-derived from the actual source file
> found in the sandbox — never from a fixed example baked into this skill.


## Rationale

`chorus-check --explain` already classifies each `❓ incertain` / `_a_confirmer`
element and documents *why* the KB/rules could not conclude (missing slot,
ambiguous mapping, etc. — see `chorus-check.md § Phase E2` step 5). What it does
**not** do is go back to the raw original document and check whether the missing
or ambiguous data is actually present there but lost somewhere in the import
chain, or whether it is genuinely absent from the source itself.

That distinction matters operationally:

| If the data is... | Then the uncertainty is a... | Action |
|---|---|---|
| Present in the source but lost/mistranslated during import | **pipeline artefact** | Fix `chorus-import-project` / the extension module / the mapping, then re-import |
| Absent from the source itself | **genuine source limitation** | No pipeline fix possible; verdict must be validated manually, or a richer source document/dataset must be obtained |

`chorus-complete-report` formalises and automates this one specific
cross-check — turning an open question ("is this uncertain because of us, or
because of them?") into a closed, evidenced answer, without touching the
compliance verdicts themselves.

> This skill does not replace `chorus-audit-import` (which audits an imported
> project JSON against its source *before* `chorus-check` runs, to patch the
> JSON itself). `chorus-complete-report` runs *after* `chorus-check --explain`,
> targets only the elements still left uncertain in the **generated reports**,
> and never patches the project JSON — only the report files.


## Phase C0 — Locate inputs

### Step 1 — Resolve the run-report

From `--slug <slug>` (or most-recent fallback):
```
$SANDBOX/workspace/<entity>/reports/run-report-<slug>.json
```
Read `project_file` from this JSON → absolute path of the project JSON
(e.g. `.../workspace/<entity>/projet-import-cbom-004-CDX.json`).

If absent → stop: `"run-report-<slug>.json not found in workspace/<entity>/reports/ — check --slug value."`

### Step 2 — Locate explain / synthese reports

The project-slug is `basename(project_file)` without `.json`.

- `$SANDBOX/workspace/<entity>/reports/explain-<project-slug>-<slug>.md`
  (exact timestamp match preferred; fall back to highest available NNN).
  If absent → stop: `"No explain-<project-slug>-*.md found — run chorus-check --explain first."`
- `$SANDBOX/workspace/<entity>/reports/synthese-<project-slug>-<slug>.md`
  (same matching logic, optional — patch if present).

### Step 3 — Extract KB & Project context

From the `explain-*.md` header (`## 📚 KB & Project` block), read the **Origin**
line — confirms the project file and original source document reference.

### Step 4 — Resolve the source document

**If `--source <file>` is provided explicitly:**
Look up `$SANDBOX/workspace/<entity>/sources/<file>`. If absent → stop with a clear error.

**Auto-resolution (no `--source`):**
Read `_import.source_file` from the project JSON. Two path conventions coexist:

| `_import.source_file` value | Resolution |
|---|---|
| `<entity>/<file>` (e.g. `eviden/cbom.cdx.json`) | `$SANDBOX/workspace/<entity>/sources/<file>` |
| Path starting with `workspace/` or `/` | Resolve relative to `$SANDBOX` root |

Try each candidate in order; use the first that exists on the filesystem.
If no candidate resolves → stop:
`"⛔ source document unresolved — add --source <file> (looked up in workspace/<entity>/sources/)."`


## Phase C1 — Extract target elements

From `explain-<project-slug>-NNN.md`, collect every element block whose title
line ends in `[❓ incertain]`, plus every element flagged with a
`**❓ Élément marqué à confirmer :**` line (these may include elements otherwise
classified 📋/🔤 — read `chorus-check.md § Phase E2` step 5 for the class
definitions).

For each target element, record:
- its `id` and `type_element`
- the verdict/slot currently in question
- the exact **project JSON field(s)** whose value is uncertain or missing
  (read from the element's own JSON entry, using its `id`)
- any existing `_note` field on that element in the project JSON — it often
  already states *why* the value is uncertain from the import's point of view


## Phase C2 — Confirm the source document

The source document was already resolved in Phase C0 step 4.

Note in the cross-check output whether `--source` was provided explicitly or
auto-resolved from `_import.source_file`. If auto-resolved, quote the
`_import.source_file` value and the resolved filesystem path for traceability.

Do not fabricate a cross-check without a confirmed source file on the filesystem.


## Phase C3 — Format-agnostic cross-check protocol

> This is the core, generic step. It must adapt its extraction method to
> whatever the resolved source document's **actual format** is — never assume
> one specific format in advance.

### Step 1 — Identify the source document's format

Inspect the resolved file (Phase C2) and classify it into one of:

| Format family | Typical extension(s) | Locating an element within it |
|---|---|---|
| Structured data (JSON/YAML/XML/CSV) | `.json`, `.yml`, `.xml`, `.csv` | Look up the element by its **unique identifier** (whatever key the format uses: an id field, a reference field, a row key, etc.) |
| Normalized narrative document | `-vision.md` / `-text.txt` (produced by `chorus-pdf`/`chorus-word`/`chorus-excel`) | Search for the element's identifying label/name/reference as free text within the document; use surrounding paragraph/section/table context |
| Raw original document (docx/pdf/xlsx) not yet normalized | `.docx`, `.pdf`, `.xlsx` | Prefer the already-normalized `-vision.md`/`-text.txt` counterpart if one exists in the sandbox (see Phase C2); only fall back to the raw file if no normalized version is available, and note this explicitly (raw formats are unreliable to parse directly) |

### Step 2 — Locate the element's raw entry in the source

Using the identifier/label recorded in Phase C1, find the corresponding entry,
paragraph, row, or node in the resolved source document.

If no matching entry can be found at all → record:
`"<id>: no matching entry found in the source document — cannot confirm or refute; leave as-is, flag for manual lookup."`

### Step 3 — Compare source content against the uncertain value/slot

For the specific field/slot that Phase C1 flagged as uncertain, check directly
in the source entry:

- **Is the value/attribute present at all in the source, in any form** (even
  under a different name/label than the KB slot)? Read the raw content —
  do not rely on any intermediate transformation.
- If present in the source but different from what ended up in the project
  JSON → check **one more thing before concluding "pipeline artefact"**: is
  the missing catalogue/alias entry backed by an actual normative reference
  already available to the KB (a standard, RFC, ANSSI text, or any document
  present in `$SANDBOX/corpus/` / `CORPUS-DIRECTIVES.md`) — or is the source's
  naming merely an **implementation-library identifier** (e.g. a class/type
  name from a specific software library, a vendor-specific construction name)
  with **no normative text to encode**? Only the former is a genuine pipeline
  artefact (⛔ do not assume normative backing — verify it explicitly against
  the sandbox's actual corpus/directives before classifying).
- If genuinely absent from the source, with no equivalent field anywhere in
  the entry → this is a **genuine source limitation** — no import fix can
  recover data that was never captured upstream.
- If the source format itself has no way to express this kind of information
  at all (a structural limitation of the format/schema, not just this one
  entry) → note this distinctly — it explains *why* the field will never be
  populated for any element of this kind, not just this one.

### Step 4 — Classify the outcome

| Classification | Meaning |
|---|---|
| ✅ Source limitation confirmed | The uncertain value/field is genuinely absent (or the format cannot express it) in the original source — not an import defect |
| 🛠️ Pipeline artefact detected | The value **is** present in the source, **and** is backed by a normative reference already available to the KB (standard/RFC/ANSSI text in the corpus or reachable via `CORPUS-DIRECTIVES.md`) — but was lost, defaulted incorrectly, or mistranslated during import. Actionable fix: add/correct the catalogue or thesaurus alias, then re-import. |
| ❓ Still unresolved | No matching entry found, the source content itself is ambiguous, **or** the value is present but names an implementation-specific construction (library class, vendor-internal term) with no normative text in scope to adjudicate conformity — cannot conclude either way; leave the original uncertainty untouched and say so explicitly. This case requires a domain-expert arbitration (or acquiring a missing reference standard), not a catalogue/thesaurus edit. |

> Never force a ✅ or 🛠️ classification when the evidence is inconclusive —
> ❓ Still unresolved is a valid and expected outcome, not a failure of this skill.
>
> ⚠️ **Common miscalibration to avoid:** "the source names the mechanism
> explicitly" is **not sufficient** to classify 🛠️ Pipeline artefact. A
> vendor/library-specific name (e.g. a class name from a crypto library) can be
> perfectly explicit and still have **no normative reference to catalogue** —
> in that case the correct classification is ❓ Still unresolved, never 🛠️.
> Mislabelling this as a "pipeline artefact" is misleading: it implies the
> thesaurus/catalogue is incomplete or buggy by omission, when in fact no
> catalogable source exists yet — the KB's existing `⚠️ _a_confirmer` entry
> was already the correct, honest state. Before writing 🛠️, explicitly confirm
> that a standard/RFC/ANSSI text backing the missing entry is present in
> `$SANDBOX/corpus/` or documented in `CORPUS-DIRECTIVES.md` — cite it. If no
> such reference can be cited, use ❓ Still unresolved instead, and say so in
> the patch text (see Phase C4).


## Phase C4 — Patch the existing reports

> ⚠️ Never regenerate `explain-*.md`/`synthese-*.md` from scratch — only insert
> targeted additions next to the existing content for each cross-checked element.
> Never alter any verdict, motif string, or figure already present.

### Before any write

1. Create `$SANDBOX/agent/.backups/` if absent.
2. Copy each file about to be modified into `.backups/<filename>.bak-<timestamp>`
   before editing it. This applies to `explain-*.md` and `synthese-*.md`.

### Patch to `explain-<project-slug>-NNN.md`

For each cross-checked element, append directly below its existing
`**❓ Élément marqué à confirmer :**` (or equivalent) line a new line:

```markdown
**<✅|🛠️|❓> Vérification croisée (chorus-complete-report, <YYYY-MM-DD>) :** <one to
three sentences stating what was found directly in the source document, quoting
the resolved source file, and the resulting classification (source limitation
confirmed / pipeline artefact detected / still unresolved). If 🛠️: state the
concrete fix needed (which import step/module/mapping to correct, and cite the
normative reference — standard/RFC/ANSSI text — that backs the missing entry).
If ❓ due to a library/vendor-specific name with no normative backing: say so
explicitly (e.g. "no normative reference found for this construction — expert
arbitration or an additional reference standard is needed before any
catalogue/thesaurus edit"). Never phrase a ❓ Still unresolved case as if a
simple catalogue/thesaurus addition would resolve it.>
```

### Patch to `synthese-<project-slug>-NNN.md` (if present)

1. In the "Éléments à confirmer" table, append a short `✅`/`🛠️`/`❓` marker and
   one clause to the relevant row(s)' note.
2. Append one short paragraph to the "Recommandation" section summarising the
   cross-check outcome in aggregate (counts of ✅ / 🛠️ / ❓), and — if any 🛠️
   was found — explicitly recommend a corrective re-import before treating the
   compliance rate as final.
3. Never change the headline figures (`taux`, `n_conforme`, etc.) — this skill
   never re-evaluates compliance, only documents the *reliability* of the
   uncertain inputs behind it.


## Phase C5 — Optional standalone verification report

If requested by the user (or if the cross-check involved substantial manual
reasoning worth preserving independently of the patched reports), also write a
standalone report:

`$SANDBOX/agent/verification-<project-slug>-NNN.md`

containing, for each cross-checked element: the raw source excerpt consulted,
the comparison performed, and the classification reached (same content as the
patch lines in Phase C4, but with full detail/quotes rather than a condensed
one-line summary). This file is a durable, citable trace of the cross-check —
useful when comparing independently-produced verdicts on the same dataset, or
when the underlying compliance report is later regenerated by `chorus-check`
and needs re-enrichment.

No HTML/PDF is generated for this file — the `.md` is the authoritative output.


## Phase C6 — Summary output

Print a short summary to the conversation (not written to any file):

```
[chorus-complete-report] <sandbox-name> / <entity> / <project-slug>
  Run-report  : workspace/<entity>/reports/run-report-<slug>.json
  Source      : workspace/<entity>/sources/<file>  [auto | --source override]
  Elements cross-checked : N
    ✅ Source limitation confirmed : n1
    🛠️ Pipeline artefact detected  : n2
    ❓ Still unresolved             : n3
  Reports patched : workspace/<entity>/reports/explain-<project-slug>-<slug>.md
                    workspace/<entity>/reports/synthese-<project-slug>-<slug>.md  (if present)
  Backups : agent/.backups/*.bak-<timestamp>
```

If any 🛠️ (pipeline artefact) was detected, explicitly recommend as next step:
```
  Next step: fix <import step/module> then re-run chorus-import-project,
  chorus-audit-import, and chorus-check --explain --summary to refresh the
  verdicts with corrected data.
```
