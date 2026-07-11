package CobIntro::Agent::Fire;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() to be available in YAML ACTIONs (eval)
use CobIntro::Agent::Fire::Helpers qw(
    rei_required
    reaction_class_ok
    pb_thickness_min
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Fire',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # ⚠️ Inject helpers into Chorus::Engine BEFORE loadRules().
    {
        no strict 'refs';
        *{'Chorus::Engine::rei_required'}       = \&rei_required;
        *{'Chorus::Engine::reaction_class_ok'}  = \&reaction_class_ok;
        *{'Chorus::Engine::pb_thickness_min'}   = \&pb_thickness_min;
    }

    $agent->loadRules("$base/rules/fire");

    return $agent;
}

1;
