quand plusieurs corpus utilisent la même terminologie, reste-t-il prudent des les séparer dans des sandboxes distincts ?

Thought 11s

Bonne question d'architecture — et la réponse est **non, séparer est contre-productif quand la terminologie est partagée**. Voici pourquoi.

---

### Le sandbox comme unité de vocabulaire

La KB d'un sandbox repose sur deux structures centrales :

- **Aliases table** — mappage terminologie projet → slots canoniques
- **Frame Catalogue** — définition des slots et leurs types

Si deux corpus partagent la même terminologie, c'est que leurs concepts pointent vers les mêmes slots. Les dupliquer dans deux sandboxes distincts signifie **maintenir deux Aliases tables en synchronisation** — c'est la source classique de divergence silencieuse (une correction faite dans un sandbox, oubliée dans l'autre).

---

### Ce que 11-cyber-sec illustre bien

Le corpus 001 (412-1) définit les identifiants de sujet. Le corpus 002 (412-2) les utilise directement (`type_element`, `serial_number`, `has_given_name`…) pour définir des règles de profil NAT. Les slots sont **partagés, pas dupliqués** — c'est précisément pour ça que les deux corpus cohabitent dans le même sandbox et que l'agent 2 peut cibler des frames créées par l'agent 1.

Si 412-1 et 412-2 avaient été dans des sandboxes séparés, `CertProfileNat` n'aurait pas pu lire les frames de `CertProfileCommon` — les frames ne traversent pas les sandboxes.

---

### Quand séparer est justifié

| Critère                                   | Même sandbox           | Sandboxes distincts      |
|-------------------------------------------|------------------------|--------------------------|
| Terminologie partagée                     | ✅                     | ❌ (duplication + drift) |
| Pipeline chaîné (agent 1 → agent 2)       | ✅ obligatoire         | ❌ impossible            |
| Domaines métier sans intersection         | ❌ KB artificielle     | ✅                       |
| Corpus expérimental / prototypage isolé   | selon besoin           | ✅ pratique              |
| Volume de règles ingérable (> ~50 agents) | split par sous-domaine | ✅                       |

Le vrai signal pour séparer n'est pas **la taille des corpus** mais **l'absence de slots communs** entre les corpus candidats.

---

### Pour 11-cyber-sec

EN 319 412-1 à 412-4, EN 319 411, eIDAS, CAB Forum BRs — tous tournent autour du même vocabulaire (`type_element`, `serial_number`, `key_usage_bits`, `is_qualified`…). Rester dans **un seul sandbox** est la bonne décision. Les agents s'enchaînent, la KB s'enrichit de manière additive, et `chorus-check --all` valide l'ensemble cohérent.

La séparation aurait eu du sens si tu avais voulu traiter, disons, les normes NIST FIPS (crypto matérielle) en parallèle — domaine sans intersection avec les profils de certificats.
dans le sandbox 11-cyber-sec, le dossier 'normes' contient plusieurs sous-dossiers, chacun lié à une norme spécifique en cyber-secu - comment les traiter après ETSI ?

Thought 8s

Laisse-moi lire les README de chaque sous-dossier avant de te donner une stratégie.
Reading README.org (0-2000) ✅ 0s

Reading README.org (0-2000) ✅ 0s

Reading README.org (0-2000) ✅ 0s

Reading README.org (0-2000) ✅ 0s

Reading README.org (0-2000) ✅ 0s

Reading README.org (0-2000) ✅ 0s

Reading README.org (0-2000) ✅ 0s

Thought 13s

## Stratégie d'intégration après ETSI

### 1. La dépendance fondamentale : RFC 5280 en premier

Avant tout le reste, **RFC 5280 devrait être le prochain corpus** — pas parce que les README la listent en priorité 1, mais parce que c'est la fondation structurelle dont tout le monde dépend :

- ETSI EN 319 412 *étend* X.509 défini par RFC 5280
- CABForum BR *restreint* RFC 5280 pour TLS public
- eIDAS *réglemente* les usages de RFC 5280 pour la signature qualifiée
- ANSSI RGS *surcontraint* RFC 5280 côté français

Si RFC 5280 est intégré *après* les autres, ses slots (`basic_constraints`, `eku`, `san`, `aki`…) seront introduits tardivement et nécessiteront de revenir enrichir des règles déjà posées. Intégré *avant*, il fixe le vocabulaire X.509 de base sur lequel tout s'ancre.

```bash
chorus-feed 11-cyber-sec normes/ietf/rfc5280.txt --enrich
```

---

### 2. Graphe de dépendances entre les corpus

```
RFC 5280  ──────────────────────────────────────────────── fondation X.509
    │
    ├── eIDAS 910/2014 + 2024/1183 ─── cadre réglementaire QC (EU)
    │       │
    │       └── ETSI EN 319 412-x ──── profils certificats (déjà intégré)
    │               │
    │               └── ETSI EN 319 411-1/2 ── politiques NCP/QCP + OIDs
    │                       │
    │                       └── ETSI EN 319 401 ── exigences générales TSP
    │                       └── ETSI TS 119 312 ── algorithmes autorisés ETSI
    │
    ├── CABForum BR TLS/S-MIME ──────── profil TLS/S-MIME (intersecte RFC 5280)
    │
    ├── ANSSI RGS v2 + Guide crypto ─── surcontraintes françaises (≥ ETSI)
    │
    └── NIST FIPS + SP 800-xxx ──────── standards crypto US (orthogonal EU)
            │
            └── NIST SP 800-131A ────── calendrier dépréciations (intersecte ANSSI)

Common Criteria ─────────────────────── méthodologie évaluation (pas YAML-encodable)
```

---

### 3. Ordre recommandé et stratégie d'intégration

| Étape | Corpus                                            | Mode       | Nouveaux agents / règles attendus                                       |
|-------|---------------------------------------------------|------------|-------------------------------------------------------------------------|
| **A** | `normes/ietf/rfc5280.txt`                         | `--enrich` | Agent `CertStructure` : `basic_constraints`, `eku`, `san`, `aki`, `ski` |
| **B** | `eidas/eIDAS-1-reglement-UE-910-2014-FR.pdf`      | `--enrich` | Règles `is_qualified` + Annexes I/III/IV (profils QC)                   |
| **C** | `etsi-EN-319-411-1.pdf` + `etsi-EN-319-411-2.pdf` | `--enrich` | OIDs politique QC, niveaux LCP/NCP/NCP+                                 |
| **D** | `etsi-EN-319-412-3/4/5`                           | `--enrich` | Profils web, PSD2, QC avancés                                           |
| **E** | `cabforum-baseline-requirements-tls.pdf`          | `--enrich` | Agent `CertProfileTLS` : validité 398j, EKU serverAuth, SAN             |
| **F** | `anssi-RGS-v2-annexe-B1.pdf` + guide crypto       | `--enrich` | Surcontraintes FR (algos, tailles de clés, durées)                      |
| **G** | `nist-SP-800-131A.pdf` + `FIPS-186-5.pdf`         | `--enrich` | Table dépréciations algorithmes (intersecte F)                          |
| **H** | eIDAS 2.0 (`2024/1183`)                           | `--enrich` | EUDIW, PID, QEAA — nouveaux profils                                     |

---

### 4. Ce qu'il faut ne **pas** traiter tel quel

**Common Criteria (CC v3.1r5)** — les 3 PDFs présents sont la méthodologie d'évaluation, pas des règles de conformité produit. CC ne produit pas de clauses directement encodables en YAML Chorus (pas de seuils, pas de contraintes binaires sur des champs de certificats). À réserver à une revue manuelle si tu veux modéliser le niveau EAL requis comme un slot de configuration.

**RFC 3647, RFC 4210, RFC 5652, RFC 8555** — pertinentes pour l'architecture PKI (CPS, CMP, CMS, ACME) mais encodent des protocoles, pas des profils de certificats. À traiter seulement si le scope s'étend à la validation de CP/CPS ou de flux de gestion de certificats.

---

### 5. RFCs déjà en `.txt` → avantage

Les RFCs IETF sont au format texte natif — pas besoin de `chorus-pdf`. `chorus-feed` peut les consommer directement. Pour les PDFs ETSI/ANSSI/NIST/CABForum, passer par `chorus-pdf` d'abord.

Tu veux commencer par RFC 5280, ou d'abord finir le bloc ETSI (412-3/4/5 + 411) ?
le fait d'avoir commencé par ETSI pose-t-il un problème ?!

Thought 12s

**Non, aucun problème fonctionnel.** La raison tient à la conception même de Chorus.

---

### Pourquoi ça ne pose pas de problème

`chorus-feed --enrich` est **additif par design** — il ne réécrit pas les slots existants, il étend la KB. Quand RFC 5280 sera intégré, il arrivera en deux catégories :

**Slots déjà couverts par ETSI** → RFC 5280 ajoutera simplement des **aliases** dans la table existante. Par exemple `has_crl_dp` (nommé ainsi depuis ETSI 412) recevra les variants RFC 5280 (`crl_distribution_points`, `cRLDistributionPoints`…). Le slot canonique reste celui établi par le premier corpus — ici ETSI. C'est cosmétique, pas fonctionnel.

**Slots absents de ETSI** → RFC 5280 introduira de **nouveaux slots** inexistants aujourd'hui (`basic_constraints`, `eku`, `san`, `aki`, `version`…). Ces ajouts sont purement additifs, ils n'affectent pas les règles R01–R15 en place.

---

### La seule conséquence réelle

Les **noms canoniques des slots** suivent la terminologie ETSI plutôt que RFC 5280. Ce n'est pas un défaut — c'est un choix de nommage figé par le premier corpus. Dans un sandbox PKI/certificats, ETSI est un point de départ aussi légitime que RFC 5280.

Si à l'inverse tu avais commencé par RFC 5280, les slots auraient des noms plus "X.509 brut" et ETSI aurait ajouté ses variantes en aliases. Le résultat fonctionnel est **identique** — seul le nom canonique change.

---

### En résumé

```
Ordre ETSI → RFC 5280   ✅  slots nommés ETSI, aliases RFC ajoutés ensuite
Ordre RFC 5280 → ETSI   ✅  slots nommés RFC, aliases ETSI ajoutés ensuite
```

L'Aliases table est précisément là pour rendre l'ordre d'intégration des corpus **indifférent au résultat**. Tu peux continuer dans l'ordre que tu as commencé sans rien reprendre.
