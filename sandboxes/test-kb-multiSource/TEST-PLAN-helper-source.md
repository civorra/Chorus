# Test plan — HELPER-SOURCE classification (Axe 5)

- **Objet** : vérifier que `chorus-corpus-scoping` Phase 2 (Step 2, version
  corrigée sur `feat/kb-coverage-optimization`) classe automatiquement
  Annex C / Annex D correctement, **sans** marqueur manuel
  `CHORUS:helper_source` posé.
- **Référence** : `Engine/WRK-BUG-corpus-scoping-helper-source-blindspot.md`
  (rapport de bug d'origine) + `agent/skills/chorus-corpus-scoping.md`
  § HELPER-SOURCE refinement (correctif).
- **Ne pas confondre** avec une exécution précédente de ce test : la
  première tentative (2026-09-20) a écrit le résultat attendu directement
  dans les artefacts de sortie (`corpus/004-...`, `SCOPING.md`,
  `Helpers.pm`, etc.) sans jamais exécuter le skill — invalidée et
  intégralement retirée sur remarque opérateur (« en quoi consiste ce test
  s'il n'y a pas de chorus-feed à faire ?? »). Cette version corrige le
  protocole : exécution réelle, résultat constaté a posteriori.

## Entrée du test

`corpus/001-cir-binding.md` contient, en plus du contenu original (Foreword,
Terms, Article 5, Article 6, Annex A) :

- **Annex C** (informative) — table de coûts de cassage empiriques
  (`[MATRIX TABLE]`), renvoyée depuis Article 6 ("See Annex C for empirical
  benchmark data...").
- **Annex D** (informative) — méthodologie de test narrative, sans table,
  renvoyée depuis Article 5 ("See Annex D for the load-test methodology...").

Aucune des deux ne porte de marqueur `CHORUS:no_auto_rules` ni
`CHORUS:helper_source` — la classification doit être **entièrement
automatique** (heuristique Step 2).

## Hypothèse (à vérifier, pas à présupposer dans les artefacts)

D'après le correctif du skill, la classification `HELPER-SOURCE` exige
**deux conditions cumulatives** :
(a) renvoi explicite depuis une section `PRIMARY` à seuil numérique, et
(b) présence d'un artefact quantitatif structuré (`[MATRIX TABLE]` ou
équivalent).

Annex C remplit (a) et (b). Annex D remplit (a) mais pas (b) — narrative
uniquement. Si l'algorithme est correctement implémenté et correctement
suivi, Annex C devrait être promue `HELPER-SOURCE` et Annex D rester
`CONTEXT-ONLY`. **Ce test consiste précisément à vérifier que c'est bien ce
qui se produit en suivant l'algorithme écrit, pas à l'affirmer.**

## Procédure

1. **Phase 2, Step 1** — inventaire des sections de `corpus/001-cir-binding.md`
   (déjà fait implicitement — sections listées ci-dessus).
2. **Phase 2, Step 2** — appliquer l'algorithme de classification tel
   qu'écrit dans `chorus-corpus-scoping.md` à Annex C et Annex D
   spécifiquement (les autres sections ne changent pas de classification,
   déjà validées lors du test à 4 axes) :
   a. Vérifier absence de marqueur `CHORUS:no_auto_rules`/`helper_source`.
   b. Calculer le score PRIMARY (doit être 0 pour les deux — aucun mot-clé
      d'intent d'agent dans leur texte).
   c. Vérifier SHARED (doit être faux — pas de 3+ agents).
   d. Déterminer CONTEXT-ONLY par défaut (cross-référencées par §-number
      depuis une section PRIMARY).
   e. Appliquer le raffinement HELPER-SOURCE : chercher (a) renvoi
      structurel + (b) marqueur `[MATRIX TABLE]`/artefact numérique dans le
      texte de la section elle-même.
3. Documenter le résultat obtenu dans `SCOPING.md` § Corpus section
   assignment (mise à jour réelle, pas préparée à l'avance).
4. Si Annex C → `HELPER-SOURCE` : poursuivre avec `chorus-feed` Phase 1 sur
   `corpus/004-agent-algo.md` régénéré, Phase 5.5 (écriture du Helper),
   Phase 6.5 Step 1c (audit de couverture) — vérifier que
   `🧮 Helper-source pending` passe bien de 1 à 0 après écriture du Helper.
5. Consigner le résultat (succès/échec, tout écart par rapport à
   l'hypothèse) dans `README.org` § Session notes — comme un **constat**,
   pas une prédiction.

## Résultat (constat réel, 2026-09-20)

**Annex C** : `HELPER-SOURCE` confirmé.
- Step 0b : renvoi structurel depuis Art.6 (PRIMARY, seuil numérique) ✅ +
  `[MATRIX TABLE]` présente ✅ → HELPER-SOURCE, PRIMARY scoring court-circuité.
- Sans `STEP 0b`, le scoring PRIMARY aurait donné
  `score(agent-algo, Annex C) = 4` (`minimum`, `key`, `length`, `ARF`) > 0,
  verrouillant Annex C en `PRIMARY` avant que le raffinement HELPER-SOURCE
  (version initiale, gardée en aval) ne puisse s'appliquer. **Ceci est le
  bug réel découvert pendant ce test** — corrigé en repositionnant le
  contrôle HELPER-SOURCE avant le scoring PRIMARY (`chorus-corpus-scoping.md`
  § STEP 0b).
- Phase 5.5 : `key_crack_benchmark()` écrit dans
  `lib/WidgetCompliance/Helpers.pm`, `perl -c` validé.
- Step 1c (audit Phase 6.5) : `grep "Source corpus"` confirme la présence du
  commentaire de traçabilité référençant Annex C → `🧮 Helper-source
  pending = 0`.

**Annex D** : `CONTEXT-ONLY`, confirmé sans réserve après 2ᵉ correctif.
- Step 0b ne la classe pas HELPER-SOURCE (pas d'artefact quantitatif) —
  comportement correct et attendu.
- Scoring PRIMARY littéral (avant 2ᵉ correctif) : `score(agent-load, Annex
  D) = 2` (`load`, `threshold`) > 0 → aurait classé `PRIMARY` à tort.
- **Correctif `STEP 0c`** (filtre déontique) appliqué : relecture ligne à
  ligne du texte d'Annex D confirme l'absence de toute clause
  `shall`/`must`/`is required to` — uniquement descriptif. `STEP 0c` force
  donc `score = 0`, et la section retombe en `CONTEXT-ONLY` **par
  l'algorithme seul**, sans jugement manuel. Vérifié réellement, pas
  supposé — voir `Engine/WRK-BUG-corpus-scoping-primary-keyword-overmatch.md`
  (statut `FIXED`).

## Conclusion

Le test a rempli son rôle deux fois : il a validé le correctif
`HELPER-SOURCE` **et** révélé un défaut d'ordonnancement (`STEP 0b`,
corrigé), puis en creusant plus loin, un second défaut plus large et
préexistant (`STEP 0c`, corrigé et re-testé). Les deux correctifs ont été
vérifiés par relecture mécanique du texte du corpus, pas par affirmation.

## Statut

`DONE — 2026-09-20` — Step 1 à 5 exécutés réellement, 2 fois (avant/après
2ᵉ correctif). 2 correctifs appliqués (`STEP 0b`, `STEP 0c`), tous deux
re-testés réellement sur ce corpus.
