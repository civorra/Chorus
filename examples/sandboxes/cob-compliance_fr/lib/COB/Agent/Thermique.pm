package COB::Agent::Thermique;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use COB::Agent::Thermique::Helpers qw(
    r_min_zone
    calcul_r
    sd_min_m
    type_est_isolant
    type_est_membrane
    type_est_structurel_thermique
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Thermique',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    {
        no strict 'refs';
        *{'Chorus::Engine::r_min_zone'}                  = \&r_min_zone;
        *{'Chorus::Engine::calcul_r'}                    = \&calcul_r;
        *{'Chorus::Engine::sd_min_m'}                    = \&sd_min_m;
        *{'Chorus::Engine::type_est_isolant'}            = \&type_est_isolant;
        *{'Chorus::Engine::type_est_membrane'}           = \&type_est_membrane;
        *{'Chorus::Engine::type_est_structurel_thermique'} = \&type_est_structurel_thermique;
    }

    $agent->loadRules("$base/rules/thermique");
    return $agent;
}

1;
