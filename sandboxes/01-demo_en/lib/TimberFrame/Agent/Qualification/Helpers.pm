package TimberFrame::Agent::Qualification::Helpers;

use strict;
use warnings;
use Exporter 'import';

# Exhaustive list of exported helpers — chorus-check imports them all
our @EXPORT_OK = qw(
    min_strength_class_required
    class_rank
);

# -------------------------------------------------------
# min_strength_class_required
# Source corpus: §2.1 — BS EN 338 — Minimum strength class by element type
# -------------------------------------------------------
# Signature: min_strength_class_required($type_element) → string class or undef
# Called by: R01-strength-class.yml (ACTION)
# Returns the minimum BS EN 338 class required for a given element type.
# Returns undef for elements with no strength class requirement.
sub min_strength_class_required {
    my ($type) = @_;

    # §2.1 minimum class table — BS EN 338
    my %MIN_CLASS = (
        load_bearing_stud     => 'C24',
        sole_plate            => 'C24',
        top_plate             => 'C24',
        joist                 => 'C24',
        rafter                => 'C18',
        non_load_bearing_stud => 'C16',
    );

    # insulation and vapour_control_layer: no requirement → undef
    return $MIN_CLASS{$type // ''};
}

# -------------------------------------------------------
# class_rank
# Source corpus: §2.1 — BS EN 338 — Ascending strength classification
# -------------------------------------------------------
# Signature: class_rank($class) → integer rank (1..7) or 0 if unknown
# Called by: R01-strength-class.yml (ACTION) — comparison helper
# Higher rank = stronger class. Unknown class → 0 (weakest).
sub class_rank {
    my ($class) = @_;

    # §2.1 ascending strength order: C14 < C16 < C18 < C24 < C30 < C35 < C40
    my %RANK = (
        C14 => 1,
        C16 => 2,
        C18 => 3,
        C24 => 4,
        C30 => 5,
        C35 => 6,
        C40 => 7,
    );

    return $RANK{$class // ''} // 0;
}

1;
