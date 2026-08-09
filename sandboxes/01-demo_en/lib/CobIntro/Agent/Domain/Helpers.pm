package CobIntro::Agent::Domain::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    lb_stud_section_min
    thermal_r_min
    vcl_sd_min
);

# -------------------------------------------------------
# lb_stud_section_min
# Source corpus: §3.2 — BS EN 1995-1-1 §5.2 — Minimum cross-sections for load-bearing studs
# -------------------------------------------------------
# Signature: lb_stud_section_min($clear_height_mm, $spacing_mm) → ($b_min, $h_min)
# Returns the minimum (width, height) in mm for a load-bearing stud.
# clear_height defaults to 0 (→ lowest bucket), spacing defaults to 400.
sub lb_stud_section_min {
    my ($h, $sp) = @_;
    $h  //= 0;
    $sp //= 400;

    # Source corpus: §3.2 table — BS EN 1995-1-1 §5.2
    return (44, 184) if $h > 3000;                          # height > 3000 mm, any spacing
    if ($h <= 2700) {
        return (38,  89) if $sp <= 400;                     # h ≤ 2700, sp ≤ 400
        return (38, 140);                                   # h ≤ 2700, sp ≤ 600
    }
    # 2700 < h <= 3000
    return (38, 140) if $sp <= 400;                         # h ≤ 3000, sp ≤ 400
    return (44, 140);                                       # h ≤ 3000, sp ≤ 600
}

# -------------------------------------------------------
# thermal_r_min
# Source corpus: §4.1 — Part L + BS EN ISO 6946 — Minimum R by climate zone
# -------------------------------------------------------
# Signature: thermal_r_min($zone) → $r_min (m²·K/W)
# Returns R_min for climate zones A, B, C.
# Defaults to zone B (4.5) if zone is unknown.
my %R_MIN = (
    A => 6.5,   # §4.1 — highland / severe cold
    B => 4.5,   # §4.1 — temperate
    C => 3.5,   # §4.1 — mild — coastal south
);

sub thermal_r_min {
    my ($zone) = @_;
    return $R_MIN{$zone} // 4.5;   # default zone B
}

# -------------------------------------------------------
# vcl_sd_min
# Source corpus: §4.2 — BS 5250 / BS EN ISO 13788 — Minimum Sd by service class
# -------------------------------------------------------
# Signature: vcl_sd_min($service_class) → $sd_min (m)
# Returns the minimum Sd value for vapour control layer.
# Defaults to service class 1 (5 m) if class unknown.
my %SD_MIN = (
    1 => 5,    # §4.2 — service class 1 (dry interior)
    2 => 18,   # §4.2 — service class 2 (humid interior)
    3 => 50,   # §4.2 — service class 3 (very humid)
);

sub vcl_sd_min {
    my ($class) = @_;
    return $SD_MIN{$class} // 5;   # default class 1
}

1;
