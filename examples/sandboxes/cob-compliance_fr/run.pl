#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../../../lib";            # Chorus::Engine, Frame, Expert, Collection
use lib "$Bin/lib";                 # COB::*

use COB::Feed   qw(load_projet);
use COB::Expert;

my $fichier = shift @ARGV
    or die "Usage : perl run.pl <fichier-projet.json>\n";
-f $fichier or die "Fichier introuvable : $fichier\n";

# Feed — données projet → Frames Chorus
my @elements = load_projet($fichier);
printf "Feed: %d element(s) charge(s)\n\n", scalar @elements;

# Calibrage _MAX_CYCLES selon le volume réel du projet
# Heuristique : N_frames × 25 règles max × 10 (marge sécurité)
my $max_cycles = scalar(@elements) * 25 * 10;
$max_cycles = 10_000 if $max_cycles < 10_000;
my $max_iter   = scalar(@elements) * 25 * 5 * 10;
$max_iter = 50_000 if $max_iter < 50_000;

# Pipeline
my ($ok) = COB::Expert->run(
    base_dir   => $Bin,
    input      => { elements => \@elements },
    max_cycles => $max_cycles,
    max_iter   => $max_iter,
);

# Slots résultat affichés par élément
my @slots_resultat_display = qw(
    qualifie motif_refus
    ossature_ok raison_ossature_ko
    r_thermique thermique_ok raison_thermique_ko
    feu_ok raison_feu_ko
    statut_conformite raison_non_conformite
);

print "=" x 62 . "\n";
print "  RAPPORT DE CONFORMITE — COB / DTU 31.2\n";
print "=" x 62 . "\n\n";

my ($n_conforme, $n_non_conforme, $n_non_traite) = (0, 0, 0);

for my $e (@elements) {
    my $id   = $e->{id}            // '?';
    my $type = $e->{type_element}  // '?';
    my $stat = $e->{statut_conformite} // '(unprocessed)';

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
        printf "       %-32s : %s\n", '→ raison finale', $e->{raison_non_conformite};
    }
    print "\n";
}

# ── Taux de conformité ─────────────────────────────────────────────────────
my $n_total = scalar @elements;
my $taux    = $n_total ? int(0.5 + 100 * $n_conforme / $n_total) : 0;
my $bar_ok  = int($taux / 5);
my $bar_ko  = 20 - $bar_ok;
my $barre   = '█' x $bar_ok . '░' x $bar_ko;

print "─" x 62 . "\n";
printf "  Conformes      : %d / %d  (%d%%)\n", $n_conforme,     $n_total, $taux;
printf "  Non conformes  : %d / %d\n",          $n_non_conforme, $n_total;
printf "  Unprocessed    : %d / %d\n",           $n_non_traite,   $n_total;
printf "  [%s]  %d%%\n", $barre, $taux;
printf "  Pipeline       : %s\n", $ok ? 'SOLVED ✅' : 'FAILED/TIMEOUT ❌';
print "─" x 62 . "\n";

# ── Traversée par agent ────────────────────────────────────────────────────
{
    my @pipeline_def = (
        [ 'Qualification', 'besoin_qualification', 'qualifie'          ],
        [ 'Ossature',      'besoin_ossature',       'ossature_ok'       ],
        [ 'Thermique',     'besoin_thermique',      'thermique_ok'      ],
        [ 'SecuriteFeu',   'besoin_securite',       'feu_ok'            ],
        [ 'Conformite',    'besoin_conformite',     'statut_conformite' ],
    );

    print "\n  Traversee par agent\n";
    print "  " . "─" x 58 . "\n";
    printf "  %-16s  %7s  %6s  %6s  %5s\n", 'Agent', 'Ciblés', 'OK', 'KO', 'NA';
    print "  " . "─" x 58 . "\n";

    for my $def (@pipeline_def) {
        my ($label, $slot_cible, $slot_res) = @$def;
        my @cibles   = grep { defined $_->{$slot_cible} } @elements;
        my ($n_ok, $n_ko, $n_na) = (0, 0, 0);
        for my $e (@cibles) {
            my $res = $e->{$slot_res} // '';
            if    ($res eq 'NA')                              { $n_na++ }
            elsif ($res =~ /^(OUI|CONFORME)$/i)              { $n_ok++ }
            elsif ($res =~ /^(NON|NON_CONFORME)$/i)          { $n_ko++ }
        }
        printf "  %-16s  %7d  %6s  %6s  %5s\n",
            $label, scalar(@cibles),
            $n_ok ? $n_ok : '-',
            $n_ko ? $n_ko : '-',
            $n_na ? $n_na : '-';
    }
    print "  " . "─" x 58 . "\n";

    # Chemin de validation par élément
    print "\n  Chemin de validation par element\n";
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
            my $r = $res =~ /^(OUI|CONFORME)$/i ? '✓'
                  : $res =~ /^(NON|NON_CONFORME)$/i ? '✗'
                  : $res eq 'NA' ? '–' : '?';
            push @chemin, "$label($r)";
        }
        printf "  %s  %-20s  %s\n", $flag, $id, join(' → ', @chemin);
    }
    print "  " . "─" x 58 . "\n";
}

# ── Distribution par type ──────────────────────────────────────────────────
{
    my (%ok_par_type, %ko_par_type, %tous_types);
    for my $e (@elements) {
        my $type = $e->{type_element} // '?';
        $tous_types{$type}++;
        my $stat = $e->{statut_conformite} // '';
        $ok_par_type{$type}++ if $stat eq 'CONFORME';
        $ko_par_type{$type}++ if $stat eq 'NON_CONFORME';
    }
    print "\n  Distribution par type d'element\n";
    print "  " . "─" x 46 . "\n";
    printf "  %-28s  %5s  %5s\n", 'Type', '✅', '❌';
    print "  " . "─" x 46 . "\n";
    for my $t (sort keys %tous_types) {
        printf "  %-28s  %5d  %5d\n",
            $t, $ok_par_type{$t} // 0, $ko_par_type{$t} // 0;
    }
    print "  " . "─" x 46 . "\n";
}

# ── Résumé des non-conformités ─────────────────────────────────────────────
{
    my @nc = grep { ($_{statut_conformite} // '') eq 'NON_CONFORME' }
             grep { ($_{statut_conformite} // '') eq 'NON_CONFORME' } @elements;
    # Correction : utiliser le hash de référence
    @nc = grep { ($_->{statut_conformite} // '') eq 'NON_CONFORME' } @elements;
    if (@nc) {
        print "\n  Resume des non-conformites\n";
        print "  " . "─" x 58 . "\n";
        for my $e (@nc) {
            my $id    = $e->{id}   // '?';
            my $type  = $e->{type_element} // '?';
            my $raison = $e->{raison_non_conformite}
                      // $e->{motif_refus}
                      // '(raison non precisee)';
            printf "  ❌  %-20s [%s]\n      %s\n\n", $id, $type, $raison;
        }
        print "  " . "─" x 58 . "\n";
    }
}
