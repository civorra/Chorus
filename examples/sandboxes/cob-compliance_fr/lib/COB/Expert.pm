package COB::Expert;

use strict;
use warnings;
use Chorus::Expert;
use Chorus::Frame;
use COB::Agent::Qualification;
use COB::Agent::Ossature;
use COB::Agent::Thermique;
use COB::Agent::SecuriteFeu;
use COB::Agent::Conformite;

sub run {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    my $a1 = COB::Agent::Qualification->build(base_dir => $base, max_cycles => $opts{max_cycles});
    my $a2 = COB::Agent::Ossature->build(     base_dir => $base, max_cycles => $opts{max_cycles});
    my $a3 = COB::Agent::Thermique->build(    base_dir => $base, max_cycles => $opts{max_cycles});
    my $a4 = COB::Agent::SecuriteFeu->build(  base_dir => $base, max_cycles => $opts{max_cycles});
    my $a5 = COB::Agent::Conformite->build(   base_dir => $base, max_cycles => $opts{max_cycles});

    my $xprt = Chorus::Expert->new();
    # ⚠️ Bug connu : Chorus::Expert->new() ignore ses arguments
    # Forcer _MAX_ITER par affectation directe après new()
    $xprt->{_MAX_ITER} = $opts{max_iter} // 50_000;
    $xprt->register($a1, $a2, $a3, $a4, $a5);

    return $xprt->process($opts{input} // {});
}

1;
