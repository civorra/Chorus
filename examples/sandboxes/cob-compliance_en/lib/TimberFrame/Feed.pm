package TimberFrame::Feed;

use strict;
use warnings;
use Chorus::Frame;
use JSON ();
use Exporter 'import';

our @EXPORT_OK = qw(load_projet);

# Slots obligatoires par type — extrait des KB (Catalogue des Frames)
# Le slot 'needs_qualify' est injecté par load_projet sur chaque Frame
# (targeting slot Agent 1 — Strategy B).
my %SLOTS_REQUIS = (
    load_bearing_stud => [qw(
        element_type strength_class moisture_pct
        stud_spacing_mm section_b_mm section_h_mm clear_height_mm
        has_longitudinal_splice
        collective fire_rei lining_reaction_class
        lining_surface_mass_kg plasterboard_thickness_mm
    )],
    non_load_bearing_stud => [qw(
        element_type strength_class moisture_pct
        collective fire_rei lining_reaction_class
        lining_surface_mass_kg plasterboard_thickness_mm
    )],
    sole_plate => [qw(
        element_type strength_class moisture_pct
        stud_spacing_mm section_b_mm section_h_mm clear_height_mm
        collective fire_rei lining_reaction_class
        lining_surface_mass_kg plasterboard_thickness_mm
    )],
    top_plate => [qw(
        element_type strength_class moisture_pct
        stud_spacing_mm section_b_mm section_h_mm clear_height_mm
        collective fire_rei lining_reaction_class
        lining_surface_mass_kg plasterboard_thickness_mm
    )],
    rafter => [qw(
        element_type strength_class moisture_pct
        collective fire_rei lining_reaction_class
        lining_surface_mass_kg plasterboard_thickness_mm
    )],
    joist => [qw(
        element_type strength_class moisture_pct
        collective fire_rei lining_reaction_class
        lining_surface_mass_kg plasterboard_thickness_mm
    )],
    insulation => [qw(
        element_type insulation_thickness_mm insulation_lambda climate_zone
        collective fire_rei lining_reaction_class
        lining_surface_mass_kg plasterboard_thickness_mm
    )],
    vapour_control => [qw(
        element_type vapour_sd_m service_class
        collective fire_rei lining_reaction_class
        lining_surface_mass_kg plasterboard_thickness_mm
    )],
);

sub load_projet {
    my ($fichier) = @_;

    open my $fh, '<', $fichier
        or die "Cannot open $fichier: $!\n";
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data = JSON->new->utf8->decode($json);
    my @frames;

    for my $elem (@{ $data->{elements} }) {
        my $id   = $elem->{id}   // die "Element without 'id'\n";
        my $type = $elem->{type} // die "Element '$id' without 'type'\n";

        # Normalise: use 'type' as 'element_type' if needed
        $elem->{element_type} //= $type;

        my $requis = $SLOTS_REQUIS{$type};
        unless ($requis) {
            warn "Type '$type' (element '$id') out-of-scope for this sandbox — skipped\n";
            next;
        }

        for my $slot (@$requis) {
            die "Missing slot '$slot' for '$id' (type $type)\n"
                unless defined $elem->{$slot};
        }

        # Inject Agent 1 targeting slot (Strategy B — presence slot)
        $elem->{needs_qualify} = 1;

        # Chorus::Frame->new(%$elem) calls _register() which registers all
        # slots in %REPOSITORY at construction time — no post-set() needed.
        push @frames, Chorus::Frame->new(%$elem);
    }

    return @frames;
}

1;
