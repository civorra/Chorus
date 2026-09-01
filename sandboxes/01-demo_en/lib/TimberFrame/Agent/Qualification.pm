package TimberFrame::Agent::Qualification;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

use TimberFrame::Agent::Qualification::Helpers qw(
    min_strength_class_required
    class_rank
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

    # Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    {
        no strict 'refs';
        *{'Chorus::Engine::min_strength_class_required'} = \&min_strength_class_required;
        *{'Chorus::Engine::class_rank'}                  = \&class_rank;
    }

    $agent->loadRules("$base/rules/qualification");

    return $agent;
}

1;
