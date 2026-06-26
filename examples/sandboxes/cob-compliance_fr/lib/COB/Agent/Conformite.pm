package COB::Agent::Conformite;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use COB::Agent::Conformite::Helpers qw(
    est_conforme
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Conformite',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    {
        no strict 'refs';
        *{'Chorus::Engine::est_conforme'} = \&est_conforme;
    }

    $agent->loadRules("$base/rules/conformite");

    # Règle de terminaison — pure Perl addrule()
    # Jamais dans un YAML (fmatch global → boucle infinie garantie)
    # $agent capturé en closure : utiliser $agent->solved(), jamais $SELF->solved()
    $agent->addrule(
        _ID    => 'terminer',
        _SCOPE => {
            p => sub { [ Chorus::Frame::fmatch(slot => 'besoin_conformite') ] },
        },
        _APPLY => sub {
            my @sans = grep { !defined $_->{statut_conformite} }
                       Chorus::Frame::fmatch(slot => 'besoin_conformite');
            if (@sans == 0) {
                $agent->solved();
                return 1;
            }
            return;
        },
    );

    return $agent;
}

1;
