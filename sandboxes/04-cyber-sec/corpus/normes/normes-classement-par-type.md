# Classement des normes par type de certification

## 🏛️ 1. Certification d'une **organisation**

*Ces normes définissent les exigences pour qu'une organisation soit qualifiée/accréditée
comme Autorité de Certification ou Prestataire de Services de Confiance (TSP).*

| Norme | Fichier | Rôle |
|---|---|---|
| **ETSI EN 319 401** | `etsi/etsi-EN-319-401.pdf` | Socle commun tous TSPs — gouvernance, audit, sécurité physique |
| **ETSI EN 319 411-1** | `etsi/etsi-EN-319-411-1.pdf` | Politique pour TSPs émettant des certificats publics (LCP/NCP/NCP+) |
| **ETSI EN 319 411-2** | `etsi/etsi-EN-319-411-2.pdf` | Politique pour TSPs émettant des **certificats qualifiés eIDAS** (QCP-n/l) |
| **eIDAS 1 — Art. 24-34, 38** | `eidas/eIDAS-1-reglement-UE-910-2014-FR.pdf` | Conditions légales de qualification d'un TSP, supervision nationale |
| **eIDAS 2** | `eidas/eIDAS-2-reglement-UE-2024-1183-FR.pdf` | Mise à jour eIDAS : nouveaux services de confiance qualifiés (QEAA, wallet…) |
| **ANSSI Référentiel PSCE v1.3** | `anssi/anssi-referentiel-psce.pdf` | Qualification française des PSCEs — aligné RGS + ETSI 411 |
| **RFC 3647** | `ietf/rfc3647.txt` | Framework CP/CPS — cadre pour la politique de certification d'une CA |

---

## 🖥️ 2. Certification d'un **produit**

*Ces normes définissent les exigences pour certifier un produit logiciel ou matériel (cryptographique).*

| Norme | Fichier | Rôle |
|---|---|---|
| **Common Criteria v3.1r5 — Part 1** | `common-criteria/cc-v3.1r5-part1-introduction.pdf` | Introduction, concepts, cadre d'évaluation |
| **Common Criteria v3.1r5 — Part 2** | `common-criteria/cc-v3.1r5-part2-functional.pdf` | Composants fonctionnels de sécurité (FCS, FIA, FMT, FTP…) |
| **Common Criteria v3.1r5 — Part 3** | `common-criteria/cc-v3.1r5-part3-assurance.pdf` | Niveaux d'assurance EAL1→EAL7 — EAL4+ typique pour un CMS/carte à puce |
| **NIST FIPS 140-3** | `nist/nist-FIPS-140-3.pdf` | Certification des **modules cryptographiques** (HSM, logiciels crypto) |
| **NIST FIPS 197 (AES)** | `nist/nist-FIPS-197-AES.pdf` | Standard AES — référence pour conformité des implémentations |
| **NIST FIPS 186-5 (DSS)** | `nist/nist-FIPS-186-5.pdf` | Standard de signature numérique (ECDSA, EdDSA) |
| **NIST SP 800-57 Part 1** | `nist/nist-SP-800-57-part1.pdf` | Gestion du cycle de vie des clés — recommandations générales |
| **NIST SP 800-57 Part 2** | `nist/nist-SP-800-57-part2.pdf` | Gestion des clés — bonnes pratiques organisations |
| **NIST SP 800-57 Part 3** | `nist/nist-SP-800-57-part3.pdf` | Gestion des clés — guidance applicative |
| **NIST SP 800-131A Rev2** | `nist/nist-SP-800-131A-rev2.pdf` | Transition algorithmes — quand un produit doit mettre à jour ses primitives |

---

## 📄 3. Certification de **données issues de traitements**

*(certificats, profils de certificats, CRL, réponses OCSP, artefacts PKI)*

*Ces normes définissent le format, le contenu et les contraintes des données produites par
une PKI — certificats numériques, listes de révocation, réponses de statut, messages
cryptographiques, etc.*

### 3a. Profils de certificats (structure et contenu)

| Norme | Fichier | Rôle |
|---|---|---|
| **RFC 5280** | `ietf/rfc5280.txt` | Profil X.509 v3 — structure de base, extensions standard (keyUsage, SAN, validity…) |
| **ETSI EN 319 412-1** | `etsi/etsi-EN-319-412-1.pdf` | Profil général et politiques de certification (toutes catégories, §§ communs) |
| **ETSI EN 319 412-2** | `etsi/etsi-EN-319-412-2.pdf` | Profil certificats **personnes physiques** (NCP/QNCP) |
| **ETSI EN 319 412-3** | `etsi/etsi-EN-319-412-3.pdf` | Profil certificats **personnes morales** (Legal Persons) |
| **ETSI EN 319 412-4** | `etsi/etsi-EN-319-412-4.pdf` | Profil certificats **site web** (NCP-w/QNCP-w) |
| **ETSI EN 319 412-5** | `etsi/etsi-EN-319-412-5.pdf` | **QC Statements** — extensions eIDAS dans les certificats qualifiés |
| **eIDAS 1 — Annexes I, II, III** | `eidas/eIDAS-1-reglement-UE-910-2014-FR.pdf` | Exigences légales certificats qualifiés (signature, authentification, cachet) |
| **CABForum TLS BR v2.2.8** | `cabforum/cabforum-baseline-requirements-tls.pdf` | Profils certificats TLS émis par les CA membres du CABForum |
| **CABForum S/MIME BR v1.0.14** | `cabforum/cabforum-baseline-requirements-smime.pdf` | Profils certificats S/MIME |
| **CABForum Code Signing BR v3.11.0** | `cabforum/cabforum-baseline-requirements-codesigning.pdf` | Profils certificats de signature de code |
| **ETSI TS 119 312** | `etsi/etsi-TS-119-312.pdf` | Contraintes cryptographiques applicables aux artefacts PKI/TSP |
| **ANSSI RGS v2.0 — Annexe B1** | `anssi/anssi-RGS-v2-annexe-B1-algorithmes.pdf` | Contraintes FR sur algorithmes, tailles de clés, durées de validité dans les certificats |

#### Détails ETSI EN 319 412-5 — QC Statements

Extensions spécifiques eIDAS dans les certificats qualifiés :

| OID | Signification |
|---|---|
| `id-etsi-qcs-QcCompliance` | Certificat qualifié conforme eIDAS |
| `id-etsi-qcs-QcSSCD` | Clé dans dispositif sécurisé (QSCD) |
| `id-etsi-qcs-QcType: esign` | Signature électronique (personne physique) |
| `id-etsi-qcs-QcType: eseal` | Cachet électronique (personne morale) |
| `id-etsi-qcs-QcType: web` | Certificat d'authentification de site web |
| `id-etsi-qcs-QcPDS` | URL du Policy Disclosure Statement |

#### Détails eIDAS 1 — Annexe III (certificats qualifiés pour cachet électronique)

Contenu obligatoire du certificat qualifié pour cachet (personne morale) :

1. Indication qu'il s'agit d'un certificat qualifié pour cachet (QC Statement OID)
2. Données représentant sans ambiguïté le prestataire de confiance
3. Nom de la personne morale et État membre d'établissement
4. Données de validation du cachet correspondant aux données de création
5. Début et fin de la période de validité
6. Code d'identité unique du certificat (`serialNumber`)
7. Signature électronique avancée du prestataire émetteur
8. Localisation du service de validation disponible gratuitement
9. Localisation des services de révocation

#### Détails ANSSI RGS v2.0 — Durées de validité applicables aux certificats

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

### 3b. Protocoles de gestion et d'échange des certificats

| Norme | Fichier | Rôle |
|---|---|---|
| **RFC 2986 (PKCS#10)** | `ietf/rfc2986.txt` | Format des **demandes de certificat** (CSR) |
| **RFC 4210 (CMP)** | `ietf/rfc4210.txt` | Protocole de **gestion des certificats** (demande, renouvellement, révocation) |
| **RFC 4211 (CRMF)** | `ietf/rfc4211.txt` | Format des messages de demande de gestion de certificats |
| **RFC 6960 (OCSP)** | `ietf/rfc6960.txt` | Format des **réponses de statut** de certificat (révocation en ligne) |
| **RFC 5652 (CMS)** | `ietf/rfc5652.txt` | Format des **messages cryptographiques** (SignedData, EnvelopedData…) |
| **RFC 7292 (PKCS#12)** | `ietf/rfc7292.txt` | Format d'archive **certificat + clé privée** |
| **RFC 7468** | `ietf/rfc7468.txt` | Encodage PEM (`.pem`, `.crt`, `.key`) |
| **RFC 5958** | `ietf/rfc5958.txt` | Format de **stockage des clés privées** (OneAsymmetricKey) |
| **RFC 8555 (ACME)** | `ietf/rfc8555.txt` | Automatisation de la **délivrance de certificats** (Let's Encrypt) |

---

## 🔀 4. **Autres types de certifications** (protocoles, recommandations transverses)

*Normes qui encadrent la sécurité au niveau protocole ou sous forme de recommandations
générales — pas directement une certification d'entité, de produit ou d'artefact PKI.*

| Norme | Fichier | Rôle |
|---|---|---|
| **RFC 8446 (TLS 1.3)** | `ietf/rfc8446.txt` | Protocole TLS — authentification mutuelle au niveau transport |
| **RFC 8410 (Ed25519/X25519)** | `ietf/rfc8410.txt` | Algorithmes de courbes elliptiques modernes (EdDSA, ECDH) |
| **NIST SP 800-52 Rev2** | `nist/nist-SP-800-52-rev2.pdf` | Recommandations TLS pour les systèmes fédéraux |
| **NIST SP 800-63B** | `nist/nist-SP-800-63B.pdf` | Authentification et gestion du cycle de vie des identités numériques |
| **ANSSI Guide mécanismes cryptographiques v2.04** | `anssi/anssi-guide-mecanismes-cryptographiques.pdf` | Recommandations FR sur les primitives crypto (hors contraintes normatives strictes) |

---

## Synthèse — Comptage par catégorie

```
Catégorie 1 — Organisation (TSP/PSCE)              :  7 normes
Catégorie 2 — Produit (CMS/HSM)                    : 10 normes
Catégorie 3 — Données/Certificats (profils)        : 12 normes
Catégorie 3 — Données/Certificats (protocoles)     :  9 normes
                                             sous-total cat. 3 : 21 normes
Catégorie 4 — Autres (protocoles/recommandations)  :  5 normes
                                             ─────────────────
Total                                              : 43 normes*
```

> \* L'eIDAS 1 est comptée deux fois (catégories 1 et 3) car elle couvre à la fois
> la qualification TSP (Art. 24-34, 38) et les exigences des certificats qualifiés
> (Annexes I, II, III). Normes du corpus uniques : **42**.

---

## Notes sur les normes à double portée

Certaines normes couvrent plusieurs catégories :

| Norme | Catégories | Raison |
|---|---|---|
| **eIDAS 1** | 1 + 3 | Qualification TSP (Art. 24-34) **et** profils certificats qualifiés (Annexes I-III) |
| **eIDAS 2** | 1 + 3 | Nouveaux TSPs QEAA **et** nouveaux formats d'attestation d'attributs |
| **ETSI EN 319 401** | 1 + 3 | Exigences organisationnelles TSP **et** contraintes sur les artefacts émis |
| **ANSSI RGS v2.0** | 1 + 3 | Qualification PSCE française **et** contraintes sur les certificats émis |
| **ANSSI Référentiel PSCE** | 1 + 2 | Qualification organisationnelle **et** exigences produit (HSM qualifié requis) |


## Normes importantes NON présentes dans le corpus (pour mémoire)

| Norme | Catégorie | Raison de l'absence |
|---|---|---|
| **ISO/IEC 27001** | 1 | Payante — management sécurité de l'information, souvent requis pour audit TSP |
| **CABForum EV Guidelines** | 3 | Non téléchargé — validation étendue identité entreprise (TLS EV) — gratuit sur cabforum.org |
| **ISO/IEC 7816** | 2/3 | Payante — interface carte à puce |
| **ISO/IEC 15408** | 2 | Payante — texte de référence CC (le portail CC distribue les PP gratuitement) |
| **eIDAS 2 — QEAA** | 3 | Présent dans `eidas/eIDAS-2-...pdf` mais non encore intégré dans le pipeline Chorus |
