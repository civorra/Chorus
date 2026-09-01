package TimberFrame::Feed;

use strict;
use warnings;
use Chorus::Frame;
use JSON ();
use Exporter 'import';

our @EXPORT_OK = qw(load_projet);

# Input-required slots per type — ONLY type_element is mandatory at load time.
# All other slots are optional project data or computed by pipeline rules.
# Targeting slots (needs_compliance, needs_thermal, needs_fire) are set below
# by Feed itself, not provided in the project JSON.
my %SLOTS_REQUIS = (
    load_bearing_stud     => [qw(type_element)],
    non_load_bearing_stud => [qw(type_element)],
    sole_plate            => [qw(type_element)],
    top_plate             => [qw(type_element)],
    rafter                => [qw(type_element)],
    joist                 => [qw(type_element)],
    insulation            => [qw(type_element)],
    vapour_control_layer  => [qw(type_element)],
);

# Types requiring thermal agent targeting slot
my %THERMAL_TYPES = map { $_ => 1 } qw(insulation vapour_control_layer);

# Types requiring fire agent (all element types)
# Types requiring geometry (set by qualification R04, not here)

sub load_projet {
    my ($fichier) = @_;

    # Open without ':utf8' — JSON->utf8->decode handles decoding from raw bytes
    open my $fh, '<', $fichier
        or die "Cannot open $fichier: $!\n";
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data = JSON->new->utf8->decode($json);
    my @frames;

    # Project-level collective flag — propagate to each element
    my $collective = $data->{collective} // 0;

    for my $elem (@{ $data->{elements} }) {
        my $id           = $elem->{id}           // die "Element without 'id'\n";
        my $type_element = $elem->{type_element} // die "Element '$id' without 'type_element'\n";

        my $requis = $SLOTS_REQUIS{$type_element};
        unless ($requis) {
            warn "type_element '$type_element' (element '$id') out-of-scope — skipped\n";
            next;
        }

        for my $slot (@$requis) {
            die "Slot '$slot' missing for '$id' (type_element=$type_element)\n"
                unless defined $elem->{$slot};
        }

        # Build the frame from project JSON data
        my %slots = %$elem;

        # Propagate project-level collective flag if not already on the element
        $slots{collective} //= $collective;

        my $frame = Chorus::Frame->new(%slots);

        # Set agent 1 targeting slot — needs_compliance on ALL elements
        $frame->set('needs_compliance', 1);

        # Set thermal targeting slot — only on insulation and vapour_control_layer
        $frame->set('needs_thermal', 1) if $THERMAL_TYPES{$type_element};

        # Set fire targeting slot — on ALL elements (§6.1: fire_ok required for all)
        $frame->set('needs_fire', 1);

        push @frames, $frame;
    }

    return @frames;
}

1;
