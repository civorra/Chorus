# Application Domains

Chorus is not tied to any specific sector. What makes it applicable to a domain
is the nature of the problem to be solved — not the sector's technology.

---

## The pattern: when Chorus is relevant

A domain is *Chorus-compatible* when three conditions are met:

1. **The project is described by typed elements** — each object to be validated
   (construction element, software component, contractual clause, emission line,
   medical device…) has measurable attributes and a discriminating type.

2. **The standard defines thresholds, conditions and reference tables**
   — not interpretable prose, but explicit requirements: *"thermal resistance
   must be ≥ R_min(zone, class)"*, *"the DPA must contain the 9 mentions of
   Art. 28 §3"*, *"an ASIL-D component requires MC/DC coverage"*.

3. **The decision must be traceable and reproducible** — audit, certification,
   regulatory filing, litigation. Every result must be justifiable by a precise
   rule, replayable identically, and readable by a human auditor.

If these three conditions are met, the `chorus-feed` → `chorus-check` chain
can transform a normative corpus into a validation pipeline within a few weeks.

---

## Identified application domains

The following table presents domains for which the Chorus pattern has been
analysed. *Estimated onboarding* refers to the time required to build a first
operational pipeline from the raw corpus using ECA.

### 🏗️ Construction / Civil Engineering

| | |
|---|---|
| **Typical corpus** | Eurocodes (EC2/EC3/EC5), RE2020, DTU series 20/31/43 |
| **What is validated** | Sizing, thermal, acoustic, fire safety, accessibility |
| **Pattern** | Class levels × geographic zones → `Helpers.pm` tables |
| **Estimated onboarding** | 2–3 weeks (COB sandbox directly reusable) |
| **Use cases** | Verify a DCE before submission; automated RE2020 audit; validate plans before architect visa |

### 🔐 Cybersecurity / Qualification

| | |
|---|---|
| **Typical corpus** | ANSSI SecNumCloud v3.2, RGS v2, ETSI EN 319 412, NIS2 Annex II, DORA |
| **What is validated** | PKI requirements, security measures, continuity, logging |
| **Pattern** | Numbered requirements → one Frame per requirement, one agent per security domain |
| **Estimated onboarding** | 1–2 weeks (ETSI sandbox already initiated) |
| **Use cases** | Pre-qualification before ANSSI submission; NIS2 audit for OIV/OES |

### 🌿 Environment / CSRD

| | |
|---|---|
| **Typical corpus** | ESRS E1–E5, S1–S4, G1 (CSRD), GHG Protocol Scope 1/2/3, EU Taxonomy |
| **What is validated** | Mandatory data points, double materiality, emission factors, perimeter |
| **Pattern** | Mandatory vs. voluntary datapoints (phase-in 2025–2026) → `Helpers.pm` tables |
| **Estimated onboarding** | 2–3 weeks (ESRS corpus is public and well-structured) |
| **Use cases** | Verify that a CSRD report covers all required datapoints before statutory auditor filing |

> ⚡ **Regulatory urgency 2025–2026.** CSRD applies to ~50,000 European companies
> over the 2024–2028 period on a progressive schedule. This is the domain where
> demand for automated validation is most immediate.

### ⚖️ GDPR / Public Procurement

| | |
|---|---|
| **Typical corpus** | GDPR Art. 13/14/28/30/35, French Public Procurement Code, NIS2 |
| **What is validated** | Mandatory mentions in DPA (Art. 28 §3: 9 specific mentions), DPIA, contract clauses |
| **Pattern** | Finite list of requirements → one Frame per clause, one rule per mandatory mention |
| **Estimated onboarding** | 2–3 weeks (public corpus, universal, finite requirement list) |
| **Use cases** | Verify that a DPA is complete under Art. 28 before signing; NIS2 supplier audit before contracting |

### 💊 Pharmaceutical / GMP

| | |
|---|---|
| **Typical corpus** | EU GMP Annex 1 (2022), ICH Q8/Q9/Q10/Q11, European Pharmacopoeia |
| **What is validated** | IQ/OQ/PQ qualification, process validation, analytical control, batch record |
| **Pattern** | Requirements by validation phase × risk level |
| **Estimated onboarding** | 3–4 weeks |
| **Use cases** | Verify that a qualification dossier covers all GMP requirements before MA filing; gap analysis before EMA/FDA inspection |

### 🏥 Medical Devices

| | |
|---|---|
| **Typical corpus** | MDR 2017/745, ISO 13485, IEC 62304, ISO 14971, MDCG guidelines |
| **What is validated** | Technical documentation by MDR annex, device class (I/IIa/IIb/III), software (SIL A/B/C) |
| **Pattern** | 15 MDR annexes → 15 agents; class level conditions requirements (same pattern as ASIL/DAL) |
| **Estimated onboarding** | 4–5 weeks |
| **Use cases** | Verify that a CE marking dossier for a medical device is complete before submission to the notified body |

### ✈️ Aerospace / Aviation

| | |
|---|---|
| **Typical corpus** | DO-178C, ARP4754A, DO-254, AMC 20-115 (EASA) |
| **What is validated** | Development objectives by DAL level (A/B/C/D), MC/DC coverage, tool qualification |
| **Pattern** | DO-178C objectives tables by DAL (Required / Recommended / Optional) → `Helpers.pm` identical to COB pattern |
| **Estimated onboarding** | 4–6 weeks |
| **Use cases** | Generate a DO-178C compliance matrix from project artefacts; identify gaps before DER review |

### 🚗 Automotive / Functional Safety

| | |
|---|---|
| **Typical corpus** | ISO 26262 parts 4/5/6, ASPICE v3.1, IATF 16949, MISRA C:2012 |
| **What is validated** | Objectives by ASIL (A/B/C/D), supplier process ASPICE, MISRA compliance |
| **Pattern** | ISO 26262 tables by ASIL (Required/Recommended/Optional) → same structure as DO-178C |
| **Estimated onboarding** | 4–5 weeks |
| **Use cases** | ASPICE audit of a Tier-1 supplier during OEM homologation |

### 🏦 Finance / RegTech

| | |
|---|---|
| **Typical corpus** | Basel IV (CRR3), DORA, MiFID II, EMIR, IFR/IFD |
| **What is validated** | Regulatory ratios (LCR ≥ 100%, NSFR ≥ 100%, TLAC ≥ 18%), DORA operational resilience |
| **Pattern** | Precise numerical thresholds → directly codable YAML rules |
| **Estimated onboarding** | 3–4 weeks |
| **Use cases** | Pre-regulatory check before COREP/FINREP reporting |

### ⚡ Energy / Nuclear

| | |
|---|---|
| **Typical corpus** | RCC-M, IEC 61511, ASN Safety Guide, IEC 62351 |
| **What is validated** | Equipment by safety level N1/N2/N3/N4, SIL 1/2/3/4, protection system integrity |
| **Pattern** | Nuclear safety levels → same logic as ASIL/DAL, already mastered |
| **Estimated onboarding** | 6–8 weeks (some corpora are difficult to access) |
| **Use cases** | Pre-check of qualification dossiers in nuclear plants; IEC 61511 audit for SEVESO facilities |

---

## How long for a new domain?

The key variable is the **quality and accessibility of the corpus** — not the
complexity of the domain. A well-structured normative corpus (numbered requirements,
explicit reference tables, defined hierarchy levels) can be onboarded in 2 to 4 weeks.
A dispersed, proprietary or very voluminous corpus may take 6 to 8 weeks.

The ECA chain compresses most of the cost:

```
raw corpus (PDF, text)
    │ chorus-pdf --auto        → intelligent extraction (text + figures)
    │ chorus-feed              → org KB + YAML rules + Helpers.pm
    │ chorus-check             → Feed.pm + Agent/*.pm + Expert.pm + run.pl
    ▼
perl run.pl project.json      → compliance report
```

Once the pipeline is generated, **ECA is no longer involved at runtime**. The pipeline
runs in pure Perl, deterministically, on any machine. ECA is only needed again
when the normative corpus changes — to re-run `chorus-feed --enrich` and `chorus-check`.

When the standard is revised:

```
chorus-feed my-sandbox new-corpus.txt --enrich
chorus-check my-sandbox project.json
```

The KB is updated incrementally. The infrastructure is regenerated.

---

## Where to start?

**Explore an existing pipeline:**
The sandboxes `examples/sandboxes/cob-compliance_fr` and `cob-compliance_en`
contain the complete chain — corpus, org KB, YAML rules, Perl infrastructure.
Run `perl run.pl project-demo.json` to see the report live.

**Understand the ECA chain:**
See the section *"Coupling with an LLM tool — the ECA architecture"* in
[`01-intro.md`](01-intro.md).

**Start on a new domain:**
Begin with `chorus-pdf` on the corpus, then `chorus-feed` to extract knowledge.
The org KB produced (`eca/agents/*.org`) is the checkpoint where a domain expert
validates what ECA has understood before generating the code.
