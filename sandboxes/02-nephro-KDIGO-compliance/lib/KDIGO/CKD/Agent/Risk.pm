package KDIGO::CKD::Agent::Risk;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() to be available in YAML ACTIONs (eval)
use KDIGO::CKD::Agent::Risk::Helpers qw(
    monitoring_frequency_per_year
    referral_tier_from_risk
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Risk',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules().
    {
        no strict 'refs';
        *{'Chorus::Engine::monitoring_frequency_per_year'} = \&monitoring_frequency_per_year;
        *{'Chorus::Engine::referral_tier_from_risk'}       = \&referral_tier_from_risk;
    }

    $agent->loadRules("$base/rules/risk");

    return $agent;
}

1;
