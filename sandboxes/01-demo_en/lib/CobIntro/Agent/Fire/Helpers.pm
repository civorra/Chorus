package CobIntro::Agent::Fire::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    rei_required
    reaction_class_ok
    pb_thickness_min
);

# -------------------------------------------------------
# rei_required
# Source corpus: §5.1 — Building Regs Part B / BS EN 13501-2 — REI by occupancy
# -------------------------------------------------------
# Signature: rei_required($collective) → $rei_minutes
# Returns the required REI fire resistance period:
#   collective = 0 → REI 30 (single occupancy dwelling)
#   collective = 1 → REI 60 (multi-occupancy building)
sub rei_required {
    my ($collective) = @_;
    return $collective ? 60 : 30;
}

# -------------------------------------------------------
# reaction_class_ok
# Source corpus: §5.2 — BS EN 13501-1 — Reaction to fire: A1 or A2 minimum
# -------------------------------------------------------
# Signature: reaction_class_ok($class) → 1 | 0
# Returns 1 if the Euroclass is A1 or A2 (compliant), 0 otherwise.
my %CLASS_OK = (
    A1 => 1,   # §5.2 — compliant
    A2 => 1,   # §5.2 — compliant
);

sub reaction_class_ok {
    my ($class) = @_;
    return $CLASS_OK{$class} // 0;
}

# -------------------------------------------------------
# pb_thickness_min
# Source corpus: §5.3 — Building Regs Part B §B3 — Plasterboard thickness for REI
# -------------------------------------------------------
# Signature: pb_thickness_min($rei) → $thickness_mm
# Returns the minimum plasterboard thickness to achieve the required REI:
#   REI 30 → 12.5 mm
#   REI 60 → 25 mm (two layers)
sub pb_thickness_min {
    my ($rei) = @_;
    return $rei >= 60 ? 25 : 12.5;
}

1;
