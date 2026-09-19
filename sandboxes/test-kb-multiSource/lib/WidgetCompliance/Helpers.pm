package WidgetCompliance::Helpers;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    min_load_for_class
);

# ---------------------------------------------------------------------------
# min_load_for_class($perf_class) → integer|undef
#
# Returns the minimum load threshold in Newtons for a given performance class.
# Source: CIR-1.0 Art.5 — Load conformance
#         cross-ref: ARF-2.1 §3.1 (class definitions — CONTEXT, consistent)
# ---------------------------------------------------------------------------
my %LOAD_THRESHOLDS = (
    P1 => 500,   # CIR Art.5 §1 — high-load industrial
    P2 => 300,   # CIR Art.5 §2 — standard commercial
    P3 => 150,   # CIR Art.5 §3 — light domestic
);

sub min_load_for_class {
    my ($class) = @_;
    return $LOAD_THRESHOLDS{$class // ''};
}

1;
