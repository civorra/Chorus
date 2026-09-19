# Skill — chorus-complete-report

> Trigger: `chorus-complete-report <sandbox-name> <project-slug> [--source <file>]`
> Agent: `architect`
>
> `<sandbox-name>`: sandbox containing the compliance reports to enrich
> `<project-slug>`: slug identifying the `explain-<slug>-NNN.md` / `synthese-<slug>-NNN.md`
>                   pair to enrich (matches the naming convention of `chorus-check --explain/--summary`)
> `--source <file>`: optional explicit override of the original source document/dataset
>                     to cross-check against, if automatic resolution (Phase C1) fails
>                     or is ambiguous
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
> must have already produced `agent/explain-<slug>-NNN.md` (and, if `--summary` was
> used, `agent/synthese-<slug>-NNN.md`).
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

1. Read `$SANDBOX/agent/explain-<project-slug>-NNN.md` (highest `NNN` if several exist).
   If absent → stop: `"No explain-<project-slug>-*.md found — run chorus-check --explain first."`
2. If `$SANDBOX/agent/synthese-<project-slug>-NNN.md` exists (same `NNN` or the
   highest available), load it too — it will be patched in parallel (Phase C4).
3. Extract, from the `explain-*.md` header (`## 📚 KB & Project` block, itself
   copied verbatim from `chorus-check.md § Phase E0`), the **Origin** line —
   this identifies the project file and, if resolvable, the original source
   document/dataset.


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


## Phase C2 — Resolve the original source document

> Reuse the exact provenance-resolution logic already defined in
> `chorus-check.md § Phase E0.b` (steps 1–5: provenance header, `# ORIGINAL:`
> convention, fallback heuristic on basename). Do not reimplement it — call it
> out and apply it identically here, so both skills always agree on what the
> "original document" is for a given project.

If `--source <file>` was passed explicitly, use it instead of automatic
resolution and note this override in the final report.

If no source can be resolved (neither automatically nor via `--source`) →
stop for the affected element(s) and report:
`"⛔ <id>: original source document unresolved — provide --source <file> or add a '# ORIGINAL:' header to the intermediate corpus file."`
Do not fabricate a cross-check without an identified source.


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
  JSON → this is a **pipeline artefact** (mistranslation, wrong default,
  wrong mapping).
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
| 🛠️ Pipeline artefact detected | The value **is** present in the source but was lost, defaulted incorrectly, or mistranslated during import — actionable fix on `chorus-import-project`/its extensions, followed by re-import |
| ❓ Still unresolved | No matching entry found, or the source content itself is ambiguous — cannot conclude either way; leave the original uncertainty untouched and say so explicitly |

> Never force a ✅ or 🛠️ classification when the evidence is inconclusive —
> ❓ Still unresolved is a valid and expected outcome, not a failure of this skill.


## Phase C4 — Patch the existing reports

> ⚠️ Never regenerate `explain-*.md`/`synthese-*.md` from scratch — only insert
> targeted additions next to the existing content for each cross-checked element.
> Never alter any verdict, motif string, or figure already present.

### Before any write

1. Create `$SANDBOX/agent/.backups/` if absent.
2. Copy each file about to be modified into `.backups/<filename>.bak-<timestamp>`
   before editing it. This applies to `explain-*.md`, `synthese-*.md`, and their
   `.html`/`.pdf` counterparts if already generated.

### Patch to `explain-<project-slug>-NNN.md`

For each cross-checked element, append directly below its existing
`**❓ Élément marqué à confirmer :**` (or equivalent) line a new line:

```markdown
**<✅|🛠️|❓> Vérification croisée (chorus-complete-report, <YYYY-MM-DD>) :** <one to
three sentences stating what was found directly in the source document, quoting
the resolved source file, and the resulting classification (source limitation
confirmed / pipeline artefact detected / still unresolved). If 🛠️: state the
concrete fix needed (which import step/module/mapping to correct).>
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

### Regenerate HTML/PDF

After patching, regenerate the `.html` and `.pdf` counterparts of every
modified `.md` file, using the sandbox's standard tooling
(`$ENGINE/scripts/md2html.py`, `$ENGINE/scripts/md2pdf.py` per
`AGENTS.md § Markdown → PDF conversion`).


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

Regenerate `.html`/`.pdf` for this file too, per Phase C4's regeneration step.


## Phase C6 — Summary output

Print a short summary to the conversation (not written to any file):

```
[chorus-complete-report] <sandbox-name> / <project-slug>
  Elements cross-checked : N
    ✅ Source limitation confirmed : n1
    🛠️ Pipeline artefact detected  : n2
    ❓ Still unresolved             : n3
  Reports patched : agent/explain-<slug>-NNN.md, agent/synthese-<slug>-NNN.md
  HTML/PDF regenerated : yes
  Backups : agent/.backups/*.bak-<timestamp>
```

If any 🛠️ (pipeline artefact) was detected, explicitly recommend as next step:
```
  Next step: fix <import step/module> then re-run chorus-import-project,
  chorus-audit-import, and chorus-check --explain --summary to refresh the
  verdicts with corrected data.
```
