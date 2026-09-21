package WidgetCompliance::Helpers;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    min_load_for_class
    algo_status
    min_key_length
    key_crack_benchmark
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

# ---------------------------------------------------------------------------
# key_crack_benchmark($algorithm) → { key_length, cost, year } | undef
#
# Justification-only helper — never determines algo_ok (verdict stays on the
# direct min_key_length() threshold comparison in R02). Returns the closest
# published empirical benchmark record for the algorithm's approved minimum
# key length, to enrich motif_algo on the NON branch.
#
# Source corpus: CIR-1.0 Annex C (informative) — Empirical key-strength
#   benchmark data, Table C.1 — classified HELPER-SOURCE by chorus-corpus-scoping
#   Phase 2 Step 0b (real execution, 2026-09-20 — see TEST-PLAN-helper-source.md).
# ---------------------------------------------------------------------------
my %BENCHMARK_RECORDS = (
    AES => [
        { key_length => 112, cost => '4.2e18 USD', year => 2024 },
        { key_length => 128, cost => '1.8e21 USD', year => 2024 },
    ],
    RSA => [
        { key_length => 1024, cost => 'broken (feasible)',        year => 2024 },
        { key_length => 2048, cost => 'not feasible (>2e30 USD)', year => 2024 },
    ],
);

sub key_crack_benchmark {
    my ($algorithm) = @_;
    my $records = $BENCHMARK_RECORDS{$algorithm // ''} or return undef;
    my $min = min_key_length($algorithm);
    return undef unless defined $min;
    my ($closest) = sort {
        abs($a->{key_length} - $min) <=> abs($b->{key_length} - $min)
    } @$records;
    return $closest;
}

1;
