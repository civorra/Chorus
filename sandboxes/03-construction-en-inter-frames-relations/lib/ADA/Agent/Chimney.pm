package ADA::Agent::Chimney;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# No Helpers.pm for Chimney — §2D1 is a direct ratio, no table lookup required.

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Chimney',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # No Helpers.pm to inject — chimney rule R01 uses only arithmetic.

    $agent->loadRules("$base/rules/chimney");

    return $agent;
}

1;
