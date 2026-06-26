package TimberFrame::Agent::CheckGeometry;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
use TimberFrame::Agent::CheckGeometry::Helpers qw(
    _min_section_for_lb_stud
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'CheckGeometry',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # ⚠️ Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::_min_section_for_lb_stud'} = \&_min_section_for_lb_stud;
    }

    $agent->loadRules("$base/rules/check-geometry");

    return $agent;
}

1;
