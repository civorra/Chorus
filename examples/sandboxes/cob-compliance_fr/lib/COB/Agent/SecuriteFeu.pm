package COB::Agent::SecuriteFeu;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use COB::Agent::SecuriteFeu::Helpers qw(
    rei_min
    classe_reaction_ok
    epaisseur_ba_min_mm
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'SecuriteFeu',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    {
        no strict 'refs';
        *{'Chorus::Engine::rei_min'}              = \&rei_min;
        *{'Chorus::Engine::classe_reaction_ok'}   = \&classe_reaction_ok;
        *{'Chorus::Engine::epaisseur_ba_min_mm'}  = \&epaisseur_ba_min_mm;
    }

    $agent->loadRules("$base/rules/securite-feu");
    return $agent;
}

1;
