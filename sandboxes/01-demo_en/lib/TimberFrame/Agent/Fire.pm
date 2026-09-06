package TimberFrame::Agent::Fire;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use TimberFrame::Agent::Fire::Helpers qw(
    min_rei_required
    reaction_class_rank
    min_pb_thickness
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

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::min_rei_required'}    = \&min_rei_required;
        *{'Chorus::Engine::reaction_class_rank'} = \&reaction_class_rank;
        *{'Chorus::Engine::min_pb_thickness'}    = \&min_pb_thickness;
    }

    $agent->loadRules("$base/rules/fire");

    return $agent;
}

1;
