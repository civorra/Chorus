# Bug report — `chorus-corpus-scoping` Phase 2 : sur-déclenchement du score PRIMARY par recouvrement de vocabulaire incident

- **Branche concernée** : `feat/kb-coverage-optimization`
- **Skill concerné** : `agent/skills/chorus-corpus-scoping.md` (Phase 2, Step 2 — `PRIMARY match`)
- **Découvert le** : 2026-09-20, pendant le test de non-régression du
  correctif `HELPER-SOURCE` (`sandboxes/test-kb-multiSource/TEST-PLAN-helper-source.md`)
- **Gravité** : non bloquant pour le correctif `HELPER-SOURCE` (contourné par
  `STEP 0b`, qui court-circuite le scoring PRIMARY pour les sections
  remplissant les 2 conditions `HELPER-SOURCE`) — mais reste un défaut de
  précision **préexistant et plus large** du scoring PRIMARY, affectant
  potentiellement toute annexe/section informative ne remplissant pas les
  conditions `HELPER-SOURCE`.

## Résumé

L'algorithme `PRIMARY match` :
```
score(A, S) = count of distinct intent keywords of A found in S's heading + first paragraph
Primary agent = argmax score(A, S)   if max_score > 0
```
ne vérifie que la présence de mots-clés partagés entre l'intent d'un agent
et le texte d'une section — **sans vérifier qu'une formulation normative
(`shall`/`must`/`doit`/équivalent) est réellement présente**. Une section
purement informative (annexe méthodologique, glossaire étendu, note
explicative) qui documente le contexte d'une règle déjà normée ailleurs
partage naturellement du vocabulaire avec cette règle — et peut donc se
voir attribuer un score PRIMARY strictement positif sans contenir
elle-même aucune prescription vérifiable.

## Repro (cas réel observé)

Corpus de test : `sandboxes/test-kb-multiSource/corpus/001-cir-binding.md`.

- Intent `agent-load` : *"Load conformance — CIR Art.5 — P1/P2/P3 minimum
  load thresholds in Newtons"*.
- Section `Annex D (informative) — Load-test methodology` (narrative pure,
  aucune prescription) : *"Load tests are performed using a calibrated
  hydraulic press... until failure or the target threshold is reached..."*

Correspondances comptées : `load`, `threshold` → `score(agent-load, Annex D)
= 2 > 0`. Par l'algorithme littéral, Annex D obtiendrait `agent_primaire =
agent-load` et serait classée `PRIMARY` — alors qu'elle ne contient **aucune**
prescription propre (pas de "shall"/"must"), uniquement une description de
protocole de test.

Un cas symétrique existe côté `agent-algo` avec `Annex C` (*"Empirical
key-strength benchmark data"* vs intent *"...minimum key length"*) — mais ce
cas est désormais intercepté en amont par `STEP 0b` (voir
`WRK-BUG-corpus-scoping-helper-source-blindspot.md`, correctif appliqué),
ce qui masque partiellement ce défaut plus large pour les sections qui
remplissent aussi les conditions `HELPER-SOURCE`. Une section informative
qui ne contient **ni** renvoi `§-number` **ni** artefact quantitatif
(comme Annex D) reste exposée au défaut sans aucun filet de sécurité.

## Conséquence si non corrigé

Une section purement informative peut être classée `PRIMARY` par erreur,
ce qui déclenche en Phase 3 de `chorus-feed` une tentative de génération de
règle à partir d'un texte qui n'en contient aucune — au mieux un
`too-ambiguous` légitimement classé (protocole de retry Step 2b de
`chorus-feed.md`), au pire une règle mal formée ou une confusion de
traçabilité `CORPUS:`.

## Correctif appliqué (2026-09-20)

Ajout de `STEP 0c — Deontic gate` dans `chorus-corpus-scoping.md` (Phase 2,
juste avant `PRIMARY match`) : une section ne peut obtenir un score PRIMARY
`> 0` que si elle contient **au moins une clause au verbe déontique**
(`shall`/`must`/`is required to`/`shall not` ou équivalent dans la langue
du corpus — `doit`/`devra`/`est tenu de`/`ne doit pas`, selon
`#+CORPUS_LANG`). Une section sans clause déontique propre voit son score
forcé à `0` pour tous les agents, quel que soit le recouvrement de
vocabulaire — purement structurel, jamais basé sur un mot-clé de domaine.

## Test de non-régression — exécuté réellement (2026-09-20)

`sandboxes/test-kb-multiSource`, `Annex D (informative) — Load-test
methodology` : texte relu ligne à ligne, aucune occurrence de
`shall`/`must`/`is required to`/`shall not` — uniquement du descriptif
("are performed", "documents"). `STEP 0c` force donc
`score(agent-load, Annex D) = 0`, malgré le recouvrement lexical
(`load`, `threshold`) qui aurait sinon donné `score = 2 > 0`. Résultat :
`CONTEXT-ONLY` (cross-référencée depuis Art.5), confirmé par l'algorithme
seul — voir `sandboxes/test-kb-multiSource/TEST-PLAN-helper-source.md` et
`SCOPING.md` pour la trace complète.

Vérification de non-régression sur les sections déjà `PRIMARY`
(ex. ARF §3.2, CIR Art.5, CIR Art.6) : toutes contiennent au moins une
clause `shall` propre — non affectées par `STEP 0c`.

## Statut

`FIXED — 2026-09-20` — correctif appliqué et test de non-régression
exécuté réellement (pas seulement documenté).
