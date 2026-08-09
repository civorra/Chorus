package CobIntro::Agent::Compliance;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# No Helpers.pm for this agent — compliance logic is purely combinatorial.

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Compliance',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    $agent->loadRules("$base/rules/compliance");

    # Termination rule — pure Perl addrule() after loadRules().
    # Scope on type_element (always present on all frames).
    # Fires each cycle; when ALL elements have compliance_status set → solved().
    # $agent captured as closure — correct form for pure Perl addrule().
    $agent->addrule(
        _ID    => 'terminate',
        _SCOPE => {
            p => sub { [ Chorus::Frame::fmatch(slot => 'type_element') ] },
        },
        _APPLY => sub {
            my @pending = grep { !defined $_->{compliance_status} }
                          Chorus::Frame::fmatch(slot => 'type_element');
            if (@pending == 0) {
                $agent->solved();
                return 1;
            }
            return;
        },
    );

    return $agent;
}

1;
