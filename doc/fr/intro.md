# Introduction à Chorus

## Qu'est-ce que Chorus ?

**Chorus** est un framework d'inférence léger écrit en Perl pur.
Il permet de modéliser un problème sous forme de **connaissances** (des objets)
et de **règles** (des conditions + des actions), puis de laisser le moteur
trouver automatiquement comment les appliquer pour résoudre le problème.

L'idée centrale : plutôt que d'écrire un algorithme qui dit *comment* résoudre
un problème étape par étape, on déclare *ce qu'on sait* et *ce qu'on cherche*,
et Chorus se charge du reste — de façon déterministe et traçable.

Le framework s'organise en trois couches emboîtées :

```
Chorus::Expert      coordonne les agents, détecte la fin
  └─ Chorus::Engine   un agent = un ensemble de règles
       └─ Chorus::Frame   la connaissance = des objets avec des slots
```

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

Un assistant IA comme **[ECA](https://eca.dev/)** peut s'intégrer directement
dans la boucle de développement Chorus, en jouant le rôle de *générateur de
connaissance* là où le moteur joue le rôle d'*exécuteur certifiable*.

L'architecture repose sur trois couches qui communiquent via des fichiers texte lisibles par l'humain
**et** par le LLM :

```
Corpus brut (PDF, DTU, normes…)
        │
        ▼  ECA lit, extrait, structure
┌───────────────────────────────────┐
│  Base de connaissance  (org-mode) │  ← lue et maintenue par ECA
│  eca/agents/qualification.org     │    • domaine, ontologie
│  eca/agents/ossature.org          │    • dictionnaire des slots
│  eca/agents/thermique.org  …      │    • catalogue de règles
└───────────────────────────────────┘
        │
        ▼  ECA génère / affine
┌──────────────────────┐   ┌──────────────────────────┐
│  Règles YAML         │   │  Helpers Perl             │
│  rules/qualification │   │  lib/COB/Agent/           │
│  rules/ossature  …   │   │  Qualification/Helpers.pm │
└──────────────────────┘   └──────────────────────────┘
        │                           │
        └──────────┬────────────────┘
                   ▼  Chorus exécute (règles + Frames)
        ┌──────────────────────────────────┐
        │  Chorus::Expert                  │
        │    Agent::Qualification          │
        │    Agent::Ossature               │
        │    Agent::Thermique  …           │
        │    Agent::Controle (terminaison) │
        └──────────────────────────────────┘
                   │
                   ▼
        Résultat certifiable + traçable
```

**Le rôle de chaque couche :**

- **Le corpus** (PDF de norme, DTU, document technique) est la source de vérité
  du domaine. ECA le lit et en extrait la connaissance structurée.

- **Les fichiers org-mode** (`eca/agents/*.org`) sont la base de connaissance
  locale : un fichier par agent, avec son domaine, son ontologie, le dictionnaire
  de ses slots, le catalogue de ses règles et ses contraintes. C'est l'interface
  de collaboration entre l'humain, le LLM et le moteur.

- **ECA** lit ces fichiers org via ses skills et génère ou affine les règles YAML
  et les helpers Perl en s'appuyant dessus — sans halluciner, car la connaissance
  est explicitement posée dans la KB locale.

- **Chorus** exécute le résultat de façon déterministe, sans LLM, sur le jeu
  de Frames issu du projet réel.

**Cycle de mise à jour quand une norme change :**

1. ECA lit le nouveau corpus et met à jour les fichiers org ;
2. ECA génère les règles YAML et helpers Perl correspondants ;
3. Chorus exécute le pipeline mis à jour — résultat garanti conforme aux règles
   telles qu'elles ont été définies, sans dérive stochastique.

La connaissance reste lisible et auditable à chaque étape. L'humain garde la
maîtrise : il peut modifier les fichiers org directement, relire les règles YAML,
et valider le code Perl généré avant de l'intégrer.

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
