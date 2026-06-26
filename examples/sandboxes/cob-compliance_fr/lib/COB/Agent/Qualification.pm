package COB::Agent::Qualification;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use COB::Agent::Qualification::Helpers qw(
    classe_min_pour_type
    classe_ok
    fleche_admissible_mm
    type_est_structurel
    type_est_non_structural
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Qualification',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    {
        no strict 'refs';
        *{'Chorus::Engine::classe_min_pour_type'}    = \&classe_min_pour_type;
        *{'Chorus::Engine::classe_ok'}               = \&classe_ok;
        *{'Chorus::Engine::fleche_admissible_mm'}    = \&fleche_admissible_mm;
        *{'Chorus::Engine::type_est_structurel'}     = \&type_est_structurel;
        *{'Chorus::Engine::type_est_non_structural'} = \&type_est_non_structural;
    }

    $agent->loadRules("$base/rules/qualification");
    return $agent;
}

1;
