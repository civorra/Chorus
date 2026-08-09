package KDIGO::CKD::Agent::Treatment;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() to be available in YAML ACTIONs (eval)
use KDIGO::CKD::Agent::Treatment::Helpers qw(
    rasi_indicated
    sglt2i_indicated
    mra_indicated
    statin_indicated
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Treatment',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules().
    {
        no strict 'refs';
        *{'Chorus::Engine::rasi_indicated'}   = \&rasi_indicated;
        *{'Chorus::Engine::sglt2i_indicated'} = \&sglt2i_indicated;
        *{'Chorus::Engine::mra_indicated'}    = \&mra_indicated;
        *{'Chorus::Engine::statin_indicated'} = \&statin_indicated;
    }

    $agent->loadRules("$base/rules/treatment");

    return $agent;
}

1;
