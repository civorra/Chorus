package ADA::Agent::Masonry;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
use ADA::Agent::Masonry::Helpers qw(
    diagram9_condition
    min_strength_table6
    min_normalised_table7
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Masonry',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::diagram9_condition'}    = \&diagram9_condition;
        *{'Chorus::Engine::min_strength_table6'}   = \&min_strength_table6;
        *{'Chorus::Engine::min_normalised_table7'} = \&min_normalised_table7;
    }

    $agent->loadRules("$base/rules/masonry");

    return $agent;
}

1;
