# Domaines d'application

Chorus n'est pas lié à un secteur. Ce qui le rend applicable à un domaine,
c'est la nature du problème à résoudre — pas la technologie du secteur.

---

## Le pattern : quand Chorus est pertinent

Un domaine est *Chorus-compatible* dès lors que trois conditions sont réunies :

1. **Le projet est décrit par des éléments typés** — chaque objet à valider
   (élément de construction, composant logiciel, clause contractuelle, ligne
   d'émission, dispositif médical…) a des attributs mesurables et un type
   discriminant.

2. **La norme énonce des seuils, des conditions et des tableaux de référence**
   — pas de prose interprétable à géométrie variable, mais des exigences
   explicites : *"la résistance thermique doit être ≥ R_min(zone, classe)"*,
   *"le DPA doit contenir les 9 mentions de l'Art. 28 §3"*, *"le composant ASIL-D
   requiert MC/DC coverage"*.

3. **La décision doit être traçable et reproductible** — audit, certification,
   dépôt réglementaire, contentieux. Chaque résultat doit pouvoir être justifié
   par une règle précise, rejoué à l'identique, relu par un auditeur humain.

Si ces trois conditions sont réunies, la chaîne `chorus-feed` → `chorus-check`
peut transformer le corpus normatif en pipeline de validation en quelques semaines.

---

## Domaines d'application identifiés

Le tableau suivant présente les domaines pour lesquels le pattern Chorus a été
analysé. *L'onboarding estimé* désigne le temps nécessaire pour construire un
premier pipeline opérationnel depuis le corpus brut avec ECA.

### 🏗️ Construction / BTP

| | |
|---|---|
| **Corpus type** | Eurocodes (EC2/EC3/EC5), RE2020, DTU séries 20/31/43 |
| **Ce qu'on valide** | Dimensionnement, thermique, acoustique, incendie, accessibilité |
| **Pattern** | Niveaux de classe × zones géographiques → tables `Helpers.pm` |
| **Onboarding estimé** | 2–3 semaines (sandbox COB réutilisable directement) |
| **Cas d'usage** | Vérifier un DCE avant dépôt ; audit RE2020 automatique ; validation plans avant visa architecte |

### 🔐 Cybersécurité / Qualification

| | |
|---|---|
| **Corpus type** | ANSSI SecNumCloud v3.2, RGS v2, ETSI EN 319 412, NIS2 Annexe II, DORA |
| **Ce qu'on valide** | Exigences PKI, mesures de sécurité, continuité, journalisation |
| **Pattern** | Exigences numérotées → une Frame par exigence, un agent par domaine de sécurité |
| **Onboarding estimé** | 1–2 semaines (sandbox ETSI déjà amorcé) |
| **Cas d'usage** | Pré-qualification cloud avant soumission ANSSI ; audit NIS2 pour OIV/OES |

### 🌿 Environnement / CSRD

| | |
|---|---|
| **Corpus type** | ESRS E1–E5, S1–S4, G1 (CSRD), GHG Protocol Scope 1/2/3, Taxonomie EU |
| **Ce qu'on valide** | Points de données obligatoires, matérialité double, facteurs d'émission, périmètre |
| **Pattern** | Datapoints obligatoires vs. volontaires (phase-in 2025–2026) → tables `Helpers.pm` |
| **Onboarding estimé** | 2–3 semaines (corpus ESRS publics et très structurés) |
| **Cas d'usage** | Vérifier qu'un rapport CSRD couvre tous les datapoints requis avant dépôt commissaire aux comptes |

> ⚡ **Urgence réglementaire 2025–2026.** La CSRD s'applique à ~50 000 entreprises
> européennes sur la période 2024–2028 selon un calendrier progressif. C'est le
> domaine où la demande de validation automatisée est la plus immédiate.

### ⚖️ RGPD / Marchés publics

| | |
|---|---|
| **Corpus type** | RGPD Art. 13/14/28/30/35, Code de la Commande Publique, NIS2 |
| **Ce qu'on valide** | Mentions obligatoires DPA (Art. 28 §3 : 9 mentions précises), DPIA, clauses CCAP |
| **Pattern** | Liste finie d'exigences → une Frame par clause, une règle par mention obligatoire |
| **Onboarding estimé** | 2–3 semaines (corpus public, universel, liste d'exigences finie) |
| **Cas d'usage** | Vérifier qu'un DPA est complet Art. 28 avant signature ; audit NIS2 fournisseur avant contractualisation |

### 💊 Industrie pharmaceutique / BPF

| | |
|---|---|
| **Corpus type** | EU GMP Annexe 1 (2022), ICH Q8/Q9/Q10/Q11, Pharmacopée Européenne |
| **Ce qu'on valide** | Qualification IQ/OQ/PQ, validation procédés, contrôle analytique, dossier de lot |
| **Pattern** | Exigences par phase de validation × niveau de risque |
| **Onboarding estimé** | 3–4 semaines |
| **Cas d'usage** | Vérifier qu'un dossier de qualification couvre toutes les exigences GMP avant AMM ; gap analysis avant inspection EMA/FDA |

### 🏥 Dispositifs médicaux

| | |
|---|---|
| **Corpus type** | MDR 2017/745, ISO 13485, IEC 62304, ISO 14971, MDCG guidelines |
| **Ce qu'on valide** | Documentation technique par annexe MDR, classe DM (I/IIa/IIb/III), logiciel (SIL A/B/C) |
| **Pattern** | 15 annexes MDR → 15 agents ; niveau de classe conditionne les exigences (identique au pattern ASIL/DAL) |
| **Onboarding estimé** | 4–5 semaines |
| **Cas d'usage** | Vérifier qu'un dossier de marquage CE DM est complet avant soumission à l'organisme notifié |

### ✈️ Aérospatial / Aviation

| | |
|---|---|
| **Corpus type** | DO-178C, ARP4754A, DO-254, AMC 20-115 (EASA) |
| **Ce qu'on valide** | Objectifs de développement par niveau DAL (A/B/C/D), couverture MC/DC, qualification outil |
| **Pattern** | Tables d'objectifs DO-178C par DAL (Obligatoire / Recommandé / Optionnel) → `Helpers.pm` identique au pattern COB |
| **Onboarding estimé** | 4–6 semaines |
| **Cas d'usage** | Générer une compliance matrix DO-178C depuis les artefacts projet ; identifier les gaps avant revue DER |

### 🚗 Automobile / Sécurité fonctionnelle

| | |
|---|---|
| **Corpus type** | ISO 26262 parts 4/5/6, ASPICE v3.1, IATF 16949, MISRA C:2012 |
| **Ce qu'on valide** | Objectifs par ASIL (A/B/C/D), processus fournisseur ASPICE, conformité MISRA |
| **Pattern** | Tables ISO 26262 par ASIL (Obligatoire/Recommandé/Optionnel) → même structure que DO-178C |
| **Onboarding estimé** | 4–5 semaines |
| **Cas d'usage** | Audit ASPICE d'un fournisseur Tier-1 lors de l'homologation OEM |

### 🏦 Finance / RegTech

| | |
|---|---|
| **Corpus type** | Bâle IV (CRR3), DORA, MiFID II, EMIR, IFR/IFD |
| **Ce qu'on valide** | Ratios réglementaires (LCR ≥ 100%, NSFR ≥ 100%, TLAC ≥ 18%), résilience opérationnelle DORA |
| **Pattern** | Seuils numériques précis → règles YAML directement codables |
| **Onboarding estimé** | 3–4 semaines |
| **Cas d'usage** | Pré-contrôle réglementaire avant déclaration COREP/FINREP |

### ⚡ Énergie / Nucléaire

| | |
|---|---|
| **Corpus type** | RCC-M, IEC 61511, Guide de sûreté ASN, IEC 62351 |
| **Ce qu'on valide** | Équipements par niveau N1/N2/N3/N4, SIL 1/2/3/4, intégrité des systèmes de protection |
| **Pattern** | Niveaux de sûreté nucléaire → même logique que ASIL/DAL, déjà maîtrisée |
| **Onboarding estimé** | 6–8 semaines (certains corpus difficiles d'accès) |
| **Cas d'usage** | Pré-contrôle de dossiers de qualification en centrale ; audit IEC 61511 pour installations SEVESO |

---

## Combien de temps pour un nouveau domaine ?

La variable principale est la **qualité et l'accessibilité du corpus** — pas la
complexité du domaine. Un corpus normatif bien structuré (exigences numérotées,
tableaux de référence explicites, niveaux hiérarchiques définis) s'onboarde en
2 à 4 semaines. Un corpus dispersé, propriétaire ou très volumineux peut
demander 6 à 8 semaines.

La chaîne ECA comprime l'essentiel du coût :

```
corpus brut (PDF, texte)
    │ chorus-pdf --auto        → extraction intelligente (texte + figures)
    │ chorus-feed              → KB org + règles YAML + Helpers.pm
    │ chorus-check             → Feed.pm + Agent/*.pm + Expert.pm + run.pl
    ▼
perl run.pl projet.json       → rapport de conformité
```

Une fois le pipeline généré, **ECA n'intervient plus à l'exécution**. Le pipeline
tourne en Perl pur, de façon déterministe, sur n'importe quelle machine. ECA n'est
à nouveau nécessaire que si le corpus normatif évolue — pour relancer
`chorus-feed --enrich` puis `chorus-check`.

Quand la norme est révisée :

```
chorus-feed mon-sandbox nouveau-corpus.txt --enrich
chorus-check mon-sandbox projet.json
```

La KB est mise à jour de façon incrémentale. L'infrastructure est régénérée.

---

## Par où commencer ?

**Explorer un pipeline existant :**
Les sandboxes `examples/sandboxes/cob-compliance_fr` et `cob-compliance_en`
contiennent la chaîne complète — corpus, KB org, règles YAML, infrastructure
Perl. Lancer `perl run.pl project-demo.json` pour voir le rapport en direct.

**Comprendre la chaîne ECA :**
Voir la section *« Couplage avec un outil LLM — l'architecture ECA »* dans
[`01-intro.md`](01-intro.md).

**Démarrer sur un nouveau domaine :**
Commencer par `chorus-pdf` sur le corpus, puis `chorus-feed` pour extraire
la connaissance. La KB org produite (`eca/agents/*.org`) est le point de
contrôle où un expert du domaine valide ce qu'ECA a compris avant de générer
le code.
