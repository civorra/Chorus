package TimberFrame::Agent::Geometry::Helpers;

use strict;
use warnings;
use Exporter 'import';

# Exhaustive list of exported helpers — chorus-check imports them all
our @EXPORT_OK = qw(
    min_lb_section
);

# -------------------------------------------------------
# min_lb_section
# Source corpus: §3.2 — BS EN 1995-1-1 §5.2 — Minimum cross-sections for load-bearing studs
# -------------------------------------------------------
# Signature: min_lb_section($clear_height_mm, $spacing_mm) → ($b_min, $h_min) in mm
# Called by: R02-lb-cross-section.yml (ACTION)
# Returns (0, 0) for element types outside the load-bearing perimeter — neutral value,
# any section satisfies b >= 0 && h >= 0.
sub min_lb_section {
    my ($height, $spacing) = @_;

    # Guard: undefined inputs → neutral (no constraint)
    return (0, 0) unless defined $height && defined $spacing;

    # §3.2 table — BS EN 1995-1-1 §5.2
    # Conditions checked in order of increasing height:
    if ($height <= 2700) {
        if ($spacing <= 400) {
            return (38,  89);   # §3.2: h ≤ 2700, spacing ≤ 400 → 38 × 89 mm
        } else {
            return (38, 140);   # §3.2: h ≤ 2700, spacing ≤ 600 → 38 × 140 mm
        }
    } elsif ($height <= 3000) {
        if ($spacing <= 400) {
            return (38, 140);   # §3.2: h ≤ 3000, spacing ≤ 400 → 38 × 140 mm
        } else {
            return (44, 140);   # §3.2: h ≤ 3000, spacing ≤ 600 → 44 × 140 mm
        }
    } else {
        return (44, 184);       # §3.2: h > 3000, any spacing → 44 × 184 mm
    }
}

1;
