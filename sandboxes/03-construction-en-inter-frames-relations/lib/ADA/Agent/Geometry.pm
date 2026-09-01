package ADA::Agent::Geometry;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() so they are available in YAML ACTION eval
use ADA::Agent::Geometry::Helpers qw(
    max_height_from_table_c
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Geometry',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules().
    # YAML ACTIONs are eval'd inside Chorus::Engine — the helper must be
    # visible in the Chorus::Engine namespace at eval time.
    {
        no strict 'refs';
        *{'Chorus::Engine::max_height_from_table_c'} = \&max_height_from_table_c;
    }

    $agent->loadRules("$base/rules/geometry");

    return $agent;
}

1;
