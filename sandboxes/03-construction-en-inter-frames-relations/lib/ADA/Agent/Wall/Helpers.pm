package ADA::Agent::Wall::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    min_thickness_table3
    min_tie_length_table5
    factor_x_table8
);

# -------------------------------------------------------
# min_thickness_table3
# Source corpus: Table 3 (p.18) — Minimum thickness of certain
#   external walls, compartment walls and separating walls
# -------------------------------------------------------
# Signature: min_thickness_table3($height_m, $length_m) → $min_mm
#
# Returns the minimum wall thickness in mm for the given
# wall height (m) and wall length (m), per Table 3.
#
# Table 3 matrix (H/L → minimum):
#   H ≤ 3.5m, L ≤ 12m               → 190mm (whole height)
#   3.5m < H ≤ 9m,  L ≤ 9m          → 190mm (whole height)
#   3.5m < H ≤ 9m,  9m < L ≤ 12m   → 290mm base storey, 190mm rest
#   9m < H ≤ 12m,  L ≤ 9m          → 290mm base storey, 190mm rest
#   9m < H ≤ 12m,  9m < L ≤ 12m   → 290mm base TWO storeys, 190mm rest
#
# This helper returns the MOST RESTRICTIVE thickness that applies
# anywhere in the wall (i.e. 290mm if the base-storey rule applies,
# 190mm otherwise). For a per-storey check, the caller must know
# the storey position.
#
# Called by: R01-external-wall-thickness
sub min_thickness_table3 {
    my ($h, $l) = @_;

    # Treat undef as 0 (safe fallback)
    $h //= 0;
    $l //= 0;

    # H ≤ 3.5m: 190mm regardless of length (L ≤ 12m scope)
    return 190 if $h <= 3.5;

    # 3.5m < H ≤ 9m
    if ($h <= 9.0) {
        # L ≤ 9m → 190mm whole height
        return 190 if $l <= 9.0;
        # 9m < L ≤ 12m → 290mm base storey (conservative: return 290)
        return 290 if $l <= 12.0;
        # L > 12m → outside Table 3 scope; return 290 as conservative value
        return 290;
    }

    # 9m < H ≤ 12m
    if ($h <= 12.0) {
        # Any length → at least 290mm base (one or two storeys)
        return 290;
    }

    # H > 12m → outside scope; return 290 as conservative floor
    return 290;
}

# -------------------------------------------------------
# min_tie_length_table5
# Source corpus: Table 5 (p.25) — Cavity wall ties
# -------------------------------------------------------
# Signature: min_tie_length_table5($cavity_width_mm) → $min_mm | undef
#
# Returns the minimum wall tie length (mm) for a given nominal cavity
# width (mm), per Table 5.
#
# Returns undef for cavity > 175mm — in that case the caller should
# apply Table 5 Note 3: tie length = cavity_width + 125mm.
#
# Table 5:
#   50–75mm   → 200mm
#   76–100mm  → 225mm
#   101–125mm → 250mm
#   126–150mm → 275mm
#   151–175mm → 300mm
#   >175mm    → undef (Note 3: cav_w + 125mm — specialist calculation)
#
# Note 2: embedment depth ≥ 50mm in both leaves (not checked here —
#         this is a specification requirement, not a dimension check).
#
# Called by: R01-external-wall-thickness, R02-cavity-tie
sub min_tie_length_table5 {
    my ($cav_w) = @_;
    $cav_w //= 0;

    return 200 if $cav_w >= 50  && $cav_w <= 75;
    return 225 if $cav_w >= 76  && $cav_w <= 100;
    return 250 if $cav_w >= 101 && $cav_w <= 125;
    return 275 if $cav_w >= 126 && $cav_w <= 150;
    return 300 if $cav_w >= 151 && $cav_w <= 175;

    # > 175mm: Note 3 formula applies — caller must compute cav_w + 125
    return undef if $cav_w > 175;

    # < 50mm: cavity below minimum (50mm) — return undef (outside scope)
    return undef;
}

# -------------------------------------------------------
# factor_x_table8
# Source corpus: Table 8 (p.31) — Value of Factor 'X' (see Diagram 14)
# -------------------------------------------------------
# Signature: factor_x_table8($roof_dir, $floor_type, $max_floor_span_m, $wall_thickness_mm)
#            → integer (3..6)
#
# Returns the Factor X value from Table 8 for use in §2C29 opening pier checks.
#
# Parameters:
#   $roof_dir          : 'parallel' (spans parallel to wall) or 'into_wall' (timber spans into wall)
#   $floor_type        : 'timber' or 'concrete' (or 'parallel' when floor span is parallel)
#   $max_floor_span_m  : maximum floor span (metres) — 4.5 or 6.0 threshold
#   $wall_thickness_mm : minimum wall thickness (mm) — 100 or 90 threshold in Table 8
#
# Note: Factor X can also be taken as 6 directly (§2C29 rule 8) if the declared compressive
#       strength of the masonry units is ≥ 7.3 N/mm². The caller should apply that override
#       before calling this helper (pass factor_x = 6 directly when strength condition met).
#
# Table 8 matrix (roof_dir × floor_type × floor_span × wall_t):
#   parallel / any floor   / any span  / 100mm → 6
#   parallel / any floor   / any span  / 90mm  → 6 (except concrete >6m → 5)
#   into_wall/ timber      / ≤4.5m     / 100mm → 6
#   into_wall/ timber      / ≤6.0m     / 100mm → 5
#   into_wall/ concrete    / ≤4.5m     / 100mm → 4
#   into_wall/ concrete    / ≤6.0m     / 100mm → 3
#   into_wall/ timber      / ≤4.5m     / 90mm  → 6
#   into_wall/ timber      / ≤6.0m     / 90mm  → 4
#   into_wall/ concrete    / ≤4.5m     / 90mm  → 3
#   into_wall/ concrete    / ≤6.0m     / 90mm  → 3
#
# Called by: R10-opening-factor-x (via feed pre-computation or directly)
sub factor_x_table8 {
    my ($roof_dir, $floor_type, $max_floor_span_m, $wall_t_mm) = @_;
    $roof_dir         //= 'parallel';
    $floor_type       //= 'parallel';
    $max_floor_span_m //= 4.5;
    $wall_t_mm        //= 100;

    # When roof spans parallel to wall: Factor X = 6 for all cases
    # except concrete floor > 6m with 90mm wall → 5
    if ($roof_dir eq 'parallel') {
        return 5 if $floor_type eq 'concrete'
                 && $max_floor_span_m > 6.0
                 && $wall_t_mm < 100;
        return 6;
    }

    # Timber roof spanning into wall (max roof span 9m per Table 8)
    my $thick_ok = ($wall_t_mm >= 100) ? 'thick' : 'thin';  # 100mm vs 90mm

    # Timber floor spanning into wall
    if ($floor_type eq 'timber') {
        if ($thick_ok eq 'thick') {
            return ($max_floor_span_m <= 4.5) ? 6 : 5;
        } else {
            return ($max_floor_span_m <= 4.5) ? 6 : 4;
        }
    }

    # Concrete floor spanning into wall
    if ($floor_type eq 'concrete') {
        if ($thick_ok eq 'thick') {
            return ($max_floor_span_m <= 4.5) ? 4 : 3;
        } else {
            return 3;   # 90mm wall + concrete floor → 3 in both span cases
        }
    }

    # Floor spans parallel to wall (not into wall) → Factor X = 6
    return 6;
}

1;
