# Skill — chorus-import-project

> Trigger: `chorus-import-project <sandbox-name> <source…> [--out <fichier.json>] [--batch]`
> Agent: `architect`
>
> `<sandbox-name>` : sandbox containing a KB produced by `chorus-feed`
> `<source…>`      : one or more project sources from the engineer (see modes below)
>                    Accepted formats: PDF, Word (.docx), Excel (.xlsx/.csv),
>                    plain text, table pasted in the chat, directory path
> `--out`          : output JSON filename (merge mode only;
>                    default: `projet-import-<NNN>.json`)
> `--batch`        : force batch mode even if a single source is provided
>
> ### Invocation Modes
>
> | Syntax | Mode | Behavior |
> |---|---|---|
> | `chorus-import-project sb fichier.pdf` | **Single** | 1 source → 1 JSON (original behavior) |
> | `chorus-import-project sb f1.pdf f2.xlsx f3.docx` | **Merge** | N sources → 1 merged JSON (same project, complementary files) |
> | `chorus-import-project sb ./dossier/` | **Batch** | Directory → 1 JSON per file + summary report |
> | `chorus-import-project sb *.pdf --batch` | **Batch** | Explicit glob → 1 JSON per file + summary report |
>
> **Automatic mode detection rule:**
> - 1 non-directory source argument → Single
> - N > 1 source arguments (same or mixed formats) → Merge
> - 1 directory argument or `--batch` flag present → Batch
>
> **Single responsibility: align the engineer's project terminology with the sandbox
> KB slots and types, then produce a valid project JSON file.**
>
> Prerequisites: `chorus-feed <sandbox-name>` must have been run beforehand (org KB present).
>
> ⚠️ **KB sources to use — strict order:**
> 1. `$SANDBOX/eca/agents/index.org` → Frame types, pipeline, namespace
> 2. `$SANDBOX/eca/agents/<slug>.org` → sections `Ontologie`, `Dictionnaire des slots`,
>    `Catalogue des Frames` (mandatory slots, value domains)
> 3. `$SANDBOX/eca/import-report-*.org` existing → previous alignment decisions
>
> ⛔ **Never read** `Helpers.pm`, `Feed.pm`, `Agent/*.pm` to infer slots.
> ⛔ **Never invent** a value absent from the source document — report the gap.

---

## Phase 0 — Source Data Acquisition

### Mode Detection and Source Collection

```
# Mode Batch (répertoire)
Si <source> est un répertoire :
  files = glob("$source/*.{pdf,docx,xlsx,csv,txt}")
  Trier par nom — traiter chaque fichier indépendamment (→ Phase 0B par fichier)
  Passer en Phase 0-BATCH après collecte

# Mode Batch (glob / --batch explicite)
Si --batch présent ou N sources de formats homogènes (N > 1 même extension) :
  files = liste des sources
  Trier par nom — traiter chaque fichier indépendamment
  Passer en Phase 0-BATCH après collecte

# Mode Fusion (N sources, formats mixtes, sans --batch)
Si N > 1 sources sans --batch :
  Extraire chaque source séparément → produire N blocs texte étiquetés
  Fusionner les blocs avant Phase 2 (inventaire global)
  ⚠️ Signaler si deux fichiers semblent couvrir les mêmes éléments (id dupliqués potentiels)

# Mode Unitaire
1 source non-répertoire, sans --batch → comportement historique (Phase 0A/0B ci-dessous)
```

### Phase 0-BATCH — Batch Processing

For each file `f` in `files`:
1. Extract plain text (Phase 0B below)
2. Run Phases 1–6 **autonomously** for this file
3. Name the outputs: `projet-import-<NNN>.json` and `import-report-<NNN>.org`
   (increment NNN independently for each file)
4. At the end of the batch → produce the **batch summary report** (see Phase 6-BATCH)

> ⚠️ Phase 1 (KB reading) is run **once only** at the start of the batch
> and reused for all files — the terminology reference is shared.

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

### Case B — Filesystem source (files on disk)

Identify the format and extract plain text **before** any semantic processing.

#### PDF
```bash
pdftotext -layout "<fichier.pdf>" -
# Si pdftotext absent :
python3 -c "import pdfplumber; p=pdfplumber.open('<f>'); [print(pg.extract_text()) for pg in p.pages]"
```

#### Excel / CSV
```bash
# CSV direct
cat "<fichier.csv>"

# Excel → CSV via LibreOffice
libreoffice --headless --convert-to csv "<fichier.xlsx>" --outdir /tmp/
cat /tmp/"<fichier>.csv"

# Excel via Python (si LibreOffice absent)
python3 -c "
import openpyxl
wb = openpyxl.load_workbook('<fichier.xlsx>')
for ws in wb.worksheets:
    for row in ws.iter_rows(values_only=True):
        print('\t'.join(str(c) if c is not None else '' for c in row))
"
```

#### Word (.docx)
```bash
python3 -c "
import docx
doc = docx.Document('<fichier.docx>')
for p in doc.paragraphs: print(p.text)
for t in doc.tables:
    for row in t.rows:
        print('\t'.join(c.text for c in row.cells))
"
```

> ⚠️ If extraction tools are absent → ask the engineer to provide copy-pasted content
> from their application (Case A).
> Never block the workflow over a missing tool — offer the inline alternative.

---

## Phase 1 — Read the KB (canonical terminology)

### 1.1 Pipeline Index

Read `$SANDBOX/eca/agents/index.org`:
- Namespace + agent list (slug, pos)
- Global slot dictionary (if present in the index)

### 1.2 Per-agent terminology

For each agent, read `$SANDBOX/eca/agents/<slug>.org` and extract:

| KB Section | What we extract |
|---|---|
| `Ontologie` | Domain concepts, synonyms, relationships (e.g. "entrait" = horizontal truss beam) |
| `Catalogue des Frames` | Exact types (`type_element`), mandatory slots per type |
| `Dictionnaire des slots` | Canonical names, value types, units, allowed domains |

Build an internal **terminology reference**:
```
concept_kb        → type_element / slot_kb       unité_kb    domaine
────────────────────────────────────────────────────────────────────
montant porteur   → montant_porteur              —           —
lisse              → lisse_basse / lisse_haute   —           à préciser
classe résistance → classe_bois                 —           C14/C16/C18/C24/C30
épaisseur isolant → epaisseur_mm                mm          entier positif
conductivité λ    → classe_conductivite         —           "031"/"035"/"040"
hauteur libre     → hauteur_libre_m             m           décimal
section           → section_bois                —           "BxH" ex. "45x145"
```

### 1.3 Previous alignment decisions

If `$SANDBOX/eca/import-report-*.org` exists, read the latest report:
- Retrieve previously validated mappings → reapply them without asking again
- Retrieve pending questions → re-raise them if the same terms reappear

---

## Phase 2 — Raw Inventory of Project Elements

Scan the source data and produce a **raw inventory**:
an uninterpreted list of what the engineer has provided.

```
Ligne / Cellule source          Terme identifié      Valeurs associées
────────────────────────────────────────────────────────────────────────
"Poteau porteur 45×145 C24"    "poteau porteur"     dim=45×145, classe=C24
"h libre 2,5m, entraxe 40cm"  "h libre"            2.5m / "entraxe"=40cm
"Laine de verre λ035, e=20cm" "laine de verre"     λ=0.035, e=200mm
"panneau OSB 12mm, CE"         "panneau OSB"        ep=12mm, CE=oui
```

> **Rule:** do not map at this stage — inventory first, align later.
> Preserve the original source text in the inventory for traceability.

---

## Phase 3 — Terminology Alignment

This is the core phase. For each term from the raw inventory, cross-reference against
the KB reference (Phase 1.2) and produce an alignment table:

```
Terme projet                  Slot KB / type_element    Valeur KB        Confiance
──────────────────────────────────────────────────────────────────────────────────
"poteau porteur"              type_element              montant_porteur  ✅ sûr
"45×145"                      section_bois              "45x145"         ✅ sûr
"C24"                         classe_bois               "C24"            ✅ sûr
"h libre 2,5m"                hauteur_libre_m           2.5              ✅ sûr
"entraxe 40cm"                entraxe_mm                400              ✅ sûr (×10)
"laine de verre λ035"         type_element              isolant_laine    ✅ sûr
                              classe_conductivite       "035"            ✅ sûr
"panneau OSB 12mm"            type_element              panneau_osb      ✅ sûr
                              osb_epaisseur_mm          12               ✅ sûr
"poteau intérieur cloison"    type_element              montant_non_porteur ⚠️ probable
"panneau contreventement"     type_element              panneau_osb ?    ❓ ambigu
"traitement cl. 2"            traitement_applique ?     ?                ❓ à préciser
```

### Confidence Levels

| Symbol | Meaning | Action |
|---|---|---|
| ✅ sûr | Direct or near-direct match with the KB | Map without asking |
| ⚠️ probable | Logical match but term is not exact | Propose + ask for confirmation |
| ❓ ambigu | Multiple possible mappings or unknown KB term | Block + ask for clarification |
| ⛔ gap | Mandatory slot absent from the source document | Report — do not invent |
| ⬜ hors-périmètre | `type_element` absent from this sandbox's KB | Exclude from JSON — flag `_hors_perimetre: 1` + report |

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
> # Projet mixte → deux imports ciblés
> chorus-import-project sandbox-structurel ./dossier-projet/ --batch
>     # → JSON contenant uniquement montant_porteur, lisse_basse, ...
>     # → éléments isolant_laine, membrane_etanche → ⬜ exclus + rapport
>
> chorus-import-project sandbox-thermique ./dossier-projet/ --batch
>     # → JSON contenant uniquement isolant_laine, membrane_etanche, ...
>     # → éléments montant_porteur, lisse_basse → ⬜ exclus + rapport
> ```

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
❓ "panneau contreventement" — plusieurs interprétations possibles :
   1. panneau_osb     (panneau OSB structurel §3.1)
   2. panneau_fibragglo (panneau de contreventement §3.2)
   Quel type correspond à votre document ?
```

**Do not proceed until blocking ❓ items are resolved** (ambiguous `type_element` slots).
⚠️ items may be provisionally accepted with a `_a_confirmer: 1` flag.

---

## Phase 4 — Identify Gaps

For each element, cross-reference the present slots against the KB `Catalogue des Frames`:

```
Type            Slot obligatoire    Présent ?   Source
──────────────────────────────────────────────────────────
montant_porteur classe_bois         ✅          "C24"
montant_porteur humidite_pct        ⛔ ABSENT   non mentionné
montant_porteur hauteur_libre_m     ✅          "h=2.5m"
```

### Gap Handling

| Gap type | Action |
|---|---|
| Mandatory slot absent | Ask the engineer — do not assume |
| Optional slot absent | Omit from JSON — the pipeline handles it |
| Out-of-domain value (e.g. `classe_bois: "C12"`) | Report — let the engineer correct it |
| Entire element unmappable | Include with `_incomplet: 1` — will be cleanly rejected by Feed |

---

## Phase 5 — Produce the JSON

### Single / Merge Mode — one JSON

Once all ❓ items are resolved and critical gaps are filled:

```json
{
  "projet": "<nom-projet-ingenieur>",
  "description": "Import depuis <source> — <date> — <N> éléments",
  "_import": {
    "source": "<nom-fichier-ou-inline>",
    "sources": ["<f1>", "<f2>"],
    "mode": "unitaire|fusion",
    "date": "<date>",
    "gaps": ["<id>: <slot manquant>", "..."],
    "a_confirmer": ["<id>: <terme ambigu>", "..."],
    "conflits": ["<id>: présent dans f1 et f2 — doublon renommé", "..."]
  },
  "elements": [
    {
      "id": "<id-issu-du-document>",
      "type_element": "<type_kb>",
      "<slot_1>": "<valeur>",
      "_source_fichier": "<nom-fichier>",
      "_a_confirmer": 1,
      "_conflit": 1,
      "_conflit_source": ["<f1>", "<f2>"]
    }
  ]
}
```

> **`id` convention**: keep the source document identifier if available
> (e.g. "Poteau P1", "IPE-01"), otherwise generate `<TYPE_ABREV>-<NN>`.
> Document ↔ JSON traceability is the priority.
> In merge mode, `_source_fichier` is always set on each element.

### Batch Mode — one JSON per file

Each file produces its own JSON named `projet-import-<NNN>.json`.
The `_import.mode` field is `"batch"`.
No cross-file merging — each JSON is self-contained and can be piped independently.

---

## Phase 6 — Produce the Import Report

Create `$SANDBOX/eca/import-report-<NNN>.org`:

```org
#+TITLE: Rapport d'import — <source> — <date>
#+STATUS: draft

* Source
  Fichier : <chemin ou "inline">
  Date    : <date>
  Éléments extraits : N

* Tableau d'alignement
  | Terme projet | Slot KB | Valeur KB | Confiance | Décision |
  |---|---|---|---|---|
  | ...          | ...     | ...       | ✅/⚠️/❓   | ...      |

* Transformations d'unités appliquées
  | Source | Transformation | Slot KB |
  |---|---|---|

* Gaps identifiés
  | Élément | Slot manquant | Action |
  |---|---|---|

* Ambiguïtés résolues
  | Terme | Options | Décision ingénieur |
  |---|---|---|

* Éléments avec _a_confirmer
  | id | Raison |
  |---|---|

* Éléments hors-périmètre (⬜)
  | id | type_element source | Sandbox recommandé |
  |---|---|---|

* Fichier produit
  <chemin projet-*.json>
  N éléments retenus / N complets / N avec gaps / N à confirmer / N hors-périmètre (exclus)
```

> This report is the **alignment decision memory** for this sandbox.
> It is automatically re-read during the next `chorus-import-project` run on the same sandbox.

### Phase 6-BATCH — Summary Report (batch mode only)

In addition to the individual reports, create `$SANDBOX/eca/import-batch-<NNN>.org`:

```org
#+TITLE: Rapport de synthèse batch — <répertoire ou glob> — <date>
#+STATUS: draft

* Paramètres
  Source    : <répertoire ou liste de fichiers>
  Sandbox   : <sandbox-name>
  Fichiers  : N traités / M ignorés (format non supporté)
  Date      : <date>

* Résultats par fichier
  | Fichier | JSON produit | Éléments | Retenus | Gaps | À confirmer | Conflits | Hors-périmètre |
  |---|---|---|---|---|---|---|---|
  | f1.pdf  | projet-import-001.json | 34 | 26 | 6 | 2 | 0 | 0 |
  | f2.xlsx | projet-import-002.json | 18 | 15 | 3 | 0 | 0 | 3 |
  | ...     | ...                    | .. | .. | . | . | . | . |

* Totaux
  Éléments traités    : N
  Retenus (dans JSON) : N
  Avec gaps           : N
  À confirmer         : N
  Hors-périmètre      : N (exclus du JSON — à importer dans un autre sandbox)
  Conflits d'id       : N (mode fusion uniquement — N/A en batch)

* Termes nouveaux détectés
  Termes non présents dans import-report-*.org précédents → à intégrer dans la KB
  | Terme source | Fichier | Alignement proposé | Confiance |
  |---|---|---|---|

* Fichiers ignorés
  | Fichier | Raison |
  |---|---|
  | scan-brouillon.pdf | Extraction texte vide — relire ou fournir inline |

* Prochaine étape suggérée
  perl $SANDBOX/run.pl <JSON1> <JSON2> ...
  (lancer le pipeline sur chaque JSON produit)
```

> **New terms**: if a source term was not present in previous reports AND received a
> ✅ safe alignment, it is a candidate for integration into the `Dictionnaire` section
> of the corresponding agent KB (via `chorus-feed` or manual editing of the org file).

---

## Phase 7 — Run the Pipeline (optional)

If the engineer explicitly requests it, follow up with `chorus-check`:

```bash
perl $SANDBOX/run.pl $SANDBOX/<projet-import-NNN.json>
```

If `run.pl` does not yet exist → indicate that `chorus-check` should be run first.

---

## Separation of Responsibilities

| | `chorus-feed` | `chorus-import-project` | `chorus-create-project` | `chorus-check` |
|---|---|---|---|---|
| **Reads** | normative corpus | engineer project docs + org KB | org KB | org KB + YAML |
| **Produces** | KB org, YAML, Helpers.pm | `projet-import-*.json` + `.org` report | `projet-*.json` | Feed.pm, shells, Expert.pm, run.pl |
| **Threshold source** | corpus | org KB only | org KB only | org KB |
| **Gaps** | n/a | reported, never invented | computed from KB | n/a |
| **Never reads** | — | Helpers.pm, Feed.pm | Helpers.pm, Feed.pm | — |

---

## Architectural Principle — sandbox granularity = JSON granularity

> **The granularity of a sandbox defines the granularity of the project JSON intended for it.**

A sandbox covers a coherent normative domain (e.g. structural, thermal, hygrometry).
A multi-domain project produces as many import JSONs as there are target sandboxes.
**`chorus-import-project` is the partitioning tool — not `run.pl`.**

Out-of-scope elements (⬜) are cleanly excluded at import time; `run.pl` and
`Feed.pm` only receive the types they know.

```
dossier-projet/                      ← source unique (tous domaines mélangés)
  charpente.pdf
  isolation.xlsx
  bardage.docx

  ↓ chorus-import-project sandbox-structurel ./dossier-projet/ --batch
projet-structurel-001.json           ← montants, lisses, chevrons
                                        isolants → ⬜ exclus

  ↓ chorus-import-project sandbox-thermique ./dossier-projet/ --batch
projet-thermique-001.json            ← isolants, membranes
                                        montants → ⬜ exclus

  ↓
perl sandbox-structurel/run.pl projet-structurel-001.json → rapport_struct.txt
perl sandbox-thermique/run.pl  projet-thermique-001.json  → rapport_thermo.txt
```

**Consequence for `Feed.pm`** (generated by `chorus-check`):
The template uses `warn + next` instead of `die` on an unknown type, as a safety net
in case a mixed JSON somehow reached `run.pl`. Partitioning remains the responsibility
of `chorus-import-project`.
