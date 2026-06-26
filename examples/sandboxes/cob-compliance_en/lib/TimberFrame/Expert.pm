package TimberFrame::Expert;

use strict;
use warnings;
use Chorus::Expert;
use Chorus::Frame;

use TimberFrame::Agent::QualifyMaterial;
use TimberFrame::Agent::CheckGeometry;
use TimberFrame::Agent::CheckThermal;
use TimberFrame::Agent::CheckFire;
use TimberFrame::Agent::CheckCompliance;

sub run {
    my ($class, %opts) = @_;
    my $base       = $opts{base_dir}   // '.';
    my $max_cycles = $opts{max_cycles} // 10_000;

    # Build agents in pipeline order (#+PIPELINE_POS)
    my $a1 = TimberFrame::Agent::QualifyMaterial->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a2 = TimberFrame::Agent::CheckGeometry->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a3 = TimberFrame::Agent::CheckThermal->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a4 = TimberFrame::Agent::CheckFire->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a5 = TimberFrame::Agent::CheckCompliance->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );

    my $xprt = Chorus::Expert->new();
    # ⚠️ Known bug: Chorus::Expert->new() ignores its arguments.
    # Force _MAX_ITER by direct assignment after new().
    $xprt->{_MAX_ITER} = $opts{max_iter} // 50_000;

    # Register agents in pipeline order
    $xprt->register($a1, $a2, $a3, $a4, $a5);

    # BOARD — shared state accessible via $agent->BOARD in all agents
    # Reserved keys: SOLVED (set by solved()), FAILED (set by failed()),
    #                INPUT (set by process()).
    # No custom BOARD keys needed in this pipeline.

    return $xprt->process($opts{input} // {});
}

1;
