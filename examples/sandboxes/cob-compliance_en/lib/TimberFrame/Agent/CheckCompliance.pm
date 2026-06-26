package TimberFrame::Agent::CheckCompliance;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# No Helpers.pm for CheckCompliance — all logic is inline in R01-check-compliance.yml

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'CheckCompliance',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    $agent->loadRules("$base/rules/check-compliance");

    # ⚠️ Pipeline termination — pure Perl addrule() (AFTER loadRules)
    # §6.2: solved() when ALL elements have been fully processed.
    # _SCOPE targets 'element_type' — always present, never deleted.
    # All presence slots (needs_qualify, needs_geometry, needs_thermal,
    # needs_fire, needs_compliance) are deleted after consumption.
    # When none remain, the pipeline is complete.
    # $agent captured as closure — never use $SELF->solved() here.
    $agent->addrule(
        _ID    => 'terminate-when-all-processed',
        _SCOPE => {
            e => sub { [ Chorus::Frame::fmatch(slot => 'element_type') ] },
        },
        _APPLY => sub {
            # Return early if any presence slot is still pending
            return if Chorus::Frame::fmatch(slot => 'needs_qualify');
            return if Chorus::Frame::fmatch(slot => 'needs_geometry');
            return if Chorus::Frame::fmatch(slot => 'needs_thermal');
            return if Chorus::Frame::fmatch(slot => 'needs_fire');
            return if Chorus::Frame::fmatch(slot => 'needs_compliance');
            # All presence slots consumed — pipeline complete
            $agent->solved();
            return 1;
        },
    );

    return $agent;
}

1;
