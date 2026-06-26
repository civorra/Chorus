package TimberFrame::Agent::CheckThermal;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
use TimberFrame::Agent::CheckThermal::Helpers qw(
    _r_min_for_zone
    _sd_min_for_service_class
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'CheckThermal',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # ⚠️ Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::_r_min_for_zone'}           = \&_r_min_for_zone;
        *{'Chorus::Engine::_sd_min_for_service_class'} = \&_sd_min_for_service_class;
    }

    $agent->loadRules("$base/rules/check-thermal");

    return $agent;
}

1;
