# Skill — chorus-audit-import

> Trigger: `chorus-audit-import <sandbox-name> <project.json> [--patch] [--source <file.md>] [--kb]`
> Agent: `code`
>
> `<sandbox-name>`   : sandbox whose KB was used to produce the JSON
> `<project.json>`    : imported project JSON (result of `chorus-import-project`)
>                      Accepted as relative path inside the sandbox or absolute path.
> `--patch`          : apply ✅ comblable corrections directly into the JSON file
> `--source <file>`  : add an extra source document to search (beyond `_import.source`)
> `--kb`             : also cross-check slot values against active YAML rules (KB coherence)
>
> **Purpose:** audit the quality of a `chorus-import-project` output before running
> `chorus-check`. For each gap or flag in the JSON (`_incomplet`, `_a_confirmer`,
> missing Frame types), determine whether the information is available in the source
> document, structurally absent, or requires extraction of additional pages/files.
>
> ⛔ **Every invocation — with or without `--patch` — writes/updates the `_audit`
> block in `<project.json>` (Phase 3.5), unconditionally, even with all-zero counts.**
> The webapp reads only this JSON block (never `audit-import-NNN.md`) to render the
> audit badge and patch button — an audit without this block is invisible to the
> webapp regardless of how thorough the `.md` report is.
>
> Pipeline position:
> ```
> chorus-import-project → [chorus-audit-import] → (corrections) → chorus-check
> ```
>
> Prerequisites: `chorus-import-project` must have been run — a `<project.json>` with
> `_import` metadata block must exist.


## Phase 0 — Load Inputs

### 0.1 Resolve paths

```
SANDBOX = $SANDBOXES/<sandbox-name>/
JSON    = resolve <project.json> against SANDBOX if not absolute
```

Read `$SANDBOX/agent/chorus/index.org` → namespace, agent slugs, pipeline order.

### 0.2 Read the project JSON

Read `<project.json>` and extract:

| Field | Purpose |
|---|---|
| `_import.source` | Source document(s) used during import |
| `_import.gaps` | Slots explicitly flagged as absent |
| `_import.a_confirmer` | Mappings flagged as uncertain |
| `_import.hors_perimetre` | Items explicitly excluded during import |
| `_import.couverture_kb` | Import-time coverage indicator |
| Elements with `_incomplet: 1` | Frames with missing mandatory slots |
| Elements with `_a_confirmer: 1` | Frames with uncertain slot values |

Build two working lists:
- **GAP_LIST** : `{element_id, slot, reason}` — from `_import.gaps` + `_incomplet` flags
- **CONFIRM_LIST** : `{element_id, slot, current_value, note}` — from `_import.a_confirmer` + `_a_confirmer` flags

### 0.3 Collect source documents

```
sources = [_import.source]          # from JSON metadata
if --source <file> provided:
    sources.append(<file>)          # extra source

for each s in sources:
    Read s (full text) → store in SOURCE_TEXTS[s]
```

Print: `[audit] Sources loaded: <list of files>`
Print: `[audit] GAP_LIST: <N> entries — CONFIRM_LIST: <M> entries`


## Phase 1 — KB Frame Type Coverage

Identify which `type_element` values the KB supports vs. which are present in the JSON.

### 1.1 Expected Frame types (from KB)

For each agent slug, read `$SANDBOX/agent/chorus/<slug>.org` → section `Catalogue des Frames`.
Extract the full list of declared `type_element` values.

```
KB_TYPES = set of all type_element declared across all <slug>.org files
```

### 1.2 Present Frame types (from JSON)

```
JSON_TYPES = set(element["type_element"] for element in json["elements"])
```

### 1.3 Missing Frame types

```
MISSING_TYPES = KB_TYPES - JSON_TYPES
```

For each `type_element` in MISSING_TYPES:
- Search SOURCE_TEXTS for any mention of domain terms associated with that type
  (use KB ontology vocabulary from `<slug>.org` — section `Ontologie`)
- Classify:
  - **🚫 Frame manquante** if mentions found in the source → type present but not imported
  - **❌ Hors périmètre** if no mention found → source document does not cover this type


## Phase 2 — Slot-by-Slot Source Scan

For each entry in GAP_LIST `{element_id, slot, reason}`:

### 2.1 Build search terms

From `$SANDBOX/agent/chorus/<slug>.org` (slot dictionary), retrieve:
- The slot's canonical label and known aliases
- Its expected value type (numeric, enum, boolean)
- Its unit (if applicable)

### 2.2 Search the source documents

For each source in SOURCE_TEXTS:
```
search_result = search(SOURCE_TEXTS[source], terms=[slot_label, *aliases])
```

Classify the result:

| Result | Class | Label |
|---|---|---|
| Value found, unambiguous | Comblable | ✅ |
| Mentioned but ambiguous / partial | Extraction partielle | ⚠️ |
| Not found in any source | Structurellement absent | ❌ |

**Special case — extraction partielle:** if the source document contains page headers
indicating it covers only a subset of the original PDF (e.g. `PAGE 17 / 27` in a
2-page extracted file), flag ALL absent slots as ⚠️ Extraction partielle rather than
❌, and note the unextracted page range.

### 2.3 Confirm-list review

For each entry in CONFIRM_LIST `{element_id, slot, current_value, note}`:

Search SOURCE_TEXTS for the actual value used in the document:
- If the source confirms the current mapping → class **✅ Mapping confirmé**
- If the source uses a different term that maps to a different KB value → class **🔄 Mapping à corriger**
- If the source is silent on the point → class **⚠️ Non vérifiable dans le document**

### 2.4 --kb flag (optional)

If `--kb` is active, for each slot value found:
- Read the corresponding `$SANDBOX/rules/<slug>/R*.yml` files
- Check that the value is within the allowed domain declared in the YAML (`filtre`, `attribut`)
- Flag any mismatch as **🔴 Incohérence KB**


## Phase 3 — Gap Classification Table

Assemble the full audit report. Produce one row per gap/confirm entry.

### Classification legend

| Class | Symbol | Meaning | Action |
|---|---|---|---|
| Comblable | ✅ | Value found in source — can be injected | Patch JSON |
| Extraction partielle | ⚠️ | Source is incomplete (pages/files missing) | Extract missing pages |
| Structurellement absent | ❌ | Document does not contain this information | Manual entry or out-of-scope |
| Mapping à confirmer | 🔄 | Uncertain mapping from import | Engineer decision required |
| Frame manquante | 🚫 | Frame type documented in source but not imported | Create Frame / re-import |
| Incohérence KB | 🔴 | Value outside KB-allowed domain | Correct value or enrich KB |

### Output format

```markdown
## Audit — <project.json> vs <sandbox-name> KB
Date: <YYYY-MM-DD>
Source(s): <list>
Import coverage: <couverture_kb from JSON>

### Gap analysis

| Element | Slot | Class | Found value / Note | Action |
|---|---|---|---|---|
| BAT-A | nb_niveaux | ❌ | Not mentioned in §5.1 (families only) | Manual entry |
| FAC-3B-bois | C_plus_D_m | ⚠️ | §5.4.1.1: 130 cm = regulatory minimum, not measured value | Extract full PDF |
| FAC-3B-bois | jonction_plancher_conforme | ⚠️ | IT249 slots absent — source covers pages 17-18 only | Extract pages 1-16 |
| ... | | | | |

### Mapping review

| Element | Slot | Current value | Source term | Class | Action |
|---|---|---|---|---|---|
| FAC-3B-bois | classement_europeen_facade | D-s3-d0 | "D-S2-d0" (§5.3.1) | 🔄 | Confirm: D-S2,d0 = regulatory minimum ≠ product classification |
| ... | | | | | |

### Missing Frame types

| type_element | Source evidence | Class | Action |
|---|---|---|---|
| paroi_enveloppe_logement | §5.2.1: "EI30 à l'exclusion des façades" | 🚫 | Create Frame manually |
| escalier | Not mentioned | ❌ | Out of scope for this document |
| ... | | | |

### Priority actions

1. [⚠️] Extract missing PDF pages (pages 1–16) → re-run `chorus-import-project` for classification slots
2. [🚫] Add `paroi_enveloppe_logement` Frame manually to JSON (value: EI30, families 2 & 3)
3. [🔄] Confirm `classement_europeen_facade` mapping with engineer
4. [❌] Accept as out-of-scope: escalier, paroi_separative, bloc_porte_paliere, cellier_cave

### Summary

| Class | Count |
|---|---|
| ✅ Comblable | N |
| ⚠️ Extraction partielle | N |
| ❌ Structurellement absent | N |
| 🔄 Mapping à confirmer | N |
| 🚫 Frame manquante | N |
| 🔴 Incohérence KB | N |

Estimated coverage after corrections: <X>%
```

Write report to: `$WORKSPACE/audit-import-<NNN>.md` (`$WORKSPACE` =
`$SANDBOX/workspace/`, created if absent).
Print: `[audit] Report written → workspace/audit-import-<NNN>.md`


## Phase 3.5 — Write `_audit` metadata into the JSON (ALWAYS — never conditional on `--patch`)

> ⛔ **NON-OPTIONAL, unconditional.** This phase runs at the end of **every**
> `chorus-audit-import` invocation — with or without `--patch`, whether called
> standalone or chained automatically after `chorus-import-project`. The webapp
> (`chorus/scanner.js`) reads **only** `project.json._audit` to render the audit
> badge and the patch button — it never parses `audit-import-NNN.md`. **A report
> without this JSON block is invisible to the webapp**, even though the audit was
> genuinely performed. Skipping this step is the single most common cause of
> "I ran the audit but the webapp shows nothing" incidents.

From the Phase 3 classification counts (regardless of whether this is a first run
or a re-run over an existing `_audit` block), write/update the top-level `_audit`
block in `<project.json>`:

```json
"_audit": {
  "run":               true,
  "date":              "YYYY-MM-DD",
  "report":            "workspace/<...>/audit-import-NNN.md",
  "gaps_comblables":   N,
  "gaps_partiels":     N,
  "gaps_absents":      N,
  "gaps_mapping":      N,
  "frames_manquantes": N,
  "patch_applied":     false
}
```

Field source (from Phase 3 classification table):
- `gaps_comblables`   = count of ✅ Comblable entries
- `gaps_partiels`     = count of ⚠️ Extraction partielle entries
- `gaps_absents`      = count of ❌ Structurellement absent entries
- `gaps_mapping`      = count of 🔄 Mapping à confirmer entries **+** 🔴 Incohérence KB /
                        décision de périmètre entries not yet resolved (any residual
                        gap requiring an engineer decision, not mechanically patchable)
- `frames_manquantes` = count of 🚫 Frame manquante entries
- `patch_applied`     = `false` on a report-only run (Phase 4 not executed).
  Only Phase 4.3 (actual `--patch` application) may set this to `true`.

**Rule:** this block must be written even when every count is zero (clean audit,
nothing to report) — an all-zero `_audit` block is what makes the webapp show
"✅ Audité · aucun gap actionnable" instead of nothing at all.

Write the updated JSON back to `<project.json>` (overwrite — only the `_audit`
block changes in a report-only run; all `elements` stay untouched).
Print: `[audit] _audit metadata written → <project.json>`


## Phase 4 — Patch Mode (--patch)

Only if `--patch` flag is active.

### 4.1 Collect patchable entries

From Phase 2, collect all entries classified ✅ (value found unambiguously in source).

For each patchable entry:
- Extract the exact value from the source text
- Map it to the correct KB slot type (integer, float, string, boolean)
- Prepare a JSON patch operation: `{element_id, slot, old_value: null, new_value: <value>}`

### 4.2 Confirm before applying

Print a summary of all patches:
```
[audit --patch] Ready to apply N corrections to <project.json>:
  BAT-A.nb_niveaux          : null → 4
  FAC-3B-bois.has_ouvertures: null → true
  ...
Apply? [yes / abort]
```

Require explicit `yes` confirmation before writing.

### 4.3 Apply patches

For each confirmed patch:
- Update the JSON element in place
- Remove `_incomplet: 1` flag if all mandatory slots are now filled
- Add `_patched_by: "chorus-audit-import"` and `_patched_date: "<YYYY-MM-DD>"` to the element

After applying all patches, **update the `_audit` block already written by
Phase 3.5** in the same JSON (never write it from scratch here — Phase 3.5 is
unconditional and has already run earlier in this same invocation):

```json
"_audit": {
  ...existing fields...,
  "patch_applied":          true,
  "patches_applied":        N,
  "gaps_comblables_applied": N,
  "patch_date":             "YYYY-MM-DD"
}
```

Field rules:
- `patch_applied` **must be a boolean `true`** — the webapp scanner reads this field to update the badge state.
- `patches_applied` and `gaps_comblables_applied` are informational integer counts (same value N).
- `patch_date` is the date of this `--patch` run (not the original audit date).
- All other existing `_audit` fields are **preserved unchanged** — never overwrite the original audit metadata.

Write the patched JSON back to `<project.json>` (overwrite).
Print: `[audit --patch] <N> corrections applied → <project.json>`

### 4.4 Update audit report

Add a `### Patches applied` section to the report listing all changes made.


## Output files

| File | Description |
|---|---|
| `$WORKSPACE/audit-import-<NNN>.md` | Full audit report (always produced) |
| `<project.json>` | `_audit` block written/updated (ALWAYS — see Phase 3.5, every run, even all-zero counts, even without `--patch`); `elements` additionally patched only with `--patch` after confirmation |

> **NNN** is a zero-padded 3-digit counter matching the source JSON number
> (e.g. `project-ZAC-Ferney-001.json` → `audit-import-001.md`).
> If the JSON filename contains no number, use the next available counter in
> `workspace/` (`$WORKSPACE`).

## Usage examples

```bash
# Basic audit — report only
chorus-audit-import test-04 projects/project-ZAC-Ferney—Lot-B32—Sortie-sécurité-incendie-1.json

# Audit with KB coherence check
chorus-audit-import test-04 projects/project-ZAC-Ferney—Lot-B32—Sortie-sécurité-incendie-1.json --kb

# Audit + apply comblable corrections
chorus-audit-import test-04 projects/project-ZAC-Ferney—Lot-B32—Sortie-sécurité-incendie-1.json --patch

# Audit with an additional source document
chorus-audit-import test-04 projects/project-ZAC-Ferney—Lot-B32—Sortie-sécurité-incendie-1.json \
  --source projects/004b-sortie-securite-incendie-1-pages1-16-vision.md
```
