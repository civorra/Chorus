package KDIGO::CKD::Agent::Care;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# No Helpers.pm for this agent — all logic is directly in YAML ACTIONs.

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Care',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Termination rule R03-termination.yml uses TERMINAL: solved — MCP-compatible.
    # No addrule() needed.
    $agent->loadRules("$base/rules/care");

    return $agent;
}

1;
