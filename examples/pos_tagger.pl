#!/usr/bin/perl
use strict;
use warnings;

use lib '../lib';

use Chorus::Frame;
use Chorus::Collection::List   qw($LIST);
use Chorus::Collection::Filter qw($FILTER @_VFILTER);

# =============================================================================
# pos_tagger.pl — Analyseur morpho-syntaxique minimal
#
# Démontre :
#   - Chorus::Collection::List  : la phrase = liste de frames-tokens
#   - Chorus::Collection::Filter: motifs DET ADJ* NOM (GN), VRB NOM (GV)
#   - @_VFILTER (captures)      : extraire les tokens d'un groupe capturé
#   - Frames tokens              : slots 'forme' + 'cats' (liste de catégories)
#   - Héritage entre tokens      : $TOKEN prototype + _NEEDED pour catégories
# =============================================================================

# ---------------------------------------------------------------------------
# Prototype token — _NEEDED pour la catégorie par défaut
# ---------------------------------------------------------------------------
my $TOKEN = Chorus::Frame->new(
    categorie => { _DEFAULT => 'INCONNU' },
);

# ---------------------------------------------------------------------------
# Lexique minimal : forme → liste de catégories possibles
# ---------------------------------------------------------------------------
my %LEXIQUE = (
    le      => ['DET'], la      => ['DET'], les   => ['DET'],
    un      => ['DET'], une     => ['DET'],
    chat    => ['NOM'], chien   => ['NOM'], souris  => ['NOM'],
    oiseau  => ['NOM'], maison  => ['NOM'], jardin  => ['NOM'],
    noir    => ['ADJ'], blanche => ['ADJ'], petit   => ['ADJ'],
    grands  => ['ADJ'], vieille => ['ADJ'], grand   => ['ADJ'],
    mange   => ['VRB'], voit    => ['VRB'], attrape => ['VRB'], dort => ['VRB'],
    court   => ['VRB', 'ADJ'],
);

# ---------------------------------------------------------------------------
# Filtre syntaxique — node_test : première catégorie du token
# ---------------------------------------------------------------------------
my $node_test = sub {
    my $tok = shift;
    return '' unless ref($tok);
    my $cats = eval { $tok->{cats} } // [];
    return ref($cats) eq 'ARRAY' ? ($cats->[0] // '') : '';
};

my $gn_filter = Chorus::Frame->new(_ISA => $FILTER);
$gn_filter->set_node_test($node_test);
$gn_filter->set_filter('DET ADJ* NOM');

my $gv_filter = Chorus::Frame->new(_ISA => $FILTER);
$gv_filter->set_node_test($node_test);
$gv_filter->set_filter('VRB NOM');

# Filtre avec capture — GN étendu : DET (ADJ*) NOM
my $gn_cap_filter = Chorus::Frame->new(_ISA => $FILTER);
$gn_cap_filter->set_node_test($node_test);
$gn_cap_filter->set_filter('DET (ADJ*) NOM');

# ---------------------------------------------------------------------------
# Pipeline d'analyse (3 passes)
# ---------------------------------------------------------------------------
sub analyser {
    my ($phrase) = @_;
    print "\n", "=" x 60, "\n";
    print "Phrase : \"$phrase\"\n";

    # ---- Passe 1 : Tokenisation ----
    # Crée une Chorus::Collection::List de frames-tokens
    my $sentence = Chorus::Frame->new(_ISA => $LIST);
    $sentence->build();

    for my $word (split /\s+/, lc($phrase)) {
        my $tok = Chorus::Frame->new(
            _ISA  => $TOKEN,
            forme => $word,
            cats  => ($LEXIQUE{$word} // []),
        );
        $sentence->push_items($tok);
    }

    printf "\n  [Tokenisation] %d token(s)\n", $sentence->length;

    # ---- Passe 2 : Étiquetage + désambiguïsation contextuelle ----
    print "\n  [Étiquetage]\n";
    my @items = @{ $sentence->_ITEMS };
    my $ok = 1;

    for my $i (0 .. $#items) {
        my $tok  = $items[$i];
        my @cats = @{ $tok->{cats} };

        unless (@cats) {
            printf "  %-10s : INCONNU\n", $tok->{forme};
            $ok = 0;
            last;
        }

        # Désambiguïsation simple : après DET → préférer NOM si ambigu
        if (@cats > 1 && $i > 0) {
            my @prev_cats = @{ $items[$i-1]->{cats} };
            if (grep { $_ eq 'DET' } @prev_cats) {
                my @nom = grep { $_ eq 'NOM' || $_ eq 'ADJ' } @cats;
                @cats = @nom if @nom;
            }
        }
        $tok->set('cats', [@cats]);
        printf "  %-10s : %s\n", $tok->{forme}, join(', ', @cats);
    }

    unless ($ok) {
        print "\n  => ÉCHEC (token inconnu)\n";
        return;
    }

    # ---- Passe 3 : Chunking via Collection::Filter ----
    print "\n  [Groupes syntaxiques]\n";
    my @found;
    my %seen;

    for my $start (0 .. $#items) {
        my @slice = @items[$start .. $#items];

        for my $spec ([$gn_filter, 'GN'], [$gv_filter, 'GV']) {
            my ($filt, $type) = @$spec;
            next unless $filt->check(@slice);
            my $len = $filt->length;
            my $key = "$start:" . ($start + $len - 1);
            next if $seen{$key}++;
            push @found, {
                type   => $type,
                tokens => [@items[$start .. $start + $len - 1]],
                start  => $start,
            };
        }
    }

    if (!@found) {
        print "  (aucun groupe reconnu)\n";
    } else {
        for my $g (sort { $a->{start} <=> $b->{start} } @found) {
            printf "  %-4s : [ %s ]\n",
                $g->{type},
                join(' ', map { $_->{forme} } @{ $g->{tokens} });
        }
    }

    # ---- Bonus : démonstration de @_VFILTER (captures) ----
    # Cherche DET (ADJ*) NOM et capture les adjectifs
    for my $start (0 .. $#items) {
        my @slice = @items[$start .. $#items];
        next unless $gn_cap_filter->check(@slice);
        my $adjs = $_VFILTER[0];
        next unless $adjs && @$adjs;
        printf "  capture ADJ dans GN[%d] : %s\n",
            $start,
            join(', ', map { $_->{forme} } @$adjs);
    }

    print "\n  => OK\n";
}

# ---------------------------------------------------------------------------
# Démonstration de Collection::List — méthodes utilitaires
# ---------------------------------------------------------------------------
print "\n", "=" x 60, "\n";
print "Démonstration Collection::List\n";
print "=" x 60, "\n";

my $lst = Chorus::Frame->new(_ISA => $LIST);
$lst->build(
    Chorus::Frame->new(forme => 'le'),
    Chorus::Frame->new(forme => 'chat'),
    Chorus::Frame->new(forme => 'noir'),
);

printf "  length : %d\n",              $lst->length;
printf "  first  : %s\n",              $lst->first_item->{forme};
printf "  last   : %s\n",              $lst->last_item->{forme};
printf "  HAS(forme) : %s\n",          $lst->HAS('forme') ? 'oui' : 'non';

# push_items
my $extra = Chorus::Frame->new(forme => 'dort');
$lst->push_items($extra);
printf "  après push_items : %d tokens, dernier = %s\n",
    $lst->length, $lst->last_item->{forme};

# unshift_items
my $det = Chorus::Frame->new(forme => 'un');
$lst->unshift_items($det);
printf "  après unshift_items : premier = %s\n", $lst->first_item->{forme};

# ---------------------------------------------------------------------------
# Analyse de phrases
# ---------------------------------------------------------------------------
analyser("le chat noir mange une souris");
analyser("le petit chien voit un oiseau");
analyser("la vieille maison dort");
analyser("le chat court");            # 'court' ambigu — résolu par contexte
analyser("un dahu sauvage vole");     # 'dahu', 'sauvage', 'vole' inconnus
