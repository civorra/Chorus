package KDIGO::CKD::Expert;

use strict;
use warnings;
use Chorus::Expert;
use Chorus::Frame;
use KDIGO::CKD::Agent::Staging;
use KDIGO::CKD::Agent::Risk;
use KDIGO::CKD::Agent::Treatment;
use KDIGO::CKD::Agent::Care;

sub run {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    my $a1 = KDIGO::CKD::Agent::Staging->build(
        base_dir   => $base,
        max_cycles => $opts{max_cycles},
    );
    my $a2 = KDIGO::CKD::Agent::Risk->build(
        base_dir   => $base,
        max_cycles => $opts{max_cycles},
    );
    my $a3 = KDIGO::CKD::Agent::Treatment->build(
        base_dir   => $base,
        max_cycles => $opts{max_cycles},
    );
    my $a4 = KDIGO::CKD::Agent::Care->build(
        base_dir   => $base,
        max_cycles => $opts{max_cycles},
    );

    my $xprt = Chorus::Expert->new();
    # ⚠️ Known bug: new() ignores its arguments — force _MAX_ITER directly.
    $xprt->{_MAX_ITER} = $opts{max_iter} // 50_000;
    $xprt->register($a1, $a2, $a3, $a4);   # order = #+PIPELINE_POS

    # BOARD: no inter-agent keys used in this pipeline.
    # SOLVED and FAILED keys are reserved by the engine.

    return $xprt->process($opts{input} // {});
}

1;
