package CyberSec::Agent::CertProfileNat;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;
use Exporter 'import';

our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'CertProfileNat',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    $agent->loadRules("$base/rules/cert-profile-nat");

    return $agent;
}

1;
