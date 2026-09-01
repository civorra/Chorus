package ADA::Agent::Foundation;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
use ADA::Agent::Foundation::Helpers qw(
    min_width_table10
    min_depth_2e4
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Foundation',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::min_width_table10'} = \&min_width_table10;
        *{'Chorus::Engine::min_depth_2e4'}     = \&min_depth_2e4;
    }

    $agent->loadRules("$base/rules/foundation");

    return $agent;
}

1;
