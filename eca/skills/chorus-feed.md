# Skill — chorus-feed

> Déclencheur : `chorus-feed <sandbox-name> <corpus>`
> Agent : `architect`
>
> `<sandbox-name>` : nom du répertoire sandbox sous `$CHORUS/sandboxes/`
> `<corpus>` : fichier texte/PDF ou contenu inline fourni par l'utilisateur
>
> **Responsabilité unique : enrichir la connaissance.**
> Ce skill ne génère jamais de code d'infrastructure (Feed, Agent shell, Expert, run.pl).
> Il produit :
>   - Les fichiers KB org-mode par agent (`eca/agents/<slug>.org`)
>   - Les fichiers YAML de règles (`rules/<slug>/R<NN>-xxx.yml`)
>   - Les helpers Perl de connaissance métier (`lib/<Namespace>/Agent/<Slug>/Helpers.pm`)
>   - L'index du pipeline (`eca/agents/index.org`)
>
> Pour valider un projet sur la base de cette connaissance → utiliser `chorus-check`.

---

## 0. Chargements préalables

Charger : `chorus-engine.md` — référence moteur (Frame, Engine, fmatch, YAML DSL)

---

## Mode A — Initialisation (sandbox vide ou nouveau corpus)

Utilisé quand `<sandbox-name>` n'existe pas encore ou ne contient pas de KB.

### Phase 0 — Initialisation du sandbox

Créer l'arborescence :

```bash
SANDBOX="$CHORUS/sandboxes/<sandbox-name>"
mkdir -p "$SANDBOX/eca/agents"
mkdir -p "$SANDBOX/corpus"
mkdir -p "$SANDBOX/rules"
mkdir -p "$SANDBOX/lib"
```

Sauvegarder le corpus dans `corpus/001-<slug-source>.txt`
(convention : numéroté pour permettre l'enrichissement incrémental).

Créer `README.org` :

```org
#+TITLE: Sandbox <sandbox-name>
#+DATE: <date>
#+STATUS: draft

* Corpus
  | Num | Fichier                    | Source              | Date       |
  |-----+----------------------------+---------------------+------------|
  | 001 | corpus/001-<slug>.txt      | <origine>           | <date>     |

* Pipeline identifié
  (rempli en Phase 1)

* Statut des agents
  | Agent | KB | YAML | Helpers | Enrichissements |
  |-------+----+------+---------+-----------------|

* Notes de session
```

### Phase 1 — Analyse du corpus

**1.1 Identifier les spécialités**

Lire le corpus intégralement. Regrouper les règles par thématique cohérente.
Chaque groupe = un agent. Critères :
- règles portant sur les mêmes types de Frames
- même slots entrants/sortants
- ordonnables séquentiellement sans dépendance cyclique

Résultat : liste ordonnée d'agents (slug + intention + pos pipeline).

**1.2 Identifier les Frames du domaine**

Pour chaque concept persistant du corpus (≥ 2 slots, identité stable) → Frame.
Les calculs intermédiaires restent des slots, pas des Frames.

**1.3 Identifier le pipeline**

Ordre des agents par dépendance de données :
agent N pose le slot X → agent N+1 consomme X → N+1 après N.

### Phase 2 — Stratégie de ciblage (_SCOPE)

**Ne pas sauter cette phase.**

**2.1 Rappel**

`_SCOPE` → produit cartésien. `fmatch(slot => 'X')` retourne tous les Frames
portant X. Le `filtre` réduit **avant** la boucle combinatoire.
Un Frame est invisible pour un agent s'il ne porte pas le slot ciblé.

**2.2 Règle A vs B**

```
Volume Frames < 50  ET  slots discriminants bien distribués → Stratégie A
Sinon                                                        → Stratégie B
```
Doute → préférer B (toujours plus efficace).

**2.3 Stratégie B — slot de présence**
- Nommer : `besoin_<slug_underscore>` (convention)
- Posé par : feed initial (agent 1) ou agent N-1 dans son EFFET (agents suivants)

**2.4 Stratégie A — slot discriminant**
- Identifier le slot commun + valeur de filtre
- Si `fmatch` retourne > 100 Frames avant `grep` → reconsidérer B

### Phase 3 — Remplir la KB par agent

Créer `$SANDBOX/eca/agents/<slug>.org` depuis `_template.org`.
Ordre de remplissage obligatoire :

1. En-tête (`#+AGENT`, `#+PIPELINE_POS`, `#+RULES_DIR`)
2. Domaine
3. **Slots de ciblage** — stratégie + tableau + contrat pré-population
4. Pipeline E/S (slots entrants / sortants)
5. Ontologie
6. Catalogue des Frames
7. Dictionnaire des slots
8. Catalogue des règles
9. **Helpers Perl** — signatures + corps complet du code métier
10. Contraintes & Pitfalls

> **Règle helpers :** un helper appartient à `chorus-feed` (et donc à la KB)
> s'il encode de la **connaissance extraite du corpus** : table de valeurs,
> calcul normalisé, seuil réglementaire. Il n'appartient PAS à `chorus-feed`
> s'il relève de l'infrastructure (accès fichier, parsing, réseau).

Points de vigilance :
- Idempotence : `EXCEPTION: defined $var->{<slot_pose>}` sur toute règle qui pose un slot
- Terminaison : documenter dans quelle règle et sous quelle condition `solved()` est appelé
- Nommage : `R<NN>-<slug>.yml` — ordre alpha = ordre de chargement

### Phase 4 — Créer `eca/agents/index.org`

```org
#+TITLE: Pipeline — <sandbox-name>

* Pipeline global
  | Pos | Agent (module Perl)     | Slug    | KB                 | Statut |
  |-----+-------------------------+---------+--------------------+--------|
  |   1 | <Namespace>::Agent::Xxx | <slug>  | eca/agents/x.org   | draft  |

* Cohérence du pipeline
  - Slot ciblage agent 1 : posé par → feed initial
  - Slot ciblage agent 2 : posé par → agent 1 (R<NN>-xxx.yml, EFFET)
  - Agent terminaison    : <Nom> pos <N> → règle <Rxx> → solved()

* Corpus intégré
  | Num | Fichier              | Agents impactés     |
  |-----+----------------------+---------------------|
  | 001 | corpus/001-xxx.txt   | tous (initialisation)|
```

### Phase 5 — Générer les fichiers YAML

Pour chaque règle du `Catalogue des règles` de chaque KB :

```yaml
REGLE: <nom-kebab-case>         # obligatoire — devient _ID (déduplication)
TERMINAL: solved                 # optionnel — 'solved' ou 'failed'
                                 # quand la règle tire ET TERMINAL présent →
                                 # le moteur appelle solved()/failed() automatiquement
PREMISSES:                       # optionnel — slots prérequis pour reorder()
  - <slot-prerequis>             # utilisé par $agent->reorder(\&fn) pour trier
  - <autre-slot>                 # les règles par pertinence dynamiquement
CHERCHER:                        # obligatoire — définit _SCOPE
  <var>:
    attribut: <slot_ciblage>
    filtre: '<expression si stratégie A>'
EXCEPTION: defined $<var>->{<slot_pose>}   # idempotence — return if
CONDITION: '<garde optionnelle>'            # return unless
EFFET: |
  # Contrôles de flux disponibles dans EFFET (appelables sur $agent capturé) :
  #   $agent->cut()        → sort du scope courant → règle suivante (même agent)
  #   $agent->last()       → sort de la boucle de règles → agent suivant
  #   $agent->replay()     → redémarre depuis la 1re règle de cet agent
  #   $agent->replay_all() → redémarre depuis le 1er agent (Expert)
  #   $agent->solved()     → BOARD->{SOLVED} = 'Y' → arrêt immédiat
  #   $agent->failed()     → BOARD->{FAILED} = 'Y' → arrêt immédiat
  <code Perl>
  1
```

**Quand utiliser `TERMINAL` vs `solved()` dans EFFET :**
- `TERMINAL: solved` — la règle se déclenche sur UN Frame et cela suffit à terminer
- `$agent->solved()` dans EFFET — nécessite un test global préalable
  (ex. vérifier que TOUS les Frames ont leur statut avant de terminer)

**Quand documenter `PREMISSES` :**
Toujours documenter si l'agent est susceptible d'utiliser `reorder()` pour
optimiser l'ordre des règles en cours d'exécution. Les PREMISSES déclarent
les slots dont la règle a besoin — le code de tri les consulte via `$rule->_PREMISSES`.

Checklist YAML :
- [ ] Noms de slots = Dictionnaire des slots de la KB
- [ ] Chaque règle qui pose un slot a son `EXCEPTION` idempotence
- [ ] `EFFET` termine par `1` ou expression truthy
- [ ] Utiliser `|` (block scalar) pour les `EFFET` multi-lignes — jamais `>`
- [ ] Fichiers nommés `R<NN>-<slug>.yml` (ordre alpha = ordre de chargement)
- [ ] Règle de terminaison : `TERMINAL: solved` ou `$agent->solved()` — une seule voie par agent
- [ ] Si `PREMISSES` présent : cohérent avec le `Dictionnaire des slots` de la KB

### Phase 5.5 — Générer les Helpers Perl

Pour chaque agent dont la KB contient une section `Helpers Perl` non vide,
créer `$SANDBOX/lib/<Namespace>/Agent/<Slug>/Helpers.pm`.

**Critère d'inclusion d'un helper ici :**
Le code encode de la connaissance extraite du corpus :
- table de valeurs normatives (ex. résistances par classe NF EN 338)
- calcul réglementaire (ex. formule EC5 §6.3)
- seuil ou plage issue d'un article de norme

**Ce qui n'est PAS un helper de connaissance** (→ reste dans `chorus-check`) :
- parsing de fichier, accès base de données, appel réseau
- logique d'orchestration (boucles sur agents, gestion d'erreurs)

#### Template `Helpers.pm`

```perl
package <Namespace>::Agent::<Slug>::Helpers;

use strict;
use warnings;
use Exporter 'import';

# Liste exhaustive des helpers exportés — chorus-check les importe tous
our @EXPORT_OK = qw(
    <helper1>
    <helper2>
);

# -------------------------------------------------------
# <helper1>
# Source corpus : §<N> — <titre section>
# -------------------------------------------------------
# Signature : <helper1>(<args>) → <type retour>
# Appelé par : R<NN>-<slug>.yml (EFFET)
sub <helper1> {
    my (<args>) = @_;
    # <corps extrait du corpus>
}

# -------------------------------------------------------
# <helper2>
# Source corpus : §<N> — <titre section>
# -------------------------------------------------------
sub <helper2> {
    my (<args>) = @_;
    # <corps extrait du corpus>
}

1;
```

#### Règles de génération

- **Un fichier `Helpers.pm` par agent** — même s'il n'y a qu'un seul helper.
- **`@EXPORT_OK` exhaustif** — tous les helpers listés, aucun oublié.
  `chorus-check` fait un `use ... qw(...)` complet pour les rendre disponibles
  dans le namespace avant `loadRules()`.
- **Commentaire `Source corpus`** sur chaque helper — traçabilité vers la norme.
- Si un helper est **partagé entre plusieurs agents** → le placer dans
  `lib/<Namespace>/Helpers/Shared.pm` et le documenter dans les KB des
  deux agents concernés.
- **Pas d'effet de bord** dans un helper : pas d'écriture de slots, pas d'appel
  à `$SELF`, pas de `fmatch`. Les helpers calculent et retournent une valeur —
  c'est le YAML qui appelle `$frame->set()`.
- **Pitfall `$SELF`** : dans un `_AFTER` hook ou une closure qui appelle `set()`
  sur un autre Frame, capturer `$SELF` **avant** tout appel à `set()` :
  ```perl
  # FAUX — $SELF sera écrasé par le set() interne
  _AFTER => sub { $other->set('x', $SELF->val) }
  # CORRECT
  _AFTER => sub { my $ctx = $SELF; $other->set('x', $ctx->val) }
  ```
  Ce pitfall concerne les helpers appelés depuis un `_AFTER` ou un slot procédural —
  pas les helpers purs (calcul → retour valeur).

#### Checklist Helpers

- [ ] Chaque helper référencé dans un EFFET YAML a son implémentation dans `Helpers.pm`
- [ ] `@EXPORT_OK` couvre tous les helpers du fichier
- [ ] Chaque helper a son commentaire `Source corpus`
- [ ] Aucun effet de bord (pas de `set`, pas de `fmatch`, pas d'I/O)
- [ ] Les helpers partagés sont dans `Shared.pm` et documentés dans les deux KB
- [ ] Tout helper appelé depuis un `_AFTER` ou slot procédural : capturer `$SELF`
      avant tout `set()` sur un autre Frame (`my $ctx = $SELF; ...`)

### Phase 6 — Clôture

Mettre à jour `README.org` :
- Section `Statut des agents` : KB ✓, YAML ✓, Helpers ✓ (ou `-` si aucun)
- Section `Pipeline identifié` : tableau complet

---

## Mode B — Enrichissement incrémental

Utilisé quand `<sandbox-name>` existe déjà et contient une KB.
Déclenché quand le corpus fourni est **un nouveau fragment** (nouvelle section
de norme, correction, extension de domaine).

### Phase B0 — Lire la KB existante

1. Lire `eca/agents/index.org` → pipeline actuel, agents connus
2. Lire chaque `eca/agents/<slug>.org` → Dictionnaire des slots, Catalogue des règles
3. Lire les fichiers YAML existants → règles déjà codifiées

### Phase B1 — Analyser le nouveau corpus

Classifier chaque règle/prescription du nouveau corpus en **3 catégories** :

| Catégorie | Critère | Action |
|---|---|---|
| **Affinement** | Porte sur un Frame et des slots déjà connus | Ajouter règle à un agent existant |
| **Extension** | Porte sur de nouveaux slots d'un Frame connu | Étendre KB agent existant + nouvelles règles YAML |
| **Nouveau domaine** | Porte sur des Frames ou concepts absents de la KB | Créer un nouvel agent |

### Phase B2 — Sauvegarder le nouveau corpus

Numéroter en incrémentant : `corpus/002-<slug-source>.txt`, `003-...`
Mettre à jour la table `Corpus intégré` dans `index.org`.

### Phase B3 — Appliquer les modifications

**Cas Affinement :**
- Ouvrir `eca/agents/<slug>.org`
- Ajouter la règle dans `Catalogue des règles`
- Mettre à jour `Dictionnaire des slots` si nouveaux slots
- Générer le fichier YAML correspondant dans `rules/<slug>/`
- Si la règle nécessite un helper : ajouter le helper dans `Helpers.pm`
  et mettre à jour `@EXPORT_OK`
- Vérifier l'idempotence et l'ordre des fichiers R<NN>

**Cas Extension :**
- Mettre à jour `Catalogue des Frames` (nouveaux slots)
- Mettre à jour `Dictionnaire des slots`
- Ajouter les règles dans `Catalogue des règles`
- Générer les nouveaux fichiers YAML
- Ajouter les helpers nécessaires dans `Helpers.pm`
- Vérifier que les nouveaux slots n'entrent pas en conflit avec ceux
  des autres agents (Dictionnaire des slots de l'index)

**Cas Nouveau domaine :**
- Appliquer le Mode A (Phases 1 à 5.5) sur le fragment uniquement
- Déterminer la position du nouvel agent dans le pipeline :
  - Lit-il un slot posé par un agent existant ? → après lui
  - Pose-t-il un slot consommé par un agent existant ? → avant lui
- Mettre à jour `index.org` : insérer le nouvel agent à la bonne position
- ⚠ Vérifier que l'insertion ne rompt pas la chaîne des slots de ciblage

### Phase B4 — Clôture enrichissement

Mettre à jour `README.org` :
- Ajouter la ligne dans `Corpus` (numéro + fichier + source + date)
- Mettre à jour `Statut des agents` (KB, YAML, Helpers — nouveaux ou enrichis)
- Incrémenter le compteur d'enrichissements de chaque agent modifié

---

## Référence rapide — conventions de nommage

| Artefact          | Convention                              | Exemple                           |
|-------------------|-----------------------------------------|-----------------------------------|
| Sandbox           | `test-<NNN>` ou `test-<slug>`           | `test-01`, `test-norme-ec5`       |
| Slug agent        | kebab-case                              | `conformite-fiscale`              |
| Fichier KB        | `<slug>.org`                            | `conformite-fiscale.org`          |
| Répertoire YAML   | `rules/<slug>/`                         | `rules/conformite-fiscale/`       |
| Fichiers YAML     | `R<NN>-<slug-regle>.yml`                | `R01-verif-montant.yml`           |
| Helpers agent     | `lib/<Namespace>/Agent/<Slug>/Helpers.pm` | `lib/CB/Agent/Ossature/Helpers.pm` |
| Helpers partagés  | `lib/<Namespace>/Helpers/Shared.pm`     | `lib/CB/Helpers/Shared.pm`        |
| Corpus initial    | `corpus/001-<slug-source>.txt`          | `corpus/001-dtu-31-2.txt`         |
| Corpus enrichiss. | `corpus/<NNN>-<slug>.txt`               | `corpus/002-ec5-sect3.txt`        |
| Namespace projet  | CamelCase, défini au démarrage          | `MonProjet`                       |

> ⚠ `chorus-feed` ne génère jamais : `Feed.pm`, module Agent shell (`build()`),
> `Expert.pm`, `run.pl`. Ces artefacts sont de la responsabilité exclusive de `chorus-check`.
