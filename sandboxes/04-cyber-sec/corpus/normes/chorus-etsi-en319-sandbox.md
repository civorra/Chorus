# Chorus — Sandbox ETSI EN 319 : Utilité et Structure de Dossier

---

## Partie 1 — En quoi un sandbox Chorus pour ETSI EN 319 est utile pour un opérateur PKI

### 1. Le produit est soumis à ces normes — pas par choix, par obligation

Toute infrastructure PKI délivrant des certificats qualifiés eIDAS doit démontrer sa conformité à ETSI EN 319 pour obtenir et maintenir sa qualification. Cette conformité est auditée périodiquement par un organisme tiers accrédité.

Un sandbox Chorus sur ETSI EN 319 transforme cette obligation subie en **avantage opérationnel** : l'auditeur arrive, la conformité est déjà documentée, tracée, et reproductible.

---

### 2. Réduction du coût et du risque d'audit

Un audit de qualification TSP coûte entre 50 000€ et 150 000€ selon le périmètre. Le principal risque est la découverte tardive d'une non-conformité — après des mois de préparation.

Chorus détecte ces non-conformités **avant** la soumission du dossier. Chaque itération de correction est instantanée. Le dossier soumis à l'auditeur est pré-validé.

**ROI direct** : réduction du nombre de cycles d'audit correctif, donc du coût total de qualification.

---

### 3. Accélération des mises à jour réglementaires

eIDAS 2 est en cours de déploiement. Les normes ETSI associées sont en révision. Chaque mise à jour réglementaire impose une revue de conformité complète de la CP, de la CPS, et des procédures opérationnelles.

Avec Chorus, cette revue est **automatisée** : on met à jour le corpus dans le sandbox, on relance `chorus-check`, et le delta de non-conformités apparaît immédiatement — sans relire manuellement 200 pages de normes.

---

### 4. Service à valeur ajoutée pour les clients

Un opérateur PKI a des clients qui déploient ses produits dans leurs propres infrastructures — banques, administrations, industriels. Ces clients ont leurs propres obligations de conformité eIDAS / RGS.

Chorus devient un **outil de service** proposé aux clients : vérification que leur déploiement du CMS respecte les exigences du niveau LoA qu'ils visent. C'est un différenciateur commercial fort — aucun concurrent ne propose aujourd'hui cet outil.

---

### 5. Vérification des CP/CPS publiées

Un opérateur PKI publie et maintient des Politiques de Certification pour ses clients. Ces CP/CPS doivent être conformes RFC 3647 et cohérentes avec les niveaux eIDAS déclarés.

Chorus vérifie automatiquement :

- Complétude RFC 3647 (9 sections obligatoires)
- Cohérence entre niveau LoA déclaré et engagements opérationnels
- Délais de révocation conformes EN 319 411

**Verdict typique** : *"CP client — délai révocation déclaré 48h — non conforme EN 319 411-1 §6.3.4 (24h max)."*

---

### 6. Positionnement face à eIDAS 2

eIDAS 2 introduit de nouvelles exigences — portefeuille d'identité numérique (EUDIW), certificats d'attributs qualifiés, nouveaux niveaux de garantie. Toutes les qualifications existantes devront être mises à jour.

Un sandbox Chorus sur ETSI EN 319 positionne l'opérateur PKI comme **acteur proactif** de cette transition — capable de vérifier sa propre conformité à la nouvelle réglementation avant même que l'audit officiel soit programmé.

---

### Synthèse des bénéfices

| Bénéfice | Impact |
|---|---|
| Pré-audit automatisé avant qualification | Réduction coût et risque d'audit |
| Détection continue des non-conformités | Conformité maintenue en continu |
| Revue automatique des mises à jour ETSI/eIDAS | Réactivité réglementaire |
| Service client de vérification de déploiement | Différenciateur commercial |
| Vérification CP/CPS publiées | Qualité documentaire garantie |
| Préparation eIDAS 2 | Avance concurrentielle |

> **Argument central** : Chorus ne remplace pas l'auditeur — il arrive *avant* l'auditeur, avec un dossier déjà vérifié, traçable, et reproductible.

---

## Partie 2 — Contenu d'un dossier de conformité ETSI EN 319

### Principe général

ETSI EN 319 vérifie la conformité d'un **opérateur de service de confiance** (TSP), pas d'un produit. Le dossier soumis à Chorus représente l'état déclaré d'un TSP à un instant donné — ses engagements, ses procédures, sa configuration.

---

### 1. Documents de politique (obligatoires)

**Politique de Certification (CP)**
Document public décrivant les engagements du TSP envers ses abonnés et les tiers de confiance. Structure RFC 3647 obligatoire — 9 sections couvrant identification, enrôlement, cycle de vie des certificats, révocation, audit, responsabilités.

**Practice Statement (CPS)**
Document opérationnel décrivant comment le TSP implémente concrètement sa CP. Niveau de détail supérieur — procédures pas-à-pas, délais effectifs, ressources mobilisées.

**Ce que Chorus vérifie** : complétude des sections RFC 3647, cohérence CP↔CPS, conformité des délais déclarés aux seuils EN 319 411.

---

### 2. Caractéristiques du service déclaré

**Type de service**

- CA émettrice (EN 319 411-1 ou 411-2)
- Service d'horodatage TSA (EN 319 421)
- Service de validation (EN 319 102)
- Service de préservation (EN 319 162)

**Niveau de qualification visé**

- eIDAS : NCP, NCP+, QCP-n, QCP-l, QCP-w, QCP-n-qscd, QCP-l-qscd
- RGS : ★, ★★
- LoA eIDAS : low, substantial, high

**Ce que Chorus vérifie** : les exigences applicables sont conditionnelles au type de service et au niveau déclaré — un Frame Chorus charge le profil d'exigences correspondant.

---

### 3. Infrastructure technique déclarée

**HSM (Hardware Security Module)**

- Marque, modèle, version firmware
- Certification obtenue : CC EAL4+, FIPS 140-2 Level 3, FIPS 140-3
- Périmètre d'utilisation (génération de clés CA, signature, horodatage)

**Algorithmes cryptographiques**

- Algorithmes de signature (RSA, ECDSA, EdDSA)
- Longueurs de clés
- Algorithmes de hachage
- Date de fin de validité prévue selon recommandations SOG-IS / ANSSI / ETSI TS 119 312

**Profil des certificats émis**

- Extensions X.509 présentes (AIA, CDP, OCSP, QcStatements…)
- Valeur maximale de durée de validité
- Politique de certificat (OID)

**Ce que Chorus vérifie** : HSM certifié au niveau requis, algorithmes conformes ETSI TS 119 312, extensions obligatoires présentes, durées de validité dans les bornes EN 319 411.

---

### 4. Procédures opérationnelles déclarées

**Enrôlement et vérification d'identité**

- Mode de vérification : présentiel, à distance, eIDAS-based
- Documents acceptés pour la vérification d'identité
- Délai maximum entre vérification et émission

**Révocation**

- Délai de traitement d'une demande de révocation (EN 319 411 impose ≤ 24h pour compromission)
- Disponibilité du service de révocation (CRL, OCSP)
- Fréquence de publication des CRL

**Renouvellement et re-clé**

- Politique de renouvellement avant expiration
- Procédure de re-clé d'urgence

**Cérémonie de génération de clés CA**

- Présence de témoins
- Enregistrement vidéo
- Split knowledge / dual control documenté

**Ce que Chorus vérifie** : délais déclarés vs seuils EN 319 411, disponibilité OCSP conforme, cérémonie documentée selon exigences QCP.

---

### 5. Organisation et personnel

**Rôles de confiance définis**

- Security Officer, CA Administrator, Registration Authority Officer, Auditor interne
- Séparation des rôles (pas de cumul interdit)
- Habilitations et vérifications d'antécédents

**Formation**

- Plan de formation documenté
- Fréquence des formations sécurité

**Ce que Chorus vérifie** : rôles obligatoires présents, séparation des rôles conforme, plan de formation documenté.

---

### 6. Sécurité physique et environnementale

**Datacenter**

- Niveau de contrôle d'accès physique (badges, biométrie, journaux)
- Zones de sécurité définies (zone CA racine, zone CA émettrice)
- Alimentation redondante, climatisation

**Ce que Chorus vérifie** : présence des zones de sécurité requises selon le niveau QCP, contrôles d'accès documentés.

---

### 7. Continuité et audit

**Plan de continuité d'activité**

- RTO/RPO déclarés
- Procédure de bascule documentée
- Tests de continuité (fréquence)

**Audit interne**

- Fréquence des audits internes
- Périmètre couvert
- Traitement des écarts

**Ce que Chorus vérifie** : fréquence d'audit conforme EN 319 401, RTO/RPO documentés, tests de continuité effectués.

---

### Structure type d'un dossier Chorus

```
dossier_tsp/
├── meta.yaml              ← type de service, niveau visé, périmètre
├── cp.pdf / cp.yaml       ← Politique de Certification
├── cps.pdf / cps.yaml     ← Practice Statement
├── infrastructure.yaml    ← HSM, algorithmes, profil certificats
├── procedures.yaml        ← enrôlement, révocation, renouvellement
├── organisation.yaml      ← rôles, personnel, formation
├── physique.yaml          ← datacenter, zones de sécurité
└── continuite.yaml        ← BCP, audit interne
```

> **Point clé pour Chorus** : les fichiers YAML sont ingérés directement par `chorus-feed`. Les PDF (CP, CPS) passent d'abord par `chorus-pdf` pour extraction structurée, puis par `chorus-feed`. Le fichier `meta.yaml` est le point d'entrée — il conditionne le chargement du profil d'exigences applicable (NCP, QCP-l, QCP-n-qscd…).

---

*Document généré dans le cadre du projet Chorus — sandbox cybersécurité ETSI EN 319.*
