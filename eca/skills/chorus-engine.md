# Skill — Chorus::Engine

> Chargé automatiquement pour tout code Perl créé ou modifié dans `$ENGINE`.
> Référence : rapport `$SESSIONS/2026-06-22-16-54-deep-analysis-engine.md`

---

## 1. Mécanismes fondamentaux

### 1.1 La chaîne Expert → Agent → Frame

```
Chorus::Expert          orchestration de la boucle + terminaison
  └─ Chorus::Engine     agent = Frame héritant de $ENGINE
       └─ _RULES        liste de Frames-règles
            └─ _SCOPE   adresse des Chorus::Frame du domaine
                 └─ Chorus::Frame   connaissance + hooks
```

**Règle de conception :** chaque niveau a une responsabilité unique.

| Niveau | Responsabilité |
|---|---|
| Expert | quand itérer les agents, détecter la terminaison |
| Agent | quelles règles, dans quel ordre, contrôle de flux |
| Frame | connaissance métier, héritage, hooks procéduraux |

---

### 1.2 Chorus::Frame — slots essentiels

| Slot | Rôle |
|---|---|
| `_ISA` | héritage (scalar ou arrayref de Frames) |
| `_VALUE` | valeur principale du Frame |
| `_DEFAULT` | fallback si `_VALUE` absent |
| `_NEEDED` | coderef de dernier recours (chaînage arrière) |
| `_BEFORE` | hook avant modification d'un slot |
| `_AFTER` | hook après modification d'un slot (propagation avant) |
| `_REQUIRE` | validation : retourner `REQUIRE_FAILED` bloque `_setValue` |
| `_NOFRAME` | empêche la promotion automatique d'un hash en Frame |

**Slots système réservés** — ne jamais utiliser comme noms de slots métier :
`_KEY` `_PARENT_KEY` `_ISA` `_VALUE` `_DEFAULT` `_NEEDED` `_BEFORE` `_AFTER` `_REQUIRE` `_NOFRAME` `_SERIALIZE`

**Modes d'héritage `get()` :**
- **Mode N** (défaut) : pour chaque clé de valuation (`_VALUE`, `_DEFAULT`, `_NEEDED`), parcourir tout l'arbre avant de passer à la suivante.
- **Mode Z** : tester la séquence complète `(_VALUE, _DEFAULT, _NEEDED)` sur chaque Frame avant de descendre dans les parents.

```perl
Chorus::Frame::setMode(GET => 'Z');   # passe en mode Z
Chorus::Frame::setMode(GET => 'N');   # retour au mode N
```

**`$SELF`** = contexte courant, disponible dans tout slot de type `sub { }` :

```perl
my $f = Chorus::Frame->new(
    label => sub { "Je suis " . $SELF->name },
    name  => 'Chorus',
);
```

**`fmatch()`** — sélection efficace par slot via `%REPOSITORY` + `%INSTANCES` :

```perl
# tous les Frames ayant le slot 'couleur'
my @c = fmatch(slot => 'couleur');

# intersection de slots
my @r = fmatch(slot => ['couleur', 'score']);

# espace de recherche restreint
my @r = fmatch(slot => 'couleur', from => \@subset);
```

---

### 1.3 Chorus::Engine — déclenchement des règles

Un agent est **lui-même un Frame** héritant du prototype interne `$ENGINE`.

```perl
my $agent = Chorus::Engine->new(_IDENT => 'MonAgent');
```

**Structure d'une règle :**

```perl
$agent->addrule(
    _ID    => 'nom-unique',         # optionnel — déduplication
    _SCOPE => {
        var => sub { [ fmatch(slot => 'slot_cible') ] },
        # ou: var => [liste_statique]
    },
    _APPLY => sub {
        my %opts = @_;
        # $opts{var} = un Frame de la combinaison courante
        return unless <condition>;  # règle ne s'applique pas
        # ... effets ...
        return 1;                   # règle s'est appliquée
    },
);
```

**Boucle d'inférence :**
- `loop()` appelle `applyrules()` en boucle tant qu'au moins une règle retourne vrai.
- Pour chaque règle : expansion de `_SCOPE` → produit cartésien → appel `_APPLY(%opts)`.
- Sécurité : `_MAX_CYCLES` (défaut 10 000) → warning + arrêt si dépassé.

**Contrôles de flux :**

| Méthode | Portée | Effet |
|---|---|---|
| `$agent->cut()` | règle courante | sort des boucles de scope → règle suivante (même agent) |
| `$agent->last()` | agent courant | sort de la boucle de règles → agent suivant |
| `$agent->replay()` | agent courant | redémarre depuis la 1re règle de cet agent |
| `$agent->replay_all()` | tous les agents | redémarre depuis le 1er agent (remonte à l'Expert) |
| `$agent->solved()` | global | `BOARD->{SOLVED} = 'Y'` → arrêt immédiat |
| `$agent->failed()` | global | `BOARD->{FAILED} = 'Y'` → arrêt immédiat |
| `$agent->pause()` | agent | désactive jusqu'à `wakeup()` |
| `$agent->reorder(\&fn)` | agent | retrie `_RULES` + `replay()` |

---

### 1.4 Chorus::Expert — orchestration

```perl
my $xprt = Chorus::Expert->new();
$xprt->register($agent1, $agent2, $agent3);
my $ok = $xprt->process($input);  # 1=solved, undef=failed
```

- `register()` injecte le **BOARD partagé** dans chaque agent (`$agent->BOARD`).
- `process()` : `do { for each agent: agent->loop() } until BOARD->{SOLVED|FAILED}`
- `$input` accessible via `$agent->BOARD->INPUT`.
- Communication inter-agents : écrire/lire des slots sur `$agent->BOARD`.
- `_LOCK_UNTIL_STABLE` sur un agent : il est sauté si un agent précédent a déjà réussi dans l'itération courante.

---

## 2. Pattern multi-spécialités

### 2.1 Structure de projet recommandée

```
MyExpert/
  lib/
    MyExpert/
      Agent/
        Specialite1.pm     # constructeur agent + helpers Perl
        Specialite2.pm
        Specialite3.pm
      Expert.pm            # assembly + process()
  rules/
    specialite1/           # règles YAML de l'agent 1
      R01-xxx.yml
      R02-yyy.yml
    specialite2/
      R01-zzz.yml
    specialite3/
      R01-www.yml
  t/
    01-pipeline.t
```

### 2.2 Template d'agent avec helpers Perl

```perl
package MyExpert::Agent::Specialite1;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;
use Exporter 'import';

our @EXPORT_OK = qw($agent helper1 helper2);

# -- Helpers Perl appelables depuis les règles YAML --

sub helper1 {
    my ($frame) = @_;
    # ...
    return $result;
}

sub helper2 { ... }

# -- Constructeur de l'agent --

our $agent;

sub build {
    my ($class, %opts) = @_;
    $agent = Chorus::Engine->new(_IDENT => 'Specialite1');
    $agent->loadRules($opts{rules_dir} // "rules/specialite1");
    return $agent;
}

1;
```

### 2.3 Template d'assembly Expert

```perl
package MyExpert::Expert;

use strict;
use Chorus::Expert;
use MyExpert::Agent::Specialite1;
use MyExpert::Agent::Specialite2;
use MyExpert::Agent::Specialite3;

sub run {
    my ($class, $input) = @_;

    my $a1 = MyExpert::Agent::Specialite1->build();
    my $a2 = MyExpert::Agent::Specialite2->build();
    my $a3 = MyExpert::Agent::Specialite3->build();

    # Agent de contrôle (terminaison) — règle Perl pur
    my $a_ctrl = Chorus::Engine->new(_IDENT => 'Ctrl');
    $a_ctrl->addrule(
        _SCOPE => { p => sub { [ fmatch(slot => 'slot_cle') ] } },
        _APPLY => sub {
            my @all = fmatch(slot => 'slot_cle');
            return unless @all && (grep { defined $_->{statut} } @all) == scalar(@all);
            $a_ctrl->solved();
            return 1;
        },
    );

    my $xprt = Chorus::Expert->new();
    $xprt->register($a1, $a2, $a3, $a_ctrl);
    return $xprt->process($input);
}

1;
```

### 2.4 Pipeline implicite par slot

Le chaînage des agents se fait par le slot ciblé dans `CHERCHER` :

| Agent | `CHERCHER.attribut` | Pose le slot |
|---|---|---|
| Spécialité 1 | `slot_brut` | `slot_enrichi` |
| Spécialité 2 | `slot_enrichi` | `slot_calcule` |
| Spécialité 3 | `slot_calcule` | `statut` |
| Ctrl | `slot_cle` (+ vérif `statut`) | appelle `solved()` |

> **Règle d'or :** chaque agent cherche un slot que seul l'agent précédent peut avoir posé.
> Cela garantit l'ordre d'exécution sans couplage explicite.

---

## 3. Guide YAML complet

### 3.1 Structure complète d'une règle

```yaml
REGLE: nom-de-la-regle          # obligatoire — devient _ID (déduplication)
TERMINAL: solved                 # optionnel — 'solved' ou 'failed'
PREMISSES:                       # optionnel — métadonnées pour reorder()
  - slot-prerequis
  - autre-slot
CHERCHER:                        # obligatoire — définit _SCOPE
  var1:
    attribut: nom-du-slot        # → fmatch(slot => 'nom-du-slot')
    filtre: '$_->prop > 0'       # optionnel → grep { ... }
  var2:
    attribut: autre-slot
CONDITION: '$var1->ok'           # optionnel — return unless CONDITION
EXCEPTION: 'defined $var1->{r}' # optionnel — return if EXCEPTION
EFFET: |                         # obligatoire — corps de _APPLY
  $var1->set('result', $var2->value);
  1
```

### 3.2 CHERCHER — portée des variables

```yaml
CHERCHER:
  p:
    attribut: classe_bois
# → _SCOPE => { p => sub { [ fmatch(slot => 'classe_bois') ] } }

  p:
    attribut: level
    filtre: '$_->level < 5'
# → _SCOPE => { p => sub { [ grep { $_->level < 5 } fmatch(slot => 'level') ] } }
```

- **`attribut`** : slot passé à `fmatch` — définit l'espace de recherche.
- **`filtre`** : expression Perl sur `$_` (le Frame courant) — rétrécit l'espace avant `_APPLY`.
- Le filtre est évalué **avant** la boucle combinatoire → optimisation critique.

### 3.3 CONDITION vs EXCEPTION

| Clé | Sémantique | Code généré |
|---|---|---|
| `CONDITION` | La règle **doit** être vraie pour s'appliquer | `return unless <CONDITION>;` |
| `EXCEPTION` | La règle **ne doit pas** s'appliquer si vraie | `return if <EXCEPTION>;` |

> **Convention d'idempotence :** toujours ajouter `EXCEPTION: defined $var->{slot_pose}`
> pour éviter qu'une règle se déclenche en boucle sur le même Frame.

```yaml
EXCEPTION: defined $p->{fm_d}    # ne s'applique pas si fm_d déjà calculé
```

### 3.4 EFFET — syntaxes

**Bloc mono-instruction :**
```yaml
EFFET: "$frame->increase; 1"
```

**Bloc multi-lignes (YAML block scalar `|`) :**
```yaml
EFFET: |
  my $W = $p->{largeur} * $p->{hauteur} ** 2 / 6;
  my $M = $p->{q_lineique} * $p->{portee} ** 2 / 8;
  $p->set('sigma_m', $M / $W);
  1
```

**Liste d'effets séquentiels :**
```yaml
EFFET:
  - '$p->set("step1", "y")'
  - '$p->set("done", "y"); 1'
```

> ⚠️ La **dernière instruction doit retourner une valeur vraie** pour que la règle soit
> considérée comme ayant "tiré". Terminer par `1` ou par une expression vraie.

> ⚠️ Utiliser `|` (newlines préservés) et non `>` (newlines pliés) pour les blocs multi-lignes.

### 3.5 TERMINAL — terminaison automatique

```yaml
REGLE: tout-est-traite
CHERCHER:
  p:
    attribut: statut
TERMINAL: solved
EXCEPTION: '$p->{statut} ne "FINAL"'
EFFET: "1"
```

Quand la règle tire **et** `_TERMINAL => 'solved'`, l'engine appelle automatiquement `solved()`.

### 3.6 Ordre de chargement

`loadRules($dir)` charge les fichiers `*.yml` en **ordre alphabétique**.

```
R01-etape-un.yml      → chargée en premier
R02-etape-deux.yml
R10-etape-finale.yml
```

Plusieurs répertoires = plusieurs appels `loadRules()` :
```perl
$agent->loadRules("$RULES/phase1");
$agent->loadRules("$RULES/phase2");
```

### 3.7 PREMISSES — pour reorder()

`PREMISSES` est une liste de slots que la règle nécessite. Non utilisé par le moteur directement, mais accessible via `$rule->_PREMISSES` pour trier dynamiquement les règles :

```perl
sub sort_by_interest {
    my ($r1, $r2) = @_;
    return 1  if $r1->_PREMISSES->{CAT_NOM};
    return -1 if $r2->_PREMISSES->{CAT_NOM};
    return 0;
}
$agent->reorder(\&sort_by_interest);
```

---

## 4. Chorus::Collection

### 4.1 Collection::List — séquences ordonnées de Frames

```perl
use Chorus::Collection::List qw($LIST);

my $sequence = Chorus::Frame->new(_ISA => $LIST);
$sequence->build($f1, $f2, $f3);   # initialise _ITEMS, pose _CONTAINER sur chaque item

$sequence->push_items($f4);         # ajout à droite
$sequence->unshift_items($f0);      # ajout à gauche
$sequence->first_item;              # $f0
$sequence->last_item;               # $f4
$sequence->length;                  # 5

$sequence->HAS('slot');             # premier item ayant le slot truthy
$sequence->HAS_NO('slot');          # vrai si aucun item n'a ce slot
$sequence->STARTS_WITH('slot');     # teste le premier item
$sequence->ENDS_WITH('slot');       # teste le dernier item
```

**Double chaînage prev/succ :**
```perl
$f2->connect_left($f1);    # $f2->prev = $f1, $f1->succ = $f2
$f2->connect_right($f3);   # $f2->succ = $f3, $f3->prev = $f2
```

**Fusion de listes :**
```perl
$target->merge_left($list_a, $list_b);   # déplace les items à gauche
$target->merge_right($list_c);           # déplace les items à droite
# les listes sources sont vidées après merge
```

**Nom du container :** par défaut `_CONTAINER`, personnalisable :
```perl
$sequence->set_container_name('_PHRASE');
# chaque item aura un slot _PHRASE → $item->_PHRASE == $sequence
```

### 4.2 Collection::Filter — pattern matching sur séquences

```perl
use Chorus::Collection::Filter qw($FILTER @_VFILTER);

my $filtre = Chorus::Frame->new(_ISA => $FILTER);

# Définir le test par nœud (obligatoire pour comparer des valeurs de slots)
$filtre->set_node_test(sub {
    my ($frame) = @_;
    return $frame->categorie;    # retourne la valeur à comparer au motif
});

# Compiler le motif
$filtre->set_filter('^NOM (ADJ+) !PONCT*$');

# Tester une séquence
if ($filtre->check(@tokens)) {
    my ($adjectifs) = @_VFILTER;   # capture du groupe (ADJ+)
}
```

**Syntaxe des motifs :**

| Token | Signification |
|---|---|
| `^` | ancre début de séquence |
| `$` | ancre fin de séquence |
| `X` | exactement le token X |
| `[A B C]` | OU : A ou B ou C |
| `!X` | NON : n'est pas X |
| `.` | ANYTHING : n'importe quel token |
| `X+` | 1 ou plusieurs |
| `X*` | 0 ou plusieurs (greedy) |
| `X?` | 0 ou 1 (lazy) |
| `X{m,n}` | entre m et n occurrences |
| `(...)` | groupe de capture → `@_VFILTER` |

> `@_VFILTER` est réinitialisé à chaque `check()`. Capturer immédiatement après.

---

## 5. Checklist — anti-pitfalls

### ✅ Règles YAML

- [ ] **Toujours** terminer `EFFET` par une valeur vraie (`1` ou expression truthy)
- [ ] **Pitfall EFFET conditionnel sans `else`** : si le `if` ne modifie rien et que la règle retourne `1`,
      le moteur croit qu'elle a travaillé → `applyrules()` retourne vrai → boucle infinie jusqu'à `_MAX_CYCLES`.
      **Règle :** retourner `0` (ou `return 0`) quand aucun slot n'a été modifié.
      ```yaml
      # FAUX — boucle infinie si la condition n'est jamais vraie
      EFFET: |
        if ($p->{val} > 5) { $p->set('flag', 'KO') }
        1
      # CORRECT
      EFFET: |
        if ($p->{val} > 5) { $p->set('flag', 'KO'); return 1 }
        0
      ```
- [ ] **Toujours** ajouter `EXCEPTION: defined $var->{slot_pose}` pour l'idempotence
- [ ] Utiliser `|` (block scalar) pour les `EFFET` multi-lignes, jamais `>`
- [ ] Nommer les fichiers avec préfixe `R01-`, `R02-` pour contrôler l'ordre
- [ ] `filtre` dans `CHERCHER` pour réduire le scope **avant** `_APPLY`

### ✅ Frames

- [ ] Ne jamais utiliser `$f->{slot}` pour lire une valeur — utiliser `$f->slot` ou `$f->get('slot')`
- [ ] Ne jamais utiliser `$f->{slot} = $val` pour écrire — utiliser `$f->set('slot', $val)`
- [ ] Ne jamais utiliser `delete $f->{slot}` — utiliser `$f->delete('slot')`
- [ ] Ne jamais nommer un slot métier avec un `_MAJUSCULE` (réservé au système)
- [ ] Dans `_AFTER` : capturer `$SELF` **avant** tout appel à `set()` sur un autre Frame

```perl
# FAUX — $SELF sera écrasé par le set() interne
_AFTER => sub { $other->set('x', $SELF->val) }

# CORRECT
_AFTER => sub { my $ctx = $SELF; $other->set('x', $ctx->val) }
```

### ✅ Engine / Expert

- [ ] Au moins un agent ou une règle doit appeler `solved()` (sinon boucle infinie)
- [ ] Vérifier `_MAX_CYCLES` si le pipeline est long
- [ ] L'agent de terminaison doit être enregistré **en dernier** dans `register()`
- [ ] Dédupliquer les `_ID` : deux règles avec le même `REGLE` dans le même agent → la 2e est silencieusement ignorée
- [ ] `addrule()` est appelé avec `$SELF` comme contexte lors de `loadRules()` — ne pas appeler depuis un autre contexte Frame

### ✅ Collection::Filter

- [ ] Toujours appeler `set_node_test()` avant `check()` (le défaut retourne le Frame brut)
- [ ] `@_VFILTER` est global partagé — capturer immédiatement après `check()`
- [ ] Un motif avec `^` et `$` doit couvrir **exactement** toute la séquence

### ✅ Architecture multi-spécialités

- [ ] **1 spécialité = 1 agent = 1 répertoire YAML = 1 module Perl optionnel**
- [ ] Le pipeline implicite : chaque agent lit le slot posé par le précédent
- [ ] Les helpers Perl doivent être dans le namespace au moment du `loadRules()` / `eval`
- [ ] `eca/` jamais commité dans le dépôt git Engine

---

## 6. Référence rapide

### Symbols exportés

```perl
# Chorus::Frame
use Chorus::Frame;           # $SELF, &fmatch, &setMode, REQUIRE_FAILED

# Chorus::Collection::List
use Chorus::Collection::List qw($LIST);

# Chorus::Collection::Filter
use Chorus::Collection::Filter qw($FILTER @_VFILTER);
```

### Clés YAML DSL

```
REGLE       → _ID
TERMINAL    → 'solved' | 'failed'
PREMISSES   → [slot, ...]
CHERCHER    → _SCOPE (attribut + filtre optionnel)
CONDITION   → return unless ...
EXCEPTION   → return if ...
EFFET       → corps _APPLY (doit retourner vrai)
```

### Slots Engine internes

```
_RULES  _SCOPE  _APPLY  _ID  _TERMINAL  _PREMISSES
_CUT  _LAST  _REPLAY  _REPLAY_ALL  _SLEEPING  _SUCCES
_MAX_CYCLES  _LOCK_UNTIL_STABLE  _IDENT
```

### Slots BOARD (Expert)

```
SOLVED   FAILED   INPUT
```
