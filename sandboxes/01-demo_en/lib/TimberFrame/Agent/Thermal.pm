package TimberFrame::Agent::Thermal;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use TimberFrame::Agent::Thermal::Helpers qw(
    r_min_by_zone
    sd_min_by_service_class
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Thermal',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::r_min_by_zone'}          = \&r_min_by_zone;
        *{'Chorus::Engine::sd_min_by_service_class'} = \&sd_min_by_service_class;
    }

    $agent->loadRules("$base/rules/thermal");

    return $agent;
}

1;
