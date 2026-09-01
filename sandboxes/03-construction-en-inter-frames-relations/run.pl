#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';

use FindBin qw($Bin);
use lib "$Bin/../../lib";   # Chorus::Engine, Frame, Expert, Collection
use lib "$Bin/lib";                # ADA::*

use ADA::Feed   qw(load_projet);
use ADA::Expert;

my $fichier = shift @ARGV
    or die "Usage: perl run.pl <project-file.json>\n";
-f $fichier or die "File not found: $fichier\n";

# ── Feed ──────────────────────────────────────────────────────────────────────
my @elements = load_projet($fichier);
printf "Feed: %d element(s) loaded\n\n", scalar @elements;

# ── Calibrate _MAX_CYCLES to actual project volume ────────────────────────────
# ADA pipeline (2025-07-16): 6 agents, ~29 rules total
#   Robustness(1) + Geometry(3) + Wall(15) + Masonry(4) + Foundation(5) + Chimney(1)
# Heuristic: N_frames × N_rules_total × safety_margin
my $n_el       = scalar @elements;
my $max_cycles = $n_el * 30 * 20;
$max_cycles    = 10_000 if $max_cycles < 10_000;
my $max_iter   = $max_cycles * 6;    # Expert outer loop (one pass per agent)

# ── Pipeline ──────────────────────────────────────────────────────────────────
my ($ok) = ADA::Expert->run(
    base_dir   => $Bin,
    input      => { elements => \@elements },
    max_cycles => $max_cycles,
    max_iter   => $max_iter,
);

# ── Result slots to display ───────────────────────────────────────────────────
# One entry per relevant output slot from the pipeline KB (index.org)
my @slots_display = qw(
    consequence_class robustness_ok robustness_note
    geometry_ok       geometry_violations
    wall_ok           wall_violations      wall_thickness_ok cavity_ok tie_ok
    tie_spacing_ok    buttressing_ok       loading_ok        end_restraint_ok
    buttress_opening_ok opening_factor_ok  chase_ok          lateral_support_ok
    gable_strapping_ok  lateral_interruption_ok small_building_wall_ok mortar_ok
    masonry_ok        masonry_violations   masonry_condition masonry_strength_ok
    masonry_normalised_ok
    foundation_ok     foundation_violations foundation_width_ok
    foundation_depth_ok foundation_thickness_ok min_foundation_width_mm
    stepped_foundation_ok pier_foundation_ok
    chimney_ok        chimney_violations   chimney_proportion_ok
);

print "=" x 64 . "\n";
print "  COMPLIANCE REPORT — ADA (Approved Document A)\n";
print "=" x 64 . "\n\n";

my ($n_ok, $n_ko, $n_unproc) = (0, 0, 0);

for my $e (@elements) {
    my $id   = $e->{id}           // '?';
    my $type = $e->{type_element} // '?';

    # Determine overall status by aggregating ALL agent verdicts
    my $status = _element_status($e);

    if    ($status eq 'OK')    { $n_ok++ }
    elsif ($status eq 'KO')    { $n_ko++ }
    else                       { $n_unproc++ }

    my $flag = $status eq 'OK'  ? '✅'
             : $status eq 'KO'  ? '❌'
             : '⚠️ ';

    printf "  %s  [%-22s — %s]\n", $flag, $id, $type;

    for my $slot (@slots_display) {
        next unless defined $e->{$slot};
        next if $e->{$slot} eq '';
        printf "       %-36s : %s\n", $slot, $e->{$slot};
    }
    print "\n";
}

# ── Block 1: Compliance summary ───────────────────────────────────────────────
my $n_total  = scalar @elements;
my $pct_ok   = $n_total ? int(0.5 + 100 * $n_ok / $n_total) : 0;
my $bar_ok   = int($pct_ok / 5);
my $barre    = '█' x $bar_ok . '░' x (20 - $bar_ok);

print "─" x 64 . "\n";
printf "  OK (conformant)    : %d / %d  (%d%%)\n", $n_ok,    $n_total, $pct_ok;
printf "  KO (non-conformant): %d / %d\n",          $n_ko,    $n_total;
printf "  Unprocessed        : %d / %d\n",           $n_unproc, $n_total;
printf "  [%s]  %d%%\n", $barre, $pct_ok;
printf "  Pipeline           : %s\n", $ok ? 'SOLVED ✅' : 'FAILED/TIMEOUT ❌';
print "─" x 64 . "\n";

# ── Block 2: Traversal by agent ───────────────────────────────────────────────
{
    # [ label, targeting_slot_or_type_filter, result_slot, ok_values ]
    # For Geometry and Robustness: use a list of targeted type_element values
    # For others: use the besoin_* presence slot
    my @pipeline_def = (
        [ 'Robustness', \&_is_building_with_use, 'robustness_ok',   [qw(YES)] ],
        [ 'Geometry',   \&_is_building,           'geometry_ok',     [qw(YES)] ],
        [ 'Wall',       'besoin_wall',             'wall_ok',         [qw(YES)] ],
        [ 'Masonry',    'besoin_masonry',           'masonry_ok',      [qw(YES)] ],
        [ 'Foundation', 'besoin_foundation',        'foundation_ok',   [qw(YES)] ],
        [ 'Chimney',    \&_is_chimney,              'chimney_ok',      [qw(YES)] ],
    );

    print "\n  Validation traversal by agent\n";
    print "  " . "─" x 60 . "\n";
    printf "  %-14s  %8s  %6s  %6s  %5s\n", 'Agent', 'Targeted', 'OK', 'KO', 'NA';
    print "  " . "─" x 60 . "\n";

    for my $def (@pipeline_def) {
        my ($label, $sel, $slot_res, $ok_vals) = @$def;
        my %ok_set = map { $_ => 1 } @$ok_vals;
        my @cibles = ref($sel) eq 'CODE'
            ? grep { $sel->($_) } @elements
            : grep { defined $_->{$sel} } @elements;

        my ($n_pass, $n_fail, $n_na) = (0, 0, 0);
        for my $e (@cibles) {
            my $res = $e->{$slot_res} // '';
            if    (!$res)           { $n_na++ }
            elsif ($ok_set{$res})   { $n_pass++ }
            else                    { $n_fail++ }
        }
        printf "  %-14s  %8d  %6s  %6s  %5s\n",
            $label, scalar @cibles,
            $n_pass || '-', $n_fail || '-', $n_na || '-';
    }
    print "  " . "─" x 60 . "\n";

    # Per-element path
    print "\n  Validation path per element\n";
    print "  " . "─" x 60 . "\n";
    for my $e (@elements) {
        my $id   = $e->{id} // '?';
        my $stat = _element_status($e);
        my $flag = $stat eq 'OK' ? '✅' : $stat eq 'KO' ? '❌' : '⚠️ ';
        my @path;
        for my $def (@pipeline_def) {
            my ($label, $sel, $slot_res, $ok_vals) = @$def;
            my %ok_set = map { $_ => 1 } @$ok_vals;
            my $targeted = ref($sel) eq 'CODE'
                ? $sel->($e)
                : defined $e->{$sel};
            next unless $targeted;
            my $res = $e->{$slot_res} // '';
            my $sym = !$res         ? '?'
                    : $ok_set{$res} ? '✓'
                    :                  '✗';
            push @path, "$label($sym)";
        }
        printf "  %s  %-24s  %s\n", $flag, $id,
            join(' → ', @path) || '(no agent targeted)';
    }
    print "  " . "─" x 60 . "\n";
}

# ── Block 3: Distribution by element type ────────────────────────────────────
{
    my (%ok_t, %ko_t, %all_t);
    for my $e (@elements) {
        my $t    = $e->{type_element} // '?';
        my $stat = _element_status($e);
        $all_t{$t}++;
        if    ($stat eq 'OK') { $ok_t{$t}++ }
        elsif ($stat eq 'KO') { $ko_t{$t}++ }
    }
    print "\n  Distribution by element type\n";
    print "  " . "─" x 48 . "\n";
    printf "  %-32s  %5s  %5s\n", 'Type', '✅', '❌';
    print "  " . "─" x 48 . "\n";
    for my $t (sort keys %all_t) {
        printf "  %-32s  %5d  %5d\n",
            $t, $ok_t{$t} // 0, $ko_t{$t} // 0;
    }
    print "  " . "─" x 48 . "\n";
}

# ── Block 4: Non-conformity detail ───────────────────────────────────────────
{
    my @ko_elems = grep { _element_status($_) eq 'KO' } @elements;
    if (@ko_elems) {
        print "\n  Non-conformity detail\n";
        print "  " . "─" x 64 . "\n";
        for my $e (@ko_elems) {
            my $id   = $e->{id}           // '?';
            my $type = $e->{type_element} // '?';
            # Collect ALL violation details across agents
            my @violations;
            for my $vslot (qw(geometry_violations wall_violations masonry_violations
                               foundation_violations chimney_violations)) {
                my $v = $e->{$vslot} // '';
                push @violations, $v if $v ne '';
            }
            my $detail = @violations
                ? join(' | ', @violations)
                : '(no violation detail)';
            printf "  ❌  %-22s [%s]\n      %s\n\n", $id, $type, $detail;
        }
        print "  " . "─" x 64 . "\n";
    }
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# Determine overall element status by aggregating ALL agent verdicts.
# An element is KO if ANY verdict slot is 'NO'.
# An element is UNPROC if no verdict slot is defined.
sub _element_status {
    my ($e) = @_;
    my @verdict_slots = qw(
        geometry_ok  wall_ok  masonry_ok  foundation_ok
        robustness_ok  chimney_ok
    );
    my @found = grep { defined $e->{$_} } @verdict_slots;
    return 'UNPROC' unless @found;
    return 'KO' if grep { ($e->{$_} // '') eq 'NO' } @found;
    return 'OK';
}

sub _is_building      { ($_[0]{type_element}//'') =~
    /^(residential_building|non_residential_building|annexe)$/ }
sub _is_building_with_use { _is_building($_[0]) && defined $_[0]{building_use} }
sub _is_chimney       { ($_[0]{type_element}//'') eq 'masonry_chimney' }
