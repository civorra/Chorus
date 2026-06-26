package COB::Agent::Qualification::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    classe_min_pour_type
    classe_ok
    fleche_admissible_mm
    type_est_structurel
    type_est_non_structural
);

# -------------------------------------------------------
# classe_min_pour_type($type_element) → string|undef
# Source corpus : §2.1 — Classes de résistance par type d'usage (NF EN 338)
# -------------------------------------------------------
my %CLASSE_MIN = (
    montant_porteur      => 'C24',
    montant_non_porteur  => 'C18',
    lisse_basse          => 'C24',
    lisse_haute          => 'C24',
    entrait              => 'C24',
    chevron              => 'C18',
);

sub classe_min_pour_type {
    my ($type) = @_;
    return $CLASSE_MIN{$type};
}

# -------------------------------------------------------
# classe_ok($classe_bois, $classe_min) → bool
# Source corpus : §2.1 — NF EN 338 — ordre des classes
# -------------------------------------------------------
my @ORDRE_CLASSES = qw(C14 C16 C18 C24 C30 C35 C40);
my %RANG_CLASSE   = map { $ORDRE_CLASSES[$_] => $_ } 0 .. $#ORDRE_CLASSES;

sub classe_ok {
    my ($classe_bois, $classe_min) = @_;
    return 0 unless defined $RANG_CLASSE{$classe_bois} && defined $RANG_CLASSE{$classe_min};
    return $RANG_CLASSE{$classe_bois} >= $RANG_CLASSE{$classe_min};
}

# -------------------------------------------------------
# fleche_admissible_mm($portee_mm) → float
# Source corpus : §2.3 — Flèche admissible = L/300
# -------------------------------------------------------
sub fleche_admissible_mm {
    my ($portee_mm) = @_;
    return ($portee_mm // 0) / 300;
}

# -------------------------------------------------------
# type_est_structurel($type_element) → bool
# Source corpus : §1.1 — types structuraux
# -------------------------------------------------------
my %TYPES_STRUCTURAUX = map { $_ => 1 } qw(
    montant_porteur montant_non_porteur
    lisse_basse lisse_haute entrait chevron
);

sub type_est_structurel {
    my ($type) = @_;
    return $TYPES_STRUCTURAUX{$type} ? 1 : 0;
}

# -------------------------------------------------------
# type_est_non_structural($type_element) → bool
# Source corpus : §1.1 + §4.1 — types non structuraux
# -------------------------------------------------------
my %TYPES_NON_STRUCTURAUX = map { $_ => 1 } qw(
    isolant_laine isolant_rigide membrane_etanche
);

sub type_est_non_structural {
    my ($type) = @_;
    return $TYPES_NON_STRUCTURAUX{$type} ? 1 : 0;
}

1;
