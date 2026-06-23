# Skill — chorus-import-project

> Déclencheur : `chorus-import-project <sandbox-name> <source…> [--out <fichier.json>] [--batch]`
> Agent : `architect`
>
> `<sandbox-name>` : sandbox contenant une KB produite par `chorus-feed`
> `<source…>`      : une ou plusieurs sources projet de l'ingénieur (voir modes ci-dessous)
>                    Formats acceptés : PDF, Word (.docx), Excel (.xlsx/.csv),
>                    texte brut, tableau collé dans le chat, chemin de répertoire
> `--out`          : nom du fichier JSON de sortie (mode fusion uniquement ;
>                    défaut : `projet-import-<NNN>.json`)
> `--batch`        : forcer le mode batch même si une seule source est donnée
>
> ### Modes d'invocation
>
> | Syntaxe | Mode | Comportement |
> |---|---|---|
> | `chorus-import-project sb fichier.pdf` | **Unitaire** | 1 source → 1 JSON (comportement historique) |
> | `chorus-import-project sb f1.pdf f2.xlsx f3.docx` | **Fusion** | N sources → 1 JSON fusionné (même projet, fichiers complémentaires) |
> | `chorus-import-project sb ./dossier/` | **Batch** | Répertoire → 1 JSON par fichier + rapport de synthèse |
> | `chorus-import-project sb *.pdf --batch` | **Batch** | Glob explicite → 1 JSON par fichier + rapport de synthèse |
>
> **Règle de détection automatique du mode :**
> - 1 argument source non-répertoire → Unitaire
> - N > 1 arguments sources (même format ou formats mixtes) → Fusion
> - 1 argument répertoire ou flag `--batch` présent → Batch
>
> **Responsabilité unique : aligner la terminologie projet de l'ingénieur
> sur les slots et types KB du sandbox, puis produire un fichier projet JSON valide.**
>
> Prérequis : `chorus-feed <sandbox-name>` exécuté au préalable (KB org présente).
>
> ⚠️ **Sources KB à utiliser — ordre strict :**
> 1. `$SANDBOX/eca/agents/index.org` → types de Frames, pipeline, namespace
> 2. `$SANDBOX/eca/agents/<slug>.org` → sections `Ontologie`, `Dictionnaire des slots`,
>    `Catalogue des Frames` (slots obligatoires, domaines de valeurs)
> 3. `$SANDBOX/eca/import-report-*.org` existants → décisions d'alignement précédentes
>
> ⛔ **Ne jamais lire** `Helpers.pm`, `Feed.pm`, `Agent/*.pm` pour déduire les slots.
> ⛔ **Ne jamais inventer** une valeur absente du document source — signaler le gap.

---

## Phase 0 — Acquisition des données sources

### Détection du mode et collecte des sources

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

### Phase 0-BATCH — Traitement en lot

Pour chaque fichier `f` dans `files` :
1. Extraire le texte brut (Phase 0B ci-dessous)
2. Exécuter les Phases 1–6 **de manière autonome** pour ce fichier
3. Nommer les sorties : `projet-import-<NNN>.json` et `import-report-<NNN>.org`
   (incrémenter NNN indépendamment pour chaque fichier)
4. À la fin du lot → produire le **rapport de synthèse batch** (voir Phase 6-BATCH)

> ⚠️ La Phase 1 (lecture KB) est exécutée **une seule fois** en début de batch
> et réutilisée pour tous les fichiers — le référentiel terminologique est commun.

### Phase 0-FUSION — Fusion multi-sources

Après extraction individuelle de chaque source :
1. Concaténer les blocs texte en les étiquetant par fichier source :
   ```
   === SOURCE: structure.pdf ===
   <texte extrait>

   === SOURCE: isolation.xlsx ===
   <texte extrait>
   ```
2. L'inventaire (Phase 2) traite l'ensemble comme une source unique
3. Conserver l'attribut `_source_fichier` dans chaque élément JSON pour traçabilité
4. **Gestion des conflits d'id** : si deux sources définissent un élément avec le même `id` :
   - Inclure les deux avec suffixe `_a` / `_b` sur le doublon
   - Ajouter `_conflit: 1` et `_conflit_source: ["fichier1", "fichier2"]`
   - Signaler le conflit dans le rapport d'import

### Cas A — Source inline (données collées dans le chat)

L'ingénieur colle directement un extrait de tableau, une liste d'éléments, ou un
texte descriptif. Traiter le contenu tel quel — passer directement à la Phase 1.

### Cas B — Source filesystem (fichiers sur disque)

Identifier le format et extraire le texte brut **avant** tout traitement sémantique.

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

> ⚠️ Si les outils d'extraction sont absents → demander à l'ingénieur de fournir
> le contenu copié-collé depuis son application (Cas A).
> Ne jamais bloquer le workflow pour un outil manquant — proposer l'alternative inline.

---

## Phase 1 — Lire la KB (terminologie canonique)

### 1.1 Index du pipeline

Lire `$SANDBOX/eca/agents/index.org` :
- Namespace + liste des agents (slug, pos)
- Dictionnaire global des slots (si présent dans l'index)

### 1.2 Terminologie par agent

Pour chaque agent, lire `$SANDBOX/eca/agents/<slug>.org` et extraire :

| Section KB | Ce qu'on en tire |
|---|---|
| `Ontologie` | Concepts du domaine, synonymes, relations (ex. "entrait" = poutre horizontale de ferme) |
| `Catalogue des Frames` | Types exacts (`type_element`), slots obligatoires par type |
| `Dictionnaire des slots` | Noms canoniques, types de valeurs, unités, domaines admis |

Construire un **référentiel terminologique** interne :
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

### 1.3 Décisions d'alignement précédentes

Si `$SANDBOX/eca/import-report-*.org` existe, lire le dernier rapport :
- Récupérer les mappings déjà validés → les réappliquer sans redemander
- Récupérer les questions en suspens → les reposer si les mêmes termes réapparaissent

---

## Phase 2 — Inventaire brut des éléments projet

Parcourir les données sources et produire un **inventaire brut** :
une liste non-interprétée de ce que l'ingénieur a fourni.

```
Ligne / Cellule source          Terme identifié      Valeurs associées
────────────────────────────────────────────────────────────────────────
"Poteau porteur 45×145 C24"    "poteau porteur"     dim=45×145, classe=C24
"h libre 2,5m, entraxe 40cm"  "h libre"            2.5m / "entraxe"=40cm
"Laine de verre λ035, e=20cm" "laine de verre"     λ=0.035, e=200mm
"panneau OSB 12mm, CE"         "panneau OSB"        ep=12mm, CE=oui
```

> **Règle :** ne pas mapper à ce stade — inventorier d'abord, aligner ensuite.
> Préserver le texte source original dans l'inventaire pour traçabilité.

---

## Phase 3 — Alignement terminologique

C'est la phase centrale. Pour chaque terme de l'inventaire brut, croiser avec
le référentiel KB (Phase 1.2) et produire un tableau d'alignement :

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

### Niveaux de confiance

| Symbole | Signification | Action |
|---|---|---|
| ✅ sûr | Correspondance directe ou quasi-directe avec la KB | Mapper sans demander |
| ⚠️ probable | Correspondance logique mais terme non exact | Proposer + demander confirmation |
| ❓ ambigu | Plusieurs mappings possibles ou terme inconnu KB | Bloquer + demander clarification |
| ⛔ gap | Slot obligatoire absent du document source | Signaler — ne pas inventer |
| ⬜ hors-périmètre | `type_element` absent de la KB de ce sandbox | Exclure du JSON — flag `_hors_perimetre: 1` + signaler dans le rapport |

> **Règle hors-périmètre :** un élément reçoit `⬜` si son `type_element` n'est
> reconnu par **aucun** `Catalogue des Frames` du sandbox cible. Il n'est pas
> bloquant — l'import continue. L'élément est exclu du JSON de sortie et listé
> dans la section `Éléments hors-périmètre` du rapport d'import.
>
> **Conséquence architecturale :** un projet multi-domaines (ex. structurel +
> thermique) doit être importé **une fois par sandbox cible** — chaque import
> ne retient que les types que ce sandbox connaît. `chorus-import-project` est
> l'outil de partition ; `run.pl` ne voit que les éléments qui le concernent.
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

### Transformations d'unités

Documenter explicitement toute conversion :

| Pattern source | Transformation | Slot KB |
|---|---|---|
| `2,5m` / `2.5m` / `250cm` | → `2.5` | `hauteur_libre_m` |
| `40cm` / `400mm` / `0,4m` | → `400` | `entraxe_mm` |
| `20cm` / `200mm` | → `200` | `epaisseur_mm` |
| `λ=0,035` / `λ035` / `laine 035` | → `"035"` | `classe_conductivite` |
| `45/145` / `45×145` / `45x145` | → `"45x145"` | `section_bois` |
| `C 24` / `classe C24` / `C24 EN338` | → `"C24"` | `classe_bois` |

### Résolution des ambiguïtés

Pour chaque terme ❓, présenter à l'ingénieur :
```
❓ "panneau contreventement" — plusieurs interprétations possibles :
   1. panneau_osb     (panneau OSB structurel §3.1)
   2. panneau_fibragglo (panneau de contreventement §3.2)
   Quel type correspond à votre document ?
```

**Ne pas continuer avant résolution des ❓ bloquants** (slots `type_element` ambigus).
Les ⚠️ peuvent être provisoirement acceptés avec un flag `_a_confirmer: 1`.

---

## Phase 4 — Identifier les gaps

Pour chaque élément, croiser les slots présents avec le `Catalogue des Frames` KB :

```
Type            Slot obligatoire    Présent ?   Source
──────────────────────────────────────────────────────────
montant_porteur classe_bois         ✅          "C24"
montant_porteur humidite_pct        ⛔ ABSENT   non mentionné
montant_porteur hauteur_libre_m     ✅          "h=2.5m"
```

### Traitement des gaps

| Type de gap | Action |
|---|---|
| Slot obligatoire absent | Demander à l'ingénieur — ne pas supposer |
| Slot optionnel absent | Omettre du JSON — le pipeline s'en passe |
| Valeur hors domaine (ex. `classe_bois: "C12"`) | Signaler — laisser l'ingénieur corriger |
| Élément entier non-mappable | Inclure avec `_incomplet: 1` — sera rejeté proprement par Feed |

---

## Phase 5 — Produire le JSON

### Mode Unitaire / Fusion — un seul JSON

Une fois tous les ❓ résolus et les gaps critiques comblés :

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

> **Convention `id`** : conserver l'identifiant du document source si disponible
> (ex. "Poteau P1", "IPE-01"), sinon générer `<TYPE_ABREV>-<NN>`.
> Traçabilité document ↔ JSON = priorité.
> En mode fusion, `_source_fichier` est toujours renseigné sur chaque élément.

### Mode Batch — un JSON par fichier

Chaque fichier produit son propre JSON nommé `projet-import-<NNN>.json`.
Le champ `_import.mode` vaut `"batch"`.
Pas de fusion inter-fichiers — chaque JSON est autonome et pipelinable indépendamment.

---

## Phase 6 — Produire le rapport d'import

Créer `$SANDBOX/eca/import-report-<NNN>.org` :

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

> Ce rapport est la **mémoire des décisions d'alignement** pour ce sandbox.
> Il est relu automatiquement lors du prochain `chorus-import-project` sur le même sandbox.

### Phase 6-BATCH — Rapport de synthèse (mode batch uniquement)

En plus des rapports individuels, créer `$SANDBOX/eca/import-batch-<NNN>.org` :

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

> **Termes nouveaux** : si un terme source n'était pas dans les rapports précédents
> ET qu'il a reçu un alignement ✅ sûr, il est candidat à être intégré dans la
> section `Dictionnaire` de la KB agent correspondant (via `chorus-feed` ou édition
> manuelle de l'org file).

---

## Phase 7 — Lancer le pipeline (optionnel)

Si l'ingénieur le demande explicitement, enchaîner avec `chorus-check` :

```bash
perl $SANDBOX/run.pl $SANDBOX/<projet-import-NNN.json>
```

Si `run.pl` n'existe pas encore → indiquer de lancer `chorus-check` d'abord.

---

## Séparation des responsabilités

| | `chorus-feed` | `chorus-import-project` | `chorus-create-project` | `chorus-check` |
|---|---|---|---|---|
| **Lit** | corpus normatif | docs projet ingénieur + KB org | KB org | KB org + YAML |
| **Produit** | KB org, YAML, Helpers.pm | `projet-import-*.json` + rapport `.org` | `projet-*.json` | Feed.pm, shells, Expert.pm, run.pl |
| **Source des seuils** | corpus | KB org uniquement | KB org uniquement | KB org |
| **Gaps** | n/a | signalés, jamais inventés | calculés depuis KB | n/a |
| **Ne lit jamais** | — | Helpers.pm, Feed.pm | Helpers.pm, Feed.pm | — |

---

## Principe architectural — granularité sandbox = granularité JSON

> **La granularité d'un sandbox définit la granularité du JSON projet qui lui est destiné.**

Un sandbox couvre un domaine normatif cohérent (ex. structurel, thermique, hygrométrie).
Un projet multi-domaines produit autant de JSONs d'import que de sandboxes cibles.
**`chorus-import-project` est l'outil de partition — pas `run.pl`.**

Les éléments hors-périmètre (⬜) sont exclus proprement à l'import ; `run.pl` et
`Feed.pm` ne reçoivent que les types qu'ils connaissent.

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

**Conséquence pour `Feed.pm`** (généré par `chorus-check`) :
Le template utilise `warn + next` au lieu de `die` sur un type inconnu,
comme filet de sécurité si un JSON mixte atteignait `run.pl` malgré tout.
La partition reste la responsabilité de `chorus-import-project`.
