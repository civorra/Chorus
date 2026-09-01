package CyberSec::Feed;

use strict;
use warnings;
use Chorus::Frame;
use JSON ();
use Exporter 'import';

our @EXPORT_OK = qw(load_projet);

# Input-required slots per type_element.
# All non-type_element slots are provided in the project JSON and read directly
# by the rules — they are not rule-computed.
# The targeting slot 'needs_cert_validation' is injected by Feed at Frame creation time.
my %SLOTS_REQUIS = (
    cert_ext => [qw(type_element)],
    nat      => [qw(type_element)],
    leg      => [qw(type_element)],
    web      => [qw(type_element)],
    gen      => [qw(type_element)],
);

sub load_projet {
    my ($fichier) = @_;

    # JSON->new->utf8->decode() handles UTF-8 decoding from raw bytes itself
    # — open without ':utf8' to avoid double decoding (Wide character).
    open my $fh, '<', $fichier
        or die "Cannot open $fichier: $!\n";
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data     = JSON->new->utf8->decode($json);
    my @elements = @{ $data->{elements} // [] };
    my @frames;

    for my $elem (@elements) {
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

        my $frame = Chorus::Frame->new(%$elem);

        # Inject the Agent 1 (CertProfileCommon) targeting slot on every frame.
        # Agent 2 (CertProfileNat) and Agent 3 (CertProfileLeg) targeting slots
        # are set by CertProfileCommon R90 based on type_element.
        $frame->set('needs_cert_validation', 'Y');

        push @frames, $frame;
    }

    # Create a pipeline control frame — holds handoff flags for R91 and R13.
    # This frame is invisible to all domain rules (none of them target
    # 'pipeline_ctrl'). It is used by R91 and R13 EXCEPTION guards to prevent
    # re-firing on subsequent Expert outer-loop cycles.
    my $ctrl = Chorus::Frame->new(pipeline_ctrl => 'Y');
    push @frames, $ctrl;

    return @frames;
}

1;
