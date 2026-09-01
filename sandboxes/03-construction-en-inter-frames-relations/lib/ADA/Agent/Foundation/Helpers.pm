package ADA::Agent::Foundation::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    min_width_table10
    min_depth_2e4
);

# -------------------------------------------------------
# min_width_table10
# Source corpus: Table 10 (p.39) — Minimum width of strip footings
# -------------------------------------------------------
# Signature: min_width_table10($soil_type, $load_kn_m) → $mm | undef
#
# Returns the minimum strip foundation width (mm) from Table 10 for
# the given soil type (I–VII) and total load of load-bearing walling
# (kN/linear metre).
#
# Load columns in Table 10: 20, 30, 40, 50, 60, 70 kN/m
# Conservative approach: use the column whose threshold >= actual load
# (round up to next column).
#
# Return values:
#   undef → soil type I (rock): width = wall width (no numeric minimum)
#   undef → soil type VII: specialist advice required
#   undef → soil types V/VI with load > 30kN/m: outside Table 10 scope
#   undef → load > 70kN/m: outside Table 10 scope (all soil types)
#
# Called by: R01-foundation-width
sub min_width_table10 {
    my ($soil, $load) = @_;
    $soil //= 'II';
    $load //= 0;

    # Load columns (kN/m) and their indices (0..5)
    my @LOADS = (20, 30, 40, 50, 60, 70);

    # Minimum widths (mm) per soil type for each load column
    # undef = not applicable (out of scope or specialist advice)
    my %TABLE10 = (
        # Soil I: Rock — not inferior to sandstone, limestone or firm chalk
        # Width = wall width for all loads → all undef (sentinel)
        I   => [undef, undef, undef, undef, undef, undef],

        # Soil II: Gravel or sand (medium dense)
        II  => [250,   300,   400,   500,   600,   650  ],

        # Soil III: Clay/Sandy clay (stiff)
        III => [250,   300,   400,   500,   600,   650  ],

        # Soil IV: Clay/Sandy clay (firm)
        IV  => [300,   350,   450,   600,   750,   850  ],

        # Soil V: Sand/Silty sand/Clayey sand (loose)
        # Note: foundations on soil type V do not fall within these provisions
        # if total load > 30kN/m (Table 10 note)
        V   => [400,   600,   undef, undef, undef, undef],

        # Soil VI: Silt/Clay/Sandy clay (soft)
        # Same constraint as V: > 30kN/m is outside scope
        VI  => [450,   650,   undef, undef, undef, undef],

        # Soil VII: Very soft — refer to specialist advice
        VII => [undef, undef, undef, undef, undef, undef],
    );

    # Unknown soil type → conservative fallback (treat as IV)
    unless (exists $TABLE10{$soil}) {
        $soil = 'IV';
    }

    # Load > 70kN/m → outside Table 10 scope
    return undef if $load > 70;

    # Find the load column index (round up to next threshold)
    my $col_idx = undef;
    for my $i (0 .. $#LOADS) {
        if ($load <= $LOADS[$i]) {
            $col_idx = $i;
            last;
        }
    }
    # load > 70 already handled above; if still undef something is wrong
    return undef unless defined $col_idx;

    return $TABLE10{$soil}[$col_idx];
}

# -------------------------------------------------------
# min_depth_2e4
# Source corpus: §2E4 (p.37) — Minimum depth of strip foundations
# -------------------------------------------------------
# Signature: min_depth_2e4($shrink_class) → $metres
#
# Returns the minimum depth to the underside of strip foundations
# in metres, per §2E4.
#
# Standard minimum (frost protection): 0.45m
# Shrinkable clay overrides (Modified Plasticity Index):
#   low    → 0.75m  (MPI 10–20%)
#   medium → 0.90m  (MPI 20–40%)
#   high   → 1.00m  (MPI ≥ 40%)
#   none   → 0.45m  (non-shrinkable / non-clay)
#
# ⚠ These are REGULATORY MINIMA. §2E4 states depths may need to
# be increased near trees or where ground movements are expected.
# Site-specific adjustments are outside the scope of this helper.
#
# Called by: R02-foundation-depth
sub min_depth_2e4 {
    my ($shrink_class) = @_;
    $shrink_class //= 'none';

    my %MIN_DEPTH = (
        none   => 0.45,   # §2E4 general minimum (frost protection)
        low    => 0.75,   # §2E4 low shrinkage clay (MPI 10–20%)
        medium => 0.90,   # §2E4 medium shrinkage clay (MPI 20–40%)
        high   => 1.00,   # §2E4 high shrinkage clay (MPI ≥ 40%)
    );

    # Unknown shrink_class → conservative fallback to 'none' (0.45m)
    return $MIN_DEPTH{$shrink_class} // 0.45;
}

1;
