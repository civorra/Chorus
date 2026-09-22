# Bug report — `chorus-corpus-scoping` / `chorus-feed` : angle mort sur le contenu « Helper-source »

- **Branche concernée** : `feat/kb-coverage-optimization`
- **Skills concernés** : `agent/skills/chorus-corpus-scoping.md` (Phase 2),
  `agent/skills/chorus-feed.md` (Phase 6.5 — Coverage report)
- **Découvert le** : 2026-09-20
- **Découvert dans** : `sandboxes/cyber/03-cyber-sec-ANSSI-PG-083+RGS_v-2-0_B2-REBUILD`
  (sandbox de validation dédié à cette branche, comparé au sandbox de
  référence `sandboxes/cyber/02-cyber-sec-ANSSI-PG-083+RGS_v-2-0_B2`,
  généré avec l'ancienne méthode — pré-branche)
- **Gravité** : bloquant pour le merge — invalide la garantie centrale de
  la branche (`kb-coverage-optimization`)

## Résumé

Le pré-split de corpus (Phase 2 de `chorus-corpus-scoping`) classe tout
contenu ne générant aucune règle de conformité dans une seule catégorie
`OUT-OF-SCOPE (no_auto_rules)`, sans distinguer :

1. le contenu **réellement hors périmètre** (bibliographie, table des
   matières, front matter) — aucune information exploitable ;
2. le contenu **« Helper-source »** — annexes à données quantitatives
   (records de cryptanalyse, coûts d'attaque, tables de référence) qui ne
   génèrent eux-mêmes aucune règle de conformité, mais qui **doivent**
   alimenter des `Helper` Perl pour enrichir le `motif_*`/justification
   d'une règle existante (pattern déjà établi et documenté dans
   `chorus-feed.md`, cf. section Helpers de `SCOPING.md` d'origine et les
   sandboxes de référence).

Le rapport `* Coverage` produit par `chorus-feed` Phase 6.5 ne possède que
3 catégories : `✅ Integrated`, `⏭ Deferred — needs chorus-feed --enrich`,
`⛔ Out of scope`. Le contenu « Helper-source » mal classé en 1. tombe
silencieusement dans `⛔ Out of scope`, **sans jamais transiter par
`⏭ Deferred`** — donc sans jamais déclencher de signal actionnable pour
l'opérateur ni pour une passe `--enrich` ultérieure.

## Repro minimal

1. Fournir à `chorus-corpus-scoping` (Mode A, Phase 2) un corpus contenant :
   - une section normative avec seuil chiffré (ex. « la clé doit faire au
     moins 128 bits ») → génère une règle R01 avec ce seuil ;
   - une annexe contenant des données empiriques chiffrées corroborant ce
     seuil (ex. table de records de cassage historiques), **sans énoncer
     elle-même de règle** (pas de `RègleXxx`/`RecoXxx` numérotée).
2. Laisser le pré-split classer l'annexe.
3. Observer `SCOPING.md` § Corpus section assignment : l'annexe est classée
   `OUT-OF-SCOPE (no_auto_rules)`, au même titre qu'une vraie bibliographie.
4. Lancer `chorus-feed` (Mode A) sur les fichiers pré-splittés — le `Helper`
   correspondant n'est jamais généré, aucune trace du gap n'apparaît dans
   `README.org` § Coverage (`⏭ Deferred` reste à 0).
5. `chorus-check` s'exécute avec succès, pipeline `SOLVED`, aucune alerte —
   le gap reste totalement invisible sans comparaison externe.

## Cas réel observé

- Corpus : `sandboxes/cyber/03-cyber-sec-ANSSI-PG-083+RGS_v-2-0_B2-REBUILD/corpus/001-anssi-guide-mecanismes-crypto-3.00-2-vision.md`
- `SCOPING.md` (ligne « Corpus section assignment ») :
  ```
  | 001 bibliographie + annexes (tables/figures) | — | — | OUT-OF-SCOPE (no_auto_rules) |
  ```
  Cette ligne regroupe l'Annexe C (bibliographie, réellement hors scope) et
  l'**Annexe B** (§B.1 à §B.5 — records de factorisation, log discret GF(p),
  courbes elliptiques, réduction de réseaux) sous un même verdict.
- Conséquence : les 5 Helpers de justification empirique
  (`cout_attaque_symetrique`, `record_factorisation_le_plus_recent`,
  `record_log_discret_gfp_le_plus_recent`,
  `record_courbe_elliptique_le_plus_recent`,
  `record_reduction_reseau_le_plus_recent`) présents dans le sandbox de
  référence `02-cyber-sec-ANSSI-PG-083+RGS_v-2-0_B2` (généré avec l'ancienne
  méthode, sans pré-split) sont **totalement absents** de `03-`.
- `README.org` de `03-` affichait `** ⏭ Deferred — needs chorus-feed --enrich (0 sections)`
  après un `chorus-check` réussi — rapport honnête au regard de la méthode,
  mais faux au regard de la complétude réelle.
- Détecté uniquement via une comparaison manuelle opérateur des deux
  `README.org` (`02-` vs `03-`), à la demande explicite de l'opérateur —
  **aucun signal automatique** du pipeline n'a permis de le détecter.

## Hypothèse sur l'origine de la régression

`02-` (généré avant cette branche, sans pré-split Phase 2) a traité le
corpus **linéairement** : l'Annexe B a été rencontrée « au fil de l'eau »
pendant la lecture séquentielle du document et correctement associée aux
règles qu'elle justifie. `03-` (généré avec cette branche, pré-split Phase 2
en fichiers dédiés par agent, ciblés uniquement sur les `RègleXxx`/`RecoXxx`
numérotées) **exclut activement** tout ce qui n'est pas une règle numérotée
du pré-split — gain de précision sur le découpage des règles, mais **perte
d'exhaustivité** sur le contenu de justification empirique qui ne porte pas
de numéro `RègleXxx` propre.

Le pré-split, censé améliorer la couverture (`kb-coverage-optimization`),
introduit ici une régression par rapport à la méthode linéaire qu'il
remplace.

## Correctif proposé

1. **`chorus-corpus-scoping.md` (Phase 2)** — introduire une catégorie
   `HELPER-SOURCE` distincte de `OUT-OF-SCOPE` dans la table § Corpus
   section assignment. Critère de classification : contenu quantitatif
   (tables, exemples chiffrés, records) **référencé en note de bas de page
   ou en renvoi explicite** (`voir annexe X`, `cf. table N`) depuis une
   section normative déjà scopée — à extraire dans un fichier corpus dédié
   au même titre que les sections `PRIMARY`, plutôt que d'être absorbé dans
   `OUT-OF-SCOPE`.
2. **`chorus-feed.md` (Phase 6.5 — Coverage report)** — faire apparaître le
   contenu `HELPER-SOURCE` non encore traité comme
   `⏭ Deferred — needs Helper` (compteur dédié, distinct des sections
   normatives non codifiées), pour qu'un `README.org` affichant
   `0 Deferred` soit une garantie fiable d'exhaustivité — y compris sur les
   Helpers, pas seulement sur les règles de conformité.
3. **Test de non-régression** (`t/` ou `sandboxes/test-kb-multiSource`) —
   fixture avec (a) une vraie section hors-scope (bibliographie/ToC) et
   (b) une annexe à données empiriques référencée par une règle normative
   déjà scopée ; assertion que Phase 2 les classe différemment et que
   Phase 6.5 signale (b) comme `Deferred` tant que le Helper n'est pas
   généré.

## Critère de validation avant merge

Regénérer `sandboxes/cyber/03-cyber-sec-ANSSI-PG-083+RGS_v-2-0_B2-REBUILD`
**sans** le correctif manuel appliqué le 2026-09-20
(`corpus/013-annexe-b-empirique.md` +
`lib/ANSSICrypto/Helpers/JustificationEmpirique.pm` retirés), avec le skill
corrigé, et vérifier que `chorus-corpus-scoping` + `chorus-feed` (Mode A
intégrale) détectent et traitent l'Annexe B **sans intervention manuelle
ni comparaison à `02-`**.
