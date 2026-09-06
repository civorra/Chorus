package TimberFrame::Agent::Thermal::Helpers;

use strict;
use warnings;
use Exporter 'import';

# Exhaustive list of exported helpers — chorus-check imports them all
our @EXPORT_OK = qw(
    r_min_by_zone
    sd_min_by_service_class
);

# -------------------------------------------------------
# r_min_by_zone
# Source corpus: §4.1 — Part L + BS EN ISO 6946 — Minimum R by climate zone
# -------------------------------------------------------
# Signature: r_min_by_zone($climate_zone) → float (R_min in m²·K/W) or undef
# Called by: R01-thermal-resistance.yml (ACTION)
# Returns undef for unknown climate zones (caller treats as no requirement).
sub r_min_by_zone {
    my ($zone) = @_;

    # §4.1 minimum thermal resistance by climate zone
    my %R_MIN = (
        A => 6.5,   # highland / severe cold
        B => 4.5,   # temperate
        C => 3.5,   # mild — coastal south
    );

    return $R_MIN{$zone // ''};
}

# -------------------------------------------------------
# sd_min_by_service_class
# Source corpus: §4.2 — BS 5250 / BS EN ISO 13788 — Minimum Sd by service class
# -------------------------------------------------------
# Signature: sd_min_by_service_class($service_class) → float (Sd_min in m) or undef
# Called by: R02-vapour-sd.yml (ACTION)
# Returns undef for unknown service classes (caller treats as no requirement).
sub sd_min_by_service_class {
    my ($class) = @_;

    # §4.2 minimum Sd value by service class
    my %SD_MIN = (
        1 =>  5,    # dry interior
        2 => 18,    # humid interior
        3 => 50,    # very humid
    );

    return $SD_MIN{$class // ''};
}

1;
