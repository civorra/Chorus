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
Read `project_file` from this JSON → path of the project JSON.

> ⚠️ `project_file` is written by `run.pl` with the **container-internal path**
> (e.g. `/chorus/sandboxes/<sb>/workspace/<entity>/<slug>.json`).
> Remap to the real filesystem path by replacing the `/chorus/sandboxes/` prefix
> with `$SANDBOXES/`, or simply extract `workspace/<entity>/<slug>.json` as a
> relative path and resolve it under `$SANDBOX/`.

If the run-report or `project_file` is absent → stop:
`"run-report-<slug>.json not found in workspace/<entity>/reports/ — check --slug value."`

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

### Step 3b — Detect `$REPORT_LANG` of the existing report (mandatory)

> This skill **patches** an existing `explain-*.md`/`synthese-*.md` pair produced
> by `chorus-check --explain`/`--summary`, which already resolved its own
> `$REPORT_LANG` (see `chorus-check.md § Phase L0`) — en or fr. The patch
> blocks added by this skill (Phase C4) **must match that same language**;
> never assume French by default, and never re-run Phase L0's YAML/corpus
> heuristics here (that would risk a different answer than the report in
> hand actually used).
>
> Detect directly from the report's own header, which is unambiguous and
> already resolved:
> - `## 📚 KB & Project` (English) vs `## 📚 KB & Projet` (French) in `explain-*.md`
> - if `synthese-*.md` is being patched instead/also, use the same detection
>   on its paired `explain-*.md` — never detect independently per file, the
>   pair always shares one `$REPORT_LANG`.
>
> Log line (mandatory, same convention as `chorus-check.md`):
> ```
> [lang] $REPORT_LANG=<fr|en>  source=explain-header
> ```

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

> ⚠️ **Zero-target guard — mandatory check before proceeding to Phase C2.**
> If this collection yields **zero** elements (no `[❓ incertain]` title, no
> `**❓ Élément marqué à confirmer :**` line anywhere in the explain report —
> e.g. a synthetic/stress project where every evaluated element resolved to a
> clear 📋/🔤 classification with no residual uncertainty), **stop here**.
> Do not proceed to Phase C2/C3/C4's per-element cross-check — there is
> nothing to cross-check against the source document.
>
> However, **do still insert a lightweight trace banner** at the very top of
> `explain-<project-slug>-NNN.md` (immediately after its title/date/status
> header lines, before the first `---`) — without this, the report carries no
> record that `chorus-complete-report` ran at all, and a user re-opening the
> same report later has no way to tell "I haven't run this yet" from "I ran
> it and there was nothing to do" — leading them to re-run the skill
> needlessly every time they revisit the report (this exact confusion was
> reported by a user after `chorus-web`'s cross-check button stayed active
> indefinitely with no visual difference between the two states). Still
> follow the "Before any write" backup step below before touching the file.
>
> Detect `$REPORT_LANG` the same way as Step 3b (`## 📚 KB & Project` vs
> `## 📚 KB & Projet` in the report header) before choosing which banner to
> insert — never default to French.
>
> Insert (French, `$REPORT_LANG = fr`):
> ```markdown
> > 🔎 **Vérification croisée** (`chorus-complete-report`, <YYYY-MM-DD>) — ℹ️ Rien à vérifier
> >
> > Aucun élément `❓ incertain` ni `_a_confirmer` trouvé dans ce rapport —
> > toutes les non-conformités sont déjà classées 📋/🔤 avec certitude. Ce
> > skill ne cross-check que les éléments incertains ; relancer
> > `chorus-complete-report` sur ce rapport sans nouvel élément incertain ne
> > produira pas de résultat différent.
> ```
>
> Insert (English, `$REPORT_LANG = en`):
> ```markdown
> > 🔎 **Cross-check** (`chorus-complete-report`, <YYYY-MM-DD>) — ℹ️ Nothing to verify
> >
> > No `❓ uncertain` nor `_a_confirmer` element found in this report — all
> > non-conformities are already classified 📋/🔤 with certainty. This skill
> > only cross-checks uncertain elements; re-running `chorus-complete-report`
> > on this report without a new uncertain element will not produce a
> > different result.
> ```
>
> This banner uses a **distinct marker** (`ℹ️ Rien à vérifier` / `ℹ️ Nothing to
> verify`) from the per-element classification banners of Phase C4
> (`✅|🛠️|❓|🏷️|⚖️`) so that tooling (e.g. `chorus-web`'s
> `detectCompleteReportDone()`) can tell "nothing to do, by design" apart from
> "genuinely cross-checked N element(s)" and render a different badge/state
> accordingly — never the same "✅ Croisé avec source" / "✅ Cross-checked"
> badge used for an actual cross-check.
>
> Then print exactly:
> ```
> [chorus-complete-report] <sandbox-name> / <entity> / <project-slug>
>   Run-report  : workspace/<entity>/reports/run-report-<slug>.json
>   Elements cross-checked : 0 — no ❓ incertain / _a_confirmer element found in
>     explain-<project-slug>-<slug>.md. Trace banner inserted (ℹ️ Rien à
>     vérifier) — nothing else patched.
> ```
> Then end the skill.


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

### Step 3.5 — Check the element's *typing*, not only its value

> **Why this step exists:** a value can be perfectly correct and verbatim-present
> in the source, while the **`type_element` assigned to it at import time** is
> wrong — in which case the compliance pipeline evaluated the element against
> the wrong KB rule entirely, independently of whether the value itself matches.
> A plain text search for the already-aligned value (Steps 1-3 above) will
> **not** catch this: the search succeeds (the term is found verbatim), masking
> the real defect. Observed case: 15 CC components named `<FAMILY>_EXT.N` were
> imported as plain `component_identifier` (generic catalogue grammar rule),
> while the source document carried a dedicated "EXTENDED COMPONENTS DEFINITION"
> section and the sandbox thesaurus already held a validated
> `type_element: extended_component` mapping (under a different wording) — the
> generic grammar rule rejected all 15 as malformed identifiers, a false
> NON_CONFORME block entirely explainable by mistyping, not a real product
> defect nor a genuine source limitation.

For every target element (Phase C1), before concluding Steps 1-3 above settle
the case, check:

1. **Does the element's located entry in the source sit under a structurally
   self-declaring section** (a heading that names a normative category
   regardless of wording — e.g. "Extended components definition", "Composants
   étendus", or any other standard-specific self-labelled section relevant to
   the active KB's domain)? If so, does that category match the `type_element`
   actually assigned to this element in the project JSON?
2. **Does the sandbox thesaurus hold a mapping** (`agent/thesaurus/*.org`) for
   this normative category, under **any** wording (see
   `chorus-import-project.md § Thesaurus alias variants`) — even one that does
   not textually match this document? If the category matches but the
   `type_element` actually assigned differs from the thesaurus mapping's
   target → this is a **mistyping at import**, not a value/pipeline-artefact
   issue.

If a mistyping is detected, do **not** classify this element under Steps 1-3's
outcomes (✅/🛠️/❓ as currently defined) — use the dedicated classification
below (🏷️ Mistyped at import) instead, regardless of what Steps 1-3 found
about the value itself.

### Step 3.6 — Check the verdict *logic* itself, not only the value/typing

> **Why this step exists:** a value can be correct, verbatim-present in the
> source, and correctly typed (`type_element` matches the normative category)
> — and the element can **still** be wrongly marked NON_CONFORME because the
> **rule/verdict-computation logic itself** does not correctly express the
> standard's actual requirement for this case. Neither Steps 1-3 (value
> fidelity) nor Step 3.5 (typing) catch this — both can report "everything
> matches the source" while the verdict is nonetheless wrong. Observed case:
> an EAL claim legitimately augmented beyond baseline (e.g. "EAL4 augmented
> with ALC_FLR.3", explicitly stated in the ST §2.3 and its component table)
> was computed as NON_CONFORME by a generic verdict function that treats
> *any* flagged augmentation as disqualifying — while the KB's own rule
> comments explicitly state that detecting an augmentation is not the same as
> judging it insufficient. The cross-check had **unrestricted read access**
> to the relevant rule file and chose not to consult it, settling for
> "❓ Still unresolved — consult the rule directly" instead of actually doing
> so. **This skill has no restriction (unlike `chorus-check --from-report`)
> preventing it from reading `rules/**/*.yml` or `agent/chorus/*.org` — do not
> conflate the two skills' rules.** If the uncertain element's slots are
> confirmed correct and correctly typed (Steps 1-3.5 pass) and the verdict is
> still in question, **read the specific rule file(s)** that produced the
> slots behind this verdict (identified via `_rule_trace` if present in the
> run-report, or by locating the rule(s) that reference this element's
> `type_element`/slots in `rules/<agent>/*.yml`) and the corresponding KB org
> section, to determine whether:

1. The rule's own documentation/comments acknowledge a limitation relevant
   here (e.g. "this rule only flags X, it does not judge sufficiency of Y" —
   exactly the kind of self-documented scope limit that should be read, not
   guessed at).
2. The verdict is computed by a **downstream generic function** (e.g. a
   catch-all `element_verdict()`-style dispatcher in `run.pl`) that combines
   multiple slots from possibly multiple rules into a final binary verdict —
   if so, check whether that combination logic correctly reflects the
   standard's actual requirement (here: whether a *justified, explicitly
   claimed* augmentation should be treated differently from an undocumented
   one) or applies an overly blunt rule (any augmentation ⇒ NON_CONFORME,
   regardless of justification).
3. The source document explicitly justifies/claims the condition the verdict
   is penalising (as in the EAL augmentation example) — if so, this is a
   strong signal that the defect lies in the verdict-computation logic, not
   in the data or its typing.

> ⚠️ **Contamination guard — do not inherit `--from-report`'s restrictions by
> association.** If the `explain-*.md` being patched carries a banner stating
> it was generated in `chorus-check --from-report` mode (e.g. "Per this mode's
> strict rules, `rules/**/*.yml` were not read"), that banner describes
> **`chorus-check`'s own limitation for the block it produced** — it says
> **nothing** about what `chorus-complete-report` itself may read while
> patching that same file. Do not let that surrounding text lead you to
> restate or extend that restriction to your own cross-check text: a phrase
> like *"`chorus-complete-report`/`--from-report` do not permit..."* is a
> **conflation error** — these are two independently-scoped skills, and this
> one has already read (or must now read, see below) the rule file in this
> very step.
>
> ⚠️ **Prove the read — do not paraphrase from prior conversational knowledge.**
> If you already "know" the likely cause of a verdict-logic defect (e.g. from
> an earlier discussion, a previous run of this skill, or general familiarity
> with this sandbox) — **re-read the actual rule file(s) and KB org section in
> this step anyway**, right now, before writing the patch. The patch text for
> an ⚖️ classification (Phase C4) must quote a **verbatim excerpt** from the
> file(s) just read (a rule comment, a YAML `ACTION`/`FIND` fragment, an org
> section sentence) — not a paraphrase reconstructed from memory. If you
> cannot quote a verbatim excerpt from a file read in this step, you have not
> actually performed Step 3.6 — fall back to ❓ Still unresolved and say so
> honestly, rather than presenting second-hand knowledge as a fresh
> cross-check finding.

If this investigation confirms a verdict-logic defect, classify as
⚖️ Verdict logic defect (below) — **do not** settle for ❓ Still unresolved
merely because the answer requires reading a rule file; reading rule files
when relevant to the question is explicitly within this skill's scope.

### Step 4 — Classify the outcome

| Classification | Meaning |
|---|---|
| ✅ Source limitation confirmed | The uncertain value/field is genuinely absent (or the format cannot express it) in the original source — not an import defect |
| 🛠️ Pipeline artefact detected | The value **is** present in the source, **and** is backed by a normative reference already available to the KB (standard/RFC/ANSSI text in the corpus or reachable via `CORPUS-DIRECTIVES.md`) — but was lost, defaulted incorrectly, or mistranslated during import. Actionable fix: add/correct the catalogue or thesaurus alias, then re-import. |
| ❓ Still unresolved | No matching entry found, the source content itself is ambiguous, **or** the value is present but names an implementation-specific construction (library class, vendor-internal term) with no normative text in scope to adjudicate conformity — cannot conclude either way; leave the original uncertainty untouched and say so explicitly. This case requires a domain-expert arbitration (or acquiring a missing reference standard), not a catalogue/thesaurus edit. |
| 🏷️ Mistyped at import | The value is correct and present in the source **as-is** — but Step 3.5 detected that the `type_element` assigned at import time does not match the normative category the source/thesaurus actually indicates for this element. The compliance pipeline evaluated it against the wrong KB rule. Actionable fix: **retype** the affected element(s) to the correct `type_element` in the project JSON (or re-run `chorus-import-project` after confirming/extending the thesaurus mapping per `chorus-import-project.md § Thesaurus alias variants`) — do not conflate with 🛠️, which assumes the value itself was mistranscribed; here the value is fine, the classification rule applied to it is wrong. |
| ⚖️ Verdict logic defect | The value is correct, correctly typed, and (if applicable) explicitly justified/claimed in the source — Step 3.6 investigation of the actual rule(s)/verdict-computation logic confirms the NON_CONFORME verdict stems from the rule or a downstream generic verdict function not correctly expressing the standard's requirement (e.g. treating a justified exception as a blanket violation). This is **not** an import/typing/value defect — the project JSON and its typing need no change. Actionable fix: correct the rule (`rules/<agent>/*.yml`) or the verdict-computation logic (e.g. `run.pl`'s generic dispatcher) to account for the distinguishing condition found (e.g. an explicit justification/claim), then re-run `chorus-check` to refresh the verdict. Do not classify as ❓ Still unresolved when Step 3.6's investigation was actually able to read and pinpoint the defect — ❓ remains reserved for cases where the rule file itself does not resolve the question (ambiguous rule intent, missing corpus reference, etc.). |

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

> **Visual distinction requirement.** Cross-check additions must be
> **visually distinguishable at a glance** from the surrounding `chorus-check`
> narrative text — a reader skimming the report must be able to tell, without
> reading word-for-word, which sentences come from the original
> `--explain` pass and which were added afterwards by this skill. Plain bold
> text (`**... :**`) blends into the rest of the report's prose (which also
> uses bold liberally for labels) and does **not** satisfy this requirement.
>
> Use a **Markdown blockquote** (`>` prefix on every line) for the cross-check
> addition — `chorus-web`'s report viewer (`marked.js` rendering, see
> `.mdv-content blockquote` styling) already renders blockquotes with a
> distinct left border and background, with zero additional tooling needed.
> This also keeps the file readable as plain text/diff in any other viewer.

For each cross-checked element, append directly below its existing
`**❓ Élément marqué à confirmer :**` (or equivalent, `**❓ Element marked to
confirm:**` in English) line a **blank line**, then the blockquote block in
the language resolved at Step 3b (`$REPORT_LANG`) — **never mix languages
within one report; never default to French without checking Step 3b first**:

French (`$REPORT_LANG = fr`):
```markdown
> 🔎 **Vérification croisée** (`chorus-complete-report`, <YYYY-MM-DD>) — <✅|🛠️|❓|🏷️|⚖️> <classification label FR>
>
> <one to three sentences, in French, stating what was found directly in the source document,
> quoting the resolved source file, and the resulting classification (source limitation
> confirmed / pipeline artefact detected / still unresolved / mistyped at import / verdict logic defect). If 🛠️: state the
> concrete fix needed (which import step/module/mapping to correct, and cite the
> normative reference — standard/RFC/ANSSI text — that backs the missing entry).
> If ❓ due to a library/vendor-specific name with no normative backing: say so
> explicitly (e.g. "aucune référence normative trouvée pour cette construction — un
> arbitrage expert ou un référentiel normatif complémentaire est requis avant toute
> modification de catalogue/thésaurus"). Never phrase a ❓ Still unresolved case as if a
> simple catalogue/thesaurus addition would resolve it. If 🏷️: state the correct
> `type_element` and the structural/thesaurus evidence found (self-declaring
> section title and/or existing thesaurus mapping under a different wording —
> see `chorus-import-project.md § Thesaurus alias variants`), and that the value
> itself was never in question — only its typing was. If ⚖️: **quote a verbatim
> excerpt** from the rule file/KB org section just read in Step 3.6 (not a
> paraphrase — see Step 3.6's "prove the read" guard), state the exact logic
> defect found, and state the source passage that justifies/claims the condition
> being wrongly penalised. Never write a phrase implying this skill itself is
> restricted from reading rule files — that restriction belongs to
> `chorus-check --from-report` only, never to this skill.
```
Where `<classification label FR>` is one of: `Limitation source confirmée` (✅),
`Artefact pipeline détecté` (🛠️), `Encore non résolu` (❓), `Mistyping détecté
à l'import` (🏷️), `Défaut de logique de verdict` (⚖️).

English (`$REPORT_LANG = en`):
```markdown
> 🔎 **Cross-check** (`chorus-complete-report`, <YYYY-MM-DD>) — <✅|🛠️|❓|🏷️|⚖️> <classification label EN>
>
> <one to three sentences, in English, stating what was found directly in the source document,
> quoting the resolved source file, and the resulting classification (source limitation
> confirmed / pipeline artefact detected / still unresolved / mistyped at import / verdict logic defect). If 🛠️: state the
> concrete fix needed (which import step/module/mapping to correct, and cite the
> normative reference — standard/RFC/ANSSI text — that backs the missing entry).
> If ❓ due to a library/vendor-specific name with no normative backing: say so
> explicitly (e.g. "no normative reference found for this construction — expert
> arbitration or an additional reference standard is needed before any
> catalogue/thesaurus edit"). Never phrase a ❓ Still unresolved case as if a
> simple catalogue/thesaurus addition would resolve it. If 🏷️: state the correct
> `type_element` and the structural/thesaurus evidence found (self-declaring
> section title and/or existing thesaurus mapping under a different wording —
> see `chorus-import-project.md § Thesaurus alias variants`), and that the value
> itself was never in question — only its typing was. If ⚖️: **quote a verbatim
> excerpt** from the rule file/KB org section just read in Step 3.6 (not a
> paraphrase — see Step 3.6's "prove the read" guard), state the exact logic
> defect found (e.g. "generic verdict dispatcher treats any flagged augmentation
> as disqualifying, regardless of explicit justification"), and state the source
> passage that justifies/claims the condition being wrongly penalised. Never
> write a phrase implying this skill itself is restricted from reading rule
> files (e.g. "X do not permit...") — that restriction belongs to
> `chorus-check --from-report` only, never to this skill.
```
Where `<classification label EN>` is one of: `Source limitation confirmed` (✅),
`Pipeline artefact detected` (🛠️), `Still unresolved` (❓), `Mistyping detected
at import` (🏷️), `Verdict logic defect` (⚖️) — matching the emoji
used, so the classification is readable both from the emoji and from the
label text (accessibility / copy-paste into plain-text contexts where emoji
may not render).

> ⚠️ Every line of the block — including the blank separator line between the
> header line and the body sentences — must start with `>` (a bare blank line
> inside a blockquote breaks it into two separate blockquotes in most Markdown
> renderers, including `marked.js`). Use `>` alone (no trailing space needed)
> for that separator line.

### Patch to `synthese-<project-slug>-NNN.md` (if present)

1. In the "Éléments à confirmer" table, append a short `✅`/`🛠️`/`❓`/`🏷️`/`⚖️` marker and
   one clause to the relevant row(s)' note.
2. Append a **new, separately-titled section** at the end of the file — never
   fold the cross-check paragraph into the existing "Recommandation" section
   (that section is produced by `chorus-check` itself and must stay a
   self-contained unit the reader can trust as "pipeline output only";
   mixing in text written by a different skill, days or weeks later, under
   the same heading defeats the "visually distinguishable" requirement
   just as much as unmarked bold text would — see the `explain-*.md` patch
   above for the same rationale):

   Use the same `$REPORT_LANG` resolved at Step 3b — never default to French:

   French (`$REPORT_LANG = fr`):
   ```markdown
   ---

   ### 🔎 Vérification croisée (chorus-complete-report)

   > **<YYYY-MM-DD>** — <N> élément(s) incertain(s) confronté(s) au document
   > source d'origine (`<resolved source path>`, <auto-résolu depuis
   > `_import.source_file` | --source explicite>).
   >
   > **Résultat :** <n1> ✅ limitation source confirmée · <n2> 🛠️ artefact
   > pipeline détecté · <n3> ❓ encore non résolu · <n4> 🏷️ mistyping à
   > l'import · <n5> ⚖️ défaut de logique de verdict.
   >
   > <one aggregate paragraph summarising the cross-check outcome — same
   > content as before, but now entirely inside the blockquote>. <if any 🛠️
   > was found: explicitly recommend a corrective re-import before treating
   > the compliance rate as final>. <if any ⚖️ was found: explicitly recommend
   > a rule/verdict-logic fix (cite the file) before treating the compliance
   > rate as final>.
   ```

   English (`$REPORT_LANG = en`):
   ```markdown
   ---

   ### 🔎 Cross-check (chorus-complete-report)

   > **<YYYY-MM-DD>** — <N> uncertain element(s) cross-checked against the
   > original source document (`<resolved source path>`, <auto-resolved from
   > `_import.source_file` | explicit --source>).
   >
   > **Result:** <n1> ✅ source limitation confirmed · <n2> 🛠️ pipeline
   > artefact detected · <n3> ❓ still unresolved · <n4> 🏷️ mistyping at
   > import · <n5> ⚖️ verdict logic defect.
   >
   > <one aggregate paragraph summarising the cross-check outcome — same
   > content as before, but now entirely inside the blockquote>. <if any 🛠️
   > was found: explicitly recommend a corrective re-import before treating
   > the compliance rate as final>. <if any ⚖️ was found: explicitly recommend
   > a rule/verdict-logic fix (cite the file) before treating the compliance
   > rate as final>.
   ```

   Every line of this block (including blank separator lines between
   paragraphs) must start with `>` — see the same Markdown-blockquote caveat
   noted in the `explain-*.md` patch above.
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
    🏷️ Mistyped at import           : n4
    ⚖️ Verdict logic defect         : n5
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

If any 🏷️ (mistyped at import) was detected, explicitly recommend as next step:
```
  Next step: retype element(s) <id list> to type_element=<correct value> in
  the project JSON (or extend the sandbox thesaurus with this document's
  wording — see chorus-import-project.md § Thesaurus alias variants — then
  re-run chorus-import-project so the correct typing is applied automatically
  on next import), then re-run chorus-check --explain --summary to refresh
  the verdicts against the correct KB rule.
```

If any ⚖️ (verdict logic defect) was detected, explicitly recommend as next step:
```
  Next step: fix <rule file(s) / verdict-computation logic, e.g. run.pl's
  element_verdict()-style dispatcher> to correctly account for <the
  distinguishing condition found — e.g. an explicit justification/claim in
  the source>, then re-run chorus-check --explain --summary to refresh the
  verdict. This is a rule/engine defect, not a data or typing issue — no
  re-import is needed.
```
