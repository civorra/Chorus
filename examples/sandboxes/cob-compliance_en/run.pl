#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../../../lib";   # Chorus::Engine, Frame, Expert, Collection
use lib "$Bin/lib";         # TimberFrame::*

use TimberFrame::Feed   qw(load_projet);
use TimberFrame::Expert;
use JSON ();

my $fichier = shift @ARGV
    or die "Usage: perl run.pl <project-demo.json>\n";
-f $fichier or die "File not found: $fichier\n";

# Feed — project data → Chorus Frames
my @elements = load_projet($fichier);
printf "Feed: %d element(s) loaded\n\n", scalar @elements;

# Calibrate _MAX_CYCLES to the actual project volume
# Heuristic: N_frames × N_rules_total × margin (10 rules/agent × 5 agents = 50)
my $max_cycles = scalar(@elements) * 50 * 10;
$max_cycles = 10_000 if $max_cycles < 10_000;

# Pipeline
my ($ok) = TimberFrame::Expert->run(
    base_dir   => $Bin,
    input      => { elements => \@elements },
    max_cycles => $max_cycles,
    max_iter   => $max_cycles * 2,
);

# Result slots to display
my @slots_resultat_display = qw(
    qualified
    frame_ok
    thermal_ok
    fire_ok
    compliance_status
);

print "=" x 62 . "\n";
print "  COMPLIANCE REPORT — TimberFrame\n";
print "=" x 62 . "\n\n";

my ($n_compliant, $n_non_compliant, $n_unprocessed) = (0, 0, 0);

for my $e (@elements) {
    my $id   = $e->{id}             // '?';
    my $type = $e->{element_type}   // $e->{type} // '?';
    my $stat = $e->{compliance_status};

    # Elements rejected upstream (qualified=NO etc.) never get compliance_status
    # from Agent 5 — post-process them as NON_COMPLIANT.
    unless (defined $stat) {
        if (defined $e->{qualified} && $e->{qualified} eq 'NO') {
            $stat = 'NON_COMPLIANT';
        } elsif (defined $e->{frame_ok} && $e->{frame_ok} eq 'NO') {
            $stat = 'NON_COMPLIANT';
        } elsif (defined $e->{thermal_ok} && $e->{thermal_ok} eq 'NO') {
            $stat = 'NON_COMPLIANT';
        } elsif (defined $e->{fire_ok} && $e->{fire_ok} eq 'NO') {
            $stat = 'NON_COMPLIANT';
        } else {
            $stat = '(unprocessed)';
        }
    }

    if    ($stat eq 'COMPLIANT')     { $n_compliant++ }
    elsif ($stat eq 'NON_COMPLIANT') { $n_non_compliant++ }
    else                             { $n_unprocessed++ }

    my $flag = $stat eq 'COMPLIANT'     ? '✅'
             : $stat eq 'NON_COMPLIANT' ? '❌'
             : '⚠️ ';

    printf "  %s  [%s — %s]\n", $flag, $id, $type;
    for my $slot (@slots_resultat_display) {
        my $val = $e->{$slot};
        next unless defined $val;
        printf "       %-30s : %s\n", $slot, $val;
    }
    print "\n";
}

# ── Compliance rate ───────────────────────────────────────────
my $n_total = scalar @elements;
my $taux    = $n_total ? int(0.5 + 100 * $n_compliant / $n_total) : 0;
my $bar_ok  = int($taux / 5);
my $bar_ko  = 20 - $bar_ok;
my $barre   = '█' x $bar_ok . '░' x $bar_ko;

print "─" x 62 . "\n";
printf "  Compliant      : %d / %d  (%d%%)\n", $n_compliant,     $n_total, $taux;
printf "  Non-compliant  : %d / %d\n",          $n_non_compliant, $n_total;
printf "  Unprocessed    : %d / %d\n",           $n_unprocessed,  $n_total;
printf "  [%s]  %d%%\n", $barre, $taux;
printf "  Pipeline       : %s\n", $ok ? 'SOLVED ✅' : 'FAILED/TIMEOUT ❌';
print "─" x 62 . "\n";

# ── Traversal by agent ────────────────────────────────────────
my @pipeline_def = (
    [ 'QualifyMaterial', 'needs_qualify',    'qualified'         ],
    [ 'CheckGeometry',   'needs_geometry',   'frame_ok'          ],
    [ 'CheckThermal',    'needs_thermal',    'thermal_ok'        ],
    [ 'CheckFire',       'needs_fire',       'fire_ok'           ],
    [ 'CheckCompliance', 'needs_compliance', 'compliance_status' ],
);

print "\n  Validation process — traversal by agent\n";
print "  " . "─" x 58 . "\n";
printf "  %-18s  %7s  %6s  %6s\n", 'Agent', 'Targeted', 'OK', 'KO';
print "  " . "─" x 58 . "\n";

for my $def (@pipeline_def) {
    my ($label, $slot_cible, $slot_res) = @$def;
    my @cibles;
    if ($slot_res eq 'qualified') {
        @cibles = @elements;
    } else {
        @cibles = grep { defined $_->{$slot_res} } @elements;
    }
    my $n_cibles = scalar @cibles;
    my ($n_ok, $n_ko) = (0, 0);
    for my $e (@cibles) {
        my $res = $e->{$slot_res} // '';
        if ($slot_res eq 'compliance_status') {
            if    ($res eq 'COMPLIANT')     { $n_ok++ }
            elsif ($res eq 'NON_COMPLIANT') { $n_ko++ }
        } else {
            if    ($res eq 'YES') { $n_ok++ }
            elsif ($res eq 'NO')  { $n_ko++ }
        }
    }
    printf "  %-18s  %7d  %6s  %6s\n",
        $label, $n_cibles,
        $n_ok ? $n_ok : '-',
        $n_ko ? $n_ko : '-';
}
print "  " . "─" x 58 . "\n";

# ── Distribution by element type ──────────────────────────────
{
    my (%ok_par, %ko_par, %tous);
    for my $e (@elements) {
        my $type = $e->{element_type} // $e->{type} // '?';
        $tous{$type}++;
        my $stat = $e->{compliance_status} // '';
        $ok_par{$type}++ if $stat eq 'COMPLIANT';
        $ko_par{$type}++ if $stat eq 'NON_COMPLIANT';
    }
    print "\n  Distribution by element type\n";
    print "  " . "─" x 46 . "\n";
    printf "  %-28s  %5s  %5s\n", 'Type', '✅', '❌';
    print "  " . "─" x 46 . "\n";
    for my $t (sort keys %tous) {
        printf "  %-28s  %5d  %5d\n", $t,
            $ok_par{$t} // 0, $ko_par{$t} // 0;
    }
    print "  " . "─" x 46 . "\n";
}
