package KDIGO::CKD::Agent::Risk::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    monitoring_frequency_per_year
    referral_tier_from_risk
);

# -------------------------------------------------------
# monitoring_frequency_per_year
# Source corpus: §2.1 — KDIGO 2024 CKD Guideline
#   Practice Points 2.1.1–2.1.2 — Monitoring overview
#   KDIGO 2024 heat-map: recommended monitoring frequency by G+A stage
# -------------------------------------------------------
# Signature: monitoring_frequency_per_year($g_category, $a_category) → $int
# Called by: rules/risk/R01-monitoring-frequency.yml (ACTION)
#
# Monitoring frequency table (visits/year):
#   G1/G2 + A1/A2 → 1   G1/G2 + A3    → 2
#   G3a   + A1/A2 → 1   G3a   + A3    → 2
#   G3b   + A1/A2 → 2   G3b   + A3    → 3
#   G4    + A1/A2 → 3   G4    + A3    → 4
#   G5    (all)   → 4  (specialist monitoring — minimum value returned)
sub monitoring_frequency_per_year {
    my ($g, $a) = @_;

    # G5: specialist / dialysis preparation → 4 visits/year minimum
    return 4 if $g eq 'G5';

    # G4
    if ($g eq 'G4') {
        return 4 if $a eq 'A3';
        return 3;   # A1 or A2
    }

    # G3b
    if ($g eq 'G3b') {
        return 3 if $a eq 'A3';
        return 2;   # A1 or A2
    }

    # G3a
    if ($g eq 'G3a') {
        return 2 if $a eq 'A3';
        return 1;   # A1 or A2
    }

    # G1 or G2
    return 2 if $a eq 'A3';
    return 1;   # A1 or A2 — annual monitoring sufficient
}

# -------------------------------------------------------
# referral_tier_from_risk
# Source corpus: §2.2 — KDIGO 2024 CKD Guideline
#   Recommendation 2.2.1 + Practice Points 2.2.1–2.2.3
#   §5.1 — Referral to specialist kidney care services
# -------------------------------------------------------
# Signature: referral_tier_from_risk($g, $kfr_2y, $kfr_5y) → $tier_str
# Called by: rules/risk/R02-referral-tier.yml (ACTION)
#
# Referral tier thresholds:
#   2-year KFR > 40%       → "krt_preparation"   (PP 2.2.3)
#   2-year KFR > 10%       → "multidisciplinary"  (PP 2.2.2)
#   5-year KFR 3–5%        → "nephrology"         (PP 2.2.1)
#   G4 or G5 (no KFR data) → "nephrology"         (conservative fallback)
#   Otherwise              → "primary_care"
sub referral_tier_from_risk {
    my ($g, $kfr_2y, $kfr_5y) = @_;

    # 2-year KFR threshold — KRT preparation (§2.2.3 PP)
    if (defined $kfr_2y && $kfr_2y > 40) {
        return 'krt_preparation';
    }

    # 2-year KFR threshold — multidisciplinary care (§2.2.2 PP)
    if (defined $kfr_2y && $kfr_2y > 10) {
        return 'multidisciplinary';
    }

    # 5-year KFR threshold — nephrology referral (§2.2.1 PP)
    if (defined $kfr_5y && $kfr_5y >= 3 && $kfr_5y <= 5) {
        return 'nephrology';
    }

    # G4/G5 without KFR score — conservative nephrology referral
    if ($g eq 'G4' || $g eq 'G5') {
        return 'nephrology';
    }

    # Default — primary care management
    return 'primary_care';
}

1;
