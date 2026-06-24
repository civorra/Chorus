# Skill — chorus-check

> Déclencheur : `chorus-check <sandbox-name> <fichier-projet>`
> Agent : `architect`
>
> `<sandbox-name>` : sandbox contenant la KB et les règles YAML (produits par `chorus-feed`)
> `<fichier-projet>` : fichier JSON décrivant les éléments du projet à valider,
>                      ou données fournies inline par l'utilisateur
>
> **Responsabilité unique : valider un projet contre la connaissance.**
> Le fichier projet est de la **donnée d'entrée runtime** — il n'influence pas
> la génération de l'infrastructure. Deux `chorus-check` sur le même sandbox
> avec des projets différents partagent exactement la même infrastructure.
>
> Prérequis : `chorus-feed <sandbox-name>` doit avoir été exécuté au préalable
> (KB org + YAML présents dans le sandbox).

---

## ⚡ Étape 0 — Détection infrastructure (PRIORITAIRE, avant tout chargement)

**C'est la première action à exécuter, sans exception.**

Appeler `eca__directory_tree` sur `$SANDBOX` (max_depth=3) et vérifier :

```
$SANDBOX/run.pl
$SANDBOX/lib/<Namespace>/Feed.pm
$SANDBOX/lib/<Namespace>/Expert.pm
$SANDBOX/lib/<Namespace>/Agent/<Nom>.pm  ← au moins un
```

### ✅ Infrastructure présente → CHEMIN RAPIDE

**Aller directement à la Phase 6. Ne pas charger `chorus-engine.md`. Ne pas lire
`index.org`. Ne pas lire les KB agents. Ne pas générer quoi que ce soit.**

L'infrastructure est liée au corpus/KB, pas au projet. Changer de fichier projet
ne justifie aucune régénération.

> **Régénération forcée** : uniquement si l'utilisateur mentionne explicitement
> qu'un `chorus-feed` a été exécuté depuis la dernière génération, ou demande
> textuellement de "régénérer" / "rebuilder" l'infrastructure.
> Un deuxième `chorus-check` avec un projet différent n'est **jamais** une
> régénération forcée.

### ❌ Infrastructure absente ou incomplète → CHEMIN COMPLET

Charger :
- `chorus-engine.md` — référence moteur
- `$SANDBOX/eca/agents/index.org` — pipeline, agents, namespace

> ⚠️ Ne pas lire les KB agents (`<slug>.org`) ni les YAML à ce stade.
> Ils ne sont nécessaires qu'en cas de génération (infrastructure absente).

Puis exécuter les Phases 0, 1–5, 6, 7 dans l'ordre.

---

## Phase 0 — Vérification des prérequis KB *(chemin complet uniquement)*

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

    # JSON->new->utf8->decode() opère lui-même le décodage UTF-8 depuis les octets
    # bruts — ouvrir sans ':utf8' pour éviter le double décodage (Wide character).
    open my $fh, '<', $fichier
        or die "Impossible d'ouvrir $fichier : $!\n";
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data = JSON->new->utf8->decode($json);
    my @frames;

    for my $elem (@{ $data->{elements} }) {
        my $id   = $elem->{id}   // die "Élément sans 'id'\n";
        my $type = $elem->{type} // die "Élément '$id' sans 'type'\n";

        my $requis = $SLOTS_REQUIS{$type};
        unless ($requis) {
            # Type hors-périmètre de ce sandbox : ignorer sans planter.
            # La partition des éléments par sandbox est la responsabilité
            # de chorus-import-project (flag _hors_perimetre). Ce warn est
            # un filet de sécurité pour les JSON mixtes qui atteindraient
            # run.pl malgré tout.
            warn "Type '$type' (élément '$id') hors-périmètre — ignoré\n";
            next;
        }

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
                                                      # heuristique : N_frames × N_règles × N_agents × 10
        # _LOCK_UNTIL_STABLE => 'Y',   # optionnel : sauter cet agent si un
                                       # agent précédent a déjà réussi dans
                                       # l'itération courante (optimisation)
    );

    # ⚠️ Injecter les helpers dans Chorus::Engine AVANT loadRules().
    # Les EFFET YAML sont eval'd dans Chorus::Engine — un simple `use ... qw(fn)`
    # dans ce module ne suffit pas : le helper doit être visible dans le namespace
    # Chorus::Engine au moment de l'eval.
    # Pattern obligatoire pour tout agent avec Helpers.pm :
    {
        no strict 'refs';
        *{'Chorus::Engine::<helper1>'} = \&<helper1>;
        *{'Chorus::Engine::<helper2>'} = \&<helper2>;
    }

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
leur statut) → **ne pas coder ça dans un YAML** (risque de boucle infinie avec `fmatch`
global) — ajouter une règle Perl pure via `addrule()` après `loadRules()` :

> ⚠️ **`$SELF` (YAML EFFET) vs `$agent` (Perl pur addrule()) :**
> | Contexte | Variable correcte | Raison |
> |---|---|---|
> | EFFET YAML | **`$SELF`** | `$agent` hors scope de l'eval Engine → crash `Global symbol` |
> | `_APPLY` dans `addrule()` | **`$agent` (closure)** | `$SELF` est le Frame-règle, pas l'Engine |
>
> Ce sont deux contextes d'exécution distincts — la confusion entre les deux
> a causé des crashs silencieux ou des boucles infinies. La règle est simple :
> - Dans un **fichier `.yml`** → toujours `$SELF->solved()`, `$SELF->cut()`, etc.
> - Dans un **`addrule()`** Perl pur → capturer `$agent` en closure, jamais `$SELF`.

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

    my $a1 = <Namespace>::Agent::<Nom1>->build(base_dir => $base, max_cycles => $opts{max_cycles});
    my $a2 = <Namespace>::Agent::<Nom2>->build(base_dir => $base, max_cycles => $opts{max_cycles});
    # ... dans l'ordre de #+PIPELINE_POS

    my $xprt = Chorus::Expert->new();
    # ⚠️ Bug connu : new() ignore ses arguments — forcer _MAX_ITER par affectation directe
    $xprt->{_MAX_ITER} = $opts{max_iter} // 50_000;
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

# Calibrer _MAX_CYCLES au volume réel du projet
# Heuristique : N_frames × N_règles_total_estimé × marge
# Valeur sûre : N_éléments × 50 × 10 (50 règles max, marge ×10)
my $max_cycles = scalar(@elements) * 50 * 10;
$max_cycles = 10_000 if $max_cycles < 10_000;  # minimum de sécurité

# Pipeline
my ($ok) = <Namespace>::Expert->run(
    base_dir   => $Bin,
    input      => { elements => \@elements },
    max_cycles => $max_cycles,
);

# Slots de résultat à afficher (posés par les agents)
# ⚠️ Adapter @slots_resultat_display au pipeline réel du sandbox.
my @slots_resultat_display = qw(
    qualifie motif_refus
    <slot_ok_agent1> <motif_refus_agent1>
    <slot_ok_agent2> <motif_refus_agent2>
    statut_conformite raison_non_conformite
    besoin_<agent1> besoin_<agent2> besoin_conformite
);

print "=" x 62 . "\n";
print "  RAPPORT DE CONFORMITÉ — <Namespace>\n";
print "=" x 62 . "\n\n";

my $n_conforme     = 0;
my $n_non_conforme = 0;
my $n_non_traite   = 0;

for my $e (@elements) {
    my $id   = $e->{id}   // '?';
    my $type = $e->{type_element} // $e->{type} // '?';
    my $stat = $e->{statut_conformite} // '(non traité)';

    if    ($stat eq 'CONFORME')     { $n_conforme++ }
    elsif ($stat eq 'NON_CONFORME') { $n_non_conforme++ }
    else                            { $n_non_traite++ }

    my $flag = $stat eq 'CONFORME'     ? '✅'
             : $stat eq 'NON_CONFORME' ? '❌'
             : '⚠️ ';

    printf "  %s  [%s — %s]\n", $flag, $id, $type;

    my @res = grep { defined $e->{$_} } @slots_resultat_display;
    for my $slot (@res) {
        next if $slot eq 'raison_non_conformite';
        printf "       %-32s : %s\n", $slot, $e->{$slot};
    }
    if (defined $e->{raison_non_conformite}) {
        printf "       %-32s : %s\n", '→ raison', $e->{raison_non_conformite};
    }
    print "\n";
}

# ── Bloc 1 : Taux de conformité ───────────────────────────────────────────
my $n_total = scalar @elements;
my $taux    = $n_total ? int(0.5 + 100 * $n_conforme / $n_total) : 0;
my $bar_ok  = int($taux / 5);
my $bar_ko  = 20 - $bar_ok;
my $barre   = '█' x $bar_ok . '░' x $bar_ko;

print "─" x 62 . "\n";
printf "  Conformes      : %d / %d  (%d%%)\n", $n_conforme,     $n_total, $taux;
printf "  Non conformes  : %d / %d\n",          $n_non_conforme, $n_total;
printf "  Non traités    : %d / %d\n",           $n_non_traite,   $n_total;
printf "  [%s]  %d%%\n", $barre, $taux;
printf "  Pipeline       : %s\n", $ok ? 'SOLVED ✅' : 'FAILED/TIMEOUT ❌';
print "─" x 62 . "\n";

# ── Bloc 2 : Processus de validation — traversée par agent ────────────────
# Adapter @pipeline_def à l'index.org du sandbox :
#   [ label, slot_ciblage, slot_resultat_ok ]
{
    my @pipeline_def = (
        [ '<Agent1>', 'besoin_<agent1>', '<slot_ok_agent1>' ],
        [ '<Agent2>', 'besoin_<agent2>', '<slot_ok_agent2>' ],
        [ 'Conformite', 'besoin_conformite', 'statut_conformite' ],
    );

    print "\n  Processus de validation — traversée par agent\n";
    print "  " . "─" x 58 . "\n";
    printf "  %-16s  %7s  %6s  %6s  %5s\n", 'Agent', 'Ciblés', 'OK', 'KO', 'NA';
    print "  " . "─" x 58 . "\n";

    for my $def (@pipeline_def) {
        my ($label, $slot_cible, $slot_res) = @$def;
        my @cibles   = grep { defined $_->{$slot_cible} } @elements;
        my $n_cibles = scalar @cibles;
        my ($n_ok, $n_ko, $n_na) = (0, 0, 0);
        for my $e (@cibles) {
            my $res = $e->{$slot_res} // '';
            if    ($res eq 'NA')                              { $n_na++ }
            elsif ($res =~ /^(OUI|CONFORME|1)$/i)            { $n_ok++ }
            elsif ($res =~ /^(NON|NON_CONFORME|KO)$/i)       { $n_ko++ }
            elsif ($slot_res eq 'statut_conformite') {
                if    ($res eq 'CONFORME')     { $n_ok++ }
                elsif ($res eq 'NON_CONFORME') { $n_ko++ }
            }
        }
        printf "  %-16s  %7d  %6s  %6s  %5s\n",
            $label, $n_cibles,
            $n_ok ? $n_ok : '-',
            $n_ko ? $n_ko : '-',
            $n_na ? $n_na : '-';
    }
    print "  " . "─" x 58 . "\n";

    # Chemin de chaque élément à travers les agents
    print "\n  Chemin de validation par élément\n";
    print "  " . "─" x 58 . "\n";
    for my $e (@elements) {
        my $id   = $e->{id}   // '?';
        my $stat = $e->{statut_conformite} // '';
        my $flag = $stat eq 'CONFORME'     ? '✅'
                 : $stat eq 'NON_CONFORME' ? '❌'
                 : '⚠️ ';
        my @chemin;
        for my $def (@pipeline_def) {
            my ($label, $slot_cible, $slot_res) = @$def;
            next unless defined $e->{$slot_cible};
            my $res = $e->{$slot_res} // '?';
            my $res_short = $res =~ /^(OUI|CONFORME|1)$/i      ? '✓'
                          : $res =~ /^(NON|NON_CONFORME|KO)$/i ? '✗'
                          : $res eq 'NA'                        ? '–'
                          : '?';
            push @chemin, "$label($res_short)";
        }
        printf "  %s  %-18s  %s\n", $flag, $id, join(' → ', @chemin);
    }
    print "  " . "─" x 58 . "\n";
}

# ── Bloc 3 : Répartition par type d'élément ───────────────────────────────
{
    my (%ok_par_type, %ko_par_type, %tous_types);
    for my $e (@elements) {
        my $type = $e->{type_element} // $e->{type} // '?';
        $tous_types{$type}++;
        my $stat = $e->{statut_conformite} // '';
        if    ($stat eq 'CONFORME')     { $ok_par_type{$type}++ }
        elsif ($stat eq 'NON_CONFORME') { $ko_par_type{$type}++ }
    }
    print "\n  Répartition par type d'élément\n";
    print "  " . "─" x 46 . "\n";
    printf "  %-30s  %5s  %5s\n", 'Type', '✅', '❌';
    print "  " . "─" x 46 . "\n";
    for my $t (sort keys %tous_types) {
        printf "  %-30s  %5d  %5d\n",
            $t,
            $ok_par_type{$t} // 0,
            $ko_par_type{$t} // 0;
    }
    print "  " . "─" x 46 . "\n";
}

# ── Bloc 4 : Synthèse des non-conformités ─────────────────────────────────
{
    my @nc;
    for my $e (@elements) {
        push @nc, $e if ($e->{statut_conformite} // '') eq 'NON_CONFORME';
    }
    if (@nc) {
        print "\n  Synthèse des non-conformités\n";
        print "  " . "─" x 58 . "\n";
        for my $e (@nc) {
            my $id   = $e->{id}   // '?';
            my $type = $e->{type_element} // $e->{type} // '?';
            # Adapter la cascade de motifs aux slots du sandbox
            my $raison = $e->{raison_non_conformite}
                      // $e->{motif_refus}
                      // '(raison non renseignée)';
            printf "  ❌  %-18s [%s]\n      %s\n\n", $id, $type, $raison;
        }
        print "  " . "─" x 58 . "\n";
    }
}
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

**Afficher la sortie complète verbatim** dans un bloc de code — systématiquement, sans
résumé ni reformulation à la place. C'est le rapport principal ; ne jamais le remplacer
par une synthèse tabulaire.

Après la sortie verbatim, signaler en commentaire court (optionnel) :
- Éléments `NON_CONFORME` avec leur motif si `ref_corpus` absent
- Éléments `(non traité)` → slot de ciblage probablement absent du Feed
- Écarts avec les `_resultats_attendus` du fichier projet (si présents)

---

## Phase 7 — Vérification finale *(post-génération uniquement)*

> ⚠️ Cette checklist s'applique **uniquement après génération** des Phases 1–5.
> Ne pas l'exécuter sur le chemin rapide (infrastructure déjà présente).

- [ ] `Feed.pm` : slot de ciblage agent 1 présent dans `%SLOTS_REQUIS`
- [ ] `Feed.pm` : validation slots obligatoires couvre tous les types du projet
- [ ] `Feed.pm` : types inconnus → `warn + next` (pas `die`) — filet de sécurité JSON mixte multi-sandboxes
- [ ] `Expert.pm` : ordre `register()` = ordre `#+PIPELINE_POS`
- [ ] `Expert.pm` : `$xprt->{_MAX_ITER}` forcé **après** `new()` (bug connu : `new()` ignore ses arguments)
- [ ] `run.pl` : chemin `../../Engine/lib` correct depuis le sandbox
- [ ] `run.pl` : aucune donnée codée en dur
- [ ] Rapport : aucun élément `(non traité)` inattendu
- [ ] `_MAX_CYCLES` : valeur calibrée au volume réel de Frames attendu.
      Heuristique : `N_frames × N_règles_total × N_agents × 10 < _MAX_CYCLES`.
      Dans `run.pl` : calculer depuis `scalar(@elements)` et passer via `Expert->run(max_cycles => ...)`.
      Ne jamais laisser la valeur par défaut (`10_000`) pour un pipeline de production.
- [ ] Agent de terminaison : `solved()` appelé sur `$agent` (closure) dans `addrule()`, jamais sur `$SELF`.
      Dans un EFFET YAML → `$SELF->solved()`. Dans un `addrule()` Perl pur → `$agent->solved()` (capturé en closure).
      ⛔ **Ne jamais coder une terminaison par `fmatch` global dans un YAML** → boucle infinie garantie.
- [ ] Si `reorder()` utilisé : la fonction de tri consulte `_PREMISSES` — cohérent avec les YAML
- [ ] Si `_LOCK_UNTIL_STABLE` activé : l'agent peut être sauté — vérifier que ce comportement est voulu
- [ ] BOARD : les clés utilisées en inter-agents sont documentées dans `index.org`
- [ ] **YAML — EFFET conditionnel sans `else`** : si le `if` ne modifie rien et que la règle retourne `1`,
      le moteur boucle jusqu'à `_MAX_CYCLES` (warning). Vérifier chaque YAML dont l'EFFET
      contient un `if` sans `else` → retourner `0` quand aucun slot n'est modifié :
      `if (...) { ...; return 1 } 0`

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
