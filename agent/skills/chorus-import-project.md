# Skill — chorus-import-project

> Trigger: `chorus-import-project <sandbox-name> <source…> [--out <fichier.json>] [--batch] [--context <label>]`
> Agent: `code`
> ⚠️ Downgraded from `architect` to `code` (claude-sonnet-4-6 / medium) — extended thinking
> (variant: large) interacts poorly with the intra-phase keepalive protocol: the model may
> batch all thinking before emitting tool calls, nullifying the TTL resets.
> Standard thinking (`code`) iterates more tightly with tool calls → keepalive writes fire
> reliably every 50 elements (Phase 2) and every 20 terms (Phase 3).
>
> `<sandbox-name>` : sandbox containing a KB produced by `chorus-feed`
> `<source…>`      : one or more project sources from the engineer (see modes below)
>                    Accepted formats: **PDF, Word (.docx), Excel (.xlsx/.csv), XML/HTML,
>                    plain text, table pasted in the chat, or directory path**.
>                    Document files (PDF/DOCX/XLSX/CSV/XML/HTML) are automatically converted
>                    to plain text before semantic processing.
> `--out`          : output JSON filename — applies to **Single and Merge modes**
>                    (overrides the default location entirely, highest priority —
>                    see "Output JSON location", Phase 5). Ignored in Batch mode.
>                    Default when absent: `project-import-<NNN>.json`, written under
>                    `$WORKSPACE/<client>/` if Scope is non-global, or `$SANDBOX/agent/`.
> `--batch`        : force batch mode even if a single source is provided
> `--check-fidelity` : after each auto-conversion of a document source
>                    (PDF/DOCX/XLSX/CSV/XML/HTML — see "Format Detection &
>                    Auto-conversion" below), invoke `chorus-markdown` on the
>                    converted file before proceeding to alignment. Optional,
>                    advisory only (non-blocking — `chorus-markdown` is invoked
>                    without `--strict`): surfaces a fidelity report
>                    (`workspace/reports/markdown-check-<slug>.md`) so the
>                    engineer can sanity-check the alignment input quality
>                    before trusting Phase 3's terminology matches. Off by
>                    default to avoid slowing down routine imports.
> `--context <label>` : declares the terminology scope for this import (e.g. a client
>                    name, a project family, a business domain). Optional — manual
>                    override only. If absent, the scope is auto-derived from the
>                    source path (`$SANDBOX/$WORKSPACE/<client>/sources/...` → scope =
>                    `<client>`) or defaults to `global` otherwise (same behaviour as
>                    before this flag existed). See "Scope derivation" (Phase 1.2b)
>                    for the full three-step cascade — this addresses multi-project/
>                    multi-client sandboxes where the same term can legitimately mean
>                    different things depending on context.
>
> ### Invocation Modes
>
> | Syntax | Mode | Behavior |
> |---|---|---|
> | `chorus-import-project sb fichier.pdf` | **Single** | 1 source → 1 JSON (original behavior) |
> | `chorus-import-project sb f1.pdf f2.xlsx f3.docx` | **Merge** | N sources → 1 merged JSON (same project, complementary files) |
> | `chorus-import-project sb ./dossier/` | **Batch** | Directory → 1 JSON per file + summary report |
> | `chorus-import-project sb *.pdf --batch` | **Batch** | Explicit glob → 1 JSON per file + summary report |
> | `chorus-import-project sb fichier.pdf --align-review` | **Align-review** | Stops after Phase 3 — produces `align-review-NNN.org` for human validation before JSON |
>
> **Automatic mode detection rule:**
> - 1 non-directory source argument → Single
> - N > 1 source arguments (same or mixed formats) → Merge
> - 1 directory argument or `--batch` flag present → Batch
> - `--align-review` present → alignment review mode (compatible with Single and Merge; incompatible with `--batch`)
>
> **Single responsibility: align the engineer's project terminology with the sandbox
> KB slots and types, then produce a valid project JSON file.**
>
> Prerequisites: `chorus-feed <sandbox-name>` must have been run beforehand (org KB present).
>
> ⚠️ **KB sources to use — strict order:**
> 1. `$SANDBOX/agent/chorus/index.org` → Frame types, pipeline, namespace
> 2. `$SANDBOX/agent/chorus/<slug>.org` → sections `Ontologie`, `Dictionnaire des slots`,
>    `Catalogue des Frames` (mandatory slots, value domains)
> 3. `$WORKSPACE/import-report-*.org` → legacy fallback (Phase 1.3 — skip if WEB-027 thesaurus present)
>
> ⛔ **Never silently reuse a prior import's alignment decisions verbatim just because
> the source file is byte-identical.** Always re-derive every element from the
> **current** KB and sandbox-local extensions. The KB evolves between imports —
> a copy-forward shortcut freezes the JSON at the KB state of the *first* import,
> defeating subsequent `chorus-feed --enrich` enrichments and extension bugfixes.
> If the engineer wants historical reuse (comparison): explicit, stated choice only.
> (Precedent: re-import copy-forward propagated a fixed extension bug — see
> `chorus-cbom-import.md § Re-import duplicate-detection shortcut`.)
>
> ⛔ **Never read** `Helpers.pm`, `Feed.pm`, `Agent/*.pm` to infer slots.
> ⛔ **Never invent** a value absent from the source document — report the gap.


## Phase -0.1 — Sandbox-local extension discovery (optional)

> **Purpose:** allow a sandbox to plug in source-format-specific pre-fill logic
> (e.g. a CBOM/OID registry, a domain-specific unit-conversion table) **without
> touching this generic skill**. This core skill stays domain-agnostic — any
> sandbox-specific knowledge lives in the sandbox itself, never here.

**Before Phase 0**, check whether `$SANDBOX/skills/` exists and contains one or
more files matching `chorus-*-import.md`.

```
extensions = glob("$SANDBOX/skills/chorus-*-import.md")
```

- **No match** → proceed directly to Phase 0. No behavior change (this is the
  case for every sandbox that has no such extension — the default, unchanged path).
- **One or more matches** → read each matching file. Each extension file
  documents:
  - which source format(s) it targets (e.g. CBOM/CycloneDX JSON),
  - a pre-fill data table or reference file it provides (e.g. an OID → KB-slot
    mapping),
  - at which phase of the standard pipeline (0/2/3) its data should be
    consulted, and how (first-class candidate vs. fallback — same spirit as
    `xref_map` in the PDF/Excel/Word pipelines).
  Apply the extension's instructions **in addition to**, never instead of, the
  standard phases below — an extension only pre-fills candidate values; the
  standard Phase 3 alignment table, gap detection (Phase 4), and `_a_confirmer`
  flagging rules still apply unchanged on top of it.
- **Ambiguous match (source format not covered by any extension)** → ignore
  extensions silently, proceed with the standard pipeline.
- **Multiple matches** → apply all applicable extensions, in the ordering each
  extension file itself declares (an extension may state a dependency on
  another extension's output — e.g. "runs after a source-format extension has
  resolved `famille_probleme_math`/size slots"). If no ordering is declared by
  any of them, apply source-format extensions (those tied to a specific file
  format, e.g. CBOM/CycloneDX) before format-agnostic enrichment extensions
  (those operating on already-resolved slots, e.g. a size→security-strength
  proxy table). Never let two extensions silently overwrite the same slot for
  the same element without surfacing the conflict — if both would set the same
  slot with different values, flag the element `_a_confirmer: 1` and report
  both candidate values.

> ⛔ This skill (`chorus-import-project.md`) never hardcodes any sandbox-specific
> registry, mapping, or vocabulary. If you find yourself about to add a
> domain-specific table here (OID lists, unit tables, etc.) — stop: it belongs
> in `$SANDBOX/skills/chorus-<domain>-import.md` instead.


## Phase 0 — Source Data Acquisition

### Format Detection & Auto-conversion

**Before mode detection**, check each source file's extension (case-insensitive).
`chorus-import-project` accepts **plain text, inline data, and directories by default**.
**However**, if a document format requiring preprocessing is detected, the corresponding
conversion skill is invoked **automatically** and the extracted output replaces the input
for subsequent phases.

| Extension | Format | Auto-conversion skill | Output file(s) |
|---|---|---|---|
| `.pdf` | PDF | `chorus-pdf <sandbox> <file> --auto` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.docx` | Word | `chorus-word <sandbox> <file>` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.xlsx` / `.csv` | Spreadsheet | `chorus-excel <sandbox> <file>` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.xml` / `.html` / `.htm` | XML/HTML | `chorus-xml <sandbox> <file>` | `<NNN>-<slug>-content.md` or `-vision.md` |
| `.txt` / `.md` / inline | Plain/Markdown | *(none)* | Use as-is |

**Auto-conversion algorithm:**

> ⚠️ **`README.org` ownership — do NOT let the invoked conversion skill touch `* Corpus`.**
> `chorus-word`/`chorus-pdf`/`chorus-excel`/`chorus-xml` each have their own Phase 4.1
> ("Update `README.org`") which unconditionally appends a row to the `* Corpus` table.
> That table is reserved for **normative texts that fed `chorus-feed`** — a project
> document routed through `chorus-import-project` is never normative corpus, even
> though it physically lands in `corpus/` (shared conversion output directory) and even
> though the same conversion skill is reused. Silently letting the invoked skill run its
> own Phase 4.1 here would misclassify the file as corpus (precedent: a converted
> project document was wrongly listed in `* Corpus` after an auto-invoked
> `chorus-word` call).
>
> **Rule:** when invoking a conversion skill from this algorithm, instruct it explicitly
> to **skip its own Phase 4.1** (pass this instruction as part of the call context —
> e.g. "invoked by chorus-import-project — do not update README.org § Corpus, the
> caller will record this file itself"). `chorus-import-project` performs the
> `README.org` update itself, under the dedicated section described in Step 4 below —
> never under `* Corpus`.

```
For each source in <source…>:
  If source is a directory:
    # Preserve directory mode — will be expanded later
    Add to sources list as-is
  Else if source ends in .pdf, .docx, .xlsx, .csv, .xml, .html, .htm:
    # Invoke conversion skill — instruct it to skip its own README.org Phase 4.1
    # (this algorithm records the file itself, see Step 4 below)
    ext = source file extension
    if ext == .pdf:
      Call: chorus-pdf <sandbox> <source> --auto   [skip-readme-update]
    elif ext == .docx:
      Call: chorus-word <sandbox> <source>          [skip-readme-update]
    elif ext in (.xlsx, .csv):
      Call: chorus-excel <sandbox> <source>         [skip-readme-update]
    elif ext in (.xml, .html, .htm):
      Call: chorus-xml <sandbox> <source>           [skip-readme-update]

    Wait for skill to complete (expected exit code 0)

    # Auto-detect converted file
    candidates = glob(<sandbox>/corpus/[0-9][0-9][0-9]-*-{text,content,vision}.{txt,md})
    converted_path = max(candidates, key=mtime)  # newest file

    # Replace source with converted file for subsequent phases
    source = converted_path
    Print: "[import] Auto-converted <original.ext> → <converted_path>"

    # Optional fidelity check — chorus-markdown (advisory, non-blocking by default)
    # Only run if --check-fidelity was passed on this invocation.
    if --check-fidelity:
      Call: chorus-markdown <sandbox> <source_original.ext> <converted_path> --report
      # Non-blocking: report surfaced to the engineer, Phase 3 proceeds regardless
      # unless the engineer explicitly stops after reviewing a ❌ row.

    # Step 4 — Record the converted file under the dedicated section
    # (NOT under * Corpus — see warning above). Done once per source, here,
    # regardless of Single/Merge/Batch mode. The produced project-import-*.json
    # name is not yet known at this point in Single/Merge mode — write it as
    # "(pending)" and patch the row in Phase 6 once the output filename is final.
    Ensure $SANDBOX/README.org contains a
      "* Imported project documents (not corpus — chorus-import-project artefacts)"
      heading (create it, with the explanatory preamble below, if absent):
        "⚠️ These files are not normative corpus — they never fed chorus-feed and
         never influenced the KB, YAML rules, or Helper catalogues. They are
         project-side documents aligned against the existing KB terminology by
         chorus-import-project. Kept in corpus/ only because that is where the
         conversion skills write their Markdown output — physical location, not
         classification."
    Append a row:
      | <NNN> | <converted_path> | <original source description> | <produced project-import-*.json, or "(pending)"> | <date> |

  Else:
    # Plain .txt, .md, or inline content — use as-is
    source remains unchanged
```

**Example scenarios:**

```bash
# Single PDF — auto-converted
chorus-import-project test-05-RGPD corpus/002-norme.pdf
→ [auto] Detected .pdf — calling chorus-pdf test-05-RGPD corpus/002-norme.pdf --auto
→ [auto] Conversion complete → corpus/003-norme-vision.md
→ [import] Using converted corpus/003-norme-vision.md
→ [Phase 1] Reading KB...

# Merge mode: mixed formats — each auto-converted separately
chorus-import-project test-05-RGPD dctp.docx isolations.xlsx norms.txt
→ [auto] dctp.docx → corpus/004-dctp-vision.md (via chorus-word)
→ [auto] isolations.xlsx → corpus/005-isolations-text.txt (via chorus-excel)
→ [auto] norms.txt → use as-is
→ [merge] Merging 3 sources...

# Batch mode: directory with mixed formats
chorus-import-project test-05-RGPD ./sources/
→ [auto] Processing sources/norme.pdf → corpus/006-norme-vision.md
→ [auto] Processing sources/dossier.docx → corpus/007-dossier-vision.md
→ [batch] Generating project-import-001.json, project-import-002.json...
```

After format detection and auto-conversion (if any), proceed to Mode Detection.

### Mode Detection and Source Collection

```
# Batch Mode (directory)
If <source> is a directory:
  files = glob("$source/*.{pdf,docx,xlsx,csv,txt}")
  Sort by name — process each file independently (→ Phase 0B per file)
  Continue to Phase 0-BATCH after collection

# Batch Mode (glob / explicit --batch)
If --batch present or N homogeneous-format sources (N > 1 same extension):
  files = source list
  Sort by name — process each file independently
  Continue to Phase 0-BATCH after collection

# Merge Mode (N sources, mixed formats, without --batch)
If N > 1 sources without --batch:
  Extract each source separately → produce N labelled text blocks
  Merge blocks before Phase 2 (global inventory)
  ⚠️ Warn if two files appear to cover the same elements (potential duplicate ids)

# Single Mode
1 non-directory source, without --batch → original behaviour (Phase 0A/0B below)
```

### Phase 0-BATCH — Batch Processing

For each file `f` in `files`:
1. Extract plain text (Phase 0B below)
2. Run Phases 1–6 **autonomously** for this file
3. Name the outputs: `project-import-<NNN>.json` (location per "Output JSON location",
   Phase 5 — `$SANDBOX/agent/` for Scope=global, or `$SANDBOX/workspace/<client>/` if
   the batch's source directory matched the `<client>/sources/` convention) and
   `import-report-<NNN>.org` (in `$WORKSPACE`, i.e. `$SANDBOX/workspace/reports/`,
   or `$SANDBOX/workspace/<client>/reports/` if the batch's source directory matched
   the `<client>/sources/` convention — see "Scope derivation", Phase 1.2b — created
   if absent) — increment NNN independently for each file
4. At the end of the batch → produce the **batch summary report** (see Phase 6-BATCH)

> ⚠️ Phase 1 (index.org read) is run **once only** at the start of the batch.
> The lazy KB cache (`loaded_agents`) is also shared across all files — each
> `<slug>.org` is loaded at most once for the entire batch (WEB-029).

### Phase 0-FUSION — Multi-Source Merge

After individually extracting each source:
1. Concatenate the text blocks, labelling each by source file:
   ```
   === SOURCE: structure.pdf ===
   <texte extrait>

   === SOURCE: isolation.xlsx ===
   <texte extrait>
   ```
2. The inventory (Phase 2) processes the whole as a single source
3. Retain the `_source_fichier` attribute on each JSON element for traceability
4. **Id conflict handling**: if two sources define an element with the same `id`:
   - Include both with suffix `_a` / `_b` on the duplicate
   - Add `_conflit: 1` and `_conflit_source: ["fichier1", "fichier2"]`
   - Report the conflict in the import report

### Case A — Inline source (data pasted in the chat)

The engineer pastes a table excerpt, a list of elements, or a descriptive text directly.
Process the content as-is — proceed directly to Phase 1.

### Case B — Filesystem source (PDF / DOCX / XLSX / CSV)

> ⛔ **Skip this section** if `source_format` ∈ {JSON, CycloneDX, XML structuré} —
> Phase -0.1 already handled acquisition via the sandbox-local extension.
> No document extraction needed.

**Load extraction pipelines for document sources:**

Load `chorus-import-extract` (sub-skill) — provides the full PDF / Excel / Word / LibreOffice
pipelines with hybrid mode (pdfminer/openpyxl/python-docx + Claude vision + XREF pass).

```
eca__skill("chorus-import-extract")
```

After loading: invoke the pipeline matching the detected format, then proceed to Mode Detection.



## Phase 1 — Read the KB (canonical terminology)

### 1.0 Sandbox inventory (first tool call — token keepalive)

**Before reading any file**, read the directory tree $SANDBOX/ immediately.

This serves two purposes:
1. Acquires the full sandbox structure early (agents list, rules dirs, existing JSON/report files)
2. Ensures at least one tool call happens before any long reading+thinking cycle,
   keeping the IDE token active from the very start.

Use this inventory to:
- Record the list of agent slugs (for lazy loading in Phase 3 — do NOT read slug.org here)
- Know which `rules/<slug>/` directories exist (noted for Phase 3 lazy loading)
- Detect the sandbox thesaurus (WEB-027) :
  `$SANDBOX/workspace/<C>/thesaurus.org` (layout WEB-027, prioritaire)
  **ou** `$SANDBOX/agent/thesaurus/<C>.org` (legacy pre-WEB-027, compat descendante)
  (voir "Thesaurus storage layout" pour la détection et la migration automatique)
- Detect any existing `import-report-*.org` files (for 1.3 — secondary memory)

### 1.1 Pipeline Index

Read `$SANDBOX/agent/chorus/index.org`:
- Namespace + agent list (slug, pos)
- Global slot dictionary (if present in the index)

### 1.2 Per-agent terminology — lazy loading (WEB-029)

> **⚠️ WEB-029 — Do NOT read `<slug>.org` files in Phase 1.**
> Loading all KB agent files upfront inflates the LLM context by ~150 KB
> (tool call outputs) before a single term is aligned — observed at 149 K tokens
> on a 6-agent sandbox, causing 20–25 min/block after blk1.
>
> **Agent KB files are loaded on demand in Phase 3**, the first time a term is
> matched to that agent's `type_element` domain.
>
> Phase 1.2 records only the **agent list** derived from Phase 1.0 (directory tree)
> and Phase 1.1 (`index.org`): slug names, their positions, and rule directories.
> No `eca__read_file` calls for `<slug>.org` happen here.

⛔ **PHASE 1.2 ENDS HERE.** Do not read any `<slug>.org` file now.
The slug loading protocol (2-step read sequence, terminology reference, type_element guard)
executes **in Phase 3** — see `### Block-based alignment protocol` § lazy KB loading.

### 1.2b Sandbox thesaurus (highest priority source)

Si un thésaurus existe (`$SANDBOX/workspace/<C>/thesaurus.org` ou legacy
`$SANDBOX/agent/thesaurus/<C>.org` — voir "Thesaurus storage layout"), **lire
le fichier entity immédiatement après Phase 1.2**, avant tout import-report.

The thesaurus is the **canonical project-terminology memory** for this sandbox. It is
separated from the normative KB (`<slug>.org`) and from import reports: it stores
project-specific synonyms validated by the engineer across all previous imports.

**Priority rule:**
```
thesaurus (1.2b)  >  import-report-*.org (1.3)  >  KB aliases (1.2)
```

A mapping present in the thesaurus is applied **at ✅ confidence without asking the
engineer again**, regardless of what the KB or previous import-reports say.

#### Structural section detection — independent of thesaurus lexical matching

> **Why this matters:** thesaurus matches on the literal wording of a previous import.
> A same concept expressed differently (other language, house style, suffix convention)
> won't match — structural section titles provide a wording-independent detection signal.

Before relying solely on thesaurus/KB-alias lexical lookup (Phase 1.2/1.2b) for a
category of elements, **scan the source document for structurally self-declaring
section titles** — sections whose heading itself names a normative category
regardless of the document's language or house style (e.g. "Extended components
definition" / "Composants étendus" / "EXTENDED COMPONENTS DEFINITION", or any
other standard-specific self-labelled section relevant to the active KB's domain).

When such a section is found:
1. **Pre-tag** every identifier/element listed under that section as a candidate
   for the `type_element` the KB associates with that category (consult the KB
   org's `Dictionnaire des slots`/Frame catalogue to confirm the exact
   `type_element` name — do not guess).
2. Only **then** consult the thesaurus/KB aliases (Phase 1.2/1.2b) — to confirm,
   refine, or override this structural pre-tag, never to be the sole detection
   mechanism for this category.
3. If a thesaurus entry for this concept already exists **under a different
   wording** than anything found in the current document, record this explicitly
   in the import report (new subsection, see below) rather than silently
   proceeding — this is a signal worth surfacing even when the structural
   pre-tag already resolved the element correctly, because it reveals a thesaurus
   coverage gap that will resurface on the *next* sandbox with yet another wording.

#### Thesaurus alias variants — accept multiple wordings per mapping

Extend each `* Aliases` row to optionally carry **several equivalent wordings**
for the same KB mapping, instead of a single fixed label — separated by `;`:

```
| Project term (variants)                                                        | KB type_element      |
|------------------------------------------------------------------------------------+-------------------------|
| brique fonctionnelle spécifique ; brique d'assurance spécifique ; Extended component ; Extended class ; Extended family | extended_component |
```

Lookup (Phase 1.2b step "How the thesaurus is used") must match **any** of the
`;`-separated variants against the document's terminology, not only the first/
original one. When a new import validates an additional wording for an
**already-mapped** `type_element`, **append** the new wording to the existing
row's variant list (do not create a duplicate row) — this is how the thesaurus
accumulates cross-language/cross-style coverage for the same concept over time.

#### Import report — cross-check against existing thesaurus mappings

When structural detection identifies a category covered by a thesaurus entry
under a different wording, add to the import report:

```org
* ⚠️ Thesaurus mapping — wording mismatch detected
  | KB type_element | Existing thesaurus wording | Wording in this document |
  |---|---|---|
  | <type_element>  | <existing wording>         | <new wording>            |
  Action: new wording appended to thesaurus variant list.
```

#### Thesaurus storage layout — sharded by Scope

**WEB-027 (2026-10-30) — Architecture thésaurus 3 niveaux.**

```
Niveau 1 — KB / CBOM-oid-registry.yml          ← automatique, partagé sandbox
  OID/RFC → KB slots. Jamais dans le thésaurus.
  Résolu par l'extension sandbox (Phase -0.1) avant toute consultation du thésaurus.

Niveau 2 — Projet (défaut pour les résolutions à l'import)
  $SANDBOX/workspace/<C>/<projId>.thesaurus.json
  Décisions spécifiques à UN projet/import. N'affecte que les réimports du même projet.
  Exemple : PBKDF2 → derivation_cle décidé pour Cosmian KMS ≠ hachage_mot_de_passe
  dans un autre projet.

Niveau 3 — Entity (promotion explicite uniquement)
  $SANDBOX/workspace/<C>/thesaurus.org
  Mappings valides pour TOUS les projets de l'entity <C>.
  Jamais automatique à l'import — promotion via bouton 🏢 webapp ou décision explicite.
```

**Règles d'écriture à l'import :**
- ✅ certaine (depuis CBOM-oid-registry, fiabilité certaine/haute) → **Niveau 2** (projet JSON)
- ✅ confirmée par l'ingénieur en session → **Niveau 2** (projet JSON) — sauf si l'ingénieur dit
  explicitement "valide pour tous les projets <C>" → **Niveau 3** (entity org)
- ⚠️ `_a_confirmer` newly seen → **Niveau 3 Pending** (entity org) — les Pending sont entity-scoped
  pour être visibles à la webapp quel que soit le projet courant
- ⬜ out-of-scope → **Niveau 3 Out-of-scope** (entity org)

**Quel fichier lire pour un import** (C = Scope de cet import, projId = nom du JSON produit) :
```
Lire en priorité : $SANDBOX/workspace/<C>/<projId>.thesaurus.json   (Niveau 2 — projet)
Puis :             $SANDBOX/workspace/<C>/thesaurus.org              (Niveau 3 — entity)
Ne jamais lire le thésaurus d'une autre entity.
```

**`* Pending`, `* Out-of-scope`, `* Conflicts`** vivent dans le fichier entity
(`workspace/<C>/thesaurus.org`). Jamais au Niveau 2 (projet JSON).

#### Format JSON — Niveau 2 (`<projId>.thesaurus.json`)

⛔ **Noms de clés stricts** — la webapp (`chorus/thesaurus.js`) lit ce fichier directement.
Ne jamais inventer d'autres noms de clés (`project_term`, `kb_type_element`, etc.).

```json
{
  "_meta": {
    "sandbox": "<sandbox-name>",
    "entity": "<C>",
    "proj_id": "<projId>",
    "created": "YYYY-MM-DD",
    "updated": "YYYY-MM-DD"
  },
  "aliases_type_element": [
    {
      "term":          "<project term>",
      "type_element":  "<KB type_element>",
      "confidence":    "certaine | confirmée",
      "source_import": "<import-report-NNN>"
    }
  ],
  "aliases_slot_values": [
    {
      "term":          "<project term>",
      "slot":          "<KB slot>",
      "value":         "<KB value>",
      "confidence":    "certaine | confirmée",
      "source_import": "<import-report-NNN>"
    }
  ],
  "out_of_scope": [
    { "term": "<project term>", "reason": "<raison>" }
  ]
}
```

> `pending` n'existe pas au Niveau 2 — les Pending sont toujours en Niveau 3 entity org.
> `proj_id` dans `_meta` doit correspondre exactement au stem du fichier JSON produit
> (ex : `project-import-1793433323491` pour `project-import-1793433323491.json`).

**Compat descendante :** si `workspace/<C>/thesaurus.org` absent, lire `agent/thesaurus/<C>.org` (legacy). Ne jamais créer de nouveaux fichiers sous `agent/thesaurus/`.

**Each shard file's own header:**
```org
#+TITLE: Project terminology thesaurus — sandbox <name> — entity: <entity>
#+UPDATED: <date>
#+DESCRIPTION: Validated project-term → KB-slot mappings, Scope=<entity>.
               Maintained automatically by chorus-import-project.
               WEB-027: canonical location = workspace/<entity>/thesaurus.org.
               Do NOT edit KB org files to add project aliases — use this file instead.
```

#### Thesaurus format — `workspace/<entity>/thesaurus.org`

Un seul fichier par entity contient toutes les sections (squelette) :

```org
#+TITLE: Project terminology thesaurus — sandbox <name> — entity: <entity>
#+UPDATED: <date>
#+DESCRIPTION: Validated project-term → KB-slot mappings, Scope=<entity>.
               WEB-027: workspace/<entity>/thesaurus.org.

* Aliases — type_element
  | Project term | KB type_element | Confidence | Source import | KB hash @ validation | Scope |
  |---|---|---|---|---|---|

* Aliases — slot values
  | Project term | KB slot | KB value | Confidence | Source import | KB hash @ validation | Scope |
  |---|---|---|---|---|---|---|

* Pending — to confirm on next import of this entity
  | Project term | Proposed KB mapping | Flag | Source import | Scope |
  |---|---|---|---|---|

* Out-of-scope terms (⬜)
  | Project term | Reason | Recommended sandbox | Last seen |
  |---|---|---|---|

* Conflicts (⚠️ CONFLICT — blocking, requires engineer arbitration)
  | Project term | Scope | Existing mapping | New mapping | First seen | Conflict raised in | Status |
  |---|---|---|---|---|---|---|
```



#### KB hash tracking & revalidation

Every `* Aliases` row records the **`.kb-hash`** in effect at the moment the mapping was
validated (`KB hash @ validation` column). This is a **read-only comparison mechanism**
— it never triggers a `.kb-hash` write or invalidation from `chorus-import-project`
itself (only `chorus-feed --enrich` / `--harvest-aliases` write `.kb-hash`, since only
they modify `<slug>.org` files).

**Why:** a `✅ confirmed` mapping is validated against a specific state of the KB (a
given slot definition, a given `type_element` semantics). If the KB is later enriched
or a `type_element`'s meaning/scope changes (`chorus-feed --enrich`), an old thesaurus
mapping could silently keep pointing at a slot that no longer means what it meant when
validated — applied at ✅ confidence forever, with no signal that anything changed.

**Mechanism:**
1. **At validation time** (Phase 3, "Immediate thesaurus update after each resolution"):
   read `$SANDBOX/agent/.kb-hash` (if present) and record its first 8 hex chars in the
   `KB hash @ validation` column of the new/updated Aliases row. If `.kb-hash` is absent
   (KB predates hash tracking, or infra never generated for this sandbox), record `—`
   and skip step 2 below for that row until a hash becomes available.
2. **At lookup time** (Phase 3, "How the thesaurus is used", steps 1–2 below): before
   applying a thesaurus hit at ✅ confidence, compare the row's `KB hash @ validation`
   to the **current** `$SANDBOX/agent/.kb-hash`:
   - **Identical** (or row has `—`) → apply normally, as today.
   - **Different** → the KB changed since this mapping was validated. Do **not** apply
     silently — downgrade the hit to `⚠️ à reconfirmer` and re-raise to the engineer:
     ```
     ⚠️ KB changed since validation — term "poteau" was mapped to montant_porteur
        when the KB hash was a1b2c3d4 (import-report-012). The KB has since changed
        (current hash: f9e8d7c6). Confirm this mapping is still correct, or update it.
        a) Still correct — reconfirm (updates KB hash @ validation to current)
        b) No longer correct — provide the new mapping
     ```
     On (a): update the row's `KB hash @ validation` to the current hash, keep
     `✅ confirmed`, keep the original `Source import`. On (b): treat as a normal
     ❓/⚠️ resolution (Phase 3, "Resolving Ambiguities") and write the corrected mapping.
3. This check is a simple string comparison of two hash values already on disk — no
   extra KB read, no extra hashing pass. Negligible cost per import.

> ⚠️ **Never** infer a `.kb-hash` value or write to `.kb-hash` from within
> `chorus-import-project` — reading it is the only allowed operation. If `.kb-hash`
> is absent for a sandbox that clearly has a generated KB (e.g. `chorus-check` was
> run before), treat all rows as `—` (no comparison) rather than guessing a value.

#### Thesaurus scoping — Scope derivation and lookup

Each `* Aliases` row carries a `Scope` column. The Scope `C` for a given import is
resolved by this **three-step cascade** (first match wins):

```
1. --context <label> passed explicitly  → C = <label>
2. All sources live under $SANDBOX/$WORKSPACE/<X>/sources/  → C = <X>
   (reports → $SANDBOX/$WORKSPACE/<X>/reports/ instead of flat reports/)
3. Otherwise  → C = "global"  (default — preserves current behaviour)
```

Step 2 triggers **only** for the exact `<X>/sources/` structure — not arbitrary paths.
A `Batch` on `./some-folder/` not under `$WORKSPACE/<X>/sources/` always resolves to `global`.

**Mixed-context batch guard:** if sources span more than one `<X>/sources/` folder → stop:
```
⛔ Sources span multiple client contexts — Scope cannot be derived unambiguously.
   Run one import per client folder, or pass --context explicitly.
```

**Lookup order for term T, context C:**
```
1. (T, Scope = C)      → exact match, apply ✅
2. (T, Scope = global) → global fallback, apply ✅
3. Not found           → standard KB lookup (Phase 3)
```

Cross-context collisions (`client-A` vs. `client-B`) are **not** conflicts — dedup key
is `(term, Scope)`. Only same-Scope, different-mapping is a real `* Conflict`.

**Promote to global:** if the same mapping is independently validated identically under
≥ 2 contexts, propose (never auto-merge):
```
💡 "terme" validated identically under N contexts — promote to Scope=global? (y/n)
```

#### How the thesaurus is used in Phase 3

When building the alignment table (Phase 3), **check the thesaurus first** for every
term in the raw inventory. In practice this means: for steps 1–2 (Aliases), only the
le fichier entity `workspace/<C>/thesaurus.org` (WEB-027) — jamais le thésaurus
d'une autre entity. Toutes les sections vivent dans ce fichier unique :

```
Pour chaque terme T, C = Scope de cet import :
  0. workspace/<C>/thesaurus.org → Conflicts     : hit non résolu → bloquer, remontée ingénieur
  1. workspace/<C>/thesaurus.org → Aliases type_element
     : hit → vérifier KB hash; identique → appliquer ✅; différent → ⚠️ à reconfirmer
  2. workspace/<C>/thesaurus.org → Aliases slot values  : idem
  3. workspace/<C>/thesaurus.org → Out-of-scope  : hit → marquer ⬜, skip KB lookup
  4. workspace/<C>/thesaurus.org → Pending       : hit → re-lever ⚠️ (eca__ask_user)
  5. Absent → KB lookup standard (Phase 3)
```

> **Scope resolution order (steps 1–2):** an exact match on the current import's
> context `C` (its own shard) always wins over a `global` row for the same term —
> check the `<C>.org` shard first, fall back to `global.org` only if no `C`-scoped row
> exists there. See "Thesaurus scoping by context" above for the full rationale and
> the promotion-to-global mechanism.

> **Rule:** a thesaurus hit at step 1–3 is **final** — do not re-ask the engineer,
> do not consult the KB, do not propose alternatives. The engineer already decided.
> **Exception:** steps 1–2 are final only if the KB hash check passes (see above) —
> a stale mapping following a KB change is never applied silently.
>
> A thesaurus hit at step 4 (Pending) re-raises the question exactly once. If the
> engineer confirms → move the entry to Aliases (in the shard matching the current
> import's Scope `C`) and record ✅. If rejected → move to Out-of-scope (global.org)
> and record ⬜.
>
> A thesaurus hit at step 0 (Conflicts, unresolved) **blocks** — never apply either
> mapping automatically. Present both candidate mappings to the engineer for
> arbitration (see "Conflict resolution" below). An unresolved conflict for a term
> takes priority over any other thesaurus section for that same term.

#### Thesaurus initialisation

If neither `$SANDBOX/agent/thesaurus/` nor a legacy `$SANDBOX/agent/thesaurus.org`
exists yet, the sharded layout is created automatically at the end of the first import
that produces at least one ✅ or ⚠️ alignment (Phase 6 — see below): `global.org` is
always created first; a `<C>.org` shard is created only if that import's Scope `C` is
not `global`. No manual creation is required.


### 1.3 Previous alignment decisions (legacy fallback only)

> **⛔ WEB-027 — Skip entirely if `workspace/<C>/thesaurus.org` exists** (thésaurus 1.2b
> déjà chargé couvre tout — relire un import-report violerait WEB-027 en réappliquant
> des décisions Niveau 2 project-scoped).

**Legacy fallback** (pré-WEB-027, sans thésaurus) : si `$WORKSPACE/import-report-*.org`
existe, lire le **dernier rapport** — réappliquer les mappings non promus, re-lever les
termes pending, ignorer tout ce que 1.2b a déjà couvert.


## Phase 2 — Raw Inventory of Project Elements

> **⛔ WEB-029 — Phase 2 = inventaire brut UNIQUEMENT.**
> Ne jamais lire de fichier `<slug>.org`, `thesaurus.org` ou tout autre fichier KB
> pendant cette phase. L'inventaire ne fait que scanner le document source et lister
> les éléments bruts. Tout lookup KB est **strictement réservé à Phase 3** (lazy
> loading au premier besoin de l'agent concerné). Lire un KB ici reconstitue
> l'anti-pattern pré-WEB-029 (149K tokens dès Phase 2).

### Keepalive — block-based inventory (intra-phase token refresh)

**Before starting the inventory**, if the source is a filesystem file, call:
```bash
wc -l "<fichier-source-extrait>"
```
or, if working from inline/already-extracted text, read the directory tree `$SANDBOX/agent/`
to confirm the report directory.

Use the line count to estimate the number of elements (`N_est ≈ lines / 8`).

#### Block-based inventory protocol

> **Why blocks instead of a single silent pass:**
> Phases 2, 3 and 4 were previously pure thinking phases with no tool calls.
> On a large source (hundreds of elements, dense terminology), the combined thinking
> time could exceed the IDE token TTL before Phase 5 writes the first file.
> The fix is simple: **write a partial file every 50 elements** — each `eca__write_file`
> call resets the token TTL without splitting the document or losing context.
> The entire source is read in one pass; only the *writes* are batched.

```
BLOCK_SIZE = 50   # elements per partial write

block_num  = 1
inventory  = []   # accumulates ALL elements across all blocks

For each element E identified in the source (full sequential scan):
  Append E to inventory

  If len(inventory) % BLOCK_SIZE == 0:
    # Keepalive write — resets IDE token TTL
    Write eca__write_file:
      path    : $SANDBOX/agent/.import-inventory-<NNN>-blk<block_num>.org
      content : partial inventory (last BLOCK_SIZE elements)
    block_num += 1
    Print: "[Phase 2] Inventory block <block_num-1> written — <len(inventory)> elements so far"

# After full scan — write consolidated inventory (used by Phase 3)
Write eca__write_file:
  path    : $SANDBOX/agent/.import-inventory-<NNN>.org
  content : full inventory (all elements, all blocks)
Print: "[Phase 2] Complete inventory written — <len(inventory)> elements total"
```

**Format of each inventory entry (org):**

```org
** Element <seq>
   :PROPERTIES:
   :source_line: <original text from document>
   :END:
   - term_raw    :: <term as found>
   - values_raw  :: <associated raw values>
   - page_or_loc :: <page N / sheet S / block B>
```

> **Rule:** do not map at this stage — inventory first, align later.
> Preserve the original source text in the inventory for traceability.
> The `.import-inventory-<NNN>.org` file is the single source of truth for Phase 3.
> Partial block files (`.import-inventory-<NNN>-blk*.org`) are transient — kept until
> Phase 6 cleanup.

Scan the source data and produce a **raw inventory**:
an uninterpreted list of what the engineer has provided.

```
Source line / cell              Term identified      Associated values
────────────────────────────────────────────────────────────────────────
"Poteau porteur 45×145 C24"    "poteau porteur"     dim=45×145, classe=C24
"h libre 2,5m, entraxe 40cm"  "h libre"            2.5m / "entraxe"=40cm
"Laine de verre λ035, e=20cm" "laine de verre"     λ=0.035, e=200mm
"panneau OSB 12mm, CE"         "panneau OSB"        ep=12mm, CE=oui
```

> **Rule:** do not map at this stage — inventory first, align later.
> Preserve the original source text in the inventory for traceability.


## Phase 3 — Terminology Alignment

### KB Coverage Gauge (pre-alignment check)

**Before starting the term-by-term alignment**, compute a coverage indicator from the
raw inventory (Phase 2) against the KB reference (Phase 1.2):

```
📊 KB Coverage Gauge
   Distinct types detected in inventory : N  (e.g. 8)
   Types recognised in KB               : n / N  (e.g. 5 / 8 = 62%)
   Critical slots covered               : n / total  (e.g. 11 / 17 = 65%)
   KB Aliases section present           : yes / no
```

| Coverage | Level | Action |
|---|---|---|
| ≥ 80% types + ≥ 80% critical slots | 🟢 Good | Proceed directly |
| 60–79% on either axis | 🟡 Moderate | Proceed with a warning — flag `_couverture_kb: moderate` in the JSON `_import` block |
| < 60% on either axis | 🔴 Low | Emit the warning below and ask whether to continue |

**🔴 Low-coverage warning (display before alignment):**

```
⚠️  KB Coverage Gauge — LOW COVERAGE DETECTED
    Types recognised   : n/N (XX%)
    Critical slots     : n/N (XX%)

    The KB may lack aliases for the project's terminology.
    Risk: many terms will receive ❓ (ambiguous) or ⬜ (out-of-scope),
    producing an incomplete or unusable JSON.

    Recommended actions (choose one or both):
      1. Run `chorus-feed --harvest-aliases <previous-import-report.org>`
         if a validated import report exists for this sandbox.
      2. Enrich the KB: add aliases to `$SANDBOX/agent/chorus/<slug>.org`
         under `** Aliases` before re-running this import.

    Continue anyway? [yes / abort]
```

If the engineer confirms `yes`, proceed — but set `"_couverture_kb": "low"` in the
`_import` block and list the unrecognised types under a dedicated section
`* KB coverage gap` in the import report (Phase 6).

> **Batch mode:** compute the gauge once per file, using the shared lazy KB cache
> (agents already loaded by Phase 3 for previous files, plus on-demand loads for new agents).
> Files with 🔴 coverage are flagged in the batch summary report (Phase 6-BATCH)
> with a `⚠️ low KB coverage` marker in the results table — the batch is not aborted.


### Alignment table

#### Block-based alignment protocol (intra-phase keepalive)

> **Why blocks:** the alignment phase processes every distinct term from the inventory
> against the KB reference. On a large project this can take 10–20 minutes of thinking
> with no tool call — enough to expire the IDE token.
> The fix: **read the consolidated inventory file written by Phase 2** (one tool call =
> keepalive), then **write a partial alignment file every 10 terms** — each write resets
> the token TTL. KB files are loaded lazily (WEB-029 — see Phase 1.2): only the *writes*
> and the on-demand KB reads are split; alignment reasoning always sees the complete picture.

```
# Step 0 — reload inventory from disk (keepalive + single source of truth)
Read eca__read_file:
  path: $SANDBOX/agent/.import-inventory-<NNN>.org
terms = all distinct terms extracted from the inventory
Print: "[Phase 3] Inventory loaded — <len(terms)> distinct terms to align"

BLOCK_SIZE = 40   # terms per partial write (lazy loading = light context → large blocks safe)

loaded_agents = {}   # slug → terminology reference (lazy — loaded on demand)
block_num  = 1
alignment  = []   # accumulates ALL aligned terms across all blocks

For each term T in terms (full sequential alignment):

  # Lazy KB loading (WEB-029): load agent KB only when first needed
  slug = infer_agent_slug(T)
  # slug inference: structural tags (Phase 1.2b) > thesaurus hit > index.org type hints
  # slug = None means the term maps to global slots only (no per-agent <slug>.org needed)
  If slug is not None and slug not in loaded_agents:
    Read eca__read_file: path = $SANDBOX/agent/chorus/<slug>.org
    Read eca__directory_tree: path = $SANDBOX/rules/<slug>/
    Read eca__read_file: path = first .yml in $SANDBOX/rules/<slug>/   # type_element guard
    loaded_agents[slug] = extracted terminology reference
    Print: "[Phase 3] KB loaded for agent '<slug>' — <len(loaded_agents)> agent(s) loaded so far"

  # Align using the now-available KB reference for this agent
  Align T against loaded_agents.get(slug) or index.org global slots → produce alignment row
  Append row to alignment

  If len(alignment) % BLOCK_SIZE == 0:
    # Keepalive write — resets IDE token TTL
    Write eca__write_file:
      path    : $SANDBOX/agent/.import-alignment-<NNN>-blk<block_num>.org
      content : partial alignment table (last BLOCK_SIZE rows)
    block_num += 1
    Print: "[Phase 3] Alignment block <block_num-1> written — <len(alignment)> terms done"

# After all terms — write consolidated alignment (used by Phase 4 and Phase 5)
Write eca__write_file:
  path    : $SANDBOX/agent/.import-alignment-<NNN>.org
  content : full alignment table (all terms)
Print: "[Phase 3] Complete alignment written — <len(alignment)> terms total"
```

> **Context integrity guarantee (WEB-029):** KB files are loaded lazily — only the
> agents actually referenced by inventory terms are ever read, and each is loaded
> exactly once. The full inventory and all loaded KB references remain in context
> throughout Phase 3. Only the *output writes* are batched; alignment reasoning
> always sees the complete picture. No information is lost, no cross-element context
> is broken. On a 6-agent sandbox with 2–3 agents active, this reduces Phase 1
> context load from ~150 KB to ~20 KB (`index.org` only), and defers the remaining
> ~130 KB to Phase 3 where it is loaded incrementally alongside alignment writes.

> **Partial block files** (`.import-alignment-<NNN>-blk*.org`) are transient.
> The **consolidated file** (`.import-alignment-<NNN>.org`) is the single source of
> truth for Phases 4 and 5. Both are cleaned up at the end of Phase 6.

---

This is the core phase. For each term from the raw inventory, cross-reference against
the KB reference (Phase 1.2) and produce an alignment table:

```
Project term                  KB slot / type_element    KB value         Confidence
──────────────────────────────────────────────────────────────────────────────────
"poteau porteur"              type_element              montant_porteur  ✅ certain
"45×145"                      section_bois              "45x145"         ✅ certain
"C24"                         classe_bois               "C24"            ✅ certain
"h libre 2,5m"                hauteur_libre_m           2.5              ✅ certain
"entraxe 40cm"                entraxe_mm                400              ✅ certain (×10)
"laine de verre λ035"         type_element              isolant_laine    ✅ certain
                              classe_conductivite       "035"            ✅ certain
"panneau OSB 12mm"            type_element              panneau_osb      ✅ certain
                              osb_epaisseur_mm          12               ✅ certain
"poteau intérieur cloison"    type_element              montant_non_porteur ⚠️ likely
"panneau contreventement"     type_element              panneau_osb ?    ❓ ambiguous
"traitement cl. 2"            traitement_applique ?     ?                ❓ to clarify
```

### Confidence Levels

| Symbol | Meaning | Action |
|---|---|---|
| ✅ certain | Direct or near-direct match with the KB | Map without asking |
| ⚠️ likely | Logical match but term is not exact | Propose + ask for confirmation |
| ❓ ambiguous | Multiple possible mappings or unknown KB term | Block + ask for clarification |
| ⛔ gap | Mandatory slot absent from the source document | Report — do not invent |
| ⬜ out-of-scope | `type_element` absent from this sandbox's KB | Exclude from JSON — flag `_hors_perimetre: 1` + report |

> **Out-of-scope rule:** an element receives `⬜` if its `type_element` is not recognised
> by **any** `Catalogue des Frames` in the target sandbox. This is non-blocking — the import
> continues. The element is excluded from the output JSON and listed in the
> `Out-of-scope elements` section of the import report.
>
> **Architectural consequence:** a multi-domain project (e.g. structural + thermal) must
> be imported **once per target sandbox** — each import retains only the types that sandbox
> knows. `chorus-import-project` is the partitioning tool; `run.pl` only sees the elements
> that concern it.
>
> ```bash
> # Mixed project → two targeted imports
> chorus-import-project sandbox-structurel ./dossier-project/ --batch
>     # → JSON containing only montant_porteur, lisse_basse, ...
>     # → elements isolant_laine, membrane_etanche → ⬜ excluded + report
>
> chorus-import-project sandbox-thermique ./dossier-project/ --batch
>     # → JSON containing only isolant_laine, membrane_etanche, ...
>     # → elements montant_porteur, lisse_basse → ⬜ excluded + report
> ```

### Figure identifiers as matching candidates (hybrid mode)

When the source document was extracted in hybrid mode, each `[FIGURE N]` block ends with
an `IDENTIFIERS: [...]` line listing the labels and codes visible in the figure (callout
tags, part numbers, element IDs).

**These identifiers are first-class matching candidates** for Phase 3:

1. **Cross-reference with KB aliases** — if `chorus-feed` has populated an
   `** Aliases from figures` table in the KB `Ontologie` (built from the XREF INDEX of
   the normative corpus), check whether the identifier appears there. A direct hit gives
   confidence ✅ and maps directly to the corresponding `type_element` or slot value.

2. **Cross-reference with figure description body** — if the identifier is not in the KB
   aliases, search the description text of the same `[FIGURE N]` block for a co-occurring
   corpus term. Example: `IDENTIFIERS: ["P1"]` + description mentions *"Poteau porteur
   45×145 C24"* → candidate `type_element: montant_porteur` at confidence ⚠️.

3. **Cross-reference with surrounding text blocks** — search the raw inventory (Phase 2)
   for text blocks on the same page that mention the identifier alongside a known slot
   value. Example: `P1` appears in a table row *"P1 — 45×145 — C24 — h=2.5m"* on the
   same page → aggregate all slot values from that row under the element `id: P1`.

4. **Preserve identifier as `id`** — when an element is successfully mapped, use the
   figure identifier as the element `id` in the output JSON (preferred over a generated
   ID), since it matches the document's own reference system and enables
   document ↔ JSON traceability.

> **Rule:** figure identifiers that could not be matched to any KB term after steps 1–3
> are listed in the import report under a dedicated section
> `* Unmatched figure identifiers` — they are candidates for a future `chorus-feed --enrich`
> run to extend the KB aliases.

### Unit Transformations

Explicitly document every conversion:

| Source pattern | Transformation | KB Slot |
|---|---|---|
| `2,5m` / `2.5m` / `250cm` | → `2.5` | `hauteur_libre_m` |
| `40cm` / `400mm` / `0,4m` | → `400` | `entraxe_mm` |
| `20cm` / `200mm` | → `200` | `epaisseur_mm` |
| `λ=0,035` / `λ035` / `laine 035` | → `"035"` | `classe_conductivite` |
| `45/145` / `45×145` / `45x145` | → `"45x145"` | `section_bois` |
| `C 24` / `classe C24` / `C24 EN338` | → `"C24"` | `classe_bois` |

### Resolving Ambiguities

For each ❓ term, present the following to the engineer:
```
❓ "panneau contreventement" — multiple interpretations possible:
   1. panneau_osb     (structural OSB panel §3.1)
   2. panneau_fibragglo (bracing panel §3.2)
   Which type matches your document?
```

**Do not proceed until blocking ❓ items are resolved** (ambiguous `type_element` slots).
⚠️ items may be provisionally accepted with a `_a_confirmer: 1` flag.

### _a_confirmer resolution — three tiers (interactive terminal + autonomous fallback)

When a `⚠️` item is encountered — either during Phase 3 alignment or during a
re-import that finds pending thesaurus entries — apply the following tier logic:

| Tier | Criterion | Action |
|---|---|---|
| **Obvious** | Derivable from external standards without domain knowledge: platform constraints (JDK API removal, RFC defaults), OID registry, mathematical definitions | Call `eca__ask_user` with proposed resolution as default option `[auto]` — countdown 30s — auto-confirmed if no response |
| **Ambiguous** | Requires domain knowledge or has competing valid interpretations (EC GFp vs GF2n without platform context, curve family not determinable from CBOM) | Call `eca__ask_user`, no auto — **block until engineer responds** |
| **Unresolvable** | Structurally absent from source (exposant RSA absent du schéma CycloneDX, primitive=other non identifiable) | Mark `❌ Structurellement absent` — never auto-resolve — document gap |

#### Obvious tier — eca__ask_user with [auto] countdown

```javascript
eca__ask_user({
  question: "RSA-2048 → exposant_public_valeur : confirmer 65537 ?",
  options: [
    {
      label:       "Confirmer 65537",
      description: "[auto] RFC 8017 §A.1.1 — Java KeyPairGenerator default, aucune surcharge détectée dans le code source"
    },
    {
      label:       "Valeur différente",
      description: "indiquer l'exposant réel (HSM legacy, configuration non standard)"
    },
    {
      label:       "Marquer _a_confirmer",
      description: "laisser pour validation manuelle ultérieure"
    }
  ],
  allowFreeform: true
})
```

The `[auto]` prefix in `description` triggers a 30s countdown in the webapp terminal
(see `chorus-web.js § lvlTermAskUser`). The engineer can:
- **Click "Confirmer"** — validates immediately, countdown cancelled
- **Click "Valeur différente" + type** — overrides with exact value
- **Do nothing** — countdown expires → auto-confirms the `[auto]` option
- **Running as sub-agent** — `eca__ask_user` returns `""` → apply Obvious-tier default silently

#### Ambiguous tier — interactive, no countdown

```javascript
eca__ask_user({
  question: "EC → type_element : GFp ou GF2n ?",
  options: [
    { label: "GFp (NIST P-256/P-384/P-521)", description: "courbes NIST standard" },
    { label: "GF2n (courbes binaires)",        description: "binaire — rare, Java 8+ a retiré le support JSSE" },
    { label: "Indéterminable",                 description: "marquer _a_confirmer permanent" }
  ],
  allowFreeform: false
})
// No [auto] marker — blocks until engineer responds.
// If eca__ask_user returns "" (sub-agent) → keep _a_confirmer: 1, do NOT auto-resolve.
```

#### ⛔ Rules for all tiers

- **Never auto-resolve an Ambiguous item** — even if the reasoning seems compelling.
  What happened before this rule existed: EC→GFp was auto-confirmed based on JDK-8235039
  reasoning without asking the engineer — technically correct in that case, but the engineer
  had no opportunity to contradict if the context were atypical (embedded JDK, custom curve).
- **Never call `eca__ask_user` in a loop** — one call per `_a_confirmer` item.
- **`"" return` in sub-agent**: Obvious tier → apply default silently. Ambiguous → keep
  `_a_confirmer: 1`, never promote to `✅`.
- **⛔ KB gap ≠ `_a_confirmer`** — if a `type_element` is recognised (the algorithm
  is known) but the KB simply does not cover it yet (e.g. Argon2id, ANSSI-PA-079
  angle mort), classify as **`gap` only** — never as `_a_confirmer`. A `_a_confirmer`
  means "the term has competing valid KB interpretations". A gap means "the KB has no
  coverage for this algorithm at all — no alignment decision is possible until the KB
  is extended". Mixing the two produces non-deterministic counts across re-imports.
  Correct classification:
  - Term known + KB covers it + interpretation uncertain → `_a_confirmer`
  - Term known + KB does NOT cover it → `gap` (document in `_import.gaps`, not in `_a_confirmer`)
  - Term unknown (not identifiable) → `❓` or `hors_perimetre`

### Immediate thesaurus update after each resolution

**After each engineer decision** (❓ resolved or ⚠️ confirmed/rejected), write the
result **immediately** — do not wait for Phase 6 — into the shard matching the current
import's Scope `C`:
- Toutes les écritures (Aliases, Pending, Out-of-scope, Conflicts) vont dans
  `$SANDBOX/workspace/<C>/thesaurus.org` (WEB-027 — entity-scoped, jamais cross-entity).
- Créer le fichier si absent (voir "Thesaurus creation" ci-dessous).
- Ne jamais écrire dans `agent/thesaurus/` pour de nouveaux imports.

This ensures the thesaurus is always up to date, even if the session is interrupted
before Phase 6 completes.

#### Mapping resolution → thesaurus section

| Engineer decision | Thesaurus action |
|---|---|
| ❓ resolved → ✅ (type_element chosen) | Append to `* Aliases — type_element` dans `workspace/<C>/thesaurus.org` — sauf si `(term, Scope=C)` existe déjà avec un mapping différent → ajouter à `* Conflicts` dans le même fichier (voir Deduplication rule) |
| ❓ resolved → ✅ (slot value chosen) | Append to `* Aliases — slot values` in the shard for the current Scope — **same conflict check as above** |
| ⚠️ confirmed → ✅ | Déplacer de `* Pending` vers `* Aliases` — dans `workspace/<C>/thesaurus.org` — même conflict check |
| ⚠️ rejected → ⬜ | Déplacer de `* Pending` vers `* Out-of-scope` — dans `workspace/<C>/thesaurus.org` |
| ❓ unresolvable → ⬜ | Ajouter à `* Out-of-scope` dans `workspace/<C>/thesaurus.org` |
| New ⚠️ (first time seen) | Ajouter à `* Pending` dans `workspace/<C>/thesaurus.org` |
| Term already in `* Conflicts` at the current Scope (unresolved), re-encountered | Do not touch any `* Aliases` shard — re-raise for arbitration (see "Conflict resolution") |

#### Write format per section

**Alias confirmed (type_element):**
```org
| <project term> | <KB type_element> | ✅ confirmed | import-report-<NNN> | <kb_hash8 or —> | <Scope: global or context-label> |
```

**Alias confirmed (slot value):**
```org
| <project term> | <KB slot> | <KB value> | ✅ confirmed | import-report-<NNN> | <kb_hash8 or —> | <Scope: global or context-label> |
```

**New pending entry:**
```org
| <project term> | type_element: <proposed> ? | ⚠️ _a_confirmer | import-report-<NNN> | <Scope: global or context-label> |
```

> The `Scope` column (5th) records the import's Scope `C` at the time the ⚠️ was raised.
> It is used by any future confirmation tool (chorus-web, chorus-import-project, etc.)
> to determine which shard the confirmed alias should be written into — without this,
> a webapp confirmation cannot know whether the term belongs in `global.org` or in a
> client shard. Rows written by older versions of this skill that lack the 5th column
> must be treated as `Scope = global` (backward-compatible default).
> For `⚠️ confirmed → ✅`, the target shard is always derived from this column, not from
> the current import's Scope — the engineer who confirms may be running a different import
> than the one that originally raised the ⚠️.

**Out-of-scope:**
```org
| <project term> | <reason> | <recommended sandbox or "unknown"> | import-report-<NNN> |
```

**Conflict (mapping mismatch at the same Scope — never a duplicate write to `* Aliases`):**
```org
| <project term> | <Scope: global or context-label> | <existing mapping> (<existing source import>) | <new mapping> (<new source import>) | <first seen import> | <conflict raised in import> | ⚠️ to arbitrate |
```

#### Thesaurus creation (first import)

Si `$SANDBOX/workspace/<C>/thesaurus.org` n'existe pas encore → le créer avec
les 4 sections vides (`* Aliases — type_element`, `* Aliases — slot values`,
`* Pending`, `* Out-of-scope terms`, `* Conflicts`). Ne jamais créer de fichier
sous `agent/thesaurus/` pour un nouveau sandbox.

> ⚠️ **Deduplication rule:** before appending any entry, check whether the pair
> `(project term, Scope)` already exists in the target shard's `* Aliases —
> type_element` or `* Aliases — slot values` — where `Scope` is the current import's
> context (resolved per "Scope derivation" above). In practice this means checking
> only the shard(s) already loaded for this import (`<C>.org` and/or `global.org` —
> never a shard for a different client, since a different-Scope row cannot exist in
> a shard that was never read for this import).
>
> - **If a row with the same `(term, Scope)` exists and its mapping is identical** to
>   the new one → **update** the existing row (confidence, source import) in place,
>   in its own shard, rather than inserting a duplicate. This is the only case where
>   a silent update is correct.
> - **If a row with the same `(term, Scope)` exists and its mapping differs** from the
>   new one → this is a **mapping conflict**, not a duplicate. **Never overwrite the
>   existing row.** Instead:
>   1. Leave the existing `Aliases` row untouched (in its shard).
>   2. Append a new row to `* Conflicts` **in `global.org`** with both mappings, their
>      respective source imports, the shared Scope, and status `⚠️ to arbitrate`.
>   3. Do **not** apply either mapping automatically on this or future imports at this
>      Scope until the conflict is arbitrated (see Phase 3 lookup step 0 and "Conflict
>      resolution" below).
> - **If the term exists only at a *different* Scope** (e.g. new row would go in
>   `client-beta.org`, but an existing row for the same term lives in
>   `client-alpha.org`, or in `global.org`) → **this is not a conflict.** Simply append
>   the new row as an independent entry in its own shard — both stay permanently
>   active side by side, in different files (see "Thesaurus scoping by context"). Note
>   that under sharding, this case is even less likely to be noticed accidentally,
>   since the two rows never even appear in the same file.
>
> This mirrors the existing **Id conflict handling** (multi-source import, § 1 above):
> conflicting evidence **at the same scope** is never silently merged — it is surfaced
> as an explicit, engineer-arbitrated conflict record. Evidence at *different* scopes
> is not conflicting evidence at all — it is deliberately parallel, valid knowledge,
> now additionally isolated by file boundary.

#### Conflict resolution (engineer arbitration)

When a term in `* Conflicts` is encountered again in a new import (or when the engineer
explicitly revisits the thesaurus), present it for arbitration:

```
⚠️ CONFLICT — term "poteau" has two validated mappings at the same Scope (global):
   1. montant_porteur      (validated in import-report-012)
   2. montant_non_porteur  (validated in import-report-340)
   This may be legitimate homonymy (same word, different meaning depending on context)
   rather than an error. How should this import's occurrence of "poteau" be resolved?
   a) Apply mapping 1 (montant_porteur) — this occurrence only
   b) Apply mapping 2 (montant_non_porteur) — this occurrence only
   c) One of the two mappings is wrong — correct it permanently (specify which)
   d) Both are legitimate but depend on context — rescope them: assign mapping 1 to a
      new context label (e.g. "client-x") and mapping 2 to another (e.g. "client-y").
      Future imports must pass --context <label> to resolve "poteau" without asking
      again; imports without --context keep hitting this conflict at global Scope
      unless one of the two rescoped rows is also duplicated as `global`.
```

- **(a) or (b)** — this occurrence only: apply the chosen mapping to the current import's
  element, but **leave the `* Conflicts` entry open** (status stays `⚠️ to arbitrate`) —
  the ambiguity remains for future imports.
- **(c)** — permanent correction: update the `* Aliases` row with the corrected mapping,
  remove the row from `* Conflicts` (status `✅ resolved`), and record which of the two
  prior imports is now considered to have been mis-mapped.
- **(d)** — rescope: split the single `global`-Scope conflict into two distinct
  `* Aliases` rows, each with its own context label as `Scope` (per "Thesaurus scoping
  by context" above). Remove the row from `* Conflicts` (status `✅ resolved — rescoped`).
  Going forward, only imports run without `--context` (or with a third, unrelated
  context) would ever re-trigger ambiguity for this term — and only if a `global` row
  is also added later for it.
- Never resolve a `* Conflicts` entry by silently picking one side without engineer input.

### --align-review mode — stop here for human validation

If `--align-review` was specified, **stop after Phase 3** and produce an alignment review
file instead of proceeding to Phase 4 / JSON generation:

1. **Write** `$WORKSPACE/align-review-<NNN>.org` (`$WORKSPACE` =
   `$SANDBOX/workspace/`, created if absent):

```org
#+TITLE: Alignment review — <source> — <date>
#+STATUS: pending-validation

* KB Coverage Gauge
  Types recognised   : n/N (XX%)
  Critical slots     : n/N (XX%)
  Coverage level     : 🟢 good / 🟡 moderate / 🔴 low

* Full alignment table
  | Project term | KB slot / type_element | KB value | Confidence | Notes |
  |---|---|---|---|---|
  | ...          | ...                    | ...      | ✅/⚠️/❓   | ...   |

* Items requiring engineer decision
  ** Ambiguous (❓) — must be resolved before JSON generation
     | Term | Options | Decision |
     |---|---|---|

  ** Likely (⚠️) — provisionally accepted, confirm or override
     | Term | Proposed mapping | Confirm? |
     |---|---|---|

  ** Out-of-scope (⬜) — will be excluded from JSON
     | Term | Reason | Correct sandbox? |
     |---|---|---|

* Gaps identified at this stage
  | Element id | Missing slot | Mandatory? |
  |---|---|---|

* How to proceed
  1. Review and annotate this file (correct ❓ decisions, confirm/reject ⚠️ items)
  2. Rerun WITHOUT --align-review to produce the JSON:
     chorus-import-project <sandbox> <source>
     The skill will reload this align-review file (Phase 1.3) and apply your decisions.
```

2. **Display** a summary to the engineer:
```
✅ Alignment review produced: $WORKSPACE/align-review-NNN.org
   ✅ certain  : N terms
   ⚠️ likely   : N terms (to confirm)
   ❓ ambiguous: N terms (must be resolved)
   ⬜ out-of-scope: N terms
   ⛔ gaps     : N mandatory slots absent

   Next step: review the file, then rerun without --align-review to generate the JSON.
```

3. **Do not** proceed to Phase 4, Phase 5, or Phase 6.
   The JSON is produced only on the subsequent run (without `--align-review`),
   after the engineer has validated the alignment file.


## Phase 3.5 — Inter-Element Relationship Detection

> **Prerequisite:** Phase 3 complete — `.import-alignment-<NNN>.org` lists all elements
> with their confirmed `id` and `type_element`.
>
> **Skip condition:** if no KB org slot has a `Frame ref` or `→` annotation (see
> `chorus-engine-infra.md §3`), skip Phase 3.5 entirely and go directly to Phase 4.
> Print: `[Phase 3.5] No inter-frame relationships defined in KB — skipped.`

This phase detects explicit cross-element relationships in the project document and
generates the `*_ref` fields that Feed.pm's inter-frame mechanism requires.

---

### Step 3.5-1 — Build the relationship blueprint from KB

Scan the KB org slot dictionaries (loaded in Phase 1) for slots whose `type` column
contains `Frame ref` or whose description contains `→ <target_type>`.  Build:

```
blueprint = { source_type → { slot_name → target_type } }
# Derived ref_field name: slot_name + "_ref"
# e.g.:
#   buttressing_wall → { supports → external_wall }     ← ref_field: supports_ref
#   external_wall    → { building → residential_building|non_residential_building }
#                                                        ← ref_field: building_ref
```

If the blueprint is empty after scanning, skip Phase 3.5.

---

### Step 3.5-2 — Scan the project document for relationship signals

For each `(source_type, slot_name, target_type)` entry in the blueprint, scan
the source document for signals that a source element is linked to a target element.

**Recognised signal patterns:**

| Signal type | Example | Confidence |
|---|---|---|
| Table column containing IDs of target type | "Building" column in a wall schedule | ✅ |
| Explicit language of containment | "Wall EW-01, located in Building B1" | ✅ |
| Explicit language of structural link | "BW-01 buttresses / supports EW-01" | ✅ |
| BIM-style attributes | "Host: RES-01", "Level: FL-01" | ✅ |
| Section/sub-section hierarchy | H2 = building, H3 = walls within it | ⚠️ |
| Spatial co-location (same figure, same row) | EW-01 and B1 on same drawing sheet | ⚠️ |
| No signal found | — | ❓ unresolved |

---

### Step 3.5-3 — Resolve target labels to element IDs

For each found relationship signal, resolve the target label to a concrete `id`
already present in `.import-alignment-<NNN>.org`:

1. **Direct match** — target label equals an `id` in the alignment → ✅
2. **Alias match** — target label matches a `_labels` alias or project term → ✅
3. **Type-filtered guess** — only one element of the expected target type → ⚠️
4. **Unresolved** — no match or multiple ambiguous matches → ❓

⛔ **Never generate a `*_ref` pointing to an ID not in the current import.**
⛔ **Never invent a relationship** absent from the document and not in the KB blueprint.

---

### Step 3.5-4 — Record findings in alignment file

Append an `* Inter-Element Relationships` section to `.import-alignment-<NNN>.org`:

```org
* Inter-Element Relationships (Phase 3.5)
  Blueprint: KB org → annotations (chorus-engine-infra.md §3)

  | element_id | slot_name | ref_field    | target_id | confidence | source_signal               |
  |------------|-----------|--------------|-----------|------------|-----------------------------|
  | BW-01      | supports  | supports_ref | EW-01     | ✅         | "BW-01 buttresses EW-01"    |
  | EW-01      | building  | building_ref | RES-01    | ✅         | Wall schedule, Building col |
  | EW-02      | building  | building_ref | RES-01    | ⚠️         | Same drawing as EW-01       |
  | IW-01      | building  | building_ref | (none)    | ❓         | No signal found in document |
```

**Confidence rules for Phase 4/5:**
- ✅ → include `*_ref` field in JSON output (Phase 5)
- ⚠️ → include with `_note` warning; flag for engineer review in import report
- ❓ → omit from JSON; report as optional gap in Phase 4

---

### Step 3.5 Print summary

```
[Phase 3.5] Inter-element relationships detected
  Blueprint entries : N (from KB org → annotations)
  ✅ resolved       : N  (will generate *_ref fields)
  ⚠️ inferred       : N  (included with warning)
  ❓ unresolved     : N  (optional — link absent from document)
```

---

### Impact on Phase 5 (JSON generation)

Phase 5 must include `*_ref` fields from the Phase 3.5 section of
`.import-alignment-<NNN>.org`:

- For each element with a ✅ or ⚠️ relationship entry → add `"<ref_field>": "<target_id>"`
- ⚠️ entries get an additional `"_note_<ref_field>": "inferred — verify"` annotation
- ❓ entries → omit silently (optional link)

```json
{
  "id": "EW-01",
  "type_element": "external_wall",
  "building_ref": "RES-01",
  "thickness_mm": 290,
  ...
}
```

> Note: `*_ref` fields are OPTIONAL in `%SLOTS_REQUIS` — their absence never causes
> Feed.pm to reject an element.  Rules use the Option A fallback pattern (direct slot
> when no link is present).  See `chorus-engine-yaml.md § Navigating a slot→Frame link`.


## Phase 4 — Identify Gaps

For each element, cross-reference the present slots against the KB `Catalogue des Frames`:

```
Type            Mandatory slot      Present?    Source
──────────────────────────────────────────────────────────
montant_porteur classe_bois         ✅          "C24"
montant_porteur humidite_pct        ⛔ ABSENT   not mentioned
montant_porteur hauteur_libre_m     ✅          "h=2.5m"
```

### Gap Handling

| Gap type | Action |
|---|---|
| Mandatory slot absent | Ask the engineer — do not assume |
| Optional slot absent | Omit from JSON — the pipeline handles it |
| `Derived:` slot absent (annotated `_NEEDED` in KB org) | **Not a gap** — omit from JSON silently; Feed.pm will compute it at runtime via `_NEEDED` coderef. Do NOT ask the engineer. |
| Out-of-domain value (e.g. `classe_bois: "C12"`) | Report — let the engineer correct it |
| Entire element unmappable | Include with `_incomplet: 1` — will be cleanly rejected by Feed |
| `Frame ref` slot (❓ in Phase 3.5) | Report as optional gap — `*_ref` absent is acceptable; rules use direct-slot fallback |


## Phase 5 — Produce the JSON

### Pre-flight — reload consolidated files (keepalive + integrity check)

Before generating the JSON, **read the two consolidated files** produced by Phases 2 and 3.
Each read is a tool call that resets the IDE token TTL and guarantees the JSON is built
from the canonical on-disk state rather than from context that may have drifted.

```
# Reload consolidated inventory (Phase 2 output)
Read eca__read_file:
  path: $SANDBOX/agent/.import-inventory-<NNN>.org
→ confirms element list, ids, source lines

# Reload consolidated alignment (Phase 3 output)
Read eca__read_file:
  path: $SANDBOX/agent/.import-alignment-<NNN>.org
→ confirms term → slot/value mappings, confidence levels, ❓/⚠️/⬜ flags

Print: "[Phase 5] Sources reloaded — <N_elements> elements / <N_terms> aligned terms"
```

> **Why reloading matters:** on a large project the agent may have spent 15–20 minutes
> thinking across Phases 2–4. Reloading from disk ensures the JSON is derived from the
> files that will persist in `$SANDBOX/agent/` — not from an in-context summary that
> could have silently compressed some detail.

### Output JSON location

The produced JSON (`project-import-<NNN>.json` in Single/Merge mode, or one such file
per source in Batch mode — see below) is written to:

```
1. --out <filename> passed explicitly       → write exactly there (path as given by
   the engineer — absolute or relative to the invocation's working directory).
   Explicit override, highest priority, unchanged behaviour.
   ⚠️ Not applicable in Batch mode (one JSON per source file — a single --out
   filename has no well-defined target; ignored with a warning if combined with
   --batch).

2. Otherwise, if this import's Scope C != "global" (i.e. it was resolved from
   $WORKSPACE/<C>/sources/ or from --context <C> — see "Scope derivation", Phase 1.2b)
   → $SANDBOX/$WORKSPACE/<C>/project-import-<NNN>.json
   (same <client>/ folder as this import's sources/ and reports/ — keeps everything
   belonging to one client together, per the workspace/<client>/ conformance rule:
   AGENTS.md § "$WORKSPACE/<client>/ convention" only requires sources/ and reports/
   to exist — a project JSON sitting alongside them at the <client>/ root is exactly
   the kind of "extra content" that convention explicitly tolerates)

3. Otherwise (Scope = global — no client folder involved)
   → $SANDBOX/agent/project-import-<NNN>.json  (unchanged legacy default)
```

`<NNN>` increments independently per Scope/location — a fresh `<client>/` folder starts
its own `project-import-001.json`, it does not continue the numbering of `global`'s or
another client's sequence.

> ⚠️ This only concerns the **produced project JSON**. It does not change where any
> other artefact is written: `import-report-<NNN>.org` / `align-review-<NNN>.org`
> already follow their own Scope-aware rule (`$WORKSPACE/reports/` or
> `$WORKSPACE/<C>/reports/` — see Phase 6), and thesaurus shards follow their own rule
> (`agent/thesaurus/global.org` or `agent/thesaurus/<C>.org` — see Phase 1.2b). All
> three now consistently key off the same Scope `C`.

### Construction de `_labels` (avant écriture du JSON)

À partir de la table d'alignement rechargée (`.import-alignment-<NNN>.org`),
construire pour chaque élément l'objet `_labels` selon l'algorithme suivant :

```
For each element E in the alignment table:
  labels = {}

  # 1. type_element : inclure si terme project ≠ valeur KB
  if alignment[E].project_term_type != alignment[E].kb_type_element:
    labels["type_element"] = alignment[E].project_term_type

  # 2. slots : inclure si terme source ≠ nom de slot KB
  for each (project_term, slot_kb, kb_value) in alignment[E].slots:
    if project_term != slot_kb:        # le document n'utilisait pas le nom exact du slot
      labels[slot_kb] = project_term

  # 3. N'inclure _labels dans le JSON que s'il est non vide
  if labels:
    E["_labels"] = labels
```

> **Règle de comparaison :** normaliser les deux termes (minuscules, underscores → espaces)
> avant comparaison. Si après normalisation ils sont identiques, ne pas inclure dans `_labels`.
> Exemple : `"section_bois"` (document) vs `"section_bois"` (KB) → identiques → pas de `_labels`.
>
> **Thésaurus hits à ✅ :** tous les slots résolus via le thésaurus ont par définition
> subi une substitution — inclure systématiquement dans `_labels` sauf si les termes
> normalisés sont identiques.

### Post-JSON — cleanup of transient partial files

After writing the final JSON (and before Phase 6), delete all transient block files:

```bash
rm -f $SANDBOX/agent/.import-inventory-<NNN>-blk*.org
rm -f $SANDBOX/agent/.import-alignment-<NNN>-blk*.org
```

The two consolidated files (`.import-inventory-<NNN>.org` and `.import-alignment-<NNN>.org`)
are **kept** — they serve as the audit trail for this import and are referenced by Phase 6
(import report) and by future `chorus-import-project` runs (Phase 1.3 secondary memory).

---

> **⚠️ Language rule — JSON annotation values:** technical structural keys (`"project"`,
> `"elements"`, `"id"`, `"type_element"`, `"_a_confirmer"`, `"_conflit"`, `"_incomplet"`,
> `"_hors_perimetre"`, `"_labels"`, etc.) are invariant; but all **annotation string values**
> (descriptions, notes, conflict messages, out-of-scope reasons) must be written in the
> **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

### Single / Merge Mode — one JSON

Once all ❓ items are resolved and critical gaps are filled:

```json
{
  "project": "<nom-project-ingenieur>",
  "description": "Import from <source> — <date> — <N> elements",
  "_import": {
    "source": "<nom-fichier-ou-inline>",
    "sources": ["<f1>", "<f2>"],
    "mode": "unitaire|fusion",
    "date": "<date>",
    "gaps": ["<id>: <slot manquant>", "..."],
    "a_confirmer": ["<id>: <terme ambigu>", "..."],
    "conflits": ["<id>: present in f1 and f2 — duplicate renamed", "..."]
  },
  "elements": [
    {
      "id": "<id-issu-du-document>",
      "type_element": "<type_kb>",
      "<slot_1>": "<valeur>",
      "_labels": {
        "type_element": "<terme project d'origine, si différent de type_kb>",
        "<slot_1>": "<terme project d'origine, si différent du nom de slot KB>"
      },
      "_source_fichier": "<nom-fichier>",
      "_a_confirmer": 1,
      "_conflit": 1,
      "_conflit_source": ["<f1>", "<f2>"]
    }
  ]
}
```

> **`_labels` — règle de population :**
> `_labels` est un objet plat `{ slot_kb → terme_projet_original }`.
> Il est construit lors de la Phase 5 à partir de la table d'alignement (Phase 3).
> **Seuls** les slots pour lesquels le terme project diffère du nom de slot KB sont inclus.
> Un slot dont le nom source est identique au slot KB (ex. `"id"`) n'est pas listé dans `_labels`.
> Si aucun slot n'a subi de substitution terminologique, `_labels` est omis (pas de clé vide `{}`).
>
> **Exemple concret :**
> ```json
> {
>   "id": "P1",
>   "type_element": "montant_porteur",
>   "section_bois": "45x145",
>   "classe_bois": "C24",
>   "epaisseur_mm": 200,
>   "_labels": {
>     "type_element": "poteau porteur",
>     "section_bois": "section",
>     "classe_bois": "classe résistance"
>   }
> }
> ```
> Ici `epaisseur_mm` n'a pas d'entrée dans `_labels` car le document source utilisait
> déjà le terme `epaisseur_mm` (pas de substitution).

> **`id` convention**: keep the source document identifier if available
> (e.g. "Poteau P1", "IPE-01"), otherwise generate `<TYPE_ABREV>-<NN>`.
> Document ↔ JSON traceability is the priority.
> In merge mode, `_source_fichier` is always set on each element.

### Batch Mode — one JSON per file

Each file produces its own JSON named `project-import-<NNN>.json`, written to the same
location as any other mode — see "Output JSON location" above (Scope-aware: under
`$WORKSPACE/<client>/` if the batch's sources were all under a `<client>/sources/`
folder, per the Mixed-context batch guard already enforced for Scope derivation).
The `_import.mode` field is `"batch"`.
No cross-file merging — each JSON is self-contained and can be piped independently.


## Phase 6 — Produce the Import Report

> **⚠️ Language rule — import report and thesaurus org files:** all section headings,
> column labels, notes, gap descriptions, and out-of-scope explanations in
> `import-report-<NNN>.org`, `align-review-<NNN>.org`, and every thesaurus shard
> (`agent/thesaurus/global.org`, `agent/thesaurus/<client>.org`, or the legacy
> monolithic `thesaurus.org`)
> must be written in the **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

Create `$WORKSPACE/import-report-<NNN>.org` (`$WORKSPACE` = `$SANDBOX/workspace/`, or
`$SANDBOX/workspace/<client>/reports/` if this import's Scope was resolved to a
non-`global` client context — see "Scope derivation", Phase 1.2b — created if absent):

```org
#+TITLE: Import report — <source> — <date>
#+STATUS: draft
#+SOURCE: <path or "inline">

* Source
  File: <path> | Date: <date> | Elements extracted: N

* Alignment table
  | Project term | KB slot | KB value | Confidence | Decision |
  |---|---|---|---|---|

* Unit transformations applied
  | Source | Transformation | KB slot |
  |---|---|---|

* Gaps identified
  | Element | Missing slot | Action |
  |---|---|---|

* Ambiguities resolved
  | Term | Options | Engineer decision |
  |---|---|---|

* Elements with _a_confirmer
  | id | Reason |
  |---|---|

* Out-of-scope elements (⬜)
  | id | source type_element | Recommended sandbox |
  |---|---|---|

* Inter-element relationships (Phase 3.5) — only if KB org has ref/→ annotations
  Blueprint entries: N
  | element_id | ref_field | target_id | confidence | signal | In JSON? |
  |---|---|---|---|---|---|

* Unmatched figure identifiers
  | Identifier | Figure | Page | Snippets seen | Action |
  |---|---|---|---|---|

* Output file
  <path project-*.json> — N retained / N complete / N gaps / N to confirm / N out-of-scope
```

> This report is the **alignment decision memory** for this sandbox.
> It is automatically re-read during the next `chorus-import-project` run on the same sandbox.

### Patch the `README.org` imported-documents row

If Phase 0 (auto-conversion) recorded a row with `(pending)` in the
`* Imported project documents (not corpus — chorus-import-project artefacts)`
section (see Phase 0 Step 4), replace `(pending)` with the actual output filename
(e.g. `project-import-<NNN>.json`) now that it is known.

⛔ Never add or move this row into `* Corpus` — that table is reserved for
normative texts read by `chorus-feed` (see Phase 0 warning). An imported project
document stays under the dedicated section regardless of format or mode
(Single/Merge/Batch).

### Post-import — thesaurus consolidation (automatic)

After writing the import report, perform a **thesaurus consolidation pass** to ensure
les fichiers de niveaux 2 et 3 sont à jour. Cette passe est idempotente (ne duplique
pas les entrées déjà présentes). Ne touche jamais les shards d'une autre entity.

**WEB-027 — Architecture 3 niveaux (voir "Thesaurus storage layout" ci-dessus) :**
- Niveau 2 = `workspace/<C>/<projId>.thesaurus.json` (projet-spécifique, défaut)
- Niveau 3 = `workspace/<C>/thesaurus.org` (entity-wide, promotion explicite)

#### Consolidation rules

```
For each alignment produced in this import (C = Scope, projId = JSON output filename stem):

  ✅ certain (résolu directement, sans intervention ingénieur) :
    → Écrire dans Niveau 2 (workspace/<C>/<projId>.thesaurus.json)
    → Si même terme déjà présent en Niveau 2 avec même mapping : mettre à jour confidence/date
    → Si même terme déjà présent en Niveau 2 avec mapping DIFFÉRENT :
        NE PAS écraser → ajouter à * Conflicts du Niveau 3 (entity org) — arbitrage requis
    → Si terme absent du Niveau 2 → créer l'entrée en Niveau 2 (jamais en Niveau 3 par défaut)
    ⛔ JAMAIS écrire des mappings OID-backed (Niveau 1) dans le thésaurus — ils sont
       couverts par CBOM-oid-registry.yml. Ne pas polluer le Niveau 2 avec
       des entrées triviales (SHA256→hachage, AES-256-GCM→chiffrement_authentifie etc.)
       qui n'apportent rien au-delà de ce que le registre fait déjà.

  ✅ confirmée par l'ingénieur en session (avec décision explicite) :
    → Si décision universelle pour l'entity ("valide pour tous les projets <C>") :
        Écrire en Niveau 3 (workspace/<C>/thesaurus.org), section * Aliases
    → Sinon (décision produit-spécifique — défaut) :
        Écrire en Niveau 2 (workspace/<C>/<projId>.thesaurus.json)
    → Même conflict check que ci-dessus

  ⚠️ newly seen (no prior record):
    → Écrire en Niveau 3 Pending (workspace/<C>/thesaurus.org, section * Pending)
    → Raison : les Pending sont entity-scoped pour être visibles dans la webapp
      quel que soit le projet courant (une entrée Pending de l'import N est utile
      lors de l'import N+1 du même produit par un autre ingénieur)

  ⚠️ confirmed by engineer in this session:
    → Supprimer de Niveau 3 * Pending + écrire en Niveau 2 * aliases_type_element
      (sauf décision entity-wide → Niveau 3 * Aliases)
    → Record source import + date

  ⬜ out-of-scope (confirmed by engineer):
    → Écrire en Niveau 3 * Out-of-scope (entity-scoped — un terme hors-périmètre
      pour cette entity l'est probablement pour tous ses projets)
    → Supprimer de Pending si présent

  ⛔ gap (mandatory slot absent — not a mapping decision):
    → do NOT write to thesaurus (gaps are import-specific, not terminology mappings)
```

**Deduplication / conflict rule:** before any write to a shard's `* Aliases`, verify
whether `(project term, Scope)` is already present there.
- Same mapping → update the existing row (confidence, source import) — no duplicate.
- Different mapping → **do not overwrite** — this is a conflict, not a duplicate. Append
  an entry to `* Conflicts` in `global.org` instead (full rule: Phase 3 § "Immediate
  thesaurus update after each resolution" → Deduplication rule).

**Update the `#+UPDATED:` header** of every shard file touched during this
consolidation pass (`global.org`, and `<C>.org` if applicable) with today's date.

#### Consolidation summary (displayed to engineer)

```
📚 Thesaurus updated (WEB-027 — 3 niveaux)
   🔑 Niveau 2 (projet) : workspace/<C>/<projId>.thesaurus.json
      ✅ N new aliases added   (type_element: n / slot values: n)
   🏢 Niveau 3 (entity) : workspace/<C>/thesaurus.org
      ⚠️  N new pending entries
      ⬜ N out-of-scope added
      🔄 N pending → confirmed (promu Niveau 3 par l'ingénieur)
```

If nothing changed (all terms already in thesaurus) → display silently:
```
📚 Thesaurus already up to date — no new entries (Niveau 2 + Niveau 3).
```

### Post-import — audit qualité (automatic)

> ⛔ **NON-OPTIONAL** — runs after every `chorus-import-project` (AUTONOMOUS_MODE,
> `--patch` never automatic). When delegating to a sub-agent, require confirmation
> of `_audit.run: true` in the sub-agent's final summary.

Execute `chorus-audit-import.md` Phases 0–3 on the produced JSON. No `eca__ask_user`.
Produces `$WORKSPACE/reports/audit-import-NNN.md`.
Batch mode: one audit per JSON, sequentially. Fusion mode: one audit on merged JSON.

**Write `_audit` block into the JSON:**

```json
"_audit": {
  "run": true, "date": "YYYY-MM-DD",
  "report": "workspace/reports/audit-import-NNN.md",
  "gaps_comblables": N, "gaps_partiels": N, "gaps_absents": N,
  "gaps_mapping": N, "frames_manquantes": N, "patch_applied": false
}
```

**Audit summary (displayed to engineer):**

```
🔍 Audit qualité — <project-import-NNN.json>
   ✅ Comblables    : N  (→ chorus-audit-import <sb> <json> --patch)
   ⚠️ Partiels      : N  (source incomplète — pages/fichiers manquants)
   ❌ Absents       : N  (hors périmètre documentaire — aucune action)
   🔄 Mappings      : N  (décision ingénieur requise)
   🚫 Frames man.   : N  (type présent dans source, non importé)
   → Rapport        : workspace/reports/audit-import-NNN.md
```

If all counts are zero:
```
✅ Audit qualité — <project-import-NNN.json> — aucun gap détecté.
```

**Post-audit guidance (displayed only if gaps > 0):**

| Situation | Action suggérée |
|---|---|
| `gaps_comblables > 0` | `chorus-audit-import <sandbox> <json> --patch` |
| `gaps_partiels > 0` | Extraire les pages manquantes, relancer `chorus-import-project` |
| `gaps_mapping > 0` | Revoir `audit-import-NNN.md § Mapping review`, corriger manuellement |
| `frames_manquantes > 0` | Ajouter les Frames manquantes manuellement ou ré-importer |
| Seulement `gaps_absents > 0` | Aucune action — hors périmètre documentaire |

> **L'audit ne bloque jamais `chorus-check`.** Un JSON avec des gaps peut être soumis
> au pipeline — le champ `_audit` signale à la webapp que les gaps sont d'origine
> documentaire et non des lacunes KB, évitant une roadmap d'enrichissement erronée.

### Post-import — optional KB harvest (secondary)

Read `global.org` header `#+LAST_HARVEST:` and count:
- `N_promotable` = ✅ Aliases rows in `global.org` not yet present in any `<slug>.org`
- `N_total` = total rows in `global.org` `* Aliases` sections (client shards excluded)
- `N_since` = distinct source-import refs in `global.org` newer than `#+LAST_HARVEST`

If **any** threshold crossed (N_promotable ≥ 20, or N_total ≥ 100, or N_since ≥ 15),
display — otherwise skip silently:

```
💡 KB harvest recommended: chorus-feed --harvest-aliases $SANDBOX/agent/thesaurus/global.org
   Reason: <list of thresholds crossed>
```

⛔ Never auto-invoke. Only `global.org` is ever harvested (client shards: never).

### Phase 6-BATCH — Summary Report (batch mode only)

In addition to the individual reports, create `$WORKSPACE/import-batch-<NNN>.org`
(`$WORKSPACE` = `$SANDBOX/workspace/`, created if absent):

```org
#+TITLE: Batch summary report — <directory or glob> — <date>
#+STATUS: draft

* Parameters
  Source    : <directory or file list>
  Sandbox   : <sandbox-name>
  Files     : N processed / M skipped (unsupported format)
  Date      : <date>

* Results per file
  | File    | JSON produced | Elements | Retained | Gaps | To confirm | Conflicts | Out-of-scope |
  |---|---|---|---|---|---|---|---|
  | f1.pdf  | project-import-001.json | 34 | 26 | 6 | 2 | 0 | 0 |
  | f2.xlsx | project-import-002.json | 18 | 15 | 3 | 0 | 0 | 3 |
  | ...     | ...                    | .. | .. | . | . | . | . |

* Totals
  Elements processed  : N
  Retained (in JSON)  : N
  With gaps           : N
  To confirm          : N
  Out-of-scope        : N (excluded from JSON — import in another sandbox)
  Id conflicts        : N (merge mode only — N/A in batch)

* New terms detected
  Terms absent from the thesaurus (appropriate shard) → newly added in this batch run
  | Source term | File | Alignment | Confidence | Thesaurus action |
  |---|---|---|---|---|

* Skipped files
  | File | Reason |
  |---|---|
  | scan-brouillon.pdf | Empty text extraction — re-read or provide inline |

* Suggested next step
  perl $SANDBOX/run.pl <JSON1> <JSON2> ...
  (run the pipeline on each produced JSON)
```

> **New terms**: if a source term received a ✅ alignment and was not already in the
> thesaurus, it has been automatically added to the appropriate shard's Aliases
> section (`global.org`, or the current Scope's `<client>.org`).
> No manual action required — the thesaurus is the primary persistence mechanism.
> Use `chorus-feed --harvest-aliases $SANDBOX/agent/thesaurus/global.org` only if you
> want to promote these mappings to the normative KB for cross-sandbox reuse.


## Phase 7 — Run the Pipeline (optional)

If the engineer explicitly requests it, follow up with `chorus-check`:

```bash
perl $SANDBOX/run.pl $SANDBOX/<project-import-NNN.json>
```

If `run.pl` does not yet exist → indicate that `chorus-check` should be run first.


## Separation of Responsibilities

| | `chorus-feed` | `chorus-import-project` | `chorus-audit-import` | `chorus-create-project` | `chorus-check` |
|---|---|---|---|---|---|
| **Reads** | normative corpus | engineer project docs + org KB | project JSON + source docs + KB | org KB | org KB + YAML |
| **Produces** | KB org, YAML, Helpers.pm | `project-import-*.json` + `.org` report + `_audit` block | `audit-import-NNN.md` + `_audit` update | `project-*.json` | Feed.pm, shells, Expert.pm, run.pl |
| **Threshold source** | corpus | org KB only | org KB (via YAML `--kb`) | org KB only | org KB |
| **Gaps** | n/a | reported, never invented | classified by origin | computed from KB | n/a |
| **Modifies JSON** | ✗ | ✅ (creates) | ✅ (`_audit` block + `--patch`) | ✅ (creates) | ✗ |
| **Never reads** | — | Helpers.pm, Feed.pm | Helpers.pm, Feed.pm | Helpers.pm, Feed.pm | — |


## Architectural Principle — sandbox granularity = JSON granularity

> **The granularity of a sandbox defines the granularity of the project JSON intended for it.**

A sandbox covers a coherent normative domain (e.g. structural, thermal, hygrometry).
A multi-domain project produces as many import JSONs as there are target sandboxes.
**`chorus-import-project` is the partitioning tool — not `run.pl`.**

Out-of-scope elements (⬜) are cleanly excluded at import time; `run.pl` and
`Feed.pm` only receive the types they know.

```
dossier-project/                      ← single source (all domains mixed)
  charpente.pdf
  isolation.xlsx
  bardage.docx

  ↓ chorus-import-project sandbox-structurel ./dossier-project/ --batch
project-structurel-001.json           ← montants, lisses, chevrons
                                        # → elements isolant_laine, membrane_etanche → ⬜ excluded + report

  ↓ chorus-import-project sandbox-thermique ./dossier-project/ --batch
project-thermique-001.json            ← isolants, membranes
                                        # → elements montant_porteur, lisse_basse → ⬜ excluded + report

  ↓
perl sandbox-structurel/run.pl project-structurel-001.json → rapport_struct.txt
perl sandbox-thermique/run.pl  project-thermique-001.json  → rapport_thermo.txt
```

**Consequence for `Feed.pm`** (generated by `chorus-check`):
The template uses `warn + next` instead of `die` on an unknown type, as a safety net
in case a mixed JSON somehow reached `run.pl`. Partitioning remains the responsibility
of `chorus-import-project`.
