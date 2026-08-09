#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../../lib";           # Chorus::Engine, Frame, Expert, Collection
use lib "$Bin/lib";                 # KDIGO::*

use KDIGO::CKD::Feed   qw(load_projet);
use KDIGO::CKD::Expert;

my $fichier = shift @ARGV
    or die "Usage: perl run.pl <fichier-projet.json>\n";
-f $fichier or die "File not found: $fichier\n";

# Feed — project data → Chorus Frames
my @elements = load_projet($fichier);
printf "Feed: %d patient(s) loaded\n\n", scalar @elements;

# Calibrate _MAX_CYCLES to the actual project volume.
# Pipeline: 4 agents × ~30 rules total × N patients × margin 10
my $max_cycles = scalar(@elements) * 30 * 10;
$max_cycles = 10_000 if $max_cycles < 10_000;   # safety minimum

# Pipeline
my ($ok) = KDIGO::CKD::Expert->run(
    base_dir   => $Bin,
    input      => { elements => \@elements },
    max_cycles => $max_cycles,
);

# Result slots to display — full pipeline output
my @slots_resultat_display = qw(
    ckd_g_category ckd_a_category ckd_stage chronicity_confirmed
    monitoring_per_year referral_tier
    rasi_indicated rasi_compliant
    sglt2i_indicated sglt2i_compliant
    mra_indicated mra_compliant
    statin_indicated statin_compliant
    bp_target_compliant
    glp1ra_indicated glp1ra_compliant
    lifestyle_activity_ok protein_intake_ok sodium_intake_ok
    uric_acid_lowering_indicated uric_acid_lowering_compliant
    antiplatelet_indicated antiplatelet_compliant
    hyperkalemia_dietary_flag
    noac_preferred krt_planning_flag gadolinium_safe drug_dosing_review_flag
    metabolic_acidosis_flag
    overall_compliance
    besoin_risk besoin_treatment besoin_care
);

print "=" x 62 . "\n";
print "  COMPLIANCE REPORT — KDIGO CKD 2024\n";
print "=" x 62 . "\n\n";

my $n_conforme     = 0;
my $n_non_conforme = 0;
my $n_non_traite   = 0;

for my $e (@elements) {
    my $id   = $e->{id}   // '?';
    my $type = $e->{type_element} // $e->{type} // '?';
    my $stat = $e->{overall_compliance} // '(unprocessed)';

    if    ($stat eq 'COMPLIANT')        { $n_conforme++ }
    elsif ($stat eq 'NON_COMPLIANT')    { $n_non_conforme++ }
    elsif ($stat eq 'PARTIAL')          { $n_non_conforme++ }
    elsif ($stat eq 'INSUFFICIENT_DATA'){ $n_non_conforme++ }
    else                                { $n_non_traite++ }

    my $flag = $stat eq 'COMPLIANT'        ? '✅'
             : $stat eq 'NON_COMPLIANT'    ? '❌'
             : $stat eq 'PARTIAL'          ? '⚠️ '
             : $stat eq 'INSUFFICIENT_DATA'? '⚠️ '
             : '❓';

    printf "  %s  [%s — %s]\n", $flag, $id, $type;

    my @res = grep { defined $e->{$_} } @slots_resultat_display;
    for my $slot (@res) {
        printf "       %-32s : %s\n", $slot, $e->{$slot};
    }
    print "\n";
}

# ── Block 1: Compliance rate ──────────────────────────────────────────────
my $n_total = scalar @elements;
my $taux    = $n_total ? int(0.5 + 100 * $n_conforme / $n_total) : 0;
my $bar_ok  = int($taux / 5);
my $bar_ko  = 20 - $bar_ok;
my $barre   = '█' x $bar_ok . '░' x $bar_ko;

print "─" x 62 . "\n";
printf "  Compliant      : %d / %d  (%d%%)\n", $n_conforme,     $n_total, $taux;
printf "  Non-compliant  : %d / %d\n",          $n_non_conforme, $n_total;
printf "  Unprocessed    : %d / %d\n",           $n_non_traite,   $n_total;
printf "  [%s]  %d%%\n", $barre, $taux;
printf "  Pipeline       : %s\n", $ok ? 'SOLVED ✅' : 'FAILED/TIMEOUT ❌';
print "─" x 62 . "\n";

# ── Block 2: Validation process — traversal by agent ──────────────────────
# slot_resultat_ok = representative result slot per agent
{
    my @pipeline_def = (
        [ 'Staging',   'type_element',    'ckd_g_category'     ],
        [ 'Risk',      'besoin_risk',      'referral_tier'      ],
        [ 'Treatment', 'besoin_treatment', 'statin_indicated'   ],
        [ 'Care',      'besoin_care',      'overall_compliance' ],
    );

    print "\n  Validation process — traversal by agent\n";
    print "  " . "─" x 58 . "\n";
    printf "  %-16s  %7s  %6s  %6s  %5s\n", 'Agent', 'Targeted', 'OK', 'KO', 'NA';
    print "  " . "─" x 58 . "\n";

    for my $def (@pipeline_def) {
        my ($label, $slot_cible, $slot_res) = @$def;
        my @cibles   = grep { defined $_->{$slot_cible} } @elements;
        my $n_cibles = scalar @cibles;
        my ($n_ok, $n_ko, $n_na) = (0, 0, 0);
        for my $e (@cibles) {
            my $res = $e->{$slot_res} // '';
            if    ($res eq 'NA')                                           { $n_na++ }
            elsif ($res =~ /^(OUI|CONFORME|COMPLIANT|1|yes)$/i)           { $n_ok++ }
            elsif ($res =~ /^(NON|NON_CONFORME|KO|NON_COMPLIANT|PARTIAL|INSUFFICIENT_DATA)$/i) { $n_ko++ }
            elsif ($res)                                                   { $n_ok++ }
        }
        printf "  %-16s  %7d  %6s  %6s  %5s\n",
            $label, $n_cibles,
            $n_ok ? $n_ok : '-',
            $n_ko ? $n_ko : '-',
            $n_na ? $n_na : '-';
    }
    print "  " . "─" x 58 . "\n";

    # Validation path per element
    print "\n  Validation path per element\n";
    print "  " . "─" x 58 . "\n";
    for my $e (@elements) {
        my $id   = $e->{id}   // '?';
        my $stat = $e->{overall_compliance} // '';
        my $flag = $stat eq 'COMPLIANT'        ? '✅'
                 : $stat eq 'NON_COMPLIANT'    ? '❌'
                 : $stat eq 'PARTIAL'          ? '⚠️ '
                 : $stat eq 'INSUFFICIENT_DATA'? '⚠️ '
                 : '❓';
        my @chemin;
        for my $def (@pipeline_def) {
            my ($label, $slot_cible, $slot_res) = @$def;
            next unless defined $e->{$slot_cible};
            my $res = $e->{$slot_res} // '?';
            my $res_short = $res =~ /^(COMPLIANT|OUI|1|yes)$/i     ? '✓'
                          : $res =~ /^(NON_COMPLIANT|NON|KO|no)$/i ? '✗'
                          : $res eq 'PARTIAL'                       ? '~'
                          : $res eq 'NA'                            ? '–'
                          : '?';
            push @chemin, "$label($res_short)";
        }
        printf "  %s  %-22s  %s\n", $flag, $id, join(' → ', @chemin);
    }
    print "  " . "─" x 58 . "\n";
}

# ── Block 3: Distribution by element type ─────────────────────────────────
{
    my (%ok_par_type, %ko_par_type, %tous_types);
    for my $e (@elements) {
        my $type = $e->{type_element} // $e->{type} // '?';
        $tous_types{$type}++;
        my $stat = $e->{overall_compliance} // '';
        if    ($stat eq 'COMPLIANT')                            { $ok_par_type{$type}++ }
        elsif ($stat =~ /^(NON_COMPLIANT|PARTIAL|INSUFFICIENT_DATA)$/) { $ko_par_type{$type}++ }
    }
    print "\n  Distribution by element type\n";
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

# ── Block 4: Non-compliance summary ───────────────────────────────────────
{
    my @nc = grep {
        ($_{overall_compliance} // $_{overall_compliance} // '') =~ /^(NON_COMPLIANT|PARTIAL)$/
    } @elements;

    # Rebuild with hashref access
    @nc = grep {
        ($_->{overall_compliance} // '') =~ /^(NON_COMPLIANT|PARTIAL)$/
    } @elements;

    if (@nc) {
        print "\n  Non-compliance summary\n";
        print "  " . "─" x 58 . "\n";

        # Compliance slots to inspect
        my @compliance_slots = qw(
            rasi_compliant sglt2i_compliant mra_compliant
            statin_compliant bp_target_compliant noac_preferred
        );

        for my $e (@nc) {
            my $id     = $e->{id}   // '?';
            my $type   = $e->{type_element} // '?';
            my $status = $e->{overall_compliance} // '?';

            # Collect failing slots
            my @failing = grep {
                defined $e->{$_} && $e->{$_} eq 'NON'
            } @compliance_slots;

            my $raison = @failing
                ? join(', ', map { "$_=NON" } @failing)
                : "(reason not specified)";

            printf "  ❌  %-22s [%s]  %s\n      %s\n\n",
                $id, $type, $status, $raison;
        }
        print "  " . "─" x 58 . "\n";
    }
}
