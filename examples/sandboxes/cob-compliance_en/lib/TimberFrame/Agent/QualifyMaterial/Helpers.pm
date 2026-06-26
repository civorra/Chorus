package TimberFrame::Agent::QualifyMaterial::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    _strength_class_rank
    _min_class_rank_for_type
);

# -------------------------------------------------------
# _strength_class_rank
# Source corpus: §2.1 — BS EN 338 — Strength class enumeration
# -------------------------------------------------------
# Signature: _strength_class_rank($class_str) → Int (1–7, 0 if unknown)
# Returns the numeric rank of a BS EN 338 strength class.
# Rank 1 = weakest (C14), rank 7 = strongest (C40).
# Returns 0 for undef or unrecognised input.
# Called by: R01-check-strength-class.yml (ACTION)
my %_SC_RANK = (
    C14 => 1,
    C16 => 2,
    C18 => 3,
    C24 => 4,
    C30 => 5,
    C35 => 6,
    C40 => 7,
);

sub _strength_class_rank {
    my ($class) = @_;
    return 0 unless defined $class;
    return $_SC_RANK{ uc $class } // 0;
}

# -------------------------------------------------------
# _min_class_rank_for_type
# Source corpus: §2.1 — BS EN 338 / BS EN 1995-1-1 — Minimum class by element type
# -------------------------------------------------------
# Signature: _min_class_rank_for_type($element_type) → Int
# Returns the minimum required strength class rank for a given element type.
# Returns 0 for non-structural types (insulation, vapour_control) and unknown types.
# Called by: R01-check-strength-class.yml (ACTION)
my %_MIN_RANK = (
    load_bearing_stud     => 4,    # C24 minimum — §2.1
    sole_plate            => 4,    # C24 minimum — §2.1
    top_plate             => 4,    # C24 minimum — §2.1
    non_load_bearing_stud => 2,    # C16 minimum — §2.1
    rafter                => 3,    # C18 minimum — §2.1
    joist                 => 4,    # C24 minimum — §2.1
    insulation            => 0,    # no strength class requirement
    vapour_control        => 0,    # no strength class requirement
);

sub _min_class_rank_for_type {
    my ($type) = @_;
    unless (defined $type && exists $_MIN_RANK{$type}) {
        warn "QualifyMaterial: unknown element_type '${\ ($type // 'undef')}'"
           . " — defaulting min rank to 0\n";
        return 0;
    }
    return $_MIN_RANK{$type};
}

1;
