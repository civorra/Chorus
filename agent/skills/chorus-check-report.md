# Skill — chorus-check-report

> **Trigger:** `chorus-check-report <sandbox-name> <run-report.json> [--explain] [--summary]`
> **Agent:** `code`
>
> `<sandbox-name>` : sandbox containing the KB that produced the run.
> `<run-report.json>` : path to an existing `run-report-*.json` produced by `chorus-check`.
>                       Relative to `$SANDBOX` (e.g. `workspace/eviden/reports/run-report-20261102-141022.json`).
> `--explain` : produce `explain-<slug>-<RUN_TIMESTAMP>.md` (rule-by-rule non-conformity details)
> `--summary` : produce `synthese-<slug>-<RUN_TIMESTAMP>.md` (one-page consultation synthesis)
>
> **Also loaded as a sub-skill by `chorus-check`** (ENG-068) when `--explain`, `--summary`,
> or `--from-report` is present. In that case the caller provides Phase 6 output directly;
> Phase FR0 is skipped (run-report already in memory).
>
> **Single responsibility:** read a run-report JSON → produce human-readable reports.
> Never runs the pipeline. Never reads YAML rule files. Never generates Perl infrastructure.

---

## Phase L0 — Report language resolution (`$REPORT_LANG`)

> **Runs once, before Phase E0, whenever `--explain` or `--summary` is present.**
> Produces `$REPORT_LANG ∈ { fr, en }` used by all subsequent phases to select
> French or English templates. Priority (highest first) :

```
1. --lang <fr|en> flag    → use directly, no further check
2. #+CORPUS_LANG in       → read first line matching "^#\+CORPUS_LANG:" in
   agent/chorus/index.org    $SANDBOX/agent/chorus/index.org
                              value must be fr or en (case-insensitive), else skip
3. YAML normative-content  → scan all files in $SANDBOX/rules/**/*.yml
   dominant language          ⚠️ do NOT use the "^RULE:"/"^REGLE:" header keyword —
                              it is a fixed structural tag from the engine's YAML
                              template (English by default, per chorus-engine-yaml.md),
                              not a reflection of the corpus's actual language, and is
                              present as "RULE:" even on French-corpus sandboxes.
                              Instead, scan the free-text normative content of each
                              rule: the "# CORPUS:" line's reference label and the
                              "# PURPOSE" block's prose. Count French-leaning markers
                              (accented characters é/è/à/ê/ç, or words matching
                              "Règle|Recommandation|Reco[A-Z]|conforme|non conforme"
                              case-insensitively) vs English-leaning markers (words
                              matching "Rule|Recommendation|compliant|non-compliant").
                              $REPORT_LANG = language with the higher marker count
                              across all scanned files; tie → fr
4. Default                → fr
```

**Log line (mandatory):**
```
[lang] $REPORT_LANG=<fr|en>  source=<flag|index.org|yaml-scan|default>
```

This log line is the only place `$REPORT_LANG` is announced — do not repeat it.
All phases below consume `$REPORT_LANG` silently; never re-run this resolution.

---

## Option `--explain` — Human-readable non-conformity explanations

> Runs **after** Phase 6 (single-file mode) or Phase 6-all (`--all` mode), once the
> compliance report has been produced and the convergence verdict is known.
> Never replaces the verbatim `run.pl` output or the structured report — it is an
> **additional, optional artefact** aimed at a non-technical reader (product owner,
> quality engineer, technical director) who needs to understand *why* an element was
> classified NON_CONFORME without reading YAML or Perl.
>
> ⚠️ **Skip this option entirely if `--explain` is absent** — it must never run by default,
> to avoid slowing down routine `chorus-check` invocations during iterative debugging.

### Rationale

The verbatim `motif_*` slot printed by `run.pl` (e.g. *"Unrecognised completion state
for a PP assignment (§8.1.2 para 254)"*) is accurate but terse: it does not show
*which* rule fired, *what* input values it read, *why* that specific rule applied
rather than a neighbouring one, nor *what corpus paragraph* it encodes. Reconstructing
this context today requires manually cross-referencing `agent/chorus/<slug>.org`,
`rules/<slug>/R*.yml`, and the project JSON — exactly the work an ECA session does
ad hoc in chat, with no persistent, reusable trace once the conversation ends.
`--explain` formalises and automates that reconstruction into a durable file.

### Phase E0 — KB recap and project recap (mandatory header data)

> Runs once, before Phase E1. Produces **one identical header block** consumed by
> **both** `--explain` (Phase E4) and `--summary` (Phase S2) — the two options
> must render the exact same KB/project recap tables, verbatim, so a reader
> switching between the two documents sees consistent context. Only the content
> *below* this header differs between the two options (per-rule detail vs.
> one-page synthesis).
>
> Keep this header **essential only** — no narrative paragraphs, no architecture/
> engineering notes, no historical commentary. It answers exactly two questions:
> "what corpus built this KB" and "what document produced this project". Anything
> else belongs in `index.org` itself, not in a generated report header.

**a) KB recap — read from `$SANDBOX/agent/chorus/index.org`:**

- `#+TITLE` → pipeline name
- `* Pipeline global` table → agent count and ordered slug list (one line, not
  the full table: `<N> agents : <slug1> → <slug2> → …`)
- `* Integrated corpus` table → reproduce as-is (Num / Fichier / Agents concernés),
  dropping the enrichment-pass narrative if it makes a cell unwieldy — one
  short clause per cell is enough (e.g. "operations (R06 étendu)", not the
  full pass history paragraph)

If `index.org` is missing or has no `* Integrated corpus` table → record
`KB recap: unavailable (index.org incomplete)` and continue (never block
`--explain`/`--summary` generation on this).

**b) Project recap — read from the project JSON file(s) being checked:**

- `project` (name) field
- `description` field, truncated to one sentence if longer (first `.` or first
  120 characters, whichever comes first) — the full description belongs in the
  JSON, not repeated verbatim in every generated report
- `_import` block if present → resolve the **full provenance chain**, not just
  `source_document` verbatim:
  1. `source_document` in `_import` almost always points to a **generated
     intermediate corpus file** (e.g. `enterprise/confluence/<NNN>-<slug>-vision.md`
     produced by `chorus-pdf`/`chorus-word`/`chorus-excel`), not the original
     document handed to the engineer. Displaying only this path silently hides
     which real-world document (docx/pdf/xlsx) the analysis actually traces back to.
  2. **Preferred method — read the provenance header:** open `source_document`
     and read its first line. Files produced by `chorus-pdf`/`chorus-word`/
     `chorus-excel` (all modes) always start with `# ORIGINAL: <path-to-original-document>`
     (see each skill's Phase — "Assemble output" step). If present, use this
     path directly — no heuristic needed.
  3. **Fallback heuristic** (only if the header is absent — e.g. corpus file
     predates this convention, or was hand-written): look for a file with the
     **same basename** (stripping any `<NNN>-` numeric prefix and `-vision`/`-text`
     suffix) and a document extension (`.docx`, `.pdf`, `.xlsx`) in the **same
     directory** as `source_document`. E.g. `005-common-criteria-security-target-id-ca-v7.3-vision.md`
     → look for `common-criteria-security-target-id-ca-v7.3.{docx,pdf,xlsx}`
     (case-insensitive match) in the same folder.
  4. If resolved (header or unique heuristic match) → display both: the
     generated corpus file (traceable, versioned in the sandbox) **and** the
     resolved original document.
  5. If unresolved (no header, zero or multiple heuristic matches) → display
     `source_document` alone and add `(document original non résolu — vérifier <dossier>)`.
  → Render as: `Import — document: <original ou "non résolu"> (converti en <source_document>, mode: <mode>, date: <date>)`
- If `_import` is absent → one line, corpus language:
  French: `Origine : project synthétique (chorus-create-project/chorus-stress)`
  English: `Origin: synthetic project (chorus-create-project/chorus-stress)`
- For `--all` / multi-file synthesis (`explain-all-*.md`) → one such project
  recap block **per project file**, not merged — each file may have a distinct
  origin and conflating them would mislead the reader.

**c) Canonical header block format** (identical in both `--explain` and `--summary`,
inserted verbatim after the document's own title/date/status lines).

> ⚠️ **Language:** render this block using `$REPORT_LANG` resolved in **Phase L0**.
> `fr` → French template below. `en` → English template beneath it.
> Do not mix languages within a single generated file.

French corpus (default template):
```markdown
## 📚 Référentiel & Projet

**Référentiel :** <N> modules : <slug1> → <slug2> → … → <slugN>

| Corpus | Fichier | Domaines couverts |
|---|---|---|
| <NNN> | <fichier> | <domaines, résumé court> |
| ... | | |

**Project :** <project> — <description tronquée>
**Origine :** <Import — document: ... (converti en ...) | project synthétique>
```

English corpus:
```markdown
## 📚 Reference & Project

**Reference:** <N> modules: <slug1> → <slug2> → … → <slugN>

| Corpus | File | Domains covered |
|---|---|---|
| <NNN> | <file> | <domains, short summary> |
| ... | | |

**Project:** <name> — <truncated description>
**Origin:** <Import — document: ... (converted to ...) | synthetic project>
```

### Phase E0.d — Thesaurus shard pre-load *(--explain only)*

> Run once after Phase E0.c, before Phase E3. Builds a lookup map so each
> `_a_confirmer` element section (Phase E3) can show the thesaurus status of
> its uncertain import mappings without re-reading org files per element.
> Non-blocking: if no thesaurus shard exists, the map is empty and Phase E3
> emits "Not in thesaurus" for all `_labels` entries.

**Shards to read (in order — later entries override earlier for the same term):**
1. `$SANDBOX/agent/thesaurus/global.org` — always, if present
2. `$SANDBOX/agent/thesaurus/<entity>.org` — entity-specific (`$ENTITY` from
   the `$WORKSPACE`/`$ENTITY` derivation at the top of this document), if present

**Tables to parse in each shard:**
- `* Aliases — type_element` → columns: Project term · KB type_element · Confidence · Source import
- `* Aliases — slot values`  → columns: Project term · KB slot · KB value · Confidence · Source import
- `* Pending — to confirm on next import of this entity` → same columns (confidence = ⏳ Pending)

**Lookup map structure:**
```
thesaurus_map[project_term_normalized] = {
  kb_slot:    <"KB type_element" column, or "KB slot" column>,
  kb_value:   <same as kb_slot for type_element entries; "KB value" for slot-value entries>,
  confidence: <verbatim confidence cell, e.g. "✅ confirmed (validated via chorus-web 2026-11-11)"
               or "⏳ pending">,
  source:     <"Source import" column>,
}
```
where `project_term_normalized = project_term.strip().toLowerCase()`.

**Lookup call in Phase E3:**
```
thesaurus_lookup(label_value) = thesaurus_map[label_value.strip().toLowerCase()] ?? null
```

---

### Phase E1 — Select elements to explain

From the elements collected in Phase 6 (or Phase 6-all across all files):

```
TARGETS = { e | element_status(e) == 'NON_CONFORME' }
        ∪ { e | e has "_a_confirmer": 1 in the project JSON }   (if present)
        ∪ { e | e.statut_conformite == '(unprocessed)'
                AND e._rule_trace is empty/absent
                AND e.motif is absent }                          (→ classe ⛔, C3)
```

> `_a_confirmer` elements are included because an uncertain terminology mapping
> (e.g. produced by `chorus-import-project`) can silently produce a NON_CONFORME
> verdict for reasons unrelated to genuine non-compliance — the reader needs to see
> both the verdict **and** the mapping uncertainty side by side.
>
> `(unprocessed)` elements without any `_rule_trace` or `motif` are included so
> that the report makes Frame-never-reached cases visible (classe ⛔) — they will
> be classified by `chorus-complete-report` Phase C1.5 and exposed in the Synthèse
> table with their probable cause (slot amont absent, see `%OPTIONAL_SLOT_HINTS`
> in T5). An `(unprocessed)` element that **does** carry a partial `_rule_trace`
> or `motif` is already included via the `NON_CONFORME` / `_a_confirmer` branch
> above (or will be classified ❓ by Phase C1.5 if it falls through).

If `TARGETS` is empty → print `[explain] No NON_CONFORME or _a_confirmer element — nothing to explain.` and skip Phases E2–E4 entirely (no file written).

### Phase E2 — Reconstruct the explanation for each target element

For each element `e` in `TARGETS`:

1. **Identify the agent and rule that produced the verdict.**
   - **Preferred — read `e._rule_trace` directly, if present.** Sandboxes whose YAML
     rules follow the `_rule_trace` traceability convention
     (`chorus-engine-yaml.md § Rule Documentation Standard`) publish, on every Frame,
     a cumulative arrayref of every rule that fired on it, in application order:
     `[ { rule_id, corpus_ref }, ... ]`. The **last entry** is normally the
     verdict-writing rule (aggregation/`publish-*` rules run last in most pipelines);
     when several entries carry distinct `corpus_ref` values, list them **all** in
     Phase E3's "Règle appliquée" field — this is precisely the case an aggregation
     rule (generic `CORPUS: (agrégation...)`) would otherwise have hidden the
     specific normative rule that actually computed the KO verdict (see incident
     below). No `agent/chorus/<slug>.org` cross-reference or `rules/<slug>/R*.yml`
     grep is needed in this case — `_rule_trace` is authoritative and already
     resolved by the engine at runtime.
   - **Fallback — `_rule_trace` absent** (sandbox predates the convention, or its
     YAML rules don't yet publish it): reconstruct manually.
     - Determine `e.type_element` → look up the owning agent via `agent/chorus/index.org`.
     - Identify the verdict slot that is `KO` (or the `_a_confirmer` flag) on `e`.
     - Read `agent/chorus/<slug>.org` § Rule Catalogue to find the rule(s) whose
       `Outputs (slots written)` include that slot.
     - Confirm by reading the matching `rules/<slug>/R*.yml` file — the rule that
       actually wrote the `KO` value is identifiable by its `FIND.filtre` condition
       matching `e`'s own slot values (e.g. `document_type`, `operation_kind`).

   > **Incident:** `agent/org/incidents-log.org § anssi-09b-01`

2. **Extract the exact corpus reference.**
   - From the rule's YAML header (`# CORPUS: §N — ...`) or inline comment
     referencing `§N para M`.
   - Quote the referenced paragraph number verbatim — do not paraphrase the
     article number.

3. **List the input values read by the rule.**
   - From the rule's `INPUTS (slots read)` header, read each corresponding value
     directly from the project JSON element `e`.

4. **Identify neighbouring rules that were NOT applied, and why.**
   - Scan sibling rules in the same agent (rules sharing the same targeting slot
     but a different `FIND.filtre` on `type`/`kind`/`document_type`).
   - For each sibling rule whose value domain *would* have accepted the element's
     actual input value, note it explicitly — this surfaces terminology-mapping
     errors (see chorus-audit-import precedent: a value valid for "selection" but
     used on an "assignment" element).
   - Example pattern (Operations agent): if `e.completion_status = "restricted"`
     failed under `R02-assignment-pp-flexible` (assignment domain), check whether
     `R04-selection-pp-flexible` (selection domain) would have accepted it — if so,
     flag this explicitly as a likely terminology-mapping issue, not a genuine
     substantive non-conformity.

5. **Classify the non-conformity nature** (new — not present in the base report):

   | Class | Meaning |
   |---|---|
   | 📋 Non-conformité substantielle | The element's data is correctly captured; the rule correctly identifies a genuine gap against the normative requirement (e.g. OP-03: assignment genuinely left uncompleted in an ST). |
   | 🔤 Anomalie de mapping terminologique | The KO verdict stems from a value that is valid in the KB grammar but for a *different* branch/type than the one carrying it (e.g. OP-07: "restricted" valid only for `selection`, misapplied to `assignment`) — likely a `chorus-import-project` alignment error, not a real defect. |
   | ❓ Incertain | Element carries `_a_confirmer: 1` — verdict may change once the ambiguous mapping is resolved by the engineer. |
   | ⛔ Non traité | Element is `(unprocessed)` with no `_rule_trace` and no `motif` — no rule ever reached this Frame. The report shows the probable cause (missing upstream slot) from `%OPTIONAL_SLOT_HINTS`. `chorus-complete-report` Phase C1.5 will assign the final ⛔ class and expose it in the Synthèse table. |

   > This classification is the single most valuable addition of `--explain` over
   > the base compliance report: it separates *"the product genuinely fails this
   > requirement"* from *"the import tooling mis-translated a term"* — two very
   > different actions for the reader (fix the product vs. fix the JSON).
   > The ⛔ class surfaces a third distinct failure mode: *"the pipeline never even
   > evaluated this element"* — invisible in the base compliance report where it
   > appears as a silent `(unprocessed)` line mixed in with conformes/non-conformes.

### Phase E3 — Per-element explanation block format

> ⚠️ **Language:** render using `$REPORT_LANG` from **Phase L0**.
> `fr` → French template. `en` → English template below. Never mix languages.

French corpus (default template):
```markdown
### <id> — <type_element>  [<classe: 📋 substantielle | 🔤 mapping | ❓ incertain>]

**Verdict :** ❌ Non conforme
**Motif :** "<motif_* verbatim string>"

**Règle appliquée :** `rules/<slug>/<R0N-rule-name>.yml`  (module `<Nom>`, position <N>)
**Référence normative :** §<N> para <M> — <one-line summary of the requirement>
<if e._rule_trace has more than one entry — chaîne complète de traçabilité:>
**Chaîne de règles (`_rule_trace`) :**

| Ordre | Règle | Référence corpus |
|---|---|---|
| 1 | `<rule_id_1>` | <corpus_ref_1> |
| 2 | `<rule_id_2>` | <corpus_ref_2> |
| ... | | |
> La dernière règle (souvent un agrégateur `publish-*`) n'apporte parfois aucune
> référence normative propre (`(agrégation — pas de règle nommée spécifique)`) —
> dans ce cas, **la règle réellement responsable du verdict est une entrée
> antérieure de la chaîne**, pas la dernière. Utiliser cette table plutôt que la
> seule dernière entrée pour citer la référence normative exacte au lecteur.

**Valeurs d'entrée lues par la règle :**

| Slot | Valeur dans le project |
|---|---|
| <slot_a> | <valeur> |
| <slot_b> | <valeur> |

**Pourquoi cette règle s'applique :**
- **Règle :** `<rule_id>` — <description d'une ligne issue du commentaire YAML ou de la KB org>
- **Condition déclenchante :** `<FIND.attribut> = <FIND.filtre>` — <pourquoi ce filtre est satisfait par cet élément>
- **Résultat :** <ce que la règle a publié ou conclu>

> ⚠️ Utiliser le gabarit T10 (`chorus-templates.md § T10`) — ne pas remplacer par
> de la prose libre. La structure fixe permet à `chorus-complete-report` de détecter
> les fiches à incertitude identique (C11b) et de les dédoublonner en annexe.

<if class == 🔤 mapping:>
**⚠️ Anomalie de mapping suspectée :** la valeur `<value>` est valide dans le
référentiel, mais uniquement pour `<other branch>` (règle
`<sibling-rule-name>.yml`, §<N> para <M>) — non pour `<this element's branch>`.
Vérifier le terme source d'origine (`<project term>`, cf. thesaurus.org / import-report)
avant de considérer cet élément comme réellement non conforme.

<if _a_confirmer present:>
**❓ Élément marqué à confirmer :** <note field from the project JSON>

<if _a_confirmer present AND e._labels non vide — ENG-019:>
**🗂️ État des alignements thésaurus** *(`agent/thesaurus/<shard>.org`)*

> Pour chaque terme source (`_labels`) utilisé lors de l'import, statut dans le
> thésaurus consolidé du sandbox.

| Terme projet (`_labels`) | Slot KB → valeur | Statut thésaurus |
|---|---|---|
<for each (slot_kb, project_term) in e._labels — lookup via thesaurus_map from Phase E0.d:>
| `<project_term>` | `<kb_slot>` → `<kb_value>` | <confidence verbatim, e.g. ✅ confirmé · ⏳ en attente · — absent du thésaurus> |
<end for>

> <Résumé une ligne selon les cas :>
> — Tous les termes confirmés → "Tous les alignements import validés — le flag `_a_confirmer`
>   reflète une incertitude d'import levée. Peut être considéré comme résolu."
> — Certains en attente → "⚠️ N terme(s) encore en attente de validation — relancer
>   `chorus-import-project` après résolution dans l'onglet Thésaurus."
> — Aucun dans le thésaurus → "Aucun alignement enregistré — termes appliqués de façon
>   heuristique à l'import."
```

English corpus:
```markdown
### <id> — <type_element>  [<class: 📋 substantial | 🔤 mapping | ❓ uncertain>]

**Verdict:** ❌ Non-compliant
**Reason:** "<motif_* verbatim string>"

**Rule applied:** `rules/<slug>/<R0N-rule-name>.yml`  (module `<Name>`, position <N>)
**Normative reference:** §<N> para <M> — <one-line summary of the requirement>
<if e._rule_trace has more than one entry — full traceability chain:>
**Rule chain (`_rule_trace`):**

| Order | Rule | Corpus reference |
|---|---|---|
| 1 | `<rule_id_1>` | <corpus_ref_1> |
| 2 | `<rule_id_2>` | <corpus_ref_2> |
| ... | | |
> The last entry (often a `publish-*` aggregation rule) sometimes carries no
> normative reference of its own (`(aggregation — no dedicated rule)`) — in that
> case, **the rule actually responsible for the verdict is an earlier entry in
> the chain**, not the last one. Use this table rather than only the last entry
> to quote the exact normative reference to the reader.

**Input values read by the rule:**

| Slot | Value in the project |
|---|---|
| <slot_a> | <value> |
| <slot_b> | <value> |

**Why this rule applies:**
- **Rule:** `<rule_id>` — <one-line description from YAML comment or KB org>
- **Triggering condition:** `<FIND.attribut> = <FIND.filtre>` — <why this filter matches this element>
- **Outcome:** <what the rule published or concluded>

> ⚠️ Use the T10 template (`chorus-templates.md § T10`) — do not replace with
> free-form prose. The fixed structure allows `chorus-complete-report` to detect
> identical-uncertainty fiches (C11b) and deduplicate them in the annexe.

<if class == 🔤 mapping:>
**⚠️ Suspected mapping anomaly:** the value `<value>` is valid in the
reference, but only for `<other branch>` (rule `<sibling-rule-name>.yml`,
§<N> para <M>) — not for `<this element's branch>`. Verify the original source
term (`<project term>`, see thesaurus.org / import-report) before treating this
element as genuinely non-compliant.

<if _a_confirmer present:>
**❓ Element marked to confirm:** <note field from the project JSON>

<if _a_confirmer present AND e._labels non-empty — ENG-019:>
**🗂️ Thesaurus alignment status** *(from `agent/thesaurus/<shard>.org`)*

> Status of each source term (`_labels`) used at import time, as recorded in
> the sandbox's consolidated thesaurus.

| Project term (`_labels`) | KB slot → value | Thesaurus status |
|---|---|---|
<for each (slot_kb, project_term) in e._labels — lookup via thesaurus_map from Phase E0.d:>
| `<project_term>` | `<kb_slot>` → `<kb_value>` | <confidence verbatim, e.g. ✅ confirmed · ⏳ pending · — not in thesaurus> |
<end for>

> <One-line summary depending on outcome:>
> — All confirmed → "All import alignments validated — the `_a_confirmer` flag
>   reflects an original import uncertainty that has since been resolved."
> — Some pending → "⚠️ N term(s) still pending validation — re-run
>   `chorus-import-project` after resolving pending entries in the Thesaurus tab."
> — None in thesaurus → "No recorded alignment — terms applied heuristically at import."
```

### Phase E4 — Assemble and write the explanation file

> ⚠️ **Language:** render using `$REPORT_LANG` from **Phase L0**.
> `fr` → French template. `en` → English template below.

French corpus (default template):
```markdown
# Explication des non-conformités — <sandbox-name> / <fichier-project ou "--all">
Date : <YYYY-MM-DD>
Analyse : RÉSOLU ✅ / ÉCHEC ❌  [→ `chorus-complete-report` mettra à jour si n_u > 0]
Éléments expliqués : <N> (📋 <n_subst> substantielle(s) · 🔤 <n_map> mapping · ❓ <n_unc> incertain(s) · ⛔ <n_unp> non traité(s))

---

<canonical header block from Phase E0.c — identical format to --summary>

---

<per-element blocks from Phase E3, one per target, in project-file order>

---

## Synthèse

| Élément | Classe | Motif court | Action recommandée |
|---|---|---|---|
| <id> | 📋/🔤/❓ | <motif tronqué> | <"Corriger le produit" \| "Vérifier le mapping <term>" \| "Valider avec l'ingénieur"> |
| ... | | | |

**Bilan :** <N> non-conformité(s) substantielle(s) réelle(s) sur <N_total> élément(s)
évaluable(s) (<X>%) — <N> anomalie(s) de mapping terminologique détectée(s)
séparément, ne comptant pas comme défaut produit.
```

English corpus:
```markdown
# Non-Conformity Explanation — <sandbox-name> / <project-file or "--all">
Date: <YYYY-MM-DD>
Analysis: RESOLVED ✅ / FAILED ❌  [→ `chorus-complete-report` will update if n_u > 0]
Elements explained: <N> (📋 <n_subst> substantial · 🔤 <n_map> mapping · ❓ <n_unc> uncertain · ⛔ <n_unp> unprocessed)

---

<canonical header block from Phase E0.c — identical format to --summary>

---

<per-element blocks from Phase E3, one per target, in project-file order>

---

## Summary

| Element | Class | Short reason | Recommended action |
|---|---|---|---|
| <id> | 📋/🔤/❓ | <truncated reason> | <"Fix the product" \| "Verify the <term> mapping" \| "Validate with the engineer"> |
| ... | | | |

**Bottom line:** <N> genuine substantial non-conformit(y/ies) out of <N_total>
evaluable element(s) (<X>%) — <N> terminology-mapping anomaly/ies detected
separately, not counted as product defects.
```

**Thesaurus decisions appendix (--explain):** Before writing, check whether
`$WORKSPACE/thesaurus-log-<project-slug>.md` exists.

If it does, append the following section **after** the `## Synthèse` / `## Summary`
table and before the closing horizontal rule at the end of the file:

French corpus:
```markdown
---

## Décisions terminologiques (résolutions manuelles)

> Termes du thésaurus confirmés ou rejetés manuellement depuis chorus-web
> (onglet Thésaurus du projet). Ces décisions sont déjà intégrées dans
> `agent/thesaurus/<shard>.org` et seront prises en compte lors du prochain
> `chorus-import-project`.

<copy the full Markdown table from thesaurus-log-<project-slug>.md here>

📒 Journal complet : `thesaurus-log-<project-slug>.md`
```

English corpus:
```markdown
---

## Terminology Decisions (manual resolutions)

> Thesaurus terms manually confirmed or rejected via the chorus-web Thesaurus tab.
> These decisions are already integrated into `agent/thesaurus/<shard>.org` and
> will be applied on the next `chorus-import-project` run.

<copy the full Markdown table from thesaurus-log-<project-slug>.md here>

📒 Full log: `thesaurus-log-<project-slug>.md`
```

If `thesaurus-log-<project-slug>.md` does not exist: skip this section entirely
(no empty placeholder — the section only appears when there is something to report).

Write to: `$WORKSPACE/explain-<project-slug>-<RUN_TIMESTAMP>.md` (`$WORKSPACE`
as defined at the top of this document — `$SANDBOX/workspace/<entity>/reports/`,
created if absent).
(`<project-slug>` derived from the project filename; `<RUN_TIMESTAMP>` = the
timestamp captured in Phase 6.0 — ensures 1:1 traceability with the
corresponding `run-report-<RUN_TIMESTAMP>.json` produced during the same invocation.
A UI panel can therefore group the three files by timestamp without any external index.)

For `--all` mode (Phase 6-all, flat `$SANDBOX/project-*.json` layout — see
the `$WORKSPACE`/`$ENTITY` note at the top of this document for why this
differs from the per-entity convention), produce a single consolidated file
at the sandbox root: `$SANDBOX/explain-all-<RUN_TIMESTAMP>.md`, with
per-project-file sub-sections.

Print: `[explain] Explanation file written → workspace/<entity>/reports/explain-<project-slug>-<RUN_TIMESTAMP>.md (<N> element(s))`
(or `$SANDBOX/explain-all-<RUN_TIMESTAMP>.md` for `--all` mode)


## Option `--summary` — Consultation-friendly synthesis document

> Runs **after** `--explain` (Phase E1–E4) if both flags are present, or standalone
> after Phase 6/6-all if `--summary` is passed without `--explain`. **Phase E0
> (KB recap + project recap) always runs first, in both cases** — it is cheap
> (no per-element reasoning) and is mandatory header content for `--summary`'s
> own output, independently of whether `--explain` also runs. In standalone mode,
> Phase E1–E2 (element selection + reconstruction) still run internally
> (silently, without producing the full `--explain` file) to gather the data needed
> for the synthesis — only the detailed per-element blocks (Phase E3) are skipped.
>
> **Purpose:** a single, short, skimmable document — one screen, no scrolling
> through YAML/corpus cross-references — intended for a reader who wants the
> verdict and the headline reasons in under a minute (e.g. a technical director
> reviewing a compliance dossier before a meeting), as opposed to `--explain`'s
> engineer-facing per-rule traceability.

### Phase S1 — Compute headline figures

From the same `element_status()` results as Phase 6:

```
n_total       = elements evaluable (excluding reference-catalogue / sentinel types)
n_conforme    = count CONFORME
n_non_conforme = count NON_CONFORME
n_incertain   = count elements with _a_confirmer: 1
taux          = round(100 * n_conforme / n_total)
```

Classify each NON_CONFORME element per Phase E2 step 5 (📋 substantielle / 🔤 mapping)
to compute:

```
n_subst = count NON_CONFORME classified 📋 substantielle
n_map   = count NON_CONFORME classified 🔤 mapping
taux_reel = round(100 * (n_conforme + n_map) / n_total)   # optimistic rate if all
                                                            # mapping anomalies turn
                                                            # out to be import errors,
                                                            # not real defects
```

### Phase S2 — One-page synthesis document

Write `$WORKSPACE/synthese-<project-slug>-<RUN_TIMESTAMP>.md` using this exact template
(`$WORKSPACE` as defined at the top of this document —
`$SANDBOX/workspace/<entity>/reports/`, created if absent).

> ⚠️ **Language:** render using `$REPORT_LANG` from **Phase L0**.
> `fr` → French template. `en` → English template below. Never mix languages.
> The filename (`synthese-<slug>-<RUN_TIMESTAMP>.md`) keeps its French-derived prefix
> regardless of `$REPORT_LANG`; `<RUN_TIMESTAMP>` is shared with the corresponding
> `run-report-<RUN_TIMESTAMP>.json` and `explain-<slug>-<RUN_TIMESTAMP>.md` (Phase 6.0).

French corpus (default template):
```markdown
# Synthèse de conformité — <Nom du produit / dossier, from project JSON if available>

**Dossier :** <fichier-project>
**Date :** <YYYY-MM-DD>
**Statut de l'analyse :** RÉSOLU ✅ / ÉCHEC ❌

---

<canonical header block from Phase E0.c — identical format to --explain>

---

## Résultat en un coup d'œil

┌─────────────────────────────────────────────────────────┐
│   Taux de conformité observé  :  <taux>%  (<n_conforme>/<n_total>)  │
│   Taux de conformité corrigé* :  <taux_reel>%  (si anomalies de mapping résolues) │
└─────────────────────────────────────────────────────────┘

| Indicateur | Valeur |
|---|---|
| Éléments évalués | <n_total> |
| ✅ Conformes | <n_conforme> |
| ❌ Non conformes | <n_non_conforme> |
| — dont non-conformités substantielles 📋 | <n_subst> |
| — dont anomalies de mapping terminologique 🔤 | <n_map> |
| ❓ Éléments à confirmer | <n_incertain> |

## Non-conformités substantielles (action requise sur le produit/dossier)

| Réf. | Domaine | Motif | Référence normative |
|---|---|---|---|
| <id> | <domaine> | <motif court, 1 ligne> | §<N> |
| ... | | | |

<if n_subst == 0:>
Aucune non-conformité substantielle détectée.

## Anomalies de mapping terminologique (action requise sur l'import, pas le produit)

| Réf. | Terme project | Mapping actuel | Anomalie |
|---|---|---|---|
| <id> | "<terme source>" | <slot>=<valeur> | <résumé 1 ligne> |
| ... | | | |

<if n_map == 0:>
Aucune anomalie de mapping détectée.

## Éléments à confirmer

| Réf. | Champ | Note |
|---|---|---|
| <id> | <slot> | <note du JSON> |
| ... | | |

<if n_incertain == 0:>
Aucun élément à confirmer.

## Recommandation

<one short paragraph, auto-generated from the figures above, e.g.:>
"<n_subst> point(s) substantiel(s) à corriger avant soumission. <n_map>
anomalie(s) de mapping à lever avec l'équipe d'import — leur résolution
porterait le taux de conformité de <taux>% à <taux_reel>%.
<Next step: chorus-strengthen <sandbox-name> si les critères semblent trop
stricts/permissifs, ou correction directe du document sinon.>"

---
*Document généré automatiquement par `chorus-check --summary` — voir
`workspace/<entity>/reports/explain-<project-slug>-<RUN_TIMESTAMP>.md` pour le détail règle-par-règle de
chaque élément.
```

English corpus:
```markdown
# Compliance Synthesis — <Product/dossier name, from project JSON if available>

**File:** <project-file>
**Date:** <YYYY-MM-DD>
**Analysis status:** RESOLVED ✅ / FAILED ❌

---

<canonical header block from Phase E0.c — identical format to --explain>

---

## Result at a glance

┌─────────────────────────────────────────────────────────────────┐
│   Observed compliance rate  :  <taux>%  (<n_conforme>/<n_total>) │
│   Adjusted compliance rate* :  <taux_reel>%  (if mapping issues resolved) │
└─────────────────────────────────────────────────────────────────┘

| Indicator | Value |
|---|---|
| Elements evaluated | <n_total> |
| ✅ Compliant | <n_conforme> |
| ❌ Non-compliant | <n_non_conforme> |
| — of which substantial non-conformities 📋 | <n_subst> |
| — of which terminology-mapping anomalies 🔤 | <n_map> |
| ❓ Elements to confirm | <n_incertain> |

## Substantial non-conformities (action required on the product/document)

| Ref. | Domain | Reason | Normative reference |
|---|---|---|---|
| <id> | <domain> | <short reason, 1 line> | §<N> |
| ... | | | |

<if n_subst == 0:>
No substantial non-conformity detected.

## Terminology-mapping anomalies (action required on the import, not the product)

| Ref. | Project term | Current mapping | Anomaly |
|---|---|---|---|
| <id> | "<source term>" | <slot>=<value> | <1-line summary> |
| ... | | | |

<if n_map == 0:>
No mapping anomaly detected.

## Elements to confirm

| Ref. | Field | Note |
|---|---|---|
| <id> | <slot> | <note from the JSON> |
| ... | | |

<if n_incertain == 0:>
No element to confirm.

## Recommendation

<one short paragraph, auto-generated from the figures above, e.g.:>
"<n_subst> substantial point(s) to correct before submission. <n_map>
mapping anomaly/ies to resolve with the import team — resolving them would
raise the compliance rate from <taux>% to <taux_reel>%.
<Next step: chorus-strengthen <sandbox-name> if the validation criteria seem too
strict/permissive, or direct correction of the document otherwise.>"

---
*Document automatically generated by `chorus-check --summary` — see
`workspace/<entity>/reports/explain-<project-slug>-<RUN_TIMESTAMP>.md` for the full rule-by-rule detail of
each element.*
```

**Thesaurus decisions note (--summary):** Before writing, check whether
`$WORKSPACE/thesaurus-log-<project-slug>.md` exists.

If it does, append the following compact section **after** the `## Recommandation` /
`## Recommendation` paragraph and before the closing `---` footnote line:

French corpus:
```markdown

## Décisions terminologiques

<N> terme(s) résolu(s) manuellement depuis chorus-web
(<n_confirm> ✅ confirmé(s) · <n_reject> ❌ rejeté(s)).
Voir le journal complet : `thesaurus-log-<project-slug>.md`
```

English corpus:
```markdown

## Terminology Decisions

<N> term(s) manually resolved via chorus-web
(<n_confirm> ✅ confirmed · <n_reject> ❌ rejected).
Full log: `thesaurus-log-<project-slug>.md`
```

Count `<N>`, `<n_confirm>`, `<n_reject>` by counting table rows (excluding the
header) in `thesaurus-log-<project-slug>.md` and matching `✅ Confirmé`/`❌ Rejeté`
(FR) or `✅ Confirmed`/`❌ Rejected` (EN) in the Action column.

If `thesaurus-log-<project-slug>.md` does not exist: skip this section entirely.

Print: `[summary] Synthesis written → workspace/<entity>/reports/synthese-<project-slug>-<RUN_TIMESTAMP>.md`

> **Consultation ergonomics:** this file is deliberately kept under one printed
> page. It never repeats the full YAML/corpus traceability of `--explain` —
> it only links to it. If both `--explain` and `--summary` are requested, generate
> `--explain` first (Phase E1–E4) so `--summary`'s classification (Phase S1) can
> reuse its per-element classification without recomputing it twice.



---

## Option `--from-report` — Analyse sans relance du pipeline

> **Trigger webapp :** bouton "🔎 Analyse" affiché dans la modale run-report quand
> aucun fichier `explain-*` / `synthese-*` lié par timestamp n'existe pour ce run.
> **Usage manuel :** `chorus-check <sandbox-name> --from-report <path> --summary --explain`

Ce mode permet de produire les rapports `--explain` et/ou `--summary` à partir
d'un run-report JSON **déjà existant**, sans rejouer le pipeline (pas de `run.pl`,
pas d'appel MCP, pas de lecture de la KB org ni des fichiers YAML).

> ⛔ **Interdictions strictes en mode `--from-report` :**
> - Ne jamais appeler `chorus_process`, `chorus_engine_create` ou `chorus_expert_create`
> - Ne jamais exécuter `perl run.pl`
> - Ne jamais lire `agent/chorus/*.org` ni `rules/**/*.yml` (les données sont dans le JSON)
> - Ne jamais régénérer `Feed.pm`, `Agent/*.pm`, `Expert.pm`

### Phase FR0 — Chargement du run-report

1. Lire `$SANDBOX/<run-report-path>` (fichier JSON produit par un précédent `chorus-check`)
2. Extraire `$RUN_TIMESTAMP` du nom de fichier :
   ```
   run-report-(\d{8}-\d{6})\.json  →  $RUN_TIMESTAMP = "YYYYMMDD-HHMMSS"
   ```
3. Extraire `$ENTITY`/`$WORKSPACE` depuis `<run-report-path>` lui-même (voir
   la note `$WORKSPACE`/`$ENTITY` en tête de ce document — même règle de
   dérivation qu'en mode normal, appliquée ici au chemin du run-report plutôt
   qu'à celui du fichier projet) :
   ```
   workspace/<entity>/reports/run-report-....json  →  $ENTITY = "<entity>"
   $WORKSPACE = $SANDBOX/workspace/$ENTITY/reports/
   ```
   ⚠️ Ne jamais écrire `explain-*.md`/`synthese-*.md` à la racine `$SANDBOX/workspace/`
   ou `$SANDBOX/` dans ce mode non plus — mêmes garde-fous qu'en mode normal.
4. Extraire depuis le JSON :
   - `elements[]` → tableau des éléments avec leurs verdicts, motifs, `_rule_trace`
   - `project_file` → déduire `<project-slug>` (basename sans `.json`)
   - `pipeline_solved` → équivalent du statut SOLVED/FAILED de Phase 6
   - `n_total`, `n_conforme`, `n_non_conforme`, `n_incertain` → stats de Phase 6.1

5. Construire le contexte équivalent à la sortie de Phase 6 :
   ```
   $phase6_elements  = data extracted from elements[]
   $phase6_solved    = json.pipeline_solved
   $phase6_stats     = { n_total, n_conforme, n_non_conforme, n_incertain }
   $project_slug     = basename(json.project_file, ".json")
   ```

> Si `elements[]` est absent ou vide → arrêter et afficher :
> `"[--from-report] run-report vide ou invalide — impossible de générer l'analyse."`

### Phase FR1 — Exécution de --explain et/ou --summary

Aller directement aux phases d'analyse en utilisant les données de Phase FR0
**à la place** de la sortie normale de Phase 6 :

- **`--explain`** → exécuter Phase E0 → E1 → E2 → E3 → E4
  - Phase E0 : lire `$SANDBOX/agent/chorus/index.org` pour le recap KB uniquement
    (nécessaire pour le header canonique — lecture seule, aucune génération)
  - Phase E1 : `TARGETS` = éléments de `$phase6_elements` avec `conforme == 'NON_CONFORME'`
    **ou** `a_confirmer == true` — une **union**, pas une intersection ni un filtre
    implicite sur le verdict. ⚠️ Un élément `a_confirmer == true` fait partie de
    `TARGETS` **quel que soit son verdict** (`CONFORME`, `NON_CONFORME`, ou
    `(unprocessed)`) — c'est le même piège que celui documenté en Phase E1 (mode
    normal, voir plus haut) : un élément CONFORME avec `a_confirmer: true` doit
    apparaître dans `explain-*.md` tout autant qu'un NON_CONFORME classique.
    Observed incident: a `--from-report` run included all 5 `a_confirmer` elements
    correctly in the `synthese-*.md` table (Phase S1/S2 iterates `$phase6_elements`
    unconditionally) but **omitted all 5 from `explain-*.md`** — root cause was
    filtering `TARGETS` down to `conforme == 'NON_CONFORME'` only, silently
    dropping the CONFORME/`(unprocessed)` members of the union. Always compute
    `TARGETS` as the full union **before** iterating Phase E2-E4 — never narrow it
    to one verdict class first.
  - Phase E2–E3 : reconstruction depuis `_rule_trace` déjà présent dans le JSON
    (aucune lecture de règles YAML nécessaire — les traces sont déjà résolues)
  - Phase E4 : écrire `$WORKSPACE/explain-<project-slug>-<RUN_TIMESTAMP>.md`

- **`--summary`** → exécuter Phase E0 → S1 → S2
  - Phase S1 : calculer `n_subst`, `n_map`, `taux` depuis `$phase6_elements`
  - Phase S2 : écrire `$WORKSPACE/synthese-<project-slug>-<RUN_TIMESTAMP>.md`

> `$RUN_TIMESTAMP` extrait en Phase FR0 garantit que les fichiers produits partagent
> le même suffixe que le `run-report-<RUN_TIMESTAMP>.json` source — le lien par
> nom de fichier (convention MVP0) est ainsi rétabli automatiquement.

Print en fin d'exécution :
```
[from-report] explain → workspace/.../explain-<slug>-<RUN_TIMESTAMP>.md
[from-report] synthese → workspace/.../synthese-<slug>-<RUN_TIMESTAMP>.md
```
