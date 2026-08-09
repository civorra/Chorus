package CobIntro::Expert;

use strict;
use warnings;
use Chorus::Expert;
use Chorus::Frame;
use CobIntro::Agent::Qualification;
use CobIntro::Agent::Domain;
use CobIntro::Agent::Fire;
use CobIntro::Agent::Compliance;

sub run {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    my $a1 = CobIntro::Agent::Qualification->build(base_dir => $base, max_cycles => $opts{max_cycles});
    my $a2 = CobIntro::Agent::Domain->build(       base_dir => $base, max_cycles => $opts{max_cycles});
    my $a3 = CobIntro::Agent::Fire->build(         base_dir => $base, max_cycles => $opts{max_cycles});
    my $a4 = CobIntro::Agent::Compliance->build(   base_dir => $base, max_cycles => $opts{max_cycles});

    my $xprt = Chorus::Expert->new();
    # ⚠️ Known bug: Chorus::Expert->new() ignores its arguments — force _MAX_ITER
    $xprt->{_MAX_ITER} = $opts{max_iter} // 50_000;
    $xprt->register($a1, $a2, $a3, $a4);   # order = #+PIPELINE_POS

    # BOARD: INPUT set by process(); SOLVED/FAILED managed by the engine.
    # No inter-agent BOARD slots required by this pipeline.

    return $xprt->process($opts{input} // {});
}

1;
