# ORIGINAL: sandboxes/test-kb-multiSource/corpus/002-arf-toolbox.md

## Scope
<!-- CHORUS:no_auto_rules — scope definition, context only -->
This framework provides technical parameters referenced by CIR-1.0.
It is not independently binding — normative force derives from CIR-1.0 Art.6.

## §3.1 — Performance class definitions
<!-- CHORUS:no_auto_rules — definitions only, thesaurus seed -->
P1: high-load industrial use (≥500 N).
P2: standard commercial use (≥300 N).
P3: light domestic use (≥150 N).

## §3.2 — Approved algorithm list

| Algorithm | Min key length (bits) | Status    |
|-----------|----------------------|-----------|
| AES       | 128                  | approved  |
| RSA       | 2048                 | approved  |
| ECC       | 256                  | approved  |
| DES       | 56                   | deprecated |
| 3DES      | 112                  | deprecated |

A widget firmware using a deprecated algorithm shall be marked non-compliant.
A widget firmware using an approved algorithm with insufficient key length
shall be marked non-compliant.

## §4.1 — Implementation guidance
Implementations should select algorithms appropriate to the security
context and threat model, considering lifecycle and operational constraints.
The choice of algorithm family should reflect the intended deployment environment.

## Annex B (informative) — Revision history
<!-- CHORUS:no_auto_rules — informative annex -->
v2.1 (2025-03): added ECC-256 to approved list, deprecated 3DES.
v2.0 (2024-06): initial release.
