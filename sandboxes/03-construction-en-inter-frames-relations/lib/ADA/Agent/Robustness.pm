package ADA::Agent::Robustness;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() so they are available in YAML ACTION eval
use ADA::Agent::Robustness::Helpers qw(
    consequence_class_table11
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Robustness',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules().
    # YAML ACTIONs are eval'd inside Chorus::Engine — the helper must be
    # visible in the Chorus::Engine namespace at eval time.
    {
        no strict 'refs';
        *{'Chorus::Engine::consequence_class_table11'} = \&consequence_class_table11;
    }

    $agent->loadRules("$base/rules/robustness");

    return $agent;
}

1;
