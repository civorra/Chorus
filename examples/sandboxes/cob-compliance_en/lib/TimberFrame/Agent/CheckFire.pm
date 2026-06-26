package TimberFrame::Agent::CheckFire;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# No Helpers.pm for CheckFire — _euroclass_rank is inline in R01-check-fire-requirements.yml

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'CheckFire',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    $agent->loadRules("$base/rules/check-fire");

    return $agent;
}

1;
