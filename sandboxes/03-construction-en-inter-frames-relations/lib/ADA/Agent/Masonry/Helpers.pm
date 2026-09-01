package ADA::Agent::Masonry::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    diagram9_condition
    min_strength_table6
    min_normalised_table7
);

# -------------------------------------------------------
# diagram9_condition
# Source corpus: Diagram 9 (p.26), §2C21 — Declared compressive strength conditions
# -------------------------------------------------------
# Signature: diagram9_condition($storey_pos, $hs_m, $num_storeys, $hf_m)
#            → 'A' | 'B' | 'C'
#
# Returns the masonry condition (A, B, or C) from Diagram 9 based on:
#   $storey_pos   — 'single' / 'top' / 'intermediate' / 'base'
#   $hs_m         — storey height Hs in metres
#   $num_storeys  — total number of storeys (1, 2 or 3)
#   $hf_m         — depth Hf below ground floor level in metres (Diagram 9 note)
#
# Diagram 9 rules:
#   Single storey:
#     Hs ≤ 2.7m → Condition A
#     Hs > 2.7m → Condition B
#
#   Two or three storeys:
#     Top storey:
#       Hs ≤ 2.7m → Condition A
#       Hs > 2.7m → Condition B
#     Intermediate storey:
#       Always Condition B (regardless of Hs)
#     Base (ground floor/lowest storey):
#       → Condition C
#
#   Basement / below-DPC portion (hf_m > 0):
#     Hf ≤ 1m → same as Condition A position (Diagram 9 key note)
#     Hf > 1m → same as Condition B position (Diagram 9 key note)
#     Wall below ground floor must be ≥ 140mm blockwork or 215mm brickwork if Hf > 1m
#
#   Parapet wall → always Condition A (above roof, minimal load)
#
# Note 2: if Hs > 2.7m, compressive strength should be at least Condition B
# or as indicated by the key, whichever is greater (B > A; C > B).
#
# Called by: R01-masonry-condition
sub diagram9_condition {
    my ($pos, $hs, $num_storeys, $hf) = @_;
    $pos         //= 'single';
    $hs          //= 0;
    $num_storeys //= 1;
    $hf          //= 0;

    # Helper: apply Diagram 9 Note 2 — if Hs > 2.7m, minimum is B
    my $raise_if_high_hs = sub {
        my ($cond) = @_;
        return $cond if $hs <= 2.7;
        # Raise A → B; leave B and C unchanged
        return ($cond eq 'A') ? 'B' : $cond;
    };

    # Parapet wall — always Condition A (above roof line)
    return 'A' if $pos eq 'parapet';

    # Single storey (one-storey building)
    if ($num_storeys == 1 || $pos eq 'single') {
        return $raise_if_high_hs->('A');
    }

    # Multi-storey
    if ($pos eq 'top') {
        return $raise_if_high_hs->('A');
    }
    if ($pos eq 'intermediate') {
        # Always B (Diagram 9 Note 2 cannot lower B)
        return $raise_if_high_hs->('B');
    }
    if ($pos eq 'base') {
        # Base of multi-storey → Condition C
        # Note: Condition C cannot be raised further
        return 'C';
    }

    # Fallback (unrecognised position) — conservative: Condition C
    return 'C';
}

# -------------------------------------------------------
# min_strength_table6
# Source corpus: Table 6 (p.25) — Declared compressive strength of masonry units (N/mm²)
# -------------------------------------------------------
# Signature: min_strength_table6($condition, $unit_type, $material, $group)
#            → $nmm2 | undef
#
# Returns the minimum declared compressive strength (N/mm²) from Table 6.
# Returns undef for:
#   - manufactured_stone (BS EN 771-5): any complying unit is acceptable
#   - clay/CaSi block → caller should use Table 7 (min_normalised_table7) instead;
#     this helper returns undef to signal "use Table 7"
#   - aac brick: not applicable (marked '–' in Table 6)
#
# Table 6 values:
#                    Condition A   Condition B   Condition C
#   clay brick Gr1      6.0           9.0          18.0
#   clay brick Gr2      9.0          13.0          25.0
#   CaSi brick Gr1      6.0           9.0          18.0
#   CaSi brick Gr2      9.0          13.0          25.0
#   aggr.conc. brick    6.0           9.0          18.0
#   aac brick            —             —             —     → undef
#   aggr.conc. block    2.9 (A)    7.3 (B/C)   7.3 (C)  *dry strength
#   aac block           2.9 (A)    7.3 (B/C)   7.3 (C)
#   clay/CaSi block   → Table 7    → Table 7    → Table 7 → undef
#   manufactured_stone  any           any          any     → undef
#
# Called by: R02-masonry-strength
sub min_strength_table6 {
    my ($cond, $unit_type, $material, $group) = @_;
    $cond      //= 'A';
    $unit_type //= 'brick';
    $material  //= 'clay';
    $group     //= 1;

    # manufactured_stone: any BS EN 771-5 compliant unit is acceptable
    return undef if $material eq 'manufactured_stone';

    if ($unit_type eq 'brick') {
        # AAC brick: not listed in Table 6 (marked '–')
        return undef if $material eq 'aac';

        # Clay or Calcium Silicate brick — identical thresholds in Table 6
        if ($material =~ /^(clay|calcium_silicate)$/) {
            my %STR = (
                A => { 1 =>  6.0, 2 =>  9.0 },
                B => { 1 =>  9.0, 2 => 13.0 },
                C => { 1 => 18.0, 2 => 25.0 },
            );
            return $STR{$cond}{$group} if exists $STR{$cond} && exists $STR{$cond}{$group};
            return undef;
        }

        # Aggregate concrete brick — same as clay Gr1 values
        if ($material eq 'aggregate_concrete') {
            my %STR = (A => 6.0, B => 9.0, C => 18.0);
            return $STR{$cond};
        }
    }

    if ($unit_type eq 'block') {
        # Clay and CaSi blocks → use Table 7 (normalised strength)
        return undef if $material =~ /^(clay|calcium_silicate)$/;

        # Aggregate concrete block — dry strengths (BS EN 772-1)
        if ($material eq 'aggregate_concrete') {
            return 2.9 if $cond eq 'A';
            return 7.3;  # Conditions B and C
        }

        # AAC (autoclaved aerated concrete) block
        if ($material eq 'aac') {
            return 2.9 if $cond eq 'A';
            return 7.3;  # Conditions B and C
        }
    }

    return undef;
}

# -------------------------------------------------------
# min_normalised_table7
# Source corpus: Table 7 (p.27) — Normalised compressive strength (N/mm²)
#   for clay and calcium silicate blocks (BS EN 771-1 and -2)
# -------------------------------------------------------
# Signature: min_normalised_table7($condition, $group) → $nmm2
#
# Returns the minimum normalised compressive strength (N/mm²) from Table 7.
# Applies only to clay and calcium silicate block units with work size
# exceeding 337.5mm length or 112.5mm height (Table 7 Note 2).
#
# Table 7 values (same for clay EN 771-1 and CaSi EN 771-2):
#   Condition A: Group 1 = 5.0,  Group 2 = 8.0
#   Condition B: Group 1 = 7.5,  Group 2 = 11.0
#   Condition C: Group 1 = 15.0, Group 2 = 21.0
#
# Called by: R03-normalised-strength-blocks
sub min_normalised_table7 {
    my ($cond, $group) = @_;
    $cond  //= 'A';
    $group //= 1;

    my %TABLE7 = (
        A => { 1 =>  5.0, 2 =>  8.0 },
        B => { 1 =>  7.5, 2 => 11.0 },
        C => { 1 => 15.0, 2 => 21.0 },
    );

    return $TABLE7{$cond}{$group} if exists $TABLE7{$cond} && exists $TABLE7{$cond}{$group};

    # Unknown condition or group — conservative fallback: Condition C Group 2
    return 21.0;
}

1;
