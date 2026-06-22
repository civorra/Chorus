# Skill — chorus-check

> Déclencheur : `chorus-check <sandbox-name> <fichier-projet>`
> Agent : `architect`
>
> `<sandbox-name>` : sandbox contenant la KB et les règles YAML (produits par `chorus-feed`)
> `<fichier-projet>` : fichier JSON décrivant les éléments du projet à valider,
>                      ou données fournies inline par l'utilisateur
>
> **Responsabilité unique : valider un projet contre la connaissance.**
> Ce skill lit la KB issue de `chorus-feed` et génère le code d'exécution
> nécessaire pour lancer le pipeline Chorus et produire un rapport de conformité.
>
> Prérequis : `chorus-feed <sandbox-name>` doit avoir été exécuté au préalable
> (KB org + YAML présents dans le sandbox).

---

## 0. Chargements préalables

Charger :
- `chorus-engine.md` — référence moteur
- Lire `$SANDBOX/eca/agents/index.org` — pipeline, agents, namespace
- Lire chaque `$SANDBOX/eca/agents/<slug>.org` — Catalogues des Frames,
  Dictionnaires des slots, Helpers Perl

---

## Phase 0 — Vérification des prérequis

```
$SANDBOX/eca/agents/index.org     ← doit exister
$SANDBOX/eca/agents/<slug>.org    ← au moins un agent
$SANDBOX/rules/<slug>/            ← au moins un fichier YAML par agent
```

Si l'un de ces éléments est absent → stopper et indiquer :
`"KB incomplète — lancer chorus-feed <sandbox-name> <corpus> d'abord."`

Extraire depuis `index.org` :
- Le namespace Perl du projet
- La liste ordonnée des agents (pos, slug, module Perl)
- L'agent de terminaison (dernier)

---

## Phase 1 — Analyser le fichier projet

### 1.1 Format attendu

```json
{
  "projet": "<nom>",
  "elements": [
    {
      "id": "<identifiant unique>",
      "type": "<type d'élément>",
      "<slot1>": <valeur1>,
      "<slot2>": <valeur2>
    }
  ]
}
```

Si le fichier projet est fourni **inline** (données collées dans le message) →
l'écrire dans `$SANDBOX/projet.json` avant de continuer.

### 1.2 Déduire les slots obligatoires

Pour chaque type d'élément présent dans le fichier projet, croiser avec le
`Catalogue des Frames` des KB pour identifier les slots marqués `obligatoire`.
Ces slots alimenteront la validation du Feed.

### 1.3 Identifier le slot de ciblage de l'agent 1

Lire la section `Slots de ciblage` de la KB de l'agent en position 1.
Ce slot doit être présent sur tous les Frames créés par le Feed.

---

## Phase 2 — Générer `Feed.pm`

Créer `$SANDBOX/lib/<Namespace>/Feed.pm` :

```perl
package <Namespace>::Feed;

use strict;
use warnings;
use Chorus::Frame;
use JSON ();
use Exporter 'import';

our @EXPORT_OK = qw(load_projet);

# Slots obligatoires par type — extrait des KB (Catalogue des Frames)
my %SLOTS_REQUIS = (
    '<type1>' => [qw(<slot_a> <slot_b>)],
    '<type2>' => [qw(<slot_a> <slot_c>)],
);

sub load_projet {
    my ($fichier) = @_;

    open my $fh, '<:utf8', $fichier
        or die "Impossible d'ouvrir $fichier : $!\n";
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data = JSON->new->utf8->decode($json);
    my @frames;

    for my $elem (@{ $data->{elements} }) {
        my $id   = $elem->{id}   // die "Élément sans 'id'\n";
        my $type = $elem->{type} // die "Élément '$id' sans 'type'\n";

        my $requis = $SLOTS_REQUIS{$type}
            or die "Type inconnu '$type' (élément '$id')\n";

        for my $slot (@$requis) {
            die "Slot '$slot' manquant pour '$id' (type $type)\n"
                unless defined $elem->{$slot};
        }

        # Le slot de ciblage de l'agent 1 (<slot_ciblage_agent1>) est
        # garanti présent par la validation ci-dessus.
        push @frames, Chorus::Frame->new(%$elem);
    }

    return @frames;
}

1;
```

**Substitutions depuis les KB :**
- `%SLOTS_REQUIS` ← slots `obligatoire` du Catalogue des Frames de chaque KB
- commentaire slot de ciblage agent 1 ← section `Slots de ciblage` KB pos 1

---

## Phase 3 — Générer les modules Agent

Pour chaque agent de l'index, créer `$SANDBOX/lib/<Namespace>/Agent/<Nom>.pm`.

Ce module est **de l'infrastructure pure** — il ne contient aucune logique métier.
La logique métier est dans les YAML (règles) et dans `Helpers.pm` (produit par `chorus-feed`).

```perl
package <Namespace>::Agent::<Nom>;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Helpers de connaissance métier — produits par chorus-feed
# Importés AVANT loadRules() pour être disponibles dans les EFFET YAML (eval)
use <Namespace>::Agent::<Nom>::Helpers qw(
    <helper1>
    <helper2>
);

# Helpers partagés entre agents (si présents)
# use <Namespace>::Helpers::Shared qw(<helper_partage>);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => '<Nom>',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,  # sécurité boucle infinie
                                                      # augmenter si pipeline long
        # _LOCK_UNTIL_STABLE => 'Y',   # optionnel : sauter cet agent si un
                                       # agent précédent a déjà réussi dans
                                       # l'itération courante (optimisation)
    );

    # Les helpers sont déjà dans le namespace — loadRules() peut les appeler
    $agent->loadRules("$base/rules/<slug>");

    # reorder() optionnel — trier les règles par pertinence après loadRules()
    # si la KB définit des PREMISSES et qu'un tri initial est bénéfique :
    # $agent->reorder(sub {
    #     my ($r1, $r2) = @_;
    #     return 1  if $r1->_PREMISSES && $r1->_PREMISSES->{<slot_cle>};
    #     return -1 if $r2->_PREMISSES && $r2->_PREMISSES->{<slot_cle>};
    #     return 0;
    # });

    # pause() optionnel — désactiver l'agent jusqu'à ce qu'une condition
    # externe appelle $agent->wakeup() :
    # $agent->pause() if $opts{deferred};

    return $agent;
}

1;
```

**Règle pour l'agent de terminaison :**
Si la KB indique `TERMINAL: solved` dans un YAML → pas de code Perl supplémentaire.
Si la terminaison nécessite un test global (ex. vérifier que TOUS les Frames ont
leur statut) → ajouter une règle Perl pure via `addrule()` après `loadRules()` :

```perl
$agent->addrule(
    _ID    => 'terminer',
    _SCOPE => {
        p => sub { [ Chorus::Frame::fmatch(slot => '<slot_ciblage>') ] },
    },
    _APPLY => sub {
        my %opts = @_;
        # Test global — ne pas utiliser cut()/last() ici sauf intention explicite
        my @sans = grep { !defined $_->{statut} }
                   Chorus::Frame::fmatch(slot => '<slot_ciblage>');
        if (@sans == 0) {
            $agent->solved();   # $agent capturé en closure — correct
            return 1;
        }
        return;
    },
);
```

> ⚠ **Contrôles de flux disponibles dans `_APPLY`** (Perl pur ou EFFET YAML) :
> - `$agent->cut()`        → sort du scope courant → règle suivante (même agent)
> - `$agent->last()`       → sort de la boucle de règles → agent suivant
> - `$agent->replay()`     → redémarre depuis la 1re règle de cet agent
> - `$agent->replay_all()` → redémarre depuis le 1er agent
> - `$agent->solved()`     → `BOARD->{SOLVED} = 'Y'` → arrêt immédiat
> - `$agent->failed()`     → `BOARD->{FAILED} = 'Y'` → arrêt immédiat
>
> ⚠ **`$agent` doit être capturé en closure** dans `addrule()` Perl pur.
> Ne jamais utiliser `$SELF->solved()` — `$SELF` est le Frame-règle courant,
> pas l'agent Engine.

**Si `Helpers.pm` est absent pour un agent** (aucun helper dans la KB) :
→ omettre les lignes `use ... ::Helpers`.

---

## Phase 4 — Générer `Expert.pm`

Créer `$SANDBOX/lib/<Namespace>/Expert.pm` :

```perl
package <Namespace>::Expert;

use strict;
use warnings;
use Chorus::Expert;
use Chorus::Frame;
use <Namespace>::Agent::<Nom1>;
use <Namespace>::Agent::<Nom2>;
# ... un use par agent dans l'ordre du pipeline

sub run {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    my $a1 = <Namespace>::Agent::<Nom1>->build(base_dir => $base);
    my $a2 = <Namespace>::Agent::<Nom2>->build(base_dir => $base);
    # ... dans l'ordre de #+PIPELINE_POS

    my $xprt = Chorus::Expert->new();
    $xprt->register($a1, $a2);   # ordre = pipeline (#+PIPELINE_POS)

    # BOARD — tableau de bord partagé entre tous les agents
    # Accessible dans les règles via : $agent->BOARD->{<cle>}
    # Exemples d'usage inter-agents :
    #   $a1->BOARD->{phase_courante} = 'validation';   # posé par a1
    #   $a2->BOARD->{phase_courante}                   # lu par a2
    # Les clés SOLVED et FAILED sont réservées au moteur.
    # INPUT est posé par process() : $agent->BOARD->{INPUT} = $input

    return $xprt->process($opts{input} // {});
}

1;
```

**Communication inter-agents via BOARD :**
Si la KB documente des dépendances entre agents qui ne passent pas par des slots
de Frames (ex. un flag global, un compteur, un état de phase) → utiliser `BOARD`.
Le BOARD est injecté dans tous les agents par `register()` — chaque agent y accède
via `$agent->BOARD`.

> ⚠ Ne pas confondre BOARD et Frames :
> - **Frame** : connaissance sur un objet du domaine (élément, entité)
> - **BOARD** : état partagé de l'exécution (flags globaux, compteurs, INPUT)

---

## Phase 5 — Générer `run.pl`

`run.pl` est le point d'entrée unique. Il ne contient **aucune donnée** :

```perl
#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../../Engine/lib";   # Chorus::Engine, Frame, Expert, Collection
use lib "$Bin/lib";                 # <Namespace>::*

use <Namespace>::Feed   qw(load_projet);
use <Namespace>::Expert;

my $fichier = shift @ARGV
    or die "Usage : perl run.pl <fichier-projet.json>\n";
-f $fichier or die "Fichier introuvable : $fichier\n";

# Feed — données projet → Frames Chorus
my @elements = load_projet($fichier);
printf "Feed : %d élément(s) chargé(s)\n\n", scalar @elements;

# Pipeline
my ($ok) = <Namespace>::Expert->run(
    base_dir => $Bin,
    input    => { elements => \@elements },
);

# Rapport
print "=" x 60 . "\n";
print "  RAPPORT DE CONFORMITÉ\n";
print "=" x 60 . "\n\n";

my $n = 0;
for my $e (@elements) {
    $n++;
    printf "  Élément %d [%s — %s]\n", $n, $e->{id}//'?', $e->{type}//'?';
    # Slots de résultat : tous les slots posés par les agents (non système)
    for my $slot (sort grep { $_ !~ /^_/ && defined $e->{$_} } keys %$e) {
        printf "    %-28s : %s\n", $slot, $e->{$slot};
    }
    print "\n";
}

printf "Pipeline : %s\n\n", $ok ? 'SOLVED' : 'FAILED/TIMEOUT';
```

---

## Phase 6 — Exécution et rapport

Lancer le pipeline :

```bash
perl $SANDBOX/run.pl $SANDBOX/projet.json
```

Capturer la sortie. Si des erreurs Perl surviennent :
- Erreur `loadRules` → vérifier les YAML (syntaxe, indentation)
- Erreur `Can't locate` → vérifier `use lib` et le namespace
- Pipeline `FAILED/TIMEOUT` → vérifier la règle de terminaison

Présenter le rapport à l'utilisateur en mettant en évidence :
- Éléments `NON_CONFORME` avec leur `ref_corpus`
- Éléments `(non traité)` → slot de ciblage probablement absent du Feed

---

## Phase 7 — Vérification finale

- [ ] `Feed.pm` : slot de ciblage agent 1 présent dans `%SLOTS_REQUIS`
- [ ] `Feed.pm` : validation slots obligatoires couvre tous les types du projet
- [ ] `Expert.pm` : ordre `register()` = ordre `#+PIPELINE_POS`
- [ ] `run.pl` : chemin `../../Engine/lib` correct depuis le sandbox
- [ ] `run.pl` : aucune donnée codée en dur
- [ ] Rapport : aucun élément `(non traité)` inattendu
- [ ] `_MAX_CYCLES` : valeur suffisante pour le volume de Frames attendu
      (règle : N_frames × N_règles × N_agents < `_MAX_CYCLES`)
- [ ] Agent de terminaison : `solved()` appelé sur `$agent` (closure), jamais sur `$SELF`
- [ ] Si `reorder()` utilisé : la fonction de tri consulte `_PREMISSES` — cohérent avec les YAML
- [ ] Si `_LOCK_UNTIL_STABLE` activé : l'agent peut être sauté — vérifier que ce comportement est voulu
- [ ] BOARD : les clés utilisées en inter-agents sont documentées dans `index.org`

---

## Séparation des responsabilités — résumé

| | `chorus-feed` | `chorus-check` |
|---|---|---|
| **Lit** | corpus de normes | KB org + YAML + Helpers.pm du sandbox |
| **Produit** | KB org, YAML, `Helpers.pm` | `Feed.pm`, `Agent/<Nom>.pm` (shell), `Expert.pm`, `run.pl` |
| **Ne produit pas** | code infrastructure | KB org, YAML, Helpers.pm |
| **Déclenché par** | nouvelle norme / enrichissement | projet à valider |
| **Résultat** | connaissance persistante | rapport de conformité |

> Un sandbox peut subir N `chorus-feed` successifs (enrichissements)
> puis N `chorus-check` indépendants (projets différents).
> La KB et les Helpers sont stables et cumulatifs.
> Les artefacts d'infrastructure (Feed, Agent shell, Expert, run.pl)
> sont régénérés à chaque `chorus-check`.
