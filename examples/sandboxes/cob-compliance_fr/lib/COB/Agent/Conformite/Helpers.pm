package COB::Agent::Conformite::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    est_conforme
);

# -------------------------------------------------------
# est_conforme($frame) → [bool, $raison]
# Source corpus : §6.1 — Conditions de conformité par type d'élément
# -------------------------------------------------------
# Vérifie l'ensemble des conditions applicables selon le type et le
# flag collectif. Retourne [1, ''] si CONFORME, [0, $raisons] sinon.
#
# Règle d'agrégation des non-conformités :
#   - Un slot 'NON' est bloquant.
#   - Un slot 'NA' ou absent est non bloquant.
#   - feu_ok = 'NON' est bloquant pour tout élément (collectif ou non).
sub est_conforme {
    my ($p) = @_;
    my @raisons;

    # 1. Qualification (tous types bois)
    if (defined $p->{qualifie} && $p->{qualifie} eq 'NON') {
        push @raisons, "Qualification KO: " . ($p->{motif_refus} // 'raison inconnue');
    }

    # 2. Ossature (éléments structuraux uniquement — 'NA' non bloquant)
    my $oss = $p->{ossature_ok} // '';
    if ($oss eq 'NON') {
        push @raisons, "Ossature KO: " . ($p->{raison_ossature_ko} // 'raison inconnue');
    }

    # 3. Thermique (isolants et membranes — 'NA' non bloquant)
    my $th = $p->{thermique_ok} // '';
    if ($th eq 'NON') {
        push @raisons, "Thermique KO: " . ($p->{raison_thermique_ko} // 'raison inconnue');
    }

    # 4. Sécurité feu (tous types)
    my $feu = $p->{feu_ok} // '';
    if ($feu eq 'NON') {
        push @raisons, "Incendie KO: " . ($p->{raison_feu_ko} // 'raison inconnue');
    }

    if (@raisons) {
        return [0, join(' | ', @raisons)];
    }
    return [1, ''];
}

1;
