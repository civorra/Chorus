# Les commandes `chorus-*` — Référence du workflow ECA

Les cinq commandes `chorus-*` forment un pipeline complet pour transformer un
corpus normatif (PDF, texte, Word, Excel) en un moteur d'inférence Perl
opérationnel qui valide des projets réels.

Ce sont des **commandes ECA** — pas des modules Perl ni des scripts shell. Chacune
est un skill chargé par ECA et exécuté de façon interactive dans l'environnement
de développement.

**ECA n'est pas une dépendance d'exécution.** Le pipeline Perl généré par la
chaîne tourne entièrement de façon autonome, sur n'importe quelle machine avec
Perl installé, sans ECA et sans connexion réseau.

**ECA est une dépendance de projet.** Pour adapter un sandbox à un nouveau
projet — aligner les documents d'ingénieur avec les slots de la KB et produire
un fichier JSON projet valide — il faut `chorus-create-project` ou
`chorus-import-project`, deux skills ECA. Le LLM lit la KB et gère l'écart de
terminologie qu'aucun script statique ne peut couvrir de façon générique. ECA
est aussi nécessaire lorsque le corpus normatif change.

---

## Le pipeline complet en un coup d'œil

```
                      ┌─────────────────────────────────┐
                      │  Corpus normatif (PDF, texte…)  │
                      └──────────────┬──────────────────┘
                                     │
                          chorus-pdf  (si PDF)
                                     │
                                     ▼
                      ┌─────────────────────────────────┐
                      │  corpus/<NNN>-<slug>-text.txt   │
                      │  corpus/<NNN>-<slug>-vision.md  │
                      └──────────────┬──────────────────┘
                                     │
                          chorus-feed
                                     │
                                     ▼
                      ┌─────────────────────────────────┐
                      │  eca/agents/<slug>.org  (KB)    │
                      │  rules/<slug>/R<NN>-xxx.yml     │
                      │  lib/…/Agent/<Slug>/Helpers.pm  │
                      └──────────────┬──────────────────┘
                                     │  ← l'expert du domaine relit, corrige
                                     │
                          chorus-check
                                     │
                                     ▼
                      ┌─────────────────────────────────┐
                      │  Feed.pm · Agent/*.pm           │
                      │  Expert.pm · run.pl             │
                      └──────────────┬──────────────────┘
                                     │
                         perl run.pl projet.json
                                     │
                                     ▼
                      ✅ CONFORME / ❌ NON_CONFORME
                         avec motif, par élément, par agent
```

Le fichier projet peut être écrit à la main, généré depuis la KB avec
`chorus-create-project`, ou aligné depuis des documents d'ingénieur avec
`chorus-import-project`.

---

## `chorus-pdf` — Extraire un corpus PDF

```
chorus-pdf <sandbox-name> <fichier.pdf> [--out <slug>] [--auto] [--images] [--batch]
```

**Responsabilité unique :** produire un fichier texte enrichi depuis un PDF.
Les outils PDF classiques suppriment silencieusement les tableaux normatifs rendus
en images, les mises en page multi-colonnes et les annotations de figures.
`chorus-pdf` les récupère.

### Modes d'extraction

| Mode | Flag | Moteur | Clé API | Sortie |
|---|---|---|---|---|
| **Texte** (défaut) | *(aucun)* | `pdfminer.six` | ❌ non requise | `<slug>-text.txt` |
| **Auto** | `--auto` | pdfminer (pages texte) + vision LLM (pages figures) | ✅ | `<slug>-vision.md` |
| **Images** | `--images` | `pdftoppm` 150 DPI + vision LLM sur toutes les pages | ✅ | `<slug>-vision.md` |

**Choisir un mode :**

```
Pas de clé API → mode texte (défaut)
Clé API disponible, document mixte (surtout texte + quelques figures) → --auto  ← recommandé
Clé API disponible, PDF surtout composé de schémas ou scanné → --images
```

`--auto` classifie d'abord chaque page (pdfminer sur les pages texte, vision sur
les pages avec figures), minimisant les appels API aux pages qui en ont réellement
besoin.

### Sortie

`corpus/<NNN>-<slug>-text.txt` ou `corpus/<NNN>-<slug>-vision.md`
(numéroté en séquence avec les fichiers corpus existants)

### Prérequis

```bash
pip install pdfminer.six pypdf
sudo apt install poppler-utils          # pour --auto et --images
export ANTHROPIC_API_KEY="sk-ant-..."   # pour --auto et --images
```

### Étape suivante

```
chorus-feed <sandbox-name> corpus/<NNN>-<slug>-text.txt
            (ou : corpus/<NNN>-<slug>-vision.md)
```

---

## `chorus-feed` — Construire la base de connaissance

```
chorus-feed <sandbox-name> <corpus> [--enrich]
```

**Responsabilité unique :** extraire la connaissance d'un corpus et l'écrire dans
des fichiers KB structurés. Ne génère **pas** d'infrastructure Perl.

`<corpus>` doit être un fichier texte (`.txt`) ou Markdown (`.md`) — jamais un PDF.
Si un PDF est fourni, `chorus-feed` s'arrête et suggère d'exécuter `chorus-pdf`
d'abord.

### Deux modes

**Mode A — Initialisation** (défaut, sans flag)

Utilisé pour un nouveau sandbox ou un nouveau départ. Crée la structure complète :

```
<sandbox-name>/
  corpus/001-<slug>.txt          ← le corpus
  eca/agents/<slug>.org          ← KB par agent (ontologie, slots, règles, helpers)
  eca/agents/index.org           ← index du pipeline
  rules/<slug>/R<NN>-xxx.yml     ← règles d'inférence YAML
  lib/…/Agent/<Slug>/Helpers.pm  ← tables normatives (extraites du corpus)
  README.org
```

Ce qu'ECA produit par agent :
- **Ontologie des slots** — les types de Frame et le dictionnaire des slots du domaine
- **Règles YAML** — un fichier par règle, nommé `R<NN>-<slug>.yml` (chargé par ordre alphabétique)
- **`Helpers.pm`** — tables de lookup normatives et calculs, annotés avec leur source
  corpus (`# §4.2 EC5 — Résistance en flexion par classe de bois`)

**Mode B — Enrichissement incrémental** (`--enrich` requis)

Utilisé quand le sandbox contient déjà une KB et qu'un nouveau corpus normatif
est arrivé. ECA lit la KB existante, classifie chaque nouvelle règle en
*raffinement*, *extension* ou *nouveau domaine*, et applique des modifications
ciblées.

```
chorus-feed <sandbox-name> nouveau-corpus.txt --enrich
```

### Ce que `chorus-feed` ne fait PAS

Il ne génère jamais `Feed.pm`, `Agent/*.pm`, `Expert.pm` ni `run.pl`.
Ces fichiers sont la responsabilité de `chorus-check`.

### Décisions de conception intégrées dans la KB

- **Stratégie de ciblage** — comment le `_SCOPE` de chaque agent trouve ses Frames
  (`fmatch` + slot de présence pour les grands volumes ; slot discriminant + filtre pour les petits)
- **Idempotence** — chaque règle YAML qui écrit un slot porte
  `EXCEPTION: defined $var->{slot}` pour éviter les re-déclenchements
- **Calibrage de `_MAX_CYCLES`** — documenté par agent, calibré sur
  `N_frames × N_règles × N_agents × 10`
- **Traçabilité normative** — chaque seuil dans `Helpers.pm` est annoté avec
  sa référence corpus

### Étape suivante

```
chorus-check <sandbox-name> projet.json
```

Ou, pour relire ce qui a été généré avant d'exécuter :
```
# Ouvrir la KB dans l'éditeur
eca/agents/<slug>.org
```

---

## `chorus-check` — Générer l'infrastructure et exécuter

```
chorus-check <sandbox-name> <fichier-projet.json>
```

**Responsabilité unique :** lire la KB, générer l'infrastructure Perl, exécuter
le pipeline contre le fichier projet et produire un rapport de conformité.

### Régénération intelligente

`chorus-check` conserve un hash des fichiers KB (`eca/.kb-hash`). À chaque appel :

- **KB inchangée** → saute toute la génération, exécute `perl run.pl` directement (chemin rapide)
- **KB modifiée** (après un `chorus-feed --enrich`) → régénère l'infrastructure, puis exécute
- **Pas encore d'infrastructure** → génère depuis zéro

Cela signifie qu'exécuter `chorus-check` deux fois sur le même sandbox avec
des fichiers projet différents ne coûte presque rien au deuxième appel.

### Ce qui est généré

| Fichier | Rôle |
|---|---|
| `lib/<NS>/Feed.pm` | Charge le JSON projet, crée les Frames, positionne les slots de ciblage |
| `lib/<NS>/Agent/<Slug>.pm` | Shell de chaque agent : importe les Helpers, charge les règles YAML |
| `lib/<NS>/Expert.pm` | Câble tous les agents, fixe `_MAX_CYCLES`, enregistre auprès de l'Expert |
| `run.pl` | Point d'entrée : `perl run.pl projet.json` |

Le code généré est du **Perl pur** — pas de dépendance ECA, pas de LLM, pas de réseau.
Il tourne sur n'importe quelle machine avec Perl et les modules CPAN installés.

### Sortie

Un rapport de conformité structuré, par élément et par agent :

```
✅ ÉLÉMENT poteau-bois-01 — CONFORME
   [qualifier-materiau] classe : C24 ✓
   [verifier-geometrie] élancement : 45 ≤ 60 ✓
   [verifier-feu]       REI 60 atteint ✓

❌ ÉLÉMENT poteau-bois-03 — NON_CONFORME
   [qualifier-materiau] teneur en humidité : 22% > 18% max (EC5 §3.3)
   [verifier-thermique] pare-vapeur : MANQUANT
```

### Étape suivante

```
# Relancer avec un autre projet (pas de régénération) :
perl run.pl autre-projet.json

# Mettre à jour le corpus et régénérer :
chorus-feed <sandbox-name> nouvel-addendum.txt --enrich
chorus-check <sandbox-name> projet.json
```

---

## `chorus-create-project` — Générer un JSON projet depuis la KB

```
chorus-create-project <sandbox-name> <fichier-sortie.json>
```

**Responsabilité unique :** lire la KB du sandbox et générer un fichier JSON
projet valide, peuplé d'éléments conformes ET non-conformes qui explorent la
variété du domaine.

Utile pour :
- **Tester** le pipeline de bout en bout avant qu'un vrai projet soit disponible
- **Démontrer** l'étendue des vérifications effectuées par le moteur
- **Amorcer** un modèle de projet qu'un ingénieur pourra remplir

### Ce qu'ECA lit

1. `eca/agents/index.org` — types de Frame, pipeline, namespace
2. `eca/agents/<slug>.org` — slots obligatoires, seuils, domaines de valeurs valides
3. Tout `projet-*.json` existant dans le sandbox — format de référence

> ⚠️ `chorus-create-project` ne lit jamais `Helpers.pm`, `Feed.pm` ni aucun
> fichier Perl généré. Les fichiers org KB sont toujours la source canonique.

### Sortie

Un fichier JSON avec :
- Un ensemble représentatif d'éléments projet (un par type de Frame, avec variations)
- Des cas conformes explicites (tous les seuils respectés)
- Des cas non-conformes explicites (une violation de règle par élément défaillant)
- Des commentaires indiquant quelle règle chaque cas défaillant est conçu à déclencher

### Étape suivante

```
chorus-check <sandbox-name> <fichier-sortie.json>
```

---

## `chorus-import-project` — Aligner des documents d'ingénieur avec la KB

```
chorus-import-project <sandbox-name> <source…> [--out <fichier.json>] [--batch]
```

**Responsabilité unique :** lire un document projet produit par un ingénieur
(PDF, Word, Excel, texte, tableau collé dans le chat) et aligner sa terminologie
avec les slots et types de la KB du sandbox, en produisant un fichier JSON
projet valide.

Cette commande comble le fossé entre la façon dont les ingénieurs décrivent un
projet (terminologie libre, jargon métier, tableaux informels) et les noms de
slots et domaines de valeurs exacts qu'attend le pipeline Chorus.

### Trois modes d'invocation

| Syntaxe | Mode | Sortie |
|---|---|---|
| `chorus-import-project sb fichier.pdf` | **Unitaire** | 1 JSON |
| `chorus-import-project sb f1.pdf f2.xlsx f3.docx` | **Fusion** | 1 JSON fusionné (même projet, fichiers complémentaires) |
| `chorus-import-project sb ./dossier/` ou `--batch` | **Batch** | 1 JSON par fichier + rapport de synthèse |

**Le mode est détecté automatiquement** en fonction du nombre et du type des
arguments sources.

### Ce qu'ECA lit

1. `eca/agents/index.org` — types de Frame, pipeline, namespace
2. `eca/agents/<slug>.org` — noms de slots, domaines de valeurs, obligatoires/optionnels
3. Tout `eca/import-report-*.org` précédent — décisions d'alignement antérieures (pour la cohérence)

### Ce qu'ECA produit

- `projet-import-<NNN>.json` — le JSON projet aligné
- `eca/import-report-<NNN>.org` — rapport d'alignement : correspondances de termes, lacunes, ambiguïtés

Les lacunes (valeurs absentes du document source) sont signalées mais jamais inventées.

### Étape suivante

```
# Relire le rapport d'import avant d'exécuter :
eca/import-report-<NNN>.org

# Puis valider :
chorus-check <sandbox-name> projet-import-<NNN>.json
```

---

## Workflow complet — de bout en bout

### Démarrer depuis un corpus PDF

```bash
# 1. Extraire le corpus (--auto recommandé pour les normes techniques)
chorus-pdf mon-sandbox corpus/norme.pdf --auto
#   → corpus/001-norme-vision.md

# 2. Construire la base de connaissance
chorus-feed mon-sandbox corpus/001-norme-vision.md
#   → eca/agents/*.org, rules/**/*.yml, lib/.../Helpers.pm
#   ← l'expert du domaine relit et corrige eca/agents/*.org

# 3. Générer l'infrastructure et exécuter
chorus-check mon-sandbox projet.json
#   → Feed.pm, Agent/*.pm, Expert.pm, run.pl
#   → rapport de conformité
```

### Démarrer depuis un document d'ingénieur

```bash
# Générer ou importer un fichier projet
chorus-create-project mon-sandbox projet-demo.json   # générer depuis la KB
chorus-import-project mon-sandbox notes-ingenieur.pdf # aligner depuis le document

# Valider
chorus-check mon-sandbox projet-demo.json
```

### Mettre à jour quand la norme change

```bash
chorus-feed mon-sandbox nouvel-addendum.txt --enrich
chorus-check mon-sandbox projet.json     # régénère uniquement ce qui a changé
```

---

## Ce qui tourne sans ECA

Une fois que `chorus-check` a généré l'infrastructure, **l'exécution est
entièrement autonome** — sans ECA, sans LLM, sans réseau :

```bash
# Sur n'importe quelle machine avec Perl et les modules CPAN requis :
perl run.pl projet.json

# Relancer avec un autre projet (pas de régénération) :
perl run.pl autre-projet.json
```

**Adapter un nouveau projet requiert ECA.** Un JSON projet peut en principe
être écrit à la main, mais `chorus-create-project` et `chorus-import-project`
sont le chemin pratique : ils lisent la KB et gèrent l'écart entre la
terminologie de l'ingénieur et les noms de slots et domaines de valeurs exacts
qu'attend le pipeline. ECA est aussi nécessaire lorsque le corpus normatif
change (`chorus-feed --enrich` suivi de `chorus-check`).

---

## Prérequis techniques

### Perl (exécution)

```bash
cpanm Chorus::Engine    # moteur d'inférence
cpanm YAML              # chargement des règles YAML
```

### Python (extraction corpus — chorus-pdf uniquement)

```bash
pip install pdfminer.six pypdf   # texte et classification des pages
sudo apt install poppler-utils   # pdftoppm (modes --auto et --images)
export ANTHROPIC_API_KEY="sk-ant-..."   # vision LLM (--auto et --images)
```

### Explorer le sandbox sans ECA

Les sandboxes `examples/sandboxes/cob-compliance_fr` et `cob-compliance_en`
contiennent la sortie complète de la chaîne — corpus, KB org, règles YAML,
infrastructure Perl. Lancer `perl run.pl project-demo.json` montre le résultat
en direct avec le JSON projet pré-construit inclus dans le sandbox. Pour
adapter un nouveau projet, ECA est requis.

---

## Référence rapide

| Commande | Entrée | Sortie | Prérequis |
|---|---|---|---|
| `chorus-pdf` | Fichier PDF | `corpus/<NNN>-<slug>-text.txt` ou `-vision.md` | `pdfminer.six` ; clé API pour `--auto`/`--images` |
| `chorus-feed` | Corpus `.txt` ou `.md` | `eca/agents/*.org`, règles YAML, `Helpers.pm` | — |
| `chorus-check` | JSON projet | `Feed.pm`, `Agent/*.pm`, `Expert.pm`, `run.pl` + rapport | `chorus-feed` exécuté au préalable |
| `chorus-create-project` | *(KB uniquement)* | JSON projet (éléments conformes + non-conformes) | `chorus-feed` exécuté au préalable |
| `chorus-import-project` | Document d'ingénieur | JSON projet aligné + rapport d'import | `chorus-feed` exécuté au préalable |

---

## Pour aller plus loin

- [`01-intro.md`](01-intro.md) — concepts Chorus, modèle Frame, moteur d'inférence, DSL YAML
- [`02-eca.md`](02-eca.md) — positionnement LLM vs Chorus, pourquoi la chaîne fonctionne
- [`03-applications.md`](03-applications.md) — analyse par domaine, temps d'onboarding
- `eca/skills/chorus-pdf.md` — référence complète du skill `chorus-pdf`
- `eca/skills/chorus-feed.md` — référence complète du skill `chorus-feed`
- `eca/skills/chorus-check.md` — référence complète du skill `chorus-check`
- `eca/skills/chorus-create-project.md` — référence complète du skill `chorus-create-project`
- `eca/skills/chorus-import-project.md` — référence complète du skill `chorus-import-project`
