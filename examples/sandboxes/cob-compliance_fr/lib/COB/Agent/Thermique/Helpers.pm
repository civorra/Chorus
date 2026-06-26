package COB::Agent::Thermique::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    r_min_zone
    calcul_r
    sd_min_m
    type_est_isolant
    type_est_membrane
    type_est_structurel_thermique
);

# -------------------------------------------------------
# r_min_zone($zone_climatique) → float
# Source corpus : §4.1 — Résistance thermique minimale par zone
# -------------------------------------------------------
my %R_MIN = (H1 => 6.0, H2 => 5.0, H3 => 4.0);

sub r_min_zone {
    my ($zone) = @_;
    return $R_MIN{$zone} // 5.0;
}

# -------------------------------------------------------
# calcul_r($epaisseur_mm, $lambda_w_mk) → float
# Source corpus : §4.1 — R = e(mm) / (1000 × λ) en m²·K/W
# -------------------------------------------------------
sub calcul_r {
    my ($e, $lambda) = @_;
    return 0 unless $lambda && $lambda > 0;
    return $e / (1000 * $lambda);
}

# -------------------------------------------------------
# sd_min_m($classe_service) → float
# Source corpus : §4.2 — Valeur Sd minimale par classe de service
# -------------------------------------------------------
my %SD_MIN = (1 => 5.0, 2 => 18.0, 3 => 50.0);

sub sd_min_m {
    my ($classe) = @_;
    return $SD_MIN{$classe} // 5.0;
}

# -------------------------------------------------------
# type_est_isolant($type_element) → bool
# Source corpus : §1.1 + §4.1 — types isolants
# -------------------------------------------------------
sub type_est_isolant {
    my ($type) = @_;
    return ($type eq 'isolant_laine' || $type eq 'isolant_rigide') ? 1 : 0;
}

# -------------------------------------------------------
# type_est_membrane($type_element) → bool
# Source corpus : §1.1 + §4.2 — type pare-vapeur
# -------------------------------------------------------
sub type_est_membrane {
    my ($type) = @_;
    return $type eq 'membrane_etanche' ? 1 : 0;
}

# -------------------------------------------------------
# type_est_structurel_thermique($type_element) → bool
# Source corpus : §1.1 — types structuraux (pass-through thermique)
# -------------------------------------------------------
my %STRUCT_THERMIQUE = map { $_ => 1 } qw(
    montant_porteur montant_non_porteur
    lisse_basse lisse_haute entrait chevron
);

sub type_est_structurel_thermique {
    my ($type) = @_;
    return $STRUCT_THERMIQUE{$type} ? 1 : 0;
}

1;
