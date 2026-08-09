package KDIGO::CKD::Agent::Treatment::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    rasi_indicated
    sglt2i_indicated
    mra_indicated
    statin_indicated
);

# -------------------------------------------------------
# rasi_indicated
# Source corpus: §3.6 — KDIGO 2024 CKD Guideline
#   Recommendations 3.6.1 (1B), 3.6.2 (2C), 3.6.3 (1B)
#   Renin-angiotensin system inhibitors
# -------------------------------------------------------
# Signature: rasi_indicated($g_category, $a_category, $has_diabetes) → "yes"|"no"
# Called by: rules/treatment/R01-rasi-indication.yml (ACTION)
#
# Indications:
#   §3.6.1: G1–G4 + A3 + no diabetes       → yes (strong rec 1B)
#   §3.6.2: G1–G4 + A2 + no diabetes       → yes (moderate rec 2C)
#   §3.6.3: G1–G4 + A2 or A3 + diabetes    → yes (strong rec 1B)
#   G5 excluded (PP 3.6.5 — may reduce/stop at eGFR <15)
#   A1 (normal to mildly increased): not indicated by §3.6
sub rasi_indicated {
    my ($g, $a, $has_diabetes) = @_;
    $has_diabetes //= 0;

    # G5 — excluded from standard RASi initiation (PP 3.6.5)
    return 'no' if $g eq 'G5';

    # Only G1–G4 considered below
    if ($has_diabetes) {
        # §3.6.3: A2 or A3 with diabetes → indicated
        return 'yes' if $a eq 'A2' || $a eq 'A3';
    } else {
        # §3.6.1: A3 without diabetes → indicated
        return 'yes' if $a eq 'A3';
        # §3.6.2: A2 without diabetes → indicated
        return 'yes' if $a eq 'A2';
    }

    # A1 or other conditions → not indicated via §3.6
    return 'no';
}

# -------------------------------------------------------
# sglt2i_indicated
# Source corpus: §3.7 — KDIGO 2024 CKD Guideline
#   Recommendations 3.7.1 (1A), 3.7.2 (1A), 3.7.3 (2B)
#   SGLT2 inhibitors
# -------------------------------------------------------
# Signature: sglt2i_indicated($egfr, $acr, $has_diabetes, $has_hf) → "mandatory"|"suggested"|"no"
# Called by: rules/treatment/R02-sglt2i-indication.yml (ACTION)
#
# §3.7.1 (1A): T2D + CKD + eGFR ≥ 20        → "mandatory"
# §3.7.2 (1A): eGFR ≥ 20 + ACR ≥ 200        → "mandatory"
# §3.7.2 (1A): heart failure (any ACR)        → "mandatory"
# §3.7.3 (2B): eGFR 20–45 + ACR < 200       → "suggested"
# eGFR < 20                                    → "no" (not initiated, though may continue)
sub sglt2i_indicated {
    my ($egfr, $acr, $has_diabetes, $has_hf) = @_;
    $has_diabetes //= 0;
    $has_hf       //= 0;
    $acr          //= 0;

    # eGFR < 20 → not initiated (initiation threshold §3.7.1-3.7.2)
    return 'no' if $egfr < 20;

    # §3.7.1 — T2D + eGFR ≥ 20 (1A — strong recommendation)
    return 'mandatory' if $has_diabetes;

    # §3.7.2 — eGFR ≥ 20 + ACR ≥ 200 (1A) regardless of diabetes
    return 'mandatory' if $acr >= 200;

    # §3.7.2 — heart failure (1A) regardless of albuminuria
    return 'mandatory' if $has_hf;

    # §3.7.3 — eGFR 20–45 + ACR < 200 (2B — suggested)
    return 'suggested' if $egfr >= 20 && $egfr <= 45 && $acr < 200;

    return 'no';
}

# -------------------------------------------------------
# mra_indicated
# Source corpus: §3.8 — KDIGO 2024 CKD Guideline
#   Recommendation 3.8.1 (2A) — Nonsteroidal MRA
# -------------------------------------------------------
# Signature: mra_indicated($egfr, $acr, $has_diabetes, $k_meq) → "yes"|"no"
# Called by: rules/treatment/R03-mra-indication.yml (ACTION)
#
# §3.8.1: T2D + eGFR > 25 + normal K+ (<5.0) + ACR > 30 (despite RASi) → yes
# Note: "despite maximum tolerated dose of RASi" is modeled as a prerequisite
#       for indicating MRA, but enforcement of prior RASi use is deferred to
#       clinical context (not available in standard project JSON).
# Normal K+ threshold: < 5.0 mEq/L (undefined K → treat as normal)
sub mra_indicated {
    my ($egfr, $acr, $has_diabetes, $k_meq) = @_;
    $has_diabetes //= 0;
    $acr          //= 0;

    # Must have T2D (§3.8.1 scope)
    return 'no' unless $has_diabetes;

    # eGFR must be > 25 (§3.8.1 threshold)
    return 'no' unless defined $egfr && $egfr > 25;

    # ACR must be > 30 mg/g (§3.8.1 — albuminuria > 30 mg/g = > 3 mg/mmol)
    return 'no' unless $acr > 30;

    # Potassium must be normal (< 5.0 mEq/L); if undef → treat as normal (PP 3.8.3)
    if (defined $k_meq && $k_meq >= 5.0) {
        return 'no';   # hyperkalemia — nonsteroidal MRA contraindicated
    }

    return 'yes';
}

# -------------------------------------------------------
# statin_indicated
# Source corpus: §3.15.1 — KDIGO 2024 CKD Guideline
#   Recommendations 3.15.1.1 (1A), 3.15.1.2 (1B), 3.15.1.3 (2A)
#   Lipid management — statin therapy
# -------------------------------------------------------
# Signature: statin_indicated($age, $g, $has_diabetes, $has_cvd, $risk_10y_pct) → "yes"|"no"
# Called by: rules/treatment/R04-statin-indication.yml (ACTION)
#
# §3.15.1.1 (1A): ≥ 50y + eGFR < 60 (G3a–G5) → yes
# §3.15.1.2 (1B): ≥ 50y + eGFR ≥ 60 (G1–G2)  → yes
# §3.15.1.3 (2A): 18–49y + (coronary disease OR T2D OR prior stroke OR 10yr risk >10%) → yes
# Age undef → conservative: apply §3.15.1.1/3.15.1.2 rules (assume adult)
sub statin_indicated {
    my ($age, $g, $has_diabetes, $has_cvd, $risk_10y) = @_;
    $has_diabetes //= 0;
    $has_cvd      //= 0;

    # Age unknown → apply adult rules conservatively
    if (!defined $age || $age >= 50) {
        # §3.15.1.1 — G3a–G5 (eGFR < 60)
        return 'yes' if $g =~ /^G(3|4|5)/;
        # §3.15.1.2 — G1–G2 (eGFR ≥ 60)
        return 'yes' if $g eq 'G1' || $g eq 'G2';
    }

    # Age 18–49: at least one of the listed conditions (§3.15.1.3)
    if (defined $age && $age >= 18 && $age < 50) {
        return 'yes' if $has_cvd;       # known coronary disease or prior stroke
        return 'yes' if $has_diabetes;  # T2D
        if (defined $risk_10y && $risk_10y > 10) {
            return 'yes';               # 10-year coronary event risk > 10%
        }
    }

    return 'no';
}

1;
