package CyberSec::Expert;

use strict;
use warnings;
use Chorus::Expert;
use Chorus::Frame;
use CyberSec::Agent::CertProfileCommon;
use CyberSec::Agent::CertProfileNat;
use CyberSec::Agent::CertProfileLeg;

sub run {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    my $a1 = CyberSec::Agent::CertProfileCommon->build(base_dir => $base, max_cycles => $opts{max_cycles});
    my $a2 = CyberSec::Agent::CertProfileNat->build(   base_dir => $base, max_cycles => $opts{max_cycles});
    my $a3 = CyberSec::Agent::CertProfileLeg->build(   base_dir => $base, max_cycles => $opts{max_cycles});

    my $xprt = Chorus::Expert->new();
    # Known bug: new() ignores its arguments — force _MAX_ITER by direct assignment
    $xprt->{_MAX_ITER} = $opts{max_iter} // 100_000;
    $xprt->register($a1, $a2, $a3);

    # BOARD notes:
    #   Agent 1 (CertProfileCommon) sets needs_nat_validation / needs_leg_validation on frames
    #   then calls $SELF->last() via R91 when all frames have cert_profile_result.
    #   Agent 2 (CertProfileNat) calls $SELF->last() via R13 when all NAT frames have nat_profile_result.
    #   Agent 3 (CertProfileLeg) terminates via R25 TERMINAL: solved when all LEG frames are done.

    return $xprt->process($opts{input} // {});
}

1;
