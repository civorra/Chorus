package COB::Agent::SecuriteFeu::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    rei_min
    classe_reaction_ok
    epaisseur_ba_min_mm
);

# -------------------------------------------------------
# rei_min($collectif) → int
# Source corpus : §5.1 — Performance REI minimale par type de bâtiment
# -------------------------------------------------------
sub rei_min {
    my ($collectif) = @_;
    return $collectif ? 60 : 30;
}

# -------------------------------------------------------
# classe_reaction_ok($classe) → bool
# Source corpus : §5.2 — Classes de réaction au feu admissibles
# Admissibles : A1, A2 (euroclasses NF EN 13501-1)
# -------------------------------------------------------
sub classe_reaction_ok {
    my ($classe) = @_;
    return ($classe eq 'A1' || $classe eq 'A2') ? 1 : 0;
}

# -------------------------------------------------------
# epaisseur_ba_min_mm($collectif) → int
# Source corpus : §5.3 — Épaisseur minimale plaque de plâtre
# -------------------------------------------------------
sub epaisseur_ba_min_mm {
    my ($collectif) = @_;
    return $collectif ? 26 : 13;
}

1;
