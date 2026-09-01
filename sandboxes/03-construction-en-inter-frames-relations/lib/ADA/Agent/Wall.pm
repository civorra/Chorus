package ADA::Agent::Wall;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
use ADA::Agent::Wall::Helpers qw(
    min_thickness_table3
    min_tie_length_table5
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Wall',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::min_thickness_table3'}  = \&min_thickness_table3;
        *{'Chorus::Engine::min_tie_length_table5'} = \&min_tie_length_table5;
    }

    $agent->loadRules("$base/rules/wall");

    return $agent;
}

1;
