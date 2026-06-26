# Introduction à Chorus

## Qu'est-ce que Chorus ?

**Chorus** est un moteur d'inférence écrit en Perl pur. Il repose sur trois
concepts fondamentaux qui s'emboîtent : une **mémoire de travail** peuplée de
frames, un **cycle d'inférence** qui applique des règles en boucle jusqu'au
point fixe, et une **orchestration multi-agents** qui décompose les problèmes
complexes en spécialités indépendantes.

**La mémoire de travail** est constituée de `Chorus::Frame` — des objets Perl
dont les propriétés (les *slots*) représentent la connaissance du domaine. Tous
les frames sont indexés dans un registre global ; la fonction `fmatch()` permet
de les interroger en temps constant. C'est sur cette mémoire que portent toutes
les règles.

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
| **3 — ECA** | Pipeline généré depuis un corpus | Perl 5 + ECA | Domaines normatifs, corpus volumineux |

Les niveaux 1 et 2 sont **100 % autonomes** : Perl pur, aucune dépendance
externe, aucun outil tiers. Le niveau 3 ajoute ECA comme outil de
*développement* — pas comme dépendance d'*exécution*. Un pipeline généré au
niveau 3 tourne exactement comme un pipeline écrit à la main au niveau 1.

> **Point de départ :** les exemples dans `examples/sandboxes/cob-compliance_fr`
> (ou `_en`) sont entièrement fonctionnels sans ECA. Ils montrent la structure
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

Les grands modèles de langage (GPT, Claude, Gemini…) atteignent aujourd'hui
des performances remarquables sur des tâches de compréhension, de génération
et de raisonnement général. Cela pose une question légitime : à quoi sert
encore un moteur à règles comme Chorus ?

La réponse tient en un mot : **maîtrise**.

### Ce que les LLMs ne donnent pas

Un LLM « sait » des choses, mais cette connaissance est implicite, distribuée
dans des milliards de paramètres, et fondamentalement opaque. On ne peut pas :

- **pointer** la règle qui a produit un résultat particulier,
- **corriger** chirurgicalement une erreur sans réentraîner le modèle,
- **garantir** qu'une contrainte métier sera toujours respectée,
- **lire ou transmettre** la connaissance modélisée à un expert humain.

Pour beaucoup d'usages, cette opacité est acceptable. Pour d'autres — domaines
réglementés, systèmes certifiables, expertise à auditer — elle est rédhibitoire.

### Ce que Chorus apporte

Avec Chorus, la connaissance est un **artefact explicite** : des frames lisibles,
des règles YAML versionnées, discutables. Un expert du domaine peut les lire,
les contester, les affiner. Chaque conclusion dispose d'une justification traçable.

### La complémentarité plutôt que la concurrence

| Tâche | Outil adapté |
|---|---|
| Compréhension de texte libre, extraction, génération | LLM |
| Validation de contraintes métier strictes | Chorus |
| Justification et traçabilité des décisions | Chorus |
| Adaptation rapide à un nouveau domaine | LLM |
| Garantie de conformité à une norme | Chorus |

Un LLM peut extraire et structurer les données d'entrée ; Chorus applique
les règles métier et certifie le résultat. Les deux se complètent sans se
concurrencer.

### Couplage avec un outil LLM — l'architecture ECA

Imaginez la scène : vous avez un PDF de 150 pages — une norme de construction,
un DTU, un cahier des charges technique. D'ici la fin de la session, vous voulez
un pipeline d'inférence Chorus opérationnel qui valide des projets réels contre
cette norme. Pas un prototype : un moteur avec des agents spécialisés, des règles
YAML idempotentes, des tables normatives extraites du document, une infrastructure
Perl correctement câblée, et un rapport de conformité structuré.

Sans assistance : plusieurs jours de travail Perl expert. Avec ECA et ses skills
Chorus, c'est l'affaire d'une session.

> **ECA est un outil de développement, pas une dépendance d'exécution.** Le
> pipeline qu'il génère est du Perl pur — `Feed.pm`, `Agent/*.pm`, `Expert.pm`,
> `run.pl`. Il tourne sur n'importe quelle machine avec Perl installé, sans ECA,
> sans connexion réseau. Une fois généré, le pipeline est entièrement autonome.

> **Les fichiers KB (`.org`)** sont du texte structuré lisible avec n'importe
> quel éditeur — vim, VSCode, nano. Emacs offre le meilleur rendu des tableaux
> et du balisage, mais il n'est pas requis pour lire, modifier ou versionner ces
> fichiers.

**Ce que la chaîne fait concrètement :**

```
chorus-pdf  norme.pdf --auto
    → extrait le texte page par page (pdfminer pour le texte,
      vision LLM pour les figures et tableaux)
    → corpus/001-norme-vision.md

chorus-feed mon-sandbox corpus/001-norme-vision.md
    → identifie les spécialités → agents
    → conçoit l'ontologie de slots
    → écrit eca/agents/<specialite>.org (KB par agent)
    → génère rules/<specialite>/R01-xxx.yml … (règles YAML)
    → génère lib/MonApp/Agent/<Specialite>/Helpers.pm (tables normatives)

chorus-check mon-sandbox projet.json
    → lit la KB, génère Feed.pm + Agent/*.pm + Expert.pm + run.pl
    → lance perl run.pl projet.json
    → affiche le rapport de conformité
```

Trois commandes. Le reste est géré.

**Ce qui rend ça possible :**

L'astuce centrale est la **base de connaissance locale** — des fichiers org-mode
produits par ECA, un par agent, qui contiennent tout ce que le moteur a besoin de
savoir : l'ontologie du domaine, le dictionnaire des slots, le catalogue des règles
avec leur code, les helpers Perl avec leur source normative (`# §4.2 DTU 31.2`).

Ces fichiers sont lisibles par un ingénieur du domaine sans qu'il sache lire du
Perl. Il peut corriger une table, contester une règle, affiner une contrainte.
ECA relit la KB corrigée et régénère les artefacts en aval. Chorus exécute le
résultat sans jamais impliquer le LLM — de façon déterministe, à l'identique,
autant de fois qu'on veut.

```
norme.pdf
    │ chorus-pdf
    ▼
corpus/
    │ chorus-feed
    ▼
eca/agents/*.org  ←──── l'expert du domaine lit, corrige, affine
rules/**/*.yml
lib/**/Helpers.pm
    │ chorus-check
    ▼
Feed.pm · Agent/*.pm · Expert.pm · run.pl
    │ perl run.pl projet.json
    ▼
✅ CONFORME / ❌ NON_CONFORME  — avec motif, par élément, par agent
```

**Quand la norme change :**

```
chorus-feed mon-sandbox nouveau-corpus.txt --enrich
chorus-check mon-sandbox projet.json
```

La KB est mise à jour de façon incrémentale. L'infrastructure Perl est régénérée.
Le pipeline tourne à nouveau — résultat garanti conforme aux règles telles qu'elles
ont été définies, sans dérive.

**En pratique, sur un vrai domaine :**

Un sandbox de test COB (Construction Ossature Bois, DTU 31.2) a été construit
avec cette chaîne : 7 agents spécialisés, 37 règles YAML, 7 modules de helpers
avec tables EC5 et NF EN 338, un pipeline validant 210 éléments de bâtiment en
une passe. L'intégralité du code Perl et YAML — environ 2 000 lignes — a été
générée par ECA depuis le corpus. Aucune ligne écrite à la main.

> Les skills ECA pour Chorus (`chorus-pdf`, `chorus-feed`, `chorus-check`,
> `chorus-create-project`, `chorus-import-project`) sont versionnés dans
> `$ENGINE/eca/skills/` et documentés dans le dépôt.

> **Explorer sans ECA :** les sandboxes `examples/sandboxes/cob-compliance_fr`
> et `cob-compliance_en` contiennent l'intégralité des artefacts produits par la
> chaîne (corpus, KB org, règles YAML, infrastructure Perl). Ils permettent de
> comprendre ce qu'ECA génère avant même de l'installer — et de lancer
> `perl run.pl project-demo.json` pour voir le résultat en direct.

### En résumé

Les LLMs excellent à traiter ce qui est **vaste et ambigu**.
Chorus excelle à traiter ce qui est **précis et certifiable**.

Pour un développeur ou un expert qui a besoin de *maîtriser* la connaissance
qu'il modélise — et pas seulement de l'utiliser — Chorus reste un outil
irremplaçable, précisément parce qu'il répond à un problème que les LLMs
ne peuvent pas résoudre par construction.

---

## Pour aller plus loin

- `perldoc Chorus::Expert` — orchestration multi-agents, BOARD partagé, `_MAX_ITER`
- `perldoc Chorus::Engine` — règles, boucle d'inférence, DSL YAML, contrôle de flux
- `perldoc Chorus::Frame` — slots, héritage, `fmatch`, `get`, `set`, `delete`
- `perldoc Chorus::Collection::List` — séquences ordonnées de frames
- `perldoc Chorus::Collection::Filter` — correspondance de motifs sur séquences
