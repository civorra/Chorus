package CobIntro::Feed;

use strict;
use warnings;
use Chorus::Frame;
use JSON ();
use Exporter 'import';

our @EXPORT_OK = qw(load_projet);

# Slots obligatoires par type — extrait des KB (Catalogue des Frames)
# The agent 1 targeting slot (needs_qualify) is required for all types.
my %SLOTS_REQUIS = (
    load_bearing_stud    => [qw(needs_qualify type_element)],
    non_lb_stud          => [qw(needs_qualify type_element)],
    sole_plate           => [qw(needs_qualify type_element)],
    top_plate            => [qw(needs_qualify type_element)],
    rafter               => [qw(needs_qualify type_element)],
    joist                => [qw(needs_qualify type_element)],
    insulation           => [qw(needs_qualify type_element)],
    vapour_control_layer => [qw(needs_qualify type_element)],
);

sub load_projet {
    my ($fichier) = @_;

    # JSON->new->utf8->decode() handles UTF-8 decoding from raw bytes itself
    # — open without ':utf8' to avoid double decoding (Wide character).
    open my $fh, '<', $fichier
        or die "Cannot open $fichier: $!\n";
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data = JSON->new->utf8->decode($json);
    my @frames;

    for my $elem (@{ $data->{elements} }) {
        my $id   = $elem->{id}   // die "Element without 'id'\n";
        my $type = $elem->{type_element} // $elem->{type}
            // die "Element '$id' without 'type_element'\n";

        # Normalise: ensure type_element is set on the frame hash
        $elem->{type_element} //= $type;

        my $requis = $SLOTS_REQUIS{$type};
        unless ($requis) {
            # Type out-of-scope for this sandbox: skip without dying.
            warn "Type '$type' (element '$id') out-of-scope — skipped\n";
            next;
        }

        for my $slot (@$requis) {
            die "Required slot '$slot' missing for '$id' (type $type)\n"
                unless defined $elem->{$slot};
        }

        # The agent 1 targeting slot (needs_qualify) is
        # guaranteed present by the validation above.
        push @frames, Chorus::Frame->new(%$elem);
    }

    return @frames;
}

1;
