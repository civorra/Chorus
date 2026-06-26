package TimberFrame::Agent::CheckGeometry::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    _min_section_for_lb_stud
);

# -------------------------------------------------------
# _min_section_for_lb_stud
# Source corpus: §3.2 — BS EN 1995-1-1 §5.2 — Cross-section matrix for load-bearing studs
# -------------------------------------------------------
# Signature: _min_section_for_lb_stud($clear_height_mm, $stud_spacing_mm) → ($b_min, $h_min)
# Returns the minimum required cross-section dimensions (width b, depth h) in mm
# for a load-bearing stud (or sole/top plate) based on the storey clear height
# and the stud centre-to-centre spacing.
# Applies the most conservative row (44 × 184 mm) for height > 3000 mm or unknown input.
# Called by: R02-check-section.yml (ACTION)
sub _min_section_for_lb_stud {
    my ($h, $sp) = @_;
    $h  //= 0;
    $sp //= 0;
    # §3.2 matrix — BS EN 1995-1-1 §5.2
    if ($h <= 2700 && $sp <= 400) { return (38,  89) }
    if ($h <= 2700 && $sp <= 600) { return (38, 140) }
    if ($h <= 3000 && $sp <= 400) { return (38, 140) }
    if ($h <= 3000 && $sp <= 600) { return (44, 140) }
    return (44, 184);    # height > 3000 mm — most conservative
}

1;
