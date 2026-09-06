package TimberFrame::Agent::Fire::Helpers;

use strict;
use warnings;
use Exporter 'import';

# Exhaustive list of exported helpers — chorus-check imports them all
our @EXPORT_OK = qw(
    min_rei_required
    reaction_class_rank
    min_pb_thickness
);

# -------------------------------------------------------
# min_rei_required
# Source corpus: §5.1 — Building Regs Part B / BS EN 13501-2 — Fire resistance by occupancy
# -------------------------------------------------------
# Signature: min_rei_required($collective) → int (minutes)
# Called by: R01-rei-period.yml (ACTION)
# Returns required REI period in minutes based on building occupancy type.
sub min_rei_required {
    my ($collective) = @_;

    # §5.1 — REI 30 for non-collective, REI 60 for multi-occupancy
    return ($collective // 0) ? 60 : 30;
}

# -------------------------------------------------------
# reaction_class_rank
# Source corpus: §5.2 — BS EN 13501-1 — Euroclass ranking (A1 best, F worst)
# -------------------------------------------------------
# Signature: reaction_class_rank($class) → int rank (1..7, higher = worse) or 99
# Called by: R02-lining-class.yml (ACTION)
# Returns 99 for unknown classes — treated as worst case (non-compliant).
sub reaction_class_rank {
    my ($class) = @_;

    # §5.2 Euroclass ascending severity
    my %RANK = (
        A1 => 1,
        A2 => 2,
        B  => 3,
        C  => 4,
        D  => 5,
        E  => 6,
        F  => 7,
    );

    return $RANK{$class // ''} // 99;
}

# -------------------------------------------------------
# min_pb_thickness
# Source corpus: §5.3 — Building Regs Part B §B3 — Plasterboard thickness by REI
# -------------------------------------------------------
# Signature: min_pb_thickness($collective) → float (mm) or undef
# Called by: R03-pb-thickness.yml (ACTION)
# Returns minimum plasterboard thickness in mm.
# Returns undef if no specific requirement applies.
sub min_pb_thickness {
    my ($collective) = @_;

    # §5.3 — 12.5 mm for REI 30 (non-collective), 25 mm for REI 60 (collective)
    return ($collective // 0) ? 25 : 12.5;
}

1;
