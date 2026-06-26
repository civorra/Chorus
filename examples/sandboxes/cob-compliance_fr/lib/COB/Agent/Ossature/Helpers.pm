package COB::Agent::Ossature::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    section_min_porteur
    type_est_porteur_ossature
    type_est_charpente
);

# -------------------------------------------------------
# section_min_porteur($hauteur_libre_mm, $entraxe_mm) → [b_min, h_min]
# Source corpus : §3.2 — Section minimale montants porteurs et lisses
# -------------------------------------------------------
# Matrice hauteur × entraxe → [b_min, h_min] en mm
sub section_min_porteur {
    my ($h, $e) = @_;
    $h //= 0;
    $e //= 600;
    if    ($h <= 2700 && $e <= 400) { return [45, 120] }
    elsif ($h <= 2700 && $e <= 600) { return [45, 145] }
    elsif ($h <= 3000 && $e <= 400) { return [45, 145] }
    elsif ($h <= 3000 && $e <= 600) { return [45, 170] }
    else                            { return [60, 200] }
}

# -------------------------------------------------------
# type_est_porteur_ossature($type_element) → bool
# Source corpus : §3.2 — types soumis aux sections porteurs
# -------------------------------------------------------
my %TYPES_PORTEURS_OSSATURE = map { $_ => 1 } qw(
    montant_porteur lisse_basse lisse_haute
);

sub type_est_porteur_ossature {
    my ($type) = @_;
    return $TYPES_PORTEURS_OSSATURE{$type} ? 1 : 0;
}

# -------------------------------------------------------
# type_est_charpente($type_element) → bool
# Source corpus : §1.1 — types charpente (pas de vérif ossature)
# -------------------------------------------------------
sub type_est_charpente {
    my ($type) = @_;
    return ($type eq 'entrait' || $type eq 'chevron') ? 1 : 0;
}

1;
