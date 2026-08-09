package CobIntro::Agent::Qualification::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    min_strength_class
    strength_class_ok
);

# -------------------------------------------------------
# min_strength_class
# Source corpus: §2.1 — BS EN 338 — Minimum strength class by element type
# -------------------------------------------------------
# Signature: min_strength_class($type_element) → $class_string | undef
# Returns undef for element types not governed by §2.1 (e.g. insulation, VCL).
my %MIN_CLASS = (
    load_bearing_stud => 'C24',   # §2.1
    sole_plate        => 'C24',   # §2.1
    top_plate         => 'C24',   # §2.1
    non_lb_stud       => 'C16',   # §2.1
    rafter            => 'C18',   # §2.1
    joist             => 'C24',   # §2.1
);

sub min_strength_class {
    my ($type) = @_;
    return $MIN_CLASS{$type};   # undef for types outside §2.1 scope
}

# -------------------------------------------------------
# strength_class_ok
# Source corpus: §2.1 — BS EN 338 — Class ordering C14..C40
# -------------------------------------------------------
# Signature: strength_class_ok($actual, $required) → 1 | 0
# Returns 1 if $actual rank >= $required rank in the BS EN 338 scale.
my %CLASS_RANK = (
    C14 => 1,
    C16 => 2,
    C18 => 3,
    C24 => 4,
    C30 => 5,
    C35 => 6,
    C40 => 7,
);

sub strength_class_ok {
    my ($actual, $required) = @_;
    my $ra = $CLASS_RANK{$actual}   // 0;
    my $rr = $CLASS_RANK{$required} // 0;
    return $ra >= $rr ? 1 : 0;
}

1;
