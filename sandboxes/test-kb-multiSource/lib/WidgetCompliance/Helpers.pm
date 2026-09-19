package WidgetCompliance::Helpers;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    min_load_for_class
    algo_status
    min_key_length
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

# ---------------------------------------------------------------------------
# algo_status($algorithm) → 'approved' | 'deprecated' | undef
#
# Returns the approval status of a cryptographic algorithm.
# Source: ARF-2.1 §3.2 — Approved algorithm list (PRIMARY)
#         pinned at v2.1 per CORPUS-DIRECTIVES (CIR-1.0 Art.6 reference)
# ---------------------------------------------------------------------------
my %ALGO_STATUS = (
    AES  => 'approved',    # ARF-2.1 §3.2
    RSA  => 'approved',    # ARF-2.1 §3.2
    ECC  => 'approved',    # ARF-2.1 §3.2 (added v2.1)
    DES  => 'deprecated',  # ARF-2.1 §3.2
    '3DES' => 'deprecated',# ARF-2.1 §3.2 (deprecated v2.1)
);

sub algo_status {
    my ($algo) = @_;
    return $ALGO_STATUS{$algo // ''};
}

# ---------------------------------------------------------------------------
# min_key_length($algorithm) → integer | undef
#
# Returns minimum key length in bits for approved algorithms.
# Source: ARF-2.1 §3.2 Table 3.2-1 (CIR-1.0 Art.6 cross-ref)
# ---------------------------------------------------------------------------
my %MIN_KEY_LENGTH = (
    AES => 128,    # ARF-2.1 §3.2 Table 3.2-1
    RSA => 2048,   # ARF-2.1 §3.2 Table 3.2-1
    ECC => 256,    # ARF-2.1 §3.2 Table 3.2-1
);

sub min_key_length {
    my ($algo) = @_;
    return $MIN_KEY_LENGTH{$algo // ''};
}

1;
