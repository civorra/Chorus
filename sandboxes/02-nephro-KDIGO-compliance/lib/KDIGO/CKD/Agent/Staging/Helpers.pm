package KDIGO::CKD::Agent::Staging::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    egfr_to_g_category
    acr_to_a_category
);

# -------------------------------------------------------
# egfr_to_g_category
# Source corpus: §1.1.2 — KDIGO 2024 CKD Guideline
#   Recommendation 1.1.2.1 — Methods for staging of CKD
#   Table: GFR categories in CKD
# -------------------------------------------------------
# Signature: egfr_to_g_category($egfr_ml_min) → $category_str
# Called by: rules/staging/R01-assign-g-category.yml (ACTION)
#
# GFR category thresholds (ml/min per 1.73 m²):
#   G1  : >= 90      (normal or high)
#   G2  : 60 – 89    (mildly decreased)
#   G3a : 45 – 59    (mildly to moderately decreased)
#   G3b : 30 – 44    (moderately to severely decreased)
#   G4  : 15 – 29    (severely decreased)
#   G5  : < 15       (kidney failure)
sub egfr_to_g_category {
    my ($egfr) = @_;
    return 'G1'  if $egfr >= 90;
    return 'G2'  if $egfr >= 60;
    return 'G3a' if $egfr >= 45;
    return 'G3b' if $egfr >= 30;
    return 'G4'  if $egfr >= 15;
    return 'G5';
}

# -------------------------------------------------------
# acr_to_a_category
# Source corpus: §1.3 — KDIGO 2024 CKD Guideline
#   Evaluation of albuminuria — Albuminuria categories
# -------------------------------------------------------
# Signature: acr_to_a_category($acr_mg_g) → $category_str
# Called by: rules/staging/R02-assign-a-category.yml (ACTION)
#
# Albuminuria category thresholds (urine ACR in mg/g):
#   A1 : < 30      (normal to mildly increased)
#   A2 : 30 – 299  (moderately increased)
#   A3 : >= 300    (severely increased)
sub acr_to_a_category {
    my ($acr) = @_;
    return 'A1' if $acr < 30;
    return 'A2' if $acr < 300;
    return 'A3';
}

1;
