package KDIGO::CKD::Feed;

use strict;
use warnings;
use Chorus::Frame;
use JSON ();
use Exporter 'import';

our @EXPORT_OK = qw(load_projet);

# Input-required slots per type_element — Phase 1.5 YAML slot analysis.
# All slots other than 'type_element' are rule-computed or optional project
# data read via $p->get() in YAML ACTION blocks.
# Agent 1 (Staging) targeting slot: type_element = "patient" (Strategy A).
my %SLOTS_REQUIS = (
    'patient' => [qw(type_element)],
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
        my $id           = $elem->{id}           // die "Element without 'id'\n";
        my $type_element = $elem->{type_element} // die "Element '$id' without 'type_element'\n";

        my $requis = $SLOTS_REQUIS{$type_element};
        unless ($requis) {
            # type_element out-of-scope for this sandbox: skip without dying.
            warn "type_element '$type_element' (element '$id') out-of-scope — skipped\n";
            next;
        }

        for my $slot (@$requis) {
            die "Slot '$slot' missing for '$id' (type_element=$type_element)\n"
                unless defined $elem->{$slot};
        }

        # type_element (agent 1 targeting slot) is guaranteed present by the
        # validation above.
        push @frames, Chorus::Frame->new(%$elem);
    }

    return @frames;
}

1;
