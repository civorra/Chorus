package TimberFrame::Agent::Geometry;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use TimberFrame::Agent::Geometry::Helpers qw(
    min_lb_section
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'Geometry',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::min_lb_section'} = \&min_lb_section;
    }

    $agent->loadRules("$base/rules/geometry");

    return $agent;
}

1;
