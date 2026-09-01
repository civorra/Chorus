package ADA::Expert;

use strict;
use warnings;
use Chorus::Expert;
use Chorus::Frame;

# Pipeline agents — in #+PIPELINE_POS order (index.org)
use ADA::Agent::Robustness;   # pos 0 — §5/A3 Table 11 consequence class
use ADA::Agent::Geometry;     # pos 1 — §2C geometry checks
use ADA::Agent::Wall;         # pos 2 — §2C6/Table 3/5 wall thickness & ties
use ADA::Agent::Masonry;      # pos 3 — §2C21/Table 6/7 masonry strength
use ADA::Agent::Foundation;   # pos 4 — §2E Table 10 strip foundation (terminal)
use ADA::Agent::Chimney;      # pos 5 — §2D1 chimney proportion (independent)

sub run {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    my $max_cycles = $opts{max_cycles} // 10_000;

    # Build agents in pipeline order (#+PIPELINE_POS)
    my $a0 = ADA::Agent::Robustness->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a1 = ADA::Agent::Geometry->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a2 = ADA::Agent::Wall->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a3 = ADA::Agent::Masonry->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a4 = ADA::Agent::Foundation->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );
    my $a5 = ADA::Agent::Chimney->build(
        base_dir   => $base,
        max_cycles => $max_cycles,
    );

    my $xprt = Chorus::Expert->new();
    # ⚠ Known bug: Chorus::Expert->new() ignores its arguments
    # Force _MAX_ITER by direct assignment after new()
    $xprt->{_MAX_ITER} = $opts{max_iter} // 200_000;

    # Register agents in pipeline order.
    # ⚠️  Chimney (pos 5 in index) is registered BEFORE Foundation (pos 4):
    #   - Chimney targets masonry_chimney Frames via type_element — no upstream
    #     dependency; fires from iteration 1.
    #   - Foundation terminates the pipeline via addrule() → $agent->solved().
    #     Once solved() is called the Expert exits before any subsequent agent runs.
    #   → Chimney must appear before Foundation in the register() list.
    #   → Robustness (pos 0) targets building Frames with building_use defined.
    $xprt->register($a0, $a1, $a2, $a3, $a5, $a4);

    # BOARD: INPUT is set by process() → $agent->BOARD->{INPUT} = $input
    # No inter-agent BOARD slots are used in this pipeline.
    # All inter-agent communication is via Frame slot chaining:
    #   besoin_wall (Geometry→Wall) → besoin_masonry (Wall→Masonry)
    #   → besoin_foundation (Masonry→Foundation)

    return $xprt->process($opts{input} // {});
}

1;
