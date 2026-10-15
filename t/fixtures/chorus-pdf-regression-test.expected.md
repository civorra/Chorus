# chorus-pdf regression test fixture — expected results (text mode)

> Cas-témoin de non-régression pour le skill `chorus-pdf`
> (`/home/civorra/Chorus/Engine/agent/skills/chorus-pdf.md`).
> Documente le comportement **réellement observé** lors de l'exécution de
> référence (mode texte, `ANTHROPIC_API_KEY` désactivée) — pas un vœu pieux.
> Toute divergence future lors d'une ré-exécution de ce test doit être
> investiguée comme un changement de comportement du skill.

## Fichiers

- `generate-chorus-pdf-regression-test.py` — générateur reportlab (5 pages)
- `chorus-pdf-regression-test.pdf` — PDF fixture généré (reproductible,
  régénérable avec `~/.local/share/pipx/venvs/pdfplumber/bin/python3
  generate-chorus-pdf-regression-test.py`)
- `extract-pdf-chorus-pdf-regression-test.py` — script d'extraction généré
  en suivant verbatim le "Script template — Text mode" du skill chorus-pdf
- `chorus-pdf-regression-test-text.md` — sortie réelle de l'extraction
- `chorus-pdf-regression-test-text.md.log` — log stderr de l'exécution

## Outil de génération PDF

`reportlab` (version 5.0.1) — non installé nativement (`ModuleNotFoundError`
sur l'interpréteur système, pas de `pip` disponible). Installé via
`pipx inject pdfplumber reportlab`, qui l'a injecté dans le venv pipx
existant `pdfplumber` (déjà utilisé par chorus-pdf lui-même pour la
reconstruction de tables). Interpréteur utilisé pour générer le PDF et
exécuter le script d'extraction :
`~/.local/share/pipx/venvs/pdfplumber/bin/python3`
(contient `reportlab==5.0.1` + `pdfplumber==0.11.10` + `pdfminer.six==20260107`).

## Commande d'exécution de référence

```bash
env -u ANTHROPIC_API_KEY python3 extract-pdf-chorus-pdf-regression-test.py
```

Le script contient le bootstrap de ré-exec automatique vers l'interpréteur
pdfplumber (comme spécifié dans le "Script template — Text mode" du skill),
donc l'invocation initiale via `python3` système se résout correctement.

## Résultat RÉEL observé (exécution de référence)

```
[chorus-pdf] Environment: pdfminer.six==20260107, pdfplumber==0.11.10 (interpreter: .../pdfplumber/bin/python3)
[chorus-pdf] Text mode — chorus-pdf-regression-test.pdf
[chorus-pdf] Table reconstruction: pdfplumber active (1 table(s) reconstructed)
[chorus-pdf]    2 formula pattern(s) tagged [FORMULA: ...] — see § Formula strategy
[chorus-pdf] ✅ 5 pages extracted, 1 table(s)
[chorus-pdf] Written to chorus-pdf-regression-test-text.md
```

### Détail page par page

| Page | Cas | Comportement attendu | Comportement RÉEL observé | Conforme ? |
|---|---|---|---|---|
| 1 | Tableau bordé (vecteurs) | `has_table=True`, reconstruction `pdfplumber` en table Markdown `\| ... \|` | ✅ Table Markdown propre reconstruite (`Component \| EAL1 \| EAL2 \| EAL3` + 3 lignes de données) | ✅ conforme |
| 2 | Tableau borderless (pas de vecteurs) | Blind spot §1.4d — aucune ligne vectorielle → `has_table=False` → **pas** de reconstruction Markdown, texte flatté en paragraphes séparés, **aucun warning dans le log** | ✅ Flatté en lignes de texte brut séparées (`Assurance family ... EAL4`, puis une ligne par rangée), aucune mention dans le log d'extraction (reporté seulement : "1 table(s)" = la page 1) | ✅ conforme (reproduit fidèlement le blind spot documenté) |
| 3 | En-tête pivoté 90° | Blind spot §1.4c — flatté en caractères empilés un par ligne, aucune détection ni fallback `pdftotext -layout` dans **ce** script (le script "Text mode" de base n'implémente pas `detect_rotated_headers()` / le fallback associé — ce sont des heuristiques additionnelles documentées mais non intégrées dans le template de base fourni) | ✅ Le texte apparaît bien étalé caractère par caractère sur des lignes séparées : `.` / `1` / `P` / `S` / `F` / `_` / `V` / `D` / `A` (ordre Y-descendant, donc "ADV_FSP." à l'envers lu de bas en haut, suivi de `1`), puis `ADV_ARC.1` et `X` normalement | ✅ conforme — reproduit bien le symptôme "un caractère par ligne" décrit en §1.4c |
| 4 | Formule réelle (exposant aplati) | `detect_and_tag_formulas()` doit taguer `2128` (précédé de "bits"/"opérations"/"complexité" dans le contexte) avec `[FORMULA: pattern detected (ambiguous exponent) ...]` | ✅ Placeholder `[FORMULA: pattern detected (ambiguous exponent) — verify against source]` inséré juste après la ligne contenant `2128 operations` | ✅ conforme — 1 placeholder sur la vraie formule, comme attendu |
| 5 | Faux positif connu ([#K], CCPART2V3.1R4.pdf) | Le faux positif historique (ligne ToC type "Cryptographic operation (FCS_COP) .... 210") devrait **toujours se reproduire** avec la regex actuelle (`EXPONENT_PATTERN = \b2\d{2,3}\b` + `EXPONENT_CONTEXT` contient "operations?") — documente le comportement réel, pas un vœu de correction | ✅ Le faux positif se reproduit : `[FORMULA: pattern detected (ambiguous exponent) — verify against source]` est inséré après la ligne `3. Cryptographic operation (FCS_COP) .................... 210` | ✅ conforme — comportement **connu et stable**, pas une régression |

### Compteurs globaux

- Pages extraites : **5** (conforme — 5 pages dans le PDF source)
- Tables reconstruites par `pdfplumber` : **1** (seule la page 1, bordée, est
  détectée — conforme à l'attente : `has_table` ne peut physiquement fire
  que sur la page 1, aucune ligne vectorielle n'existe ailleurs dans ce PDF)
- Placeholders `[FORMULA: ...]` : **2** (1 sur la vraie formule page 4,
  1 sur le faux positif connu page 5 — total conforme aux attentes
  documentées ; **aucune régression vers un 3e faux positif supplémentaire**
  observée sur ce fixture)
- Placeholders `[FIGURE — not extracted]` : **0** (attendu — ce PDF ne
  contient aucun `LTFigure` au sens pdfminer, uniquement du texte et des
  vecteurs de lignes)

## Comment détecter une régression future

Ré-exécuter :
```bash
env -u ANTHROPIC_API_KEY python3 \
  /home/civorra/Chorus/Engine/t/fixtures/extract-pdf-chorus-pdf-regression-test.py
```
puis comparer `chorus-pdf-regression-test-text.md` (et le log) à l'état de
référence versionné dans ce répertoire. Tout changement de :
- nombre de tables reconstruites (actuellement 1)
- nombre de placeholders `[FORMULA: ...]` (actuellement 2)
- apparition/disparition du placeholder sur le faux positif page 5
- apparition d'un comportement nouveau sur le tableau borderless (page 2)
  ou l'en-tête pivoté (page 3) — ex. si une future version du script
  intègre `detect_rotated_headers()` / `detect_borderless_table()` et leur
  fallback `pdftotext -layout`, ce fixture doit alors montrer les blocs
  `[MATRIX TABLE — extracted via pdftotext -layout ...]` sur les pages 2 et 3

... doit être traité comme un **changement de comportement du skill** à
documenter/valider explicitement, pas ignoré silencieusement.
