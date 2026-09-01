# Normes concernant la certification d'une entreprise

**Corpus :** `test-corpus-05-cyber-sec/normes/`
**Date :** 2026-06-23

---

## 1. Certification *de* l'entreprise en tant que prestataire de confiance (TSP/PSCE)

Ces normes définissent les exigences pour qu'une entreprise soit **qualifiée / certifiée**
comme autorité de certification ou prestataire de services de confiance.

| Norme | Fichier | Ce qu'elle couvre |
|---|---|---|
| **ETSI EN 319 401** | `etsi/etsi-EN-319-401.pdf` | Politique générale pour tous les TSPs — exigences organisationnelles, audit, gouvernance |
| **ETSI EN 319 411-1** | `etsi/etsi-EN-319-411-1.pdf` | Exigences de politique pour TSPs émettant des certificats publics (niveaux LCP/NCP/NCP+) |
| **ETSI EN 319 411-2** | `etsi/etsi-EN-319-411-2.pdf` | Exigences pour TSPs émettant des **certificats qualifiés eIDAS** |
| **eIDAS 1 — Chap. III** | `eidas/eIDAS-1-reglement-UE-910-2014-FR.pdf` | Art. 24-34 : conditions de qualification d'un prestataire de services de confiance qualifié |
| **ANSSI Référentiel PSCE** | `anssi/anssi-referentiel-psce.pdf` | Référentiel français pour la qualification des Prestataires de Services de Certification Électronique |
| **Common Criteria (EAL4+)** | `common-criteria/cc-v3.1r5-part*.pdf` | Certification des produits de l'entreprise (logiciel/HSM) — EAL4 typique pour un CMS |

### Détail par norme

#### ETSI EN 319 401 — General Policy Requirements for TSPs

- Socle commun à tous les prestataires de confiance
- Couvre : gouvernance, gestion des risques, sécurité physique, audit, continuité d'activité
- Niveau de priorité : 🔴 haute
- Version disponible : 03.02.01 (55 pages)

#### ETSI EN 319 411-1 — Policy requirements for TSPs (certificats publics)

- Définit les trois niveaux de politique : **LCP** (Lightweight), **NCP** (Normalized), **NCP+** (avec SSCD)
- Correspond aux niveaux de qualification ANSSI : NivEtoile1 / NivEtoile2 / NivEtoile3
- Version disponible : 01.05.01 (60 pages)

#### ETSI EN 319 411-2 — Policy requirements (certificats qualifiés eIDAS)

- Niveaux **QCP-n** (qualified for natural persons) et **QCP-l** (qualified for legal persons)
- Exigences renforcées : vérification d'identité face-à-face, QSCD obligatoire pour QCP+
- Version disponible : 02.06.01 (33 pages)

#### eIDAS 1 — Règlement (UE) 910/2014, Chapitre III (Art. 24-34)

- **Art. 24** : Vérification de l'identité du demandeur (personne physique ou morale)
- **Art. 28** : Exigences des certificats qualifiés pour signature électronique
- **Art. 30** : Exigences des dispositifs de création de signature qualifiée (QSCD)
- **Art. 38** : Supervision des prestataires qualifiés par les autorités nationales

#### ANSSI Référentiel PSCE (v1.3)

- Référentiel national français pour la qualification des PSCEs
- Aligné sur ETSI EN 319 411-1/2 avec contraintes supplémentaires RGS
- Applicable dans le cadre des marchés publics et systèmes d'information de l'État

#### Common Criteria v3.1 Rev5 (ISO/IEC 15408)

- Certification des **produits** de l'entreprise (CMS, HSM, applications)
- Niveau typique pour un CMS ou une carte à puce : **EAL4+** (AVA_VAN.5)
- Classes pertinentes : FCS (crypto), FIA (auth), FMT (gestion sécu), FTP (canal de confiance)
- 3 parties disponibles : Part 1 (Introduction), Part 2 (Fonctionnel), Part 3 (Assurance)

---

## 2. Certificats émis *pour* une entreprise (personne morale)

Ces normes définissent le **profil des certificats** délivrés à une entreprise
(cachet électronique, certificat d'authentification d'organisation).

| Norme | Fichier | Ce qu'elle couvre |
|---|---|---|
| **ETSI EN 319 412-3** | `etsi/etsi-EN-319-412-3.pdf` | Profil de certificat pour **personnes morales** (Legal Persons) |
| **ETSI EN 319 412-5** | `etsi/etsi-EN-319-412-5.pdf` | QC Statements — notamment `QcType: eseal` pour cachet d'entreprise |
| **eIDAS 1 — Annexe III** | `eidas/eIDAS-1-reglement-UE-910-2014-FR.pdf` | Exigences pour les certificats qualifiés pour **cachet électronique** (entreprises) |
| **CABForum EV Guidelines** | *(non téléchargé)* | Validation identité entreprise dans les certificats TLS Extended Validation |
| **ANSSI RGS v2.0** | `anssi/anssi-RGS-v2-annexe-B1-algorithmes.pdf` | Contraintes FR applicables aux certificats émis pour des entreprises dans le cadre du RGS |

### Détail par norme

#### ETSI EN 319 412-3 — Certificate Profiles for Legal Persons

- Profil spécifique pour les **personnes morales** (entreprises, organisations)
- Champs obligatoires : `organizationName`, `organizationIdentifier` (numéro SIREN/LEI/EORI...)
- Contraintes sur `subject`, `keyUsage`, extensions spécifiques
- Version disponible : 01.03.01 (10 pages)

#### ETSI EN 319 412-5 — QC Statements

Extensions spécifiques eIDAS dans le certificat d'entreprise :

| OID | Signification |
|---|---|
| `id-etsi-qcs-QcCompliance` | Certificat qualifié conforme eIDAS |
| `id-etsi-qcs-QcSSCD` | Clé dans dispositif sécurisé (QSCD) |
| `id-etsi-qcs-QcType: eseal` | Cachet électronique (personne morale) |
| `id-etsi-qcs-QcPDS` | URL du Policy Disclosure Statement |

#### eIDAS 1 — Annexe III (Certificats qualifiés pour cachet électronique)

Contenu obligatoire du certificat qualifié pour cachet (personne morale) :

1. Indication qu'il s'agit d'un certificat qualifié pour cachet (QC Statement OID)
2. Données représentant sans ambiguïté le prestataire de confiance
3. Nom de la personne morale et État membre d'établissement
4. Données de validation du cachet correspondant aux données de création
5. Début et fin de la période de validité
6. Code d'identité unique du certificat (serialNumber)
7. Signature électronique avancée du prestataire émetteur
8. Localisation du service de validation disponible gratuitement
9. Localisation des services de révocation

#### ANSSI RGS v2.0 — Contraintes françaises sur les certificats d'entreprise

Durées de validité applicables :

| Type de certificat           | Durée maximale |
|---|---|
| Certificat personne physique | 3 ans |
| Certificat serveur           | 2 ans |
| Certificat AC racine         | 20 ans |
| Certificat AC intermédiaire  | 10 ans |

Extensions obligatoires pour les certificats RGS :
- `keyUsage` : critique, valeurs selon profil
- `certificatePolicies` : OID RGS requis
- `cRLDistributionPoints` : obligatoire
- `authorityInformationAccess` (OCSP) : obligatoire

---

## Synthèse — Normes clés par besoin

| Besoin | Normes prioritaires |
|---|---|
| Qualifier une entreprise comme TSP | ETSI EN 319 401 + 411-1/2, eIDAS Art. 24-34, ANSSI PSCE |
| Émettre un cachet pour une entreprise | ETSI EN 319 412-3 + 412-5, eIDAS Annexe III |
| Certifier un produit (CMS/HSM) | Common Criteria EAL4+, NIST FIPS 140-3 |
| Contraintes cryptographiques FR | ANSSI RGS v2.0 Annexe B1, ETSI TS 119 312 |
| Certificat TLS avec identité d'entreprise (EV) | CABForum EV Guidelines *(non téléchargé)* |

---

## Note : normes importantes NON présentes dans le corpus

- **ISO/IEC 27001** : management de la sécurité de l'information — souvent requis par les audits de qualification TSP (payante)
- **CABForum EV Guidelines** : validation étendue de l'identité d'entreprise dans les certificats TLS (disponible gratuitement sur cabforum.org — non téléchargé)
- **eIDAS 2 — QEAA** : Qualified Electronic Attestation of Attributes — nouveau mécanisme pour les attributs d'entreprise (disponible dans `eidas/eIDAS-2-reglement-UE-2024-1183-FR.pdf`)
