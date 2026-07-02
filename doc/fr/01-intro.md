# Chorus Engine — Guide technique

> Ce document complète le [README](../../README.md). Il détaille la mécanique interne : DSL YAML, API Perl de référence, nouveautés v2.

---

## Le verrou que Chorus 2.0 lève

Dans Chorus v1, les règles YAML s'écrivent à la main — une règle par article de norme, slot par slot. Sur un corpus réel (quelques dizaines de pages, des centaines d'exigences), c'est le vrai frein : non pas le moteur, mais la production des règles.

Chorus 2.0 supprime ce verrou. Le moteur Perl reste le socle — frames, slots, règles YAML, chaîne d'inférence. Un agent IA s'y greffe pour lire le corpus normatif et générer les règles. Le moteur s'exécute ensuite sans LLM — déterministe, reproductible, sur n'importe quelle machine.

**Ce que ce guide documente :** la mécanique que l'agent IA génère et que l'expert du domaine peut lire, corriger et étendre — DSL YAML, Frame API, règles de ciblage.

---

## Trois niveaux d'utilisation

Trois niveaux d'utilisation, indépendants — Perl direct, règles YAML, pipeline agent IA. Chacun est un point d'entrée valable.

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

---

## DSL YAML — Formulation des règles

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
TERMINAL: solved                 # terminer le pipeline
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

### `_MAX_CYCLES` — garde-fou boucle infinie

```perl
my $agent = Chorus::Engine->new(_MAX_CYCLES => 5000);
```

`loop()` s'arrête après `_MAX_CYCLES` cycles (défaut : 10 000) et émet un
avertissement. Chaque instance possède sa propre limite, indépendante des
autres agents d'un même `Chorus::Expert`.

Calibrage recommandé : `N_frames × N_règles × N_agents × 10`. La KB
générée par `chorus-feed` documente la valeur cible dans le fichier org de
chaque agent.

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

**`fmatch()` — interrogation de la mémoire de travail :**

```perl
my @tous   = fmatch(slot => 'masse');                          # frames ayant le slot 'masse'
my @lourds = grep { $_->{masse} > 10 } fmatch(slot => 'masse'); # par condition
my @typed  = grep { $_->{type} eq 'element' } fmatch(slot => 'type'); # par valeur exacte
```

> ⚠️ **Pitfall :** toujours utiliser `$f->set('slot', $val)` et
> `$f->delete('slot')` — jamais `$f->{slot} = $val` ni `delete $f->{slot}`,
> qui court-circuitent l'index et rendent le frame invisible à `fmatch()`.

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

## Pour aller plus loin

- [`02-ai-agent.md`](02-ai-agent.md) — positionnement LLM vs Chorus, architecture daemon, pipeline complet
- [`03-applications.md`](03-applications.md) — domaines d'application, onboarding par secteur
- [`04-chorus-commands.md`](04-chorus-commands.md) — référence complète des commandes `chorus-*`
- `perldoc Chorus::Engine` — règles, boucle d'inférence, DSL YAML, contrôle de flux
- `perldoc Chorus::Frame` — slots, héritage, modes N/Z, démons (`_NEEDED`/`_AFTER`/`_ON_DELETE`), `fmatch`, `fselect`, `complete()`, `_TERMINAL_SLOTS`, `_ALTERNATIVES`
- `perldoc Chorus::Expert` — orchestration multi-agents, BOARD partagé
- `perldoc Chorus::Collection::List` — séquences ordonnées de frames
- `perldoc Chorus::Collection::Filter` — correspondance de motifs sur séquences
