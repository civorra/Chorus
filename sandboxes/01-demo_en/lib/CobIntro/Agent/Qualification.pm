package CobIntro::Agent::Qualification;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() to be available in YAML ACTIONs (eval)
use CobIntro::Agent::Qualification::Helpers qw(
    min_strength_class
    strength_class_ok
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

    # ⚠️ Inject helpers into Chorus::Engine BEFORE loadRules().
    # YAML ACTIONs are eval'd inside Chorus::Engine — the helper must be
    # visible in the Chorus::Engine namespace at eval time.
    {
        no strict 'refs';
        *{'Chorus::Engine::min_strength_class'} = \&min_strength_class;
        *{'Chorus::Engine::strength_class_ok'}  = \&strength_class_ok;
    }

    $agent->loadRules("$base/rules/qualification");

    return $agent;
}

1;
