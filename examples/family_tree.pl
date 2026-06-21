#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Chorus::Frame;
use Chorus::Engine;

# =============================================================================
# family_tree.pl — Arbre généalogique avec inférence
#
# Démonstration de :
#   - _NEEDED      : backward chaining (inférer nationality si absente)
#   - _DEFAULT     : valeur de repli sans calcul
#   - _BEFORE      : validation avant écriture (born_in doit être une ville connue)
#   - _REQUIRE     : bloquer l'écriture si validation échoue
#   - _inherits()  : ajouter un parent après construction
#   - _ISA multiple: hériter de deux parents (père et mère)
#   - setMode Z/N  : priorité locale vs héritage
#   - fmatch()     : sélection rapide par slots
#   - delete()     : retirer un attribut et son indexation REPOSITORY
# =============================================================================

# ---------------------------------------------------------------------------
# Villes connues (pour validation _BEFORE)
# ---------------------------------------------------------------------------
my %VILLES_CONNUES = map { $_ => 1 } qw(
    Paris Lyon Marseille Bordeaux Toulouse
    Madrid Barcelona Seville
    Rome Milan Naples
);

# ---------------------------------------------------------------------------
# Frame prototype : une Personne
# Slots communs avec _NEEDED pour l'inférence
# ---------------------------------------------------------------------------
my $PERSONNE = Chorus::Frame->new(

    # nationality : inférée depuis born_in ou héritée du père/mère
    nationality => {
        _NEEDED => sub {
            # Règle 1 : si born_in connu → nationality selon ville
            if (my $ville = $SELF->born_in) {
                return 'française'  if $ville =~ /^(Paris|Lyon|Marseille|Bordeaux|Toulouse)$/;
                return 'espagnole'  if $ville =~ /^(Madrid|Barcelona|Seville)$/;
                return 'italienne'  if $ville =~ /^(Rome|Milan|Naples)$/;
            }
            # Règle 2 : sinon héritée du père (mode N : premier ancêtre qui répond)
            return;  # laisse _expandInherits remonter via _ISA
        },
        _DEFAULT => 'inconnue',
    },

    # born_in : avec validation _BEFORE via _REQUIRE
    born_in => {
        _REQUIRE => sub {
            my $ville = shift;
            return unless defined $ville;
            unless ($VILLES_CONNUES{$ville}) {
                warn "  [REQUIRE] '$ville' n'est pas une ville reconnue — écriture refusée\n";
                return REQUIRE_FAILED;
            }
        },
    },

    # prénom : _DEFAULT générique
    prenom => { _DEFAULT => '(inconnu)' },
);

# ---------------------------------------------------------------------------
# Construction de l'arbre — génération I (grands-parents)
# ---------------------------------------------------------------------------
my $luigi = Chorus::Frame->new(
    _ISA     => $PERSONNE,
    prenom   => 'Luigi',
    born_in  => 'Rome',
    # nationality sera inférée : 'italienne'
);

my $elena = Chorus::Frame->new(
    _ISA     => $PERSONNE,
    prenom   => 'Elena',
    born_in  => 'Rome',
);

my $jean  = Chorus::Frame->new(
    _ISA     => $PERSONNE,
    prenom   => 'Jean',
    born_in  => 'Paris',
    # nationality : 'française'
);

my $marie = Chorus::Frame->new(
    _ISA     => $PERSONNE,
    prenom   => 'Marie',
    born_in  => 'Lyon',
);

# ---------------------------------------------------------------------------
# Génération II (parents)
# _ISA multiple : père + mère + prototype
# ---------------------------------------------------------------------------
my $marco = Chorus::Frame->new(
    _ISA   => [$PERSONNE, $luigi, $elena],
    prenom => 'Marco',
    # born_in absent → nationality héritée de $luigi (premier _ISA avec nationality)
);

my $sophie = Chorus::Frame->new(
    _ISA   => [$PERSONNE, $jean, $marie],
    prenom => 'Sophie',
    born_in => 'Bordeaux',
    # nationality inférée localement : 'française'
);

# ---------------------------------------------------------------------------
# Génération III (enfant)
# Héritage multiple : père Marco (italien) + mère Sophie (française)
# On teste setMode Z vs N pour voir lequel des parents prime
# ---------------------------------------------------------------------------
my $luca = Chorus::Frame->new(
    _ISA   => [$PERSONNE, $marco, $sophie],
    prenom => 'Luca',
    # born_in absent, nationality absente → inférence via _NEEDED puis _ISA
);

# ---------------------------------------------------------------------------
# Affichage helper
# ---------------------------------------------------------------------------
sub affiche {
    my ($label, $frame) = @_;
    Chorus::Frame::setMode('N');   # mode par défaut
    printf "  %-10s | born_in=%-12s | nationality (mode N)=%-12s",
        $frame->prenom // '?',
        $frame->born_in // '-',
        $frame->nationality // '?';
    Chorus::Frame::setMode('Z');
    printf " | nationality (mode Z)=%s\n", $frame->nationality // '?';
    Chorus::Frame::setMode('N');   # restore
}

# ---------------------------------------------------------------------------
# Section 1 : inférence de nationality
# ---------------------------------------------------------------------------
print "\n", "=" x 70, "\n";
print "1. Inférence de nationalité\n";
print "=" x 70, "\n";

for my $p ([$luigi,'Luigi'], [$elena,'Elena'], [$jean,'Jean'], [$marie,'Marie'],
           [$marco,'Marco'], [$sophie,'Sophie'], [$luca,'Luca']) {
    affiche($p->[1], $p->[0]);
}

# ---------------------------------------------------------------------------
# Section 2 : _BEFORE + _REQUIRE — ville inconnue refusée
# ---------------------------------------------------------------------------
print "\n", "=" x 70, "\n";
print "2. Validation _BEFORE/_REQUIRE — ville inconnue refusée\n";
print "=" x 70, "\n";

my $test = Chorus::Frame->new(_ISA => $PERSONNE, prenom => 'Test');

print "  Tentative born_in = 'Atlantis' :\n";
$test->set('born_in', 'Atlantis');
printf "  born_in après tentative : %s\n", $test->born_in // '(non écrit — REQUIRE_FAILED)';

print "  Tentative born_in = 'Madrid' :\n";
$test->set('born_in', 'Madrid');
printf "  born_in après écriture  : %s\n", $test->born_in // '?';
printf "  nationality inférée     : %s\n", $test->nationality // '?';

# ---------------------------------------------------------------------------
# Section 3 : _inherits() post-construction
# ---------------------------------------------------------------------------
print "\n", "=" x 70, "\n";
print "3. _inherits() post-construction\n";
print "=" x 70, "\n";

my $anna = Chorus::Frame->new(_ISA => $PERSONNE, prenom => 'Anna', born_in => 'Seville');
my $tom  = Chorus::Frame->new(prenom => 'Tom');  # pas encore de _ISA

printf "  Tom nationality AVANT _inherits : %s\n", $tom->nationality // '(undef)';

$tom->_inherits($PERSONNE, $anna);

printf "  Tom nationality APRÈS _inherits($anna->{prenom}) : %s\n",
    $tom->nationality // '(undef)';

# ---------------------------------------------------------------------------
# Section 4 : fmatch() — sélection par slots
# ---------------------------------------------------------------------------
print "\n", "=" x 70, "\n";
print "4. fmatch() — frames ayant born_in ET nationality\n";
print "=" x 70, "\n";

# nationality doit être matérialisée (via set ou _NEEDED déjà évalué)
# On force l'évaluation pour les frames qui ne l'ont pas encore
for my $p ($luigi, $elena, $jean, $marie, $marco, $sophie, $luca, $anna) {
    my $n = $p->nationality;
    $p->set('nationality', $n) if defined $n;
}

my @avec_les_deux = fmatch(slot => ['born_in', 'nationality']);
printf "  %d frame(s) avec born_in + nationality :\n", scalar @avec_les_deux;
for my $f (sort { ($a->prenom//'') cmp ($b->prenom//'') } @avec_les_deux) {
    next unless $f->prenom;  # exclure frames internes
    printf "    %-10s born_in=%-12s nationality=%s\n",
        $f->prenom, $f->born_in // '-', $f->nationality // '?';
}

# ---------------------------------------------------------------------------
# Section 5 : delete() — retrait propre d'un attribut
# ---------------------------------------------------------------------------
print "\n", "=" x 70, "\n";
print "5. delete() — retrait d'un attribut et de son indexation\n";
print "=" x 70, "\n";

printf "  Sophie born_in AVANT delete : %s\n", $sophie->born_in // '(undef)';

# Vérifier que fmatch trouve Sophie avant delete
my @avant = grep { ($_->prenom//'') eq 'Sophie' } fmatch(slot => ['born_in']);
printf "  fmatch(born_in) trouve Sophie AVANT : %s\n", @avant ? 'oui' : 'non';

$sophie->delete('born_in');

printf "  Sophie born_in APRÈS delete  : %s\n", $sophie->born_in // '(undef — héritée)';

my @apres = grep { ($_->prenom//'') eq 'Sophie' } fmatch(slot => ['born_in']);
printf "  fmatch(born_in) trouve Sophie APRÈS : %s\n", @apres ? 'oui' : 'non';

# ---------------------------------------------------------------------------
# Section 6 : setMode Z — la règle locale prime sur l'héritage
# ---------------------------------------------------------------------------
print "\n", "=" x 70, "\n";
print "6. setMode Z vs N — priorité locale vs héritage\n";
print "=" x 70, "\n";

# Luca hérite de Marco (italien) et Sophie (française)
# Mode N : _NEEDED de $PERSONNE est testé en premier sur chaque ancêtre avant
#          de passer à l'ancêtre suivant → Marco répond en premier (born_in absent
#          → remonte vers luigi → 'italienne')
# Mode Z : toute la séquence (_VALUE, _DEFAULT, _NEEDED) est testée sur Luca
#          avant de passer aux ancêtres → _NEEDED de Luca remonte lui-même

Chorus::Frame::setMode('N');
printf "  Luca nationality mode N : %s\n", $luca->nationality // '?';

Chorus::Frame::setMode('Z');
printf "  Luca nationality mode Z : %s\n", $luca->nationality // '?';

Chorus::Frame::setMode('N');   # restore

print "\n";
