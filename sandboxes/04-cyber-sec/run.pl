#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../../Engine/lib";   # Chorus::Engine, Frame, Expert, Collection
use lib "$Bin/lib";                 # CyberSec::*

use CyberSec::Feed   qw(load_projet);
use CyberSec::Expert;

my $fichier = shift @ARGV
    or die "Usage: perl run.pl <project-file.json>\n";
-f $fichier or die "File not found: $fichier\n";

# Feed — project data → Chorus Frames
my @elements = load_projet($fichier);
# Exclude the pipeline control frame from display and statistics
my @display_elements = grep { !defined $_->{pipeline_ctrl} } @elements;
printf "Feed: %d element(s) loaded\n\n", scalar @display_elements;

# Calibrate _MAX_CYCLES to the actual project volume
# Heuristic: N_frames × N_rules_total × margin
# 3 agents × ~20 rules avg × 10 margin
my $max_cycles = scalar(@elements) * 60 * 10;
$max_cycles = 10_000 if $max_cycles < 10_000;

# Pipeline
my ($ok) = CyberSec::Expert->run(
    base_dir   => $Bin,
    input      => { elements => \@elements },
    max_cycles => $max_cycles,
    max_iter   => scalar(@elements) * 200,
);

# ── Post-pipeline: derive statut_conformite from agent result slots ───────
# The pipeline produces per-agent verdicts; statut_conformite is derived here.
for my $e (@display_elements) {
    my $type = $e->{type_element} // '';

    my $conforme;
    if ($type eq 'cert_ext') {
        # cert_ext: validity only — no cert_profile_result
        my $v = $e->{validity_assured_ok} // '';
        $conforme = ($v eq 'OUI') ? 1 : ($v eq 'NON') ? 0 : undef;
    } elsif ($type eq 'nat') {
        my $cp  = $e->{cert_profile_result} // '';
        my $nat = $e->{nat_profile_result}  // '';
        if ($cp && $nat) {
            $conforme = ($cp eq 'OK' && $nat eq 'OK') ? 1 : 0;
        }
    } elsif ($type eq 'leg') {
        my $cp  = $e->{cert_profile_result} // '';
        my $leg = $e->{leg_profile_result}  // '';
        if ($cp && $leg) {
            $conforme = ($cp eq 'OK' && $leg eq 'OK') ? 1 : 0;
        }
    } elsif ($type eq 'web' || $type eq 'gen') {
        my $cp = $e->{cert_profile_result} // '';
        $conforme = ($cp eq 'OK') ? 1 : ($cp eq 'KO') ? 0 : undef if $cp;
    }

    if (defined $conforme) {
        $e->{statut_conformite} = $conforme ? 'CONFORME' : 'NON_CONFORME';
        # Build raison_non_conformite for KO frames
        unless ($conforme) {
            my @reasons;
            for my $slot (qw(
                serial_number_format_ok org_id_format_ok nra_uri_ok ntr_euid_ok
                cert_version_ok aki_ok forbidden_exts_ok aia_ok web_qcs_ok
                qcs_not_critical_ok qcs_compliance_ok qcs_cclegislation_ok
                qc_policy_oid_ok qcs_qscd_ok pk_algorithm_ok sig_suite_ok
                pk_key_size_ok san_not_critical_ok web_qevcp_ok qcs_type_ok
                nat_subject_ok nat_key_usage_ok revocation_ok cert_policies_ok qcstatements_ok
                leg_subject_ok leg_key_usage_ok
                validity_assured_ok
            )) {
                push @reasons, $slot if (($e->{$slot} // '') eq 'NON');
            }
            $e->{raison_non_conformite} = @reasons
                ? join(', ', map { "$_ = NON" } @reasons)
                : 'KO (reason unknown)';
        }
    }
}

# Result slots to display
my @slots_resultat_display = qw(
    needs_cert_validation
    cert_profile_result
    needs_nat_validation
    nat_profile_result
    needs_leg_validation
    leg_profile_result
    statut_conformite
    raison_non_conformite
);

print "=" x 62 . "\n";
print "  COMPLIANCE REPORT — CyberSec\n";
print "=" x 62 . "\n\n";

my $n_conforme     = 0;
my $n_non_conforme = 0;
my $n_non_traite   = 0;

for my $e (@display_elements) {
    my $id   = $e->{id}           // '?';
    my $type = $e->{type_element} // '?';
    my $stat = $e->{statut_conformite} // '(unprocessed)';

    if    ($stat eq 'CONFORME')     { $n_conforme++ }
    elsif ($stat eq 'NON_CONFORME') { $n_non_conforme++ }
    else                            { $n_non_traite++ }

    my $flag = $stat eq 'CONFORME'     ? '✅'
             : $stat eq 'NON_CONFORME' ? '❌'
             : '⚠️ ';

    printf "  %s  [%s — %s]\n", $flag, $id, $type;

    for my $slot (@slots_resultat_display) {
        next if $slot eq 'raison_non_conformite';
        next unless defined $e->{$slot};
        printf "       %-34s : %s\n", $slot, $e->{$slot};
    }
    if (defined $e->{raison_non_conformite}) {
        printf "       %-34s : %s\n", '→ reason', $e->{raison_non_conformite};
    }
    print "\n";
}

# ── Block 1: Compliance rate ──────────────────────────────────────────────
my $n_total = scalar @display_elements;
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

# ── Block 2: Validation process — traversal by agent ──────────────────────
{
    my @pipeline_def = (
        [ 'CertProfileCommon', 'needs_cert_validation', 'cert_profile_result' ],
        [ 'CertProfileNat',    'needs_nat_validation',  'nat_profile_result'  ],
        [ 'CertProfileLeg',    'needs_leg_validation',  'leg_profile_result'  ],
    );

    print "\n  Validation process — traversal by agent\n";
    print "  " . "─" x 58 . "\n";
    printf "  %-18s  %7s  %6s  %6s  %5s\n", 'Agent', 'Targeted', 'OK', 'KO', 'NA';
    print "  " . "─" x 58 . "\n";

    for my $def (@pipeline_def) {
        my ($label, $slot_cible, $slot_res) = @$def;
        my @cibles   = grep { defined $_->{$slot_cible} } @display_elements;
        my $n_cibles = scalar @cibles;
        my ($n_ok, $n_ko, $n_na) = (0, 0, 0);
        for my $e (@cibles) {
            my $res = $e->{$slot_res} // '';
            if    ($res =~ /^(OUI|CONFORME|1|OK)$/i)        { $n_ok++ }
            elsif ($res =~ /^(NON|NON_CONFORME|KO|0)$/i)    { $n_ko++ }
            elsif ($res eq 'NA')                             { $n_na++ }
        }
        printf "  %-18s  %7d  %6s  %6s  %5s\n",
            $label, $n_cibles,
            $n_ok ? $n_ok : '-',
            $n_ko ? $n_ko : '-',
            $n_na ? $n_na : '-';
    }
    print "  " . "─" x 58 . "\n";

    print "\n  Validation path per element\n";
    print "  " . "─" x 58 . "\n";
    for my $e (@display_elements) {
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
            my $res_short = $res =~ /^(OUI|CONFORME|1|OK)$/i   ? '✓'
                          : $res =~ /^(NON|NON_CONFORME|KO|0)$/i ? '✗'
                          : $res eq 'NA'                          ? '–'
                          : '?';
            push @chemin, "$label($res_short)";
        }
        printf "  %s  %-20s  %s\n", $flag, $id, join(' → ', @chemin);
    }
    print "  " . "─" x 58 . "\n";
}

# ── Block 3: Distribution by element type ─────────────────────────────────
{
    my (%ok_par_type, %ko_par_type, %tous_types);
    for my $e (@display_elements) {
        my $type = $e->{type_element} // '?';
        $tous_types{$type}++;
        my $stat = $e->{statut_conformite} // '';
        if    ($stat eq 'CONFORME')     { $ok_par_type{$type}++ }
        elsif ($stat eq 'NON_CONFORME') { $ko_par_type{$type}++ }
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

# ── Block 4: Non-conformity summary ───────────────────────────────────────
{
    my @nc;
    for my $e (@display_elements) {
        push @nc, $e if ($e->{statut_conformite} // '') eq 'NON_CONFORME';
    }
    if (@nc) {
        print "\n  Non-conformity summary\n";
        print "  " . "─" x 58 . "\n";
        for my $e (@nc) {
            my $id    = $e->{id}           // '?';
            my $type  = $e->{type_element} // '?';
            my $raison = $e->{raison_non_conformite}
                      // $e->{motif_refus}
                      // '(reason not specified)';
            printf "  ❌  %-20s [%s]\n      %s\n\n", $id, $type, $raison;
        }
        print "  " . "─" x 58 . "\n";
    }
}
