package TimberFrame::Agent::CheckThermal::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    _r_min_for_zone
    _sd_min_for_service_class
);

# -------------------------------------------------------
# _r_min_for_zone
# Source corpus: §4.1 — Part L + BS EN ISO 6946 — Minimum R by climate zone
# -------------------------------------------------------
# Signature: _r_min_for_zone($climate_zone) → Num (m²·K/W)
# Returns the minimum required thermal resistance for a given climate zone.
# Zone A (highland/severe) → 6.5
# Zone B (temperate)       → 4.5
# Zone C (mild/coastal)    → 3.5
# Returns 6.5 (most conservative) for any unrecognised or undef zone.
# Called by: R01-check-thermal-resistance.yml (ACTION)
my %_R_MIN = (
    A => 6.5,    # highland / severe cold      — §4.1
    B => 4.5,    # temperate                   — §4.1
    C => 3.5,    # mild — coastal south        — §4.1
);

sub _r_min_for_zone {
    my ($zone) = @_;
    return ($zone && exists $_R_MIN{ uc $zone })
        ? $_R_MIN{ uc $zone }
        : 6.5;    # conservative fallback — worst case zone A
}

# -------------------------------------------------------
# _sd_min_for_service_class
# Source corpus: §4.2 — BS 5250 / BS EN ISO 13788 — Minimum Sd by service class
# -------------------------------------------------------
# Signature: _sd_min_for_service_class($service_class) → Num (metres)
# Returns the minimum required vapour diffusion resistance (Sd in metres).
# Service class 1 (dry interior)   → 5 m
# Service class 2 (humid interior) → 18 m
# Service class 3 (very humid)     → 50 m
# Returns 50 m (most conservative) for any unrecognised or undef service class.
# Called by: R02-check-vapour-sd.yml (ACTION)
my %_SD_MIN = (
    1 =>  5,     # dry interior      — §4.2
    2 => 18,     # humid interior    — §4.2
    3 => 50,     # very humid        — §4.2
);

sub _sd_min_for_service_class {
    my ($sc) = @_;
    return (defined $sc && exists $_SD_MIN{$sc})
        ? $_SD_MIN{$sc}
        : 50;    # conservative fallback — worst case class 3
}

1;
