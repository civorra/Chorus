# Chorus Engine — Guide technique

> Ce document complète le [README](../../README.md). Il suppose acquis le modèle
> général (pipeline `chorus-*`, positionnement LLM/moteur) et détaille la mécanique
> interne : DSL YAML, nouveautés 2.0, API Perl de référence.

---

## Niveaux d'utilisation

Chorus s'adopte par étapes — on n'est pas obligé d'utiliser l'ensemble de la
chaîne dès le départ.

| Niveau | Ce qu'on utilise | Prérequis | Pour qui |
|---|---|---|---|
| **1 — Perl direct** | `addrule()`, `loop()` en Perl | Perl 5 | Découverte, prototypage, petits projets |
| **2 — YAML** | Règles DSL YAML, `loadRules()` | Perl 5 | Projets maintenables, logique métier riche |
| **3 — Agent IA** | Pipeline généré depuis un corpus | Perl 5 + agent IA | Domaines normatifs, corpus volumineux |

Niveaux 1 et 2 : **100 % autonomes** — Perl pur, aucune dépendance externe.
Le niveau 3 ajoute un agent IA comme outil de *développement* uniquement ; le
pipeline généré tourne comme un pipeline de niveau 1, sans agent IA ni réseau.

> **Point de départ :** `sandboxes/demo_en` est entièrement fonctionnel sans agent IA :
> `perl sandboxes/demo_en/run.pl sandboxes/demo_en/project-01.json`

> **Note terminologique :** le terme *neuro-symbolique* est parfois appliqué à
> des systèmes comme Chorus. Il n'est pas exact ici. Dans les systèmes
> neuro-symboliques, un modèle neuronal *apprend* à simuler des règles logiques.
> Dans Chorus, le moteur symbolique est réel — frames, slots, chaîne d'inférence —
> et le LLM est une étape de prétraitement. *Symbolique augmenté* est un label
> plus précis.
> → [Genèse](../../LISEZMOI.md#genèse)

---

## DSL YAML — référence complète

Pour les projets avec de nombreuses règles, le DSL YAML externalise la logique
métier sans code Perl répétitif.

### Structure d'une règle

```yaml
REGLE: nom-de-la-regle           # identifiant unique (_ID interne)
PREMISSES:                       # slots requis sur le frame candidat (filtre rapide)
  - slot_requis
CHERCHER:                        # bindings : nom → critères de sélection
  var:
    attribut: nom_slot           # le frame doit posséder ce slot
    filtre:   '$_->{slot} > 0'  # expression Perl évaluée sur le frame candidat
CONDITION: |                     # condition globale (tous les bindings résolus)
  $var->{slot} > seuil
EXCEPTION: |                     # court-circuit : ne pas déclencher si vrai
  defined $var->{resultat}
EFFET: |                         # corps de règle — doit retourner 1 si actif
  $var->set('resultat', calcul($var->{slot}));
  1
TERMINAL: solved                 # ← nouveauté 2.0 — terminer le pipeline
```

**Aliases anglais (2.0)** — `RULE` / `FIND` / `ACTION` / `PREMISES` sont des
synonymes acceptés de `REGLE` / `CHERCHER` / `EFFET` / `PREMISSES`. Les
sous-clés `attribut` et `filtre` sont invariantes (pas d'alias).

### Le champ `TERMINAL` — nouveauté 2.0

`TERMINAL` remplace le code Perl qui appelait `solved()` ou `failed()` depuis
`_APPLY`. Il est déclaré directement dans la règle YAML, sans glue code :

```yaml
REGLE: tout-verifie
CHERCHER:
  obj:
    attribut: statut
CONDITION: |
  $obj->{statut} eq 'ok'
TERMINAL: solved
```

Valeurs acceptées : `solved` · `failed`.

Quand la règle s'active et que `TERMINAL` est présent, le moteur appelle
`solved()` ou `failed()` puis sort de la boucle immédiatement.

### Chargement des règles

```perl
$agent->loadRules('rules/mon-agent/');       # tous les *.yml du répertoire
$agent->loadRules('rules/R01-ma-regle.yml'); # fichier unique
```

Les fichiers sont chargés **par ordre alphabétique** — nommer les fichiers
`R01-`, `R02-`… pour contrôler l'ordre d'application.

**Déduplication par identifiant (2.0) :** si deux fichiers déclarent une règle
avec le même `REGLE:` / `RULE:`, le second est ignoré et un avertissement est
émis.

### Variables de contexte dans `EFFET`

Les variables liées par `CHERCHER` sont directement accessibles sous leur nom.
`$SELF` désigne le moteur courant :

```yaml
EFFET: |
  my $val = $source->{mesure} * $SELF->{facteur};
  $cible->set('valeur_corrigee', $val);
  1
```

---

## Nouveautés 2.0 — API moteur

### Helpers scope/filtre comme méthodes d'instance

En 1.x, `setFilter`, `setScope`, `setCondition`, `setException`, `setEffect`
étaient des fonctions implicites au niveau du package, dépendantes de la
variable globale `$SELF`. En 2.0, ce sont de vraies **méthodes d'instance** :

```perl
my $agent = Chorus::Engine->new();

$agent->setFilter(sub {
    my ($self, $frame) = @_;
    $frame->{type} eq 'element';
});

$agent->setScope(sub {
    my ($self) = @_;
    [ fmatch(slot => 'type') ]
});

$agent->setCondition(sub { ... });
$agent->setException(sub { ... });
$agent->setEffect(sub { ... });
```

Le code 1.x reste compatible — `$SELF` est toujours positionné pendant
l'exécution des règles.

### `_MAX_CYCLES` — garde-fou boucle infinie

```perl
my $agent = Chorus::Engine->new(_MAX_CYCLES => 5000);
```

`loop()` s'arrête après `_MAX_CYCLES` cycles (défaut : 10 000) et émet un
avertissement. Chaque instance possède sa propre limite, indépendante des
autres agents d'un même `Chorus::Expert`.

Calibration recommandée : `N_frames × N_règles × N_agents × 10`. La KB
générée par `chorus-feed` documente la valeur cible dans le fichier org de
chaque agent.

### `Chorus::Frame::_reset()` — isolation des tests

```perl
Chorus::Frame->_reset();
```

Vide l'intégralité du registre de frames (`%FMAP`, `%REPOSITORY`, `%INSTANCES`,
`%SERIAL`, `@Heap`). Conçu pour l'isolation entre cas de test — chaque test
repart d'une mémoire de travail vierge :

```perl
use Test::More;
use Chorus::Frame;

sub setup {
    Chorus::Frame->_reset();
    Chorus::Frame->new(type => 'element', valeur => 42);
}

ok(setup() && fmatch(slot => 'type'), 'frame créé');
```

---

## Chorus::Frame — référence

### Slots, héritage et `fmatch()`

```perl
use Chorus::Frame;

my $base = Chorus::Frame->new(
    type    => 'inconnu',
    libelle => sub { "Frame " . ref($_[0]) },  # slot procédural
);

my $enfant = Chorus::Frame->new(
    _ISA   => $base,
    type   => 'element',
    masse  => 12.5,
);

print $enfant->type;     # "element"
print $enfant->libelle;  # "Frame Chorus::Frame" — hérité, évalué lazily
```

### Modes d'héritage N et Z

Le global `$getMode` contrôle la façon dont `get()` parcourt la chaîne d'héritage
quand un slot n'est pas défini localement.

**Mode N (défaut) :** pour chaque clé de valorisation (`_VALUE`, `_DEFAULT`,
`_NEEDED`), cherche dans *tous* les frames de l'arbre d'héritage avant de passer
à la clé suivante — parcours en largeur par clé.

**Mode Z :** parcourt la séquence complète `(_VALUE, _DEFAULT, _NEEDED)` sur
chaque frame avant de descendre dans ses parents — parcours en profondeur.

```perl
# Basculer en mode Z (depth-first par frame)
Chorus::Frame::setMode(GET => 'Z');

# Revenir au mode N (breadth-first par clé)
Chorus::Frame::setMode(GET => 'N');
```

> **Quand changer de mode ?** Le mode N est adapté à la majorité des cas
> (on cherche la valeur la plus spécialisée pour une clé donnée). Le mode Z
> est utile quand on veut qu'un frame héritant puisse court-circuiter
> complètement un ancêtre, y compris ses `_DEFAULT` et `_NEEDED`.

**`fmatch()` — interrogation de la mémoire de travail :**

```perl
my @tous   = fmatch(slot => 'masse');                          # frames ayant le slot 'masse'
my @lourds = grep { $_->{masse} > 10 } fmatch(slot => 'masse'); # par condition
my @typed  = grep { $_->{type} eq 'element' } fmatch(slot => 'type'); # par valeur exacte
```

> ⚠️ **Pitfall :** toujours utiliser `$f->set('slot', $val)` et
> `$f->delete('slot')` — jamais `$f->{slot} = $val` ni `delete $f->{slot}`,
> qui court-circuitent l'index et rendent le frame invisible à `fmatch()`.

### `fselect()` — reconnaissance de situation

`fselect()` répond à la question inverse de `fmatch()` : étant donné un ensemble
de propriétés observées, *quel prototype correspond le mieux ?* Chaque frame
candidat reçoit un point par paire slot/valeur correspondante.

```perl
my $acier = Chorus::Frame->new(materiau => 'acier', fy => 355, classe => 'S355');
my $beton = Chorus::Frame->new(materiau => 'béton', fck => 30,  classe => 'C30');
my $bois  = Chorus::Frame->new(materiau => 'bois',  classe => 'C24', essence => 'sapin');

my $proto   = fselect(classe => 'C24');               # → $bois
my @classes = fselect(classe => 'C24', _all => 1);    # tous, classés par score
my $best    = fselect(materiau => 'acier', _from => [$acier, $beton]);  # pool restreint

my $instance = Chorus::Frame->new(_ISA => $proto, %observations);  # instancier
```

**Options :**

| Option | Défaut | Effet |
|---|---|---|
| `_all` | — | Retourner tous les candidats classés par score |
| `_from` | tous les frames | Restreindre le pool de candidats |
| `_min` | `1` | Score minimum ; `0` pour inclure les non-correspondants |

**Usage typique dans une règle `_APPLY` :**

```perl
_APPLY => sub {
    my %o = @_;
    my $proto = fselect(classe => $o{element}->{classe});
    return unless $proto;
    $o{element}->set('prototype', $proto);
    return 1;
},
```

### Les trois démons — `_NEEDED` / `_AFTER` / `_ON_DELETE`

Trois crochets procéduraux déclenchés lors de l'accès aux slots :

| Démon | Slot | Déclencheur | Direction |
|---|---|---|---|
| if-needed | `_NEEDED` | `get()` ne peut pas résoudre le slot | Chaînage arrière |
| if-added | `_AFTER` | une valeur est écrite via `set()` | Chaînage avant |
| if-removed | `_ON_DELETE` | un slot est effacé via `delete()` | Effet de bord |

```perl
my $f = Chorus::Frame->new(
    budget     => 1000,
    _AFTER     => sub { print "budget modifié : $_[0]\n" },
    _ON_DELETE => sub { print "slot '$_[0]' supprimé\n" },
    _NEEDED    => sub {
        my ($self, $slot) = @_;
        return $self->{masse} * $self->{densite} if $slot eq 'poids';
        return undef;
    },
);

$f->set('budget', 500);    # → "budget modifié : 500"
$f->delete('budget');      # → "slot 'budget' supprimé"
```

`_ON_DELETE` reçoit le nom du slot supprimé. `$SELF` est positionné sur le frame
au moment de l'appel.

### `complete()` et `_TERMINAL_SLOTS`

`_TERMINAL_SLOTS` liste les slots qui doivent être explicitement renseignés
(pas seulement hérités ou calculés) pour qu'un frame soit considéré complet.

```perl
my $Element = Chorus::Frame->new(
    _TERMINAL_SLOTS => ['classe', 'longueur', 'section'],
    section => sub { 'non définie' },   # valeur par défaut
);

my $e1 = Chorus::Frame->new(_ISA => $Element,
    classe => 'C24', longueur => 4.2, section => '120x80');
my $e2 = Chorus::Frame->new(_ISA => $Element,
    classe => 'C24', longueur => 3.0);  # section manquante

$e1->complete;   # 1     — tous les slots terminaux présents
$e2->complete;   # undef — 'section' non défini explicitement sur $e2
```

`_TERMINAL_SLOTS` est hérité. Chaque slot est résolu via `get()` — les valeurs
procédurales héritées comptent comme remplies.

> **Usage pratique :** appeler `complete()` dans l'agent de contrôle final pour
> vérifier que tous les objets du domaine ont été traités avant d'appeler `solved()`.

### Réseaux de frames — `_ALTERNATIVES`

`_ALTERNATIVES` déclare les frames homologues à explorer quand un prototype ne
correspond pas parfaitement. S'utilise avec l'option `_alternatives` de `fselect()` :

```perl
my $Poteaux = Chorus::Frame->new(type => 'bois', porteur => 1, section => 'carree');
my $Solives = Chorus::Frame->new(type => 'bois', porteur => 1, section => 'rectangulaire');
my $Lambris = Chorus::Frame->new(type => 'bois', porteur => 0,
                                  _ALTERNATIVES => [$Poteaux, $Solives]);

# Observé : élément porteur en bois à section rectangulaire
my $match = fselect(porteur => 1, section => 'rectangulaire', _alternatives => $Lambris);
# → $Solives (score 2)
```

`_alternatives` restreint le pool au frame seed et à sa liste `_ALTERNATIVES`,
localisant la recherche à un voisinage déclaré.

---

## Chorus::Engine — référence

```perl
use Chorus::Engine;

my $agent = Chorus::Engine->new(
    _IDENT      => 'mon-agent',   # nom pour les logs
    _MAX_CYCLES => 5000,
);

# Règle Perl
$agent->addrule(
    _SCOPE => { f => sub { [ fmatch(type => 'element') ] } },
    _APPLY => sub {
        my %o = @_;
        return if $o{f}->{traite};
        $o{f}->set('traite', 1);
        return 1;
    },
);

# Chargement YAML
$agent->loadRules('rules/mon-agent/');

# Boucle autonome (sans Expert)
$agent->loop();

# Termination explicite depuis _APPLY
$agent->solved();   # BOARD->SOLVED = 'Y'
$agent->failed();   # BOARD->FAILED = 'Y'
```

**`_MAX_ITER` (Expert) vs `_MAX_CYCLES` (Engine) :**

| Paramètre | Portée | Ce qu'il limite |
|---|---|---|
| `_MAX_CYCLES` | `Chorus::Engine` | Cycles dans la boucle d'un agent |
| `_MAX_ITER` | `Chorus::Expert` | Passes sur l'ensemble des agents |

---

## Chorus::Expert — référence

```perl
use Chorus::Expert;

my $xprt = Chorus::Expert->new(_MAX_ITER => 100);

$xprt->register($agent_1, $agent_2, $agent_controle);

my $ok = $xprt->process($donnees_initiales);
# → 1 si solved(), undef si failed() ou _MAX_ITER atteint

# Tableau de bord partagé
$xprt->BOARD->set('cle', 'valeur');
my $v = $xprt->BOARD->get('cle');
```

> **Pattern courant :** enregistrer un agent de contrôle en dernière position.
> Son seul rôle est de vérifier que tous les objets ont été traités
> (`$obj->complete` pour chacun), puis d'appeler `$agent->solved()`.

---

## Chorus::Collection — référence

### `Chorus::Collection::List`

Séquence ordonnée de frames. `$LIST` est un **prototype Frame** — on en hérite
plutôt qu'on ne l'instancie directement :

```perl
use Chorus::Collection::List qw($LIST);
use Chorus::Frame;

my $lst = Chorus::Frame->new(_ISA => $LIST);
$lst->build($f1, $f2, $f3);          # initialise _ITEMS, chaîne prev/succ

my $first = $lst->first_item;
my $last  = $lst->last_item;
my $len   = $lst->length;
my $found = $lst->HAS('masse');       # premier item ayant le slot 'masse'
```

### `Chorus::Collection::Filter`

Filtrage regex-like sur des séquences de frames. `$FILTER` est lui aussi un
**prototype Frame** — même patron que `$LIST`. Les groupes de capture atterrissent
dans `@_VFILTER` après un `check()` réussi :

```perl
use Chorus::Collection::Filter qw($FILTER @_VFILTER);
use Chorus::Frame;

my $f = Chorus::Frame->new(_ISA => $FILTER);

$f->set_node_test(sub { $_[0]->{pos} });  # valeur comparée dans le pattern

$f->set_filter('^(NOM) VERB ADJ*$');

if ($f->check(@tokens)) {
    my ($sujets) = @_VFILTER;            # groupe de capture
}
```

**Syntaxe de pattern :**

| Token | Sens |
|---|---|
| `^` / `$` | Ancrage début / fin |
| `[A B C]` | OU : correspond à A, B ou C |
| `!X` | NON : exclut la valeur X |
| `.` | N'IMPORTE : tout frame |
| `X+` / `X*` / `X?` | Un ou plus / Zéro ou plus / Zéro ou un |
| `X{m,n}` | Entre m et n occurrences |
| `(...)` | Groupe de capture → `@_VFILTER` |

---

## Pour aller plus loin

- [`02-ai-agent.md`](02-ai-agent.md) — positionnement LLM vs Chorus, architecture daemon, pipeline complet
- [`03-applications.md`](03-applications.md) — domaines d'application, onboarding par secteur
- [`04-chorus-commands.md`](04-chorus-commands.md) — référence complète des commandes `chorus-*`
- `perldoc Chorus::Engine` — règles, boucle d'inférence, DSL YAML, contrôle de flux
- `perldoc Chorus::Frame` — slots, héritage, `fmatch`, `get`, `set`, `delete`
- `perldoc Chorus::Expert` — orchestration multi-agents, BOARD partagé
- `perldoc Chorus::Collection::List` — séquences ordonnées
- `perldoc Chorus::Collection::Filter` — correspondance de motifs
