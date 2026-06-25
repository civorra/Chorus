package COB::Feed;

use strict;
use warnings;
use Chorus::Frame;
use JSON ();
use Exporter 'import';

our @EXPORT_OK = qw(load_projet);

# Slots obligatoires par type — extrait des KB (Catalogue des Frames)
# Slot besoin_qualification posé sur tous les éléments (agent 1 ciblage)
my %SLOTS_REQUIS = (
    'montant_porteur'      => [qw(besoin_qualification type_element classe_bois humidite_pct fleche_mesuree_mm portee_mm entraxe_mm hauteur_libre_mm section_b_mm section_h_mm)],
    'montant_non_porteur'  => [qw(besoin_qualification type_element classe_bois humidite_pct fleche_mesuree_mm portee_mm section_b_mm section_h_mm)],
    'lisse_basse'          => [qw(besoin_qualification type_element classe_bois humidite_pct fleche_mesuree_mm portee_mm entraxe_mm hauteur_libre_mm section_b_mm section_h_mm)],
    'lisse_haute'          => [qw(besoin_qualification type_element classe_bois humidite_pct fleche_mesuree_mm portee_mm entraxe_mm hauteur_libre_mm section_b_mm section_h_mm)],
    'entrait'              => [qw(besoin_qualification type_element classe_bois humidite_pct fleche_mesuree_mm portee_mm)],
    'chevron'              => [qw(besoin_qualification type_element classe_bois humidite_pct fleche_mesuree_mm portee_mm)],
    'isolant_laine'        => [qw(besoin_qualification type_element zone_climatique classe_service epaisseur_mm lambda_w_mk)],
    'isolant_rigide'       => [qw(besoin_qualification type_element zone_climatique classe_service epaisseur_mm lambda_w_mk)],
    'membrane_etanche'     => [qw(besoin_qualification type_element classe_service sd_m)],
);

sub load_projet {
    my ($fichier) = @_;

    open my $fh, '<', $fichier
        or die "Impossible d'ouvrir $fichier : $!\n";
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data = JSON->new->utf8->decode($json);
    my @frames;

    for my $elem (@{ $data->{elements} }) {
        my $id   = $elem->{id}           // die "Element sans 'id'\n";
        my $type = $elem->{type_element} // die "Element '$id' sans 'type_element'\n";

        my $requis = $SLOTS_REQUIS{$type};
        unless ($requis) {
            warn "Type '$type' (element '$id') hors perimetre — ignore\n";
            next;
        }

        for my $slot (@$requis) {
            die "Slot '$slot' manquant pour '$id' (type $type)\n"
                unless defined $elem->{$slot};
        }

        # besoin_qualification = slot ciblage agent 1 (qualification)
        # garanti present par la validation ci-dessus
        push @frames, Chorus::Frame->new(%$elem);
    }

    return @frames;
}

1;
