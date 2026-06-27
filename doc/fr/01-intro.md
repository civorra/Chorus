# Introduction à Chorus

## Qu'est-ce que Chorus ?

**Chorus** est un moteur d'inférence écrit en Perl pur. Il repose sur trois
concepts fondamentaux qui s'emboîtent : une **mémoire de travail** peuplée de
frames, un **cycle d'inférence** qui applique des règles en boucle jusqu'au
point fixe, et une **orchestration multi-agents** qui décompose les problèmes
complexes en spécialités indépendantes.

**La mémoire de travail** est constituée de `Chorus::Frame` — des objets Perl
dont les propriétés (les *slots*) représentent la connaissance du domaine, dans
la lignée du modèle slots / défauts / attachements procéduraux introduit par
Minsky (1974). Tous les frames sont indexés dans un registre global ; la fonction
`fmatch()` permet de les interroger en temps constant. C'est sur cette mémoire que
portent toutes les règles.

**Le cycle d'inférence** est assuré par `Chorus::Engine`. Un agent contient un
ensemble de règles ; chaque règle déclare les frames sur lesquels elle s'applique
(`_SCOPE`) et l'effet qu'elle produit (`_APPLY`). Le moteur déclenche les règles
en boucle tant qu'au moins l'une d'elles a produit un effet — il s'arrête au
point fixe, quand rien ne change plus, ou dès qu'un but est atteint. Les règles
peuvent être écrites en Perl ou chargées depuis des fichiers YAML.

**L'orchestration** est assurée par `Chorus::Expert`. Plusieurs agents
spécialisés sont enregistrés et partagent un tableau de bord commun (`BOARD`).
L'Expert les fait coopérer en boucle jusqu'à ce que l'un d'eux déclare le
problème résolu. Chaque agent ignore les autres et ne traite que son périmètre ;
c'est leur enchaînement qui produit le résultat global.

```
Chorus::Expert      coordonne les agents, détecte la fin
  └─ Chorus::Engine   un agent = un ensemble de règles + boucle d'inférence
       └─ Chorus::Frame   la mémoire de travail = objets avec slots indexés
```

L'idée centrale : plutôt que d'écrire un algorithme qui dit *comment* résoudre
un problème étape par étape, on déclare *ce qu'on sait* (les frames) et *ce
qu'on sait faire* (les règles), et Chorus se charge du reste — de façon
déterministe et traçable.

---

## Niveaux d'utilisation

Chorus se découvre et s'adopte par étapes. On n'est pas obligé d'utiliser
l'ensemble de la chaîne dès le départ.

| Niveau | Ce qu'on utilise | Prérequis | Pour qui |
|---|---|---|---|
| **1 — Perl direct** | `addrule()`, `loop()` en Perl | Perl 5 | Découverte, prototypage, petits projets |
| **2 — YAML** | Règles DSL YAML, `loadRules()` | Perl 5 | Projets maintenables, logique métier riche |
| **3 — Agent IA** | Pipeline généré depuis un corpus | Perl 5 + agent IA | Domaines normatifs, corpus volumineux |

Les niveaux 1 et 2 sont **100 % autonomes** : Perl pur, aucune dépendance
externe, aucun outil tiers. Le niveau 3 ajoute un agent IA comme outil de
*développement* — pas comme dépendance d'*exécution*. Un pipeline généré au
niveau 3 tourne exactement comme un pipeline écrit à la main au niveau 1.

> **Point de départ :** les exemples dans `examples/sandboxes/cob-compliance_fr`
> (ou `_en`) sont entièrement fonctionnels sans agent IA. Ils montrent la structure
> complète d'un projet Chorus — corpus, KB, règles YAML, infrastructure Perl —
> et se lancent avec `perl run.pl project-demo.json`.

---

## Chorus::Expert — l'orchestration

`Chorus::Expert` est le chef d'orchestre. Il enregistre plusieurs agents
(`Chorus::Engine`) spécialisés, leur fournit un **tableau de bord partagé**
(`BOARD`) pour communiquer, et les fait tourner en boucle jusqu'à ce que
l'un d'eux déclare le travail terminé.

```perl
use Chorus::Expert;

my $xprt = Chorus::Expert->new();

$xprt->register($agent_analyse, $agent_calcul, $agent_controle);

my $ok = $xprt->process($donnees);   # 1 = succès, undef = échec ou timeout
```

L'Expert garantit que les agents tournent dans l'ordre d'enregistrement et
recommence tant que l'un d'eux a produit un effet. Il s'arrête dès qu'un agent
appelle `solved()` — ou quand `_MAX_ITER` cycles ont été atteints sans
convergence.

> **Pattern courant :** enregistrer un agent de contrôle en dernière position.
> Son seul rôle est de vérifier que tous les objets ont été traités, puis
> d'appeler `$agent->solved()`.

---

## Chorus::Engine — les règles

`Chorus::Engine` est le moteur d'inférence. Chaque instance est un **agent**
qui contient une liste de règles. Une règle déclare :

- son **scope** (`_SCOPE`) : comment trouver les objets sur lesquels s'appliquer ;
- son **action** (`_APPLY`) : ce qu'elle fait quand le scope est satisfait.

```perl
use Chorus::Engine;
use Chorus::Frame;   # pour fmatch()

my $agent = Chorus::Engine->new();

$agent->addrule(
    _SCOPE => {
        animal => sub { [ fmatch(slot => 'cri') ] },
    },
    _APPLY => sub {
        my %opts = @_;
        return if defined $opts{animal}->{cri_connu};   # déjà traité
        $opts{animal}->set('cri_connu', $opts{animal}->cri);
        return 1;   # la règle a produit un effet
    },
);

$agent->loop();   # boucle autonome (sans Expert)
```

Le moteur applique les règles en boucle tant qu'au moins l'une d'elles produit
un effet. Il s'arrête quand rien ne change plus, ou quand `solved()` est appelé.

---

## Chorus::Frame — la connaissance

`Chorus::Frame` est la brique de base : un objet Perl dont les propriétés
s'appellent des **slots**. Les frames peuvent hériter les uns des autres via
le slot `_ISA`, exactement comme des prototypes. Un slot peut contenir une
valeur scalaire ou une fonction calculée à la volée.

```perl
use Chorus::Frame;

my $animal = Chorus::Frame->new(
    type => 'inconnu',
    cri  => sub { "..." },
);

my $chat = Chorus::Frame->new(
    _ISA => $animal,
    type => 'félin',
    cri  => sub { "miaou" },
);

print $chat->type;   # "félin"
print $chat->cri;    # "miaou"
```

Tous les frames sont automatiquement indexés dans un registre global.
La fonction `fmatch()` permet de les retrouver rapidement par slot :

```perl
my @avec_cri = fmatch(slot => 'cri');          # tous les frames ayant un slot 'cri'
my @felins   = fmatch(type => 'félin');         # par valeur de slot
```

> **Pitfall :** toujours utiliser `$f->set('slot', $val)` et `$f->delete('slot')`
> — jamais `$f->{slot} = $val` ni `delete $f->{slot}`, qui court-circuitent
> l'index et rendent les frames invisibles à `fmatch()`.

### Sélection de frame avec `fselect()`

`fmatch()` répond à la question *"quels frames possèdent ce slot ?"* — le moteur
plonge dans la mémoire de travail et en extrait des frames.

`fselect()` inverse la direction, fidèle à l'intention originale de Minsky :
étant donné un ensemble de propriétés observées, *quel prototype correspond le
mieux à cette situation ?*  Chaque frame candidat reçoit un point par paire
slot/valeur correspondante ; le frame avec le meilleur score est retourné.

```perl
# Trois prototypes en mémoire de travail
my $oiseau = Chorus::Frame->new(type => 'animal', vole => 1,  pattes => 2);
my $poisson = Chorus::Frame->new(type => 'animal', vole => 0, pattes => 0);
my $chauve_souris = Chorus::Frame->new(type => 'animal', vole => 1, pattes => 2, nocturne => 1);

# Situation observée : quelque chose qui vole et a deux pattes
my $proto = fselect(vole => 1, pattes => 2);
# → $oiseau et $chauve_souris marquent 2 points chacun ; l'un d'eux est retourné

# Tous les candidats classés du meilleur au moins bon
my @classes = fselect(vole => 1, pattes => 2, _all => 1);

# Restreindre la recherche à un sous-ensemble connu
my $meilleur = fselect(vole => 1, _from => [$oiseau, $poisson]);

# Instancier depuis le prototype sélectionné
my $instance = Chorus::Frame->new(_ISA => $proto, %observations);
```

**Options :**

| Option | Défaut | Effet |
|---|---|---|
| `_all` | — | Retourner tous les candidats classés par score (liste ou arrayref) |
| `_from` | tous les frames | Restreindre le pool de candidats |
| `_min` | `1` | Score minimum pour être inclus ; `0` pour accepter les candidats sans correspondance |

> **Relation avec `fmatch` :** les deux fonctions sont complémentaires.
> `fmatch` est l'outil principal du moteur — il pilote les règles d'inférence.
> `fselect` est une primitive de plus haut niveau pour la reconnaissance de
> situation : choisir un *type* de frame depuis le contexte, puis utiliser
> `fmatch` pour opérer sur les instances de ce type.

### La triade Minsky complète — `_NEEDED` / `_AFTER` / `_ON_DELETE`

Minsky définissait trois *démons procéduraux* déclenchés lors de l'accès à un
slot. `Chorus::Frame` implémente désormais les trois :

| Démon | Slot | Déclencheur | Direction |
|---|---|---|---|
| if-needed | `_NEEDED` | `get()` ne peut pas résoudre le slot | Chaînage arrière |
| if-added | `_AFTER` | une valeur est écrite via `set()` | Chaînage avant |
| if-removed | `_ON_DELETE` | un slot est effacé via `delete()` | Effet de bord |

```perl
my $f = Chorus::Frame->new(
    budget     => 1000,
    _AFTER     => sub { print "budget changé : $_[0]\n" },
    _ON_DELETE => sub { print "slot '$_[0]' supprimé\n" },
    _NEEDED    => sub { 0 },   # arrière : produit une valeur par défaut
);

$f->set('budget', 500);    # → "budget changé : 500"
$f->delete('budget');      # → "slot 'budget' supprimé"
```

`_ON_DELETE` reçoit le nom du slot supprimé en argument. `$SELF` est positionné
sur le frame au moment de l'appel, ce qui permet au hook d'inspecter l'état
restant du frame.

### Slots terminaux et `complete()`

Minsky distinguait les *nœuds terminaux* — slots devant être remplis par des
données réelles observées — des slots non-terminaux qui peuvent rester
procéduraux. Le slot `_TERMINAL_SLOTS` et la méthode `complete()` implémentent
cette distinction.

```perl
my $Vehicule = Chorus::Frame->new(
    _TERMINAL_SLOTS => ['couleur', 'nb_roues'],
    nb_roues        => sub { 4 },   # non-terminal : possède une valeur par défaut
);

my $voiture = Chorus::Frame->new(_ISA => $Vehicule, couleur => 'rouge', nb_roues => 4);
my $velo    = Chorus::Frame->new(_ISA => $Vehicule, couleur => 'bleu');

$voiture->complete;   # 1    — tous les slots terminaux sont remplis
$velo->complete;      # undef — nb_roues non explicitement défini sur $velo
                      #         (le défaut procédural du prototype compte quand même)
```

`_TERMINAL_SLOTS` est hérité : un frame enfant qui ne le redéclare pas utilise
la liste de son parent. Chaque slot est résolu via `get()`, donc les valeurs
`_DEFAULT` et les slots procéduraux comptent comme remplis.

> **Usage pratique :** appeler `complete()` dans la règle d'un agent de contrôle
> pour vérifier que tous les objets du domaine ont été traités avant d'appeler
> `solved()`.

### Réseaux de frames et `_ALTERNATIVES`

Les frames de Minsky étaient organisées en *réseaux de frames alternatives* :
quand un prototype ne correspond pas à une situation, le système essaie ses
homologues déclarés. Le slot `_ALTERNATIVES` et l'option `_alternatives` de
`fselect()` implémentent ce mécanisme.

```perl
my $Chauve_souris = Chorus::Frame->new(vole => 1, pattes => 2, nocturne => 1);
my $Insecte       = Chorus::Frame->new(vole => 1, pattes => 6);
my $Oiseau        = Chorus::Frame->new(vole => 1, pattes => 2,
                                       _ALTERNATIVES => [$Chauve_souris, $Insecte]);

# Observé : quelque chose qui vole et a 6 pattes → Insecte gagne
my $match = fselect(vole => 1, pattes => 6, _alternatives => $Oiseau);
# → $Insecte (score 2) devant $Oiseau et $Chauve_souris (score 1 chacun)
```

`_alternatives` restreint le pool de candidats au frame seed et aux frames de
sa liste `_ALTERNATIVES`, localisant la recherche à un voisinage déclaré plutôt
que de parcourir tous les frames enregistrés.

### Chorus et le modèle de Minsky — synthèse de compatibilité

`Chorus::Frame` implémente le cœur du modèle de frames de Minsky (1974) :

| Concept | Chorus | Notes |
|---|---|---|
| Slots nommés + valeurs par défaut | ✅ `_DEFAULT` | Direct |
| Slots procéduraux | ✅ `sub {}` | Évalués lazily via `get()` |
| Héritage simple et multiple | ✅ `_ISA` | Direct |
| Démon *if-needed* | ✅ `_NEEDED` | Chaînage arrière |
| Démon *if-added* | ✅ `_AFTER` | Chaînage avant |
| Démon *if-removed* | ✅ `_ON_DELETE` | Effet de bord sur `delete()` |
| Nœuds terminaux | ✅ `_TERMINAL_SLOTS` + `complete()` | Sans questionnement actif |
| Sélection de frame | ✅ `fselect()` | Appel explicite, non perceptif |
| Réseaux de frames | ✅ `_ALTERNATIVES` | Voisinage déclaratif |
| Sélection automatique par perception | ⚠️ | Structurellement absent — voir ci-dessous |
| Propagation par marqueurs | ❌ | Non implémenté |

**La principale divergence restante :** dans le modèle original de Minsky, la
sélection de frame est déclenchée *automatiquement* par l'entrée perceptuelle —
le système choisit le meilleur prototype sans appel explicite. Dans Chorus,
`fselect()` doit être appelée explicitement depuis une règle ou du code Perl.
C'est un choix architectural délibéré : Chorus est un moteur d'inférence piloté
par des règles, pas un système perceptuel. Le mécanisme de sélection est
disponible et correct ; son activation est sous le contrôle du développeur.

**Sur la propagation par marqueurs :** Minsky envisageait une propagation de
marqueurs à travers le réseau de frames pour pré-activer en parallèle les frames
candidates avant la sélection explicite. `fselect()` score les candidats de façon
linéaire — correct séquentiellement, mais non propagatif. C'est suffisant pour
les domaines pilotés par des règles et n'introduit aucune limitation pratique dans
les contextes où Chorus est utilisé.

---

## Les règles en YAML

Pour les projets avec beaucoup de règles, Chorus propose un DSL YAML
qui évite d'écrire le code Perl à la main :

```yaml
REGLE: calculer-cri-connu
CHERCHER:
  animal:
    attribut: cri
EXCEPTION: defined $animal->{cri_connu}
EFFET: |
  $animal->set('cri_connu', $animal->cri);
  1
```

## Chorus est un moteur d'inférence

Ce modèle s'inscrit directement dans la lignée des systèmes experts des années
1980–90. CLIPS, OPS5 et leurs prédécesseurs partagent tous le même cycle
recognize–act, la même mémoire de travail et le même mécanisme de chaînage avant.
Chorus est une implémentation Perl moderne et minimale de cette tradition — sans
le poids d'un runtime dédié.

Chorus implémente le cycle classique *recognize–act* : à chaque itération, le
moteur cherche dans la mémoire de travail les règles dont les conditions sont
satisfaites, les déclenche, et recommence — jusqu'au **point fixe** (aucune règle
ne peut plus s'activer) ou jusqu'à ce qu'un but explicite soit atteint.

Ce mécanisme s'exprime à chaque couche de l'architecture.

### La mémoire de travail

Les registres `%FMAP`, `%REPOSITORY` et `%INSTANCES` de `Chorus::Frame`
constituent la mémoire de travail. La fonction `fmatch()` l'interroge en temps
constant pour retrouver tous les frames qui possèdent un slot donné, avec
filtrage optionnel.

### Le cycle recognize–act

`applyrules()` évalue le `_SCOPE` de chaque règle pour identifier les frames
candidats (phase *recognize*), puis appelle `_APPLY` pour chaque combinaison
(phase *act*). Elle suit `$stillworking` — vrai si au moins une règle a produit
un effet. `loop()` répète ce cycle jusqu'au point fixe.

### Le chaînage avant

À deux niveaux :
- **Au niveau des frames** : le slot `_AFTER` déclenche des effets dès qu'une
  valeur change, propageant immédiatement les conséquences au sein de la
  structure de connaissance.
- **Au niveau du moteur** : les règles enrichissent les frames en leur ajoutant
  de nouveaux slots, ce qui rend d'autres règles éligibles au prochain cycle.

### Le chaînage arrière

Quand `get()` ne peut pas résoudre un slot, il invoque le coderef `_NEEDED`
pour *produire* la valeur à la demande. Le slot est calculé uniquement quand
quelque chose en a besoin — c'est du chaînage arrière au niveau de la
représentation des connaissances.

### La termination par but

`solved()` / `failed()`, `_TERMINAL`, `_MAX_CYCLES` : le moteur raisonne
jusqu'à atteindre un état terminal explicite ou épuiser les possibilités.
L'appel à `replay_all()` permet de relancer l'intégralité du pipeline d'agents,
pour raisonner sur des états qui évoluent en cours de traitement.

---

## Pourquoi ce modèle ?

L'avantage d'un système à règles explicites est la **traçabilité** :
chaque résultat est justifiable par une règle précise. La connaissance
est séparée du moteur et peut être lue, modifiée ou étendue indépendamment,
sans toucher au code d'inférence.

C'est ce qui distingue Chorus des approches purement algorithmiques :
on décrit le **quoi**, pas le **comment**.

---

## Chorus à l'ère des LLMs

> Voir [`02-ai-agent.md`](02-ai-agent.md) — positionnement LLM vs Chorus, architecture agent IA,
> pipeline `chorus-pdf` → `chorus-feed` → `chorus-check`.

---

## Pour aller plus loin

- `perldoc Chorus::Expert` — orchestration multi-agents, BOARD partagé, `_MAX_ITER`
- `perldoc Chorus::Engine` — règles, boucle d'inférence, DSL YAML, contrôle de flux
- `perldoc Chorus::Frame` — slots, héritage, `fmatch`, `get`, `set`, `delete`
- `perldoc Chorus::Collection::List` — séquences ordonnées de frames
- `perldoc Chorus::Collection::Filter` — correspondance de motifs sur séquences
- [CLIPS](https://www.clipsrules.net/), [OPS5](https://en.wikipedia.org/wiki/OPS5) — la tradition des systèmes experts dont Chorus s'inspire
- Minsky, M. (1974). *A Framework for Representing Knowledge* — le modèle de frames à l'origine de `Chorus::Frame`
