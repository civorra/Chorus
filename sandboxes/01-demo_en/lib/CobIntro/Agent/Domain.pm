package CobIntro::Agent::Domain;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() to be available in YAML ACTIONs (eval)
use CobIntro::Agent::Domain::Helpers qw(
    lb_stud_section_min
    thermal_r_min
    vcl_sd_min
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Domain',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # ⚠️ Inject helpers into Chorus::Engine BEFORE loadRules().
    {
        no strict 'refs';
        *{'Chorus::Engine::lb_stud_section_min'} = \&lb_stud_section_min;
        *{'Chorus::Engine::thermal_r_min'}        = \&thermal_r_min;
        *{'Chorus::Engine::vcl_sd_min'}           = \&vcl_sd_min;
    }

    $agent->loadRules("$base/rules/domain");

    return $agent;
}

1;
