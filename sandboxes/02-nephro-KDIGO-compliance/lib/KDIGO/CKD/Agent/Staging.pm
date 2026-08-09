package KDIGO::CKD::Agent::Staging;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() to be available in YAML ACTIONs (eval)
use KDIGO::CKD::Agent::Staging::Helpers qw(
    egfr_to_g_category
    acr_to_a_category
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Staging',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules().
    # YAML ACTIONs are eval'd inside Chorus::Engine — the helpers must be
    # visible in the Chorus::Engine namespace at eval time.
    {
        no strict 'refs';
        *{'Chorus::Engine::egfr_to_g_category'} = \&egfr_to_g_category;
        *{'Chorus::Engine::acr_to_a_category'}  = \&acr_to_a_category;
    }

    $agent->loadRules("$base/rules/staging");

    return $agent;
}

1;
