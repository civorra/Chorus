package TimberFrame::Expert;

use strict;
use warnings;
use Chorus::Expert;
use Chorus::Frame;
use TimberFrame::Agent::Qualification;
use TimberFrame::Agent::Geometry;
use TimberFrame::Agent::Thermal;
use TimberFrame::Agent::Fire;
use TimberFrame::Agent::Compliance;

sub run {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    my $a1 = TimberFrame::Agent::Qualification->build(base_dir => $base, max_cycles => $opts{max_cycles});
    my $a2 = TimberFrame::Agent::Geometry->build(     base_dir => $base, max_cycles => $opts{max_cycles});
    my $a3 = TimberFrame::Agent::Thermal->build(      base_dir => $base, max_cycles => $opts{max_cycles});
    my $a4 = TimberFrame::Agent::Fire->build(         base_dir => $base, max_cycles => $opts{max_cycles});
    my $a5 = TimberFrame::Agent::Compliance->build(   base_dir => $base, max_cycles => $opts{max_cycles});

    my $xprt = Chorus::Expert->new();
    # ⚠️ Known bug: Chorus::Expert->new() ignores its arguments — force _MAX_ITER
    $xprt->{_MAX_ITER} = $opts{max_iter} // 50_000;
    $xprt->register($a1, $a2, $a3, $a4, $a5);   # order = #+PIPELINE_POS

    return $xprt->process($opts{input} // {});
}

1;
