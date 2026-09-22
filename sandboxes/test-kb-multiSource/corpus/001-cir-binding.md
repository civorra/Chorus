# ORIGINAL: sandboxes/test-kb-multiSource/corpus/001-cir-binding.md

## Foreword
<!-- CHORUS:no_auto_rules — informative foreword -->
This regulation establishes conformance requirements for certified widgets.

## Terms and definitions
<!-- CHORUS:no_auto_rules — definitions only, fed to thesaurus -->
**Certified widget** : a widget complying with this regulation.
**Performance class** : classification P1, P2, P3 per ARF §3.1.
**Load test** : mechanical test measuring maximum sustained load in Newtons.

## Article 5 — Load conformance
A widget of performance class P1 shall withstand a minimum load of 500 N.
A widget of performance class P2 shall withstand a minimum load of 300 N.
A widget of performance class P3 shall withstand a minimum load of 150 N.
Any widget failing this requirement shall be marked non-compliant.
See Annex D for the load-test methodology used to establish these thresholds.

## Article 6 — Cryptographic parameters
Cryptographic parameters used in widget firmware shall comply with the
approved algorithm list defined in ARF §3.2.
Key length shall meet the minimum values specified in ARF Table 3.2-1.
Use of deprecated algorithms constitutes a non-conformity.
See Annex C for empirical benchmark data underpinning these minimum
key-length values.

## Annex A (informative) — Bibliography
<!-- CHORUS:no_auto_rules — informative annex -->
ARF v2.1 — Architecture Reference Framework (2025-03).

## Annex C (informative) — Empirical key-strength benchmark data
Empirical cost estimates underpinning the minimum key-length values of ARF
Table 3.2-1, based on published cryptanalysis benchmarks. Referenced from
Article 6.

[MATRIX TABLE — extracted via pdftotext -layout]
Table C.1 — Estimated brute-force cost by key length
Algorithm   Key length (bits)   Estimated cost (USD)   Year
AES         112                 4.2e18                  2024
AES         128                 1.8e21                  2024
RSA         1024                broken (feasible)        2024
RSA         2048                not feasible (>2e30)     2024
[END MATRIX TABLE]

## Annex D (informative) — Load-test methodology
Load tests are performed using a calibrated hydraulic press, applying force
incrementally at 10 N/s until failure or the target threshold is reached,
per the internal test protocol referenced by this regulation. Referenced
from Article 5. This annex is narrative only — it documents the test
apparatus and procedure, not a quantitative reference table.
