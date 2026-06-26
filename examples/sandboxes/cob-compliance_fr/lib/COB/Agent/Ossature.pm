package COB::Agent::Ossature;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use COB::Agent::Ossature::Helpers qw(
    section_min_porteur
    type_est_porteur_ossature
    type_est_charpente
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Ossature',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    {
        no strict 'refs';
        *{'Chorus::Engine::section_min_porteur'}      = \&section_min_porteur;
        *{'Chorus::Engine::type_est_porteur_ossature'} = \&type_est_porteur_ossature;
        *{'Chorus::Engine::type_est_charpente'}       = \&type_est_charpente;
    }

    $agent->loadRules("$base/rules/ossature");
    return $agent;
}

1;
