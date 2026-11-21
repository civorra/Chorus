# Sub-skill — chorus-import-thesaurus

> **Internal sub-skill** — loaded by `chorus-import-project` Phase 1.2b when a
> thesaurus file exists in the sandbox (`$SANDBOX/workspace/<C>/thesaurus.org`).
> Contains the full thesaurus architecture reference: 3-level layout, formats,
> KB hash tracking, Scope derivation, lookup protocol, and pitfalls ENG-073/ENG-074.
>
> Trigger: loaded via `eca__read_file` on `$ENGINE/agent/skills/chorus-import-thesaurus.md`
> from `chorus-import-project` Phase 1.2b, before any alignment work in Phase 3.

---

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
  Jamais automatique à l'import — promotion EXCLUSIVEMENT via bouton 🏢 de l'onglet Thésaurus webapp. ⛔ L'assistant ECA terminal ne peut jamais écrire dans thesaurus.org § * Aliases.
```

**Règles d'écriture à l'import :**
- ✅ certaine (depuis CBOM-oid-registry, fiabilité certaine/haute) → **Niveau 2** (projet JSON)
- ✅ certaine (depuis signal structurel du document source — CBOM `primitive`/`cryptoFunctions`/
  `description`, champ XML, etc.) → **Niveau 2** (projet JSON) — **⛔ jamais Niveau 3 Aliases**,
  même si le terme figure dans Niveau 3 Pending. Le signal structurel est spécifique à CE document ;
  un autre projet de la même entity peut utiliser le même terme dans un contexte différent.
  Le Pending Niveau 3 reste intact comme filet de sécurité entity-wide.
- ✅ confirmée par l'ingénieur en session → **Niveau 2** (projet JSON) — sauf si l'ingénieur dit
  explicitement "valide pour tous les projets <C>" → **Niveau 3** (entity org)
- ⚠️ `_a_confirmer` newly seen → **Niveau 2** (`<projId>.thesaurus.json § "pending"`) —
  ⛔ jamais en Niveau 3 (ENG-071) : un mapping non tranché n'est pas une vérité entity-wide ;
  il ne sera promu qu'après décision explicite ingénieur via la webapp
- ⬜ out-of-scope → **Niveau 3 Out-of-scope** (entity org)

**Quel fichier lire pour un import** (C = Scope de cet import, projId = nom du JSON produit) :
```
Lire en priorité : $SANDBOX/workspace/<C>/<projId>.thesaurus.json   (Niveau 2 — projet)
Puis :             $SANDBOX/workspace/<C>/thesaurus.org              (Niveau 3 — entity)
Ne jamais lire le thésaurus d'une autre entity.
```

**`* Pending`** vit dans le fichier projet (`workspace/<C>/<projId>.thesaurus.json § "pending"`) — ⛔ jamais dans `thesaurus.org` (ENG-071).
**`* Out-of-scope`, `* Conflicts`** vivent dans le fichier entity (`workspace/<C>/thesaurus.org`).

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
  ],
  "pending": [
    {
      "term":             "<project term>",
      "proposed_mapping": "<type_element: X (proposé) ou Y ?>",
      "flag":             "_a_confirmer:N",
      "note":             "<raison de l'ambiguïté>",
      "source_import":    "<import-report-NNN>"
    }
  ]
}
```

> `pending` vit en Niveau 2 (projet JSON) — ⛔ jamais en Niveau 3 `thesaurus.org` (ENG-071).
> Résoudre via la webapp (thesaurus-assistant) → décision ingénieur → promotion Niveau 3 si pertinent.
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
itself (only `chorus-feed --enrich` writes `.kb-hash`, since only it modifies
`<slug>.org` files).

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

> **`$WORKFILES_DIR` — ENG-062 — initialized once after Scope `C` is resolved:**
> - `C = "global"` → `$WORKFILES_DIR = $SANDBOX/agent`
> - `C ≠ "global"` → `$WORKFILES_DIR = $SANDBOX/workspace/<C>`
>
> All `.import-inventory-*.org` and `.import-alignment-*.org` files (Phases 2, 3, 5,
> and Phase-5 cleanup) use **`$WORKFILES_DIR`** as their base directory — never
> `$SANDBOX/agent/` directly. For Scope=global the behaviour is unchanged; for
> Scope=`<client>` the files land in the client workspace alongside `thesaurus.org`
> and `project-import-*.json`, keeping `$SANDBOX/agent/` libre de toute donnée
> project-scoped.

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
> **⛔ ENG-073 — Hit Niveau 3 → écriture obligatoire dans `.thesaurus.json` Niveau 2 :**
> Quand un hit Niveau 3 (`workspace/<C>/thesaurus.org § Aliases`) résout un terme
> (steps 1–2), appliquer le mapping à la Frame JSON **ET** écrire l'entrée résolue dans
> `<projId>.thesaurus.json § aliases_type_element` (ou `aliases_slot_values`) avec
> `confidence: "confirmée"` et le `source_import` correspondant.
> ⛔ Ne **jamais** écrire de bloc custom dans le JSON projet pour tracer cette résolution
> (`thesaurus_resolution_applied` ou tout équivalent inventé) — le `.thesaurus.json`
> est l'unique emplacement canonique des décisions terminologiques.
> Raison : sans cette écriture Niveau 2, un re-import ultérieur ne retrouve pas le
> mapping dans le thésaurus projet et le re-classe `_a_confirmer`, perdant silencieusement
> la décision de l'ingénieur. (Incident : sandbox `08-ANSSI-PG-083-CENTRIC`, re-import
> 2026-11-13 — résolution appliquée en Niveau 3 mais absente du `.thesaurus.json`.)
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
>
> **⛔ ENG-074 — Annulation webapp d'une confirmation déjà figée dans un JSON projet :**
> La webapp (bouton ↩️ Annuler, `unconfirmThesaurusAlias`) peut remettre un terme en
> Pending alors qu'un JSON projet **déjà généré** (import ou re-import antérieur) a
> figé l'ancienne résolution en dur dans `elements[].type_element` ou
> `elements[].<slot>` — cette annulation ne modifie **jamais** le JSON projet
> existant (seul le thésaurus est touché). Ce JSON devient donc potentiellement
> **périmé** vis-à-vis de la nouvelle vérité thésaurus, sans qu'aucune marque ne
> l'indique dans le fichier lui-même. (Symétrique du bug ENG-073 : là où ENG-073
> traite une résolution insuffisamment propagée *vers* le Niveau 2, ENG-074 traite
> une annulation insuffisamment propagée *depuis* le Niveau 2 *vers* le JSON déjà
> généré.)
>
> **Détection obligatoire au début de Phase 3, pour tout terme repassé en Pending**
> (que ce soit via la webapp ou détecté à la lecture du thésaurus) : avant d'appliquer
> le lookup standard (step 5), vérifier si ce terme apparaît déjà dans le `_alignment_source`
> d'un élément du JSON existant lors d'un **re-import** (même `C`, même `projId`). Si oui :
> - Ne **jamais** conserver silencieusement l'ancienne valeur confirmée sur cette Frame.
> - Rouvrir la question `⚠️ _a_confirmer` pour cette Frame (re-exécuter le tier logic
>   ci-dessous — Obvious/Ambiguous/Unresolvable — comme pour un terme nouvellement vu),
>   même si un hit Pending step 4 existe déjà pour le même terme ailleurs dans l'inventaire.
> - Documenter explicitement dans `_import.gaps` ou l'alignment table que la Frame
>   a perdu sa résolution précédente suite à une annulation webapp (ne pas réutiliser
>   `_alignment_source` de l'ancienne résolution sans le mettre à jour).
>
> La webapp signale ce cas via `driftedElements` dans la réponse de
> `POST /thesaurus/unconfirm` (voir `chorus/thesaurus.js § _detectProjectJsonDrift`
> et bandeau "🔄 Ré-importer après thésaurus" dans l'onglet projet) — mais ce signal
> UI est best-effort (détection par correspondance texte sur `_alignment_source`,
> non garantie à 100%). La garantie réelle de cohérence vient de cette règle Phase 3 :
> tout re-import doit systématiquement re-vérifier la concordance JSON ↔ thésaurus,
> jamais seulement traiter les termes absents du JSON existant.

#### Thesaurus initialisation

If neither `$SANDBOX/agent/thesaurus/` nor a legacy `$SANDBOX/agent/thesaurus.org`
exists yet, the sharded layout is created automatically at the end of the first import
that produces at least one ✅ or ⚠️ alignment (Phase 6 — see below): `global.org` is
always created first; a `<C>.org` shard is created only if that import's Scope `C` is
not `global`. No manual creation is required.
