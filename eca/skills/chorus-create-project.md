# Skill — chorus-create-project

> Déclencheur : `chorus-create-project <sandbox-name> <fichier-sortie.json>`
> Agent : `architect`
>
> `<sandbox-name>` : sandbox contenant une KB produite par `chorus-feed`
> `<fichier-sortie.json>` : nom du fichier JSON à créer dans `$SANDBOX/`
>
> **Responsabilité unique : créer un fichier projet JSON valide.**
> Ce skill lit la KB du sandbox pour déduire les types, slots et seuils,
> puis génère un fichier JSON peuplé d'éléments conformes ET non-conformes
> explorant la variété du domaine.
>
> Prérequis : `chorus-feed <sandbox-name>` doit avoir été exécuté au préalable.
>
> ⚠️ **Sources à utiliser — ordre strict :**
> 1. `$SANDBOX/eca/agents/index.org` → types de Frames, pipeline, namespace
> 2. `$SANDBOX/eca/agents/<slug>.org` → slots obligatoires, seuils, helpers
> 3. Un fichier `projet-*.json` existant dans `$SANDBOX/` → format de référence
>
> ⛔ **Ne jamais lire** `Helpers.pm`, `Feed.pm`, `Agent/*.pm`, `Expert.pm`, `run.pl`
> pour créer un projet. Ces fichiers sont des dérivés des KB org — la source
> canonique est toujours la KB org.

---

## Phase 0 — Lire la KB (source unique)

### 0.1 Index du pipeline

Lire `$SANDBOX/eca/agents/index.org` :
- Namespace Perl du projet
- Liste ordonnée des agents (slug, module, pos)
- Dictionnaire global des slots (si présent)

### 0.2 KB de chaque agent

Pour chaque agent, lire `$SANDBOX/eca/agents/<slug>.org` et extraire :

| Section KB | Ce qu'on en tire |
|---|---|
| `Catalogue des Frames` | Types d'éléments + slots obligatoires / optionnels par type |
| `Dictionnaire des slots` | Noms exacts des slots, types de valeurs, domaines valides |
| `Slots de ciblage` | Slot(s) que le Feed doit poser pour que l'agent voie le Frame |
| `Helpers Perl` (section KB) | Tables normatives : seuils, plages, classes admises |
| `Contraintes & Pitfalls` | Cas limites à couvrir dans le projet |

> **Règle :** les tables de seuils sont dans la section `Helpers Perl` des KB org —
> elles sont identiques au code de `Helpers.pm`. Ne pas ouvrir `Helpers.pm`.

### 0.3 Format de référence

Si un fichier `projet-*.json` existe dans `$SANDBOX/`, lire ses 30 premières lignes
pour confirmer le format JSON (clés `projet`, `description`, `elements`, champs `id`, `type_element`).
Ne pas lire les éléments individuels — les types et slots sont dans la KB.

---

## Phase 1 — Planifier la couverture

Construire un tableau de couverture avant de générer le moindre élément :

| Type | Cas conformes | Cas non-conformes | Variantes |
|---|---|---|---|
| `<type_1>` | N | N | zones, classes, sections... |
| `<type_2>` | N | N | ... |

**Règles de couverture minimale :**
- ✅ Au moins **2 éléments conformes** par type (valeurs nominales différentes)
- ❌ Au moins **1 élément non-conforme** par règle de rejet connue (§ corpus)
- 🔀 **Variété dimensionnelle** : couvrir les plages extrêmes des slots continus
  (ex. valeurs min/max des plages normatives, catégories ou classes admises)
- 📐 **Cas limites** : valeur exactement au seuil (conforme) et juste en dessous (non-conforme)

**Volume cible :** adapter au contexte. Pour un test de scaling → ≥ 100 éléments.
Pour une validation fonctionnelle → 10–30 éléments, tous les types couverts.

---

## Phase 2 — Calculer les valeurs

Pour chaque élément, calculer les valeurs **depuis les tables des KB** — jamais à l'intuition.

### Exemples de calculs type

Adapter les exemples aux tables normatives lues dans la KB du sandbox.
Pour chaque règle de rejet, extraire le seuil et calculer une valeur franchissant
le seuil dans le bon sens.

> ⚠️ **Calculer, ne pas deviner.** Pour chaque cas non-conforme, vérifier
> que la valeur choisie franchit effectivement le seuil dans le bon sens.
> Annoter le calcul dans un commentaire `_note_calc` du JSON si utile.

---

## Phase 3 — Générer le JSON

### Structure obligatoire

```json
{
  "projet": "<nom-sans-espaces>",
  "description": "<description concise — types, zones, objectif>",
  "elements": [
    {
      "id":           "<TYPE-VARIANTE-NN>",
      "type_element": "<type>",
      "<slot_1>":     <valeur>,
      "<slot_2>":     <valeur>
    }
  ]
}
```

### Convention de nommage des `id`

```
<TYPE>-<VARIANTE>-<NN>
```

| Segment | Exemples |
|---|---|
| `<TYPE>` | abréviation du `type_element` (2–4 lettres majuscules) |
| `<VARIANTE>` | `OK`, `KO-<CRITERE>`, valeurs dimensionnelles significatives |
| `<NN>` | `01`, `02`... |

Exemples génériques : `EL-OK-01`, `EL-KO-SEC-01`, `EL-H2500-01`

### Slots à inclure

Pour chaque type, inclure dans l'ordre :
1. `id` et `type_element` — toujours en premier
2. Slots obligatoires (extraits du `Catalogue des Frames` KB)
3. Slots du slot de ciblage de l'agent 1 (nom exact dans la KB : section `Slots de ciblage`)
4. Slots optionnels pertinents pour les règles que l'on veut exercer
5. ⛔ Ne pas inclure de slots système (`_*`), ni les slots posés et calculés par les agents
   (résultats, statuts, qualifications) — ces slots sont calculés par le pipeline, pas fournis dans le JSON projet

### Slots posés par le Feed vs slots fournis dans le JSON

Certains slots sont calculés/normalisés par `Feed.pm` à partir d'un slot source ;
ils ne doivent **pas** être fournis explicitement si le Feed les calcule.

> **Règle :** si la KB documente une transformation `slot_source → slot_cible`,
> fournir le slot **source** dans le JSON, pas le slot cible.
> Identifier ces transformations depuis la section `Normalisations` de `index.org`
> — jamais depuis les seuils ou la logique de `Feed.pm`.

---

## Phase 4 — Valider le JSON avant exécution

Avant de lancer `perl run.pl`, effectuer une validation rapide :

```bash
python3 -c "import json; json.load(open('<fichier.json>')); print('JSON valide')"
```

Vérifier :
- [ ] JSON syntaxiquement valide (pas de virgule trailing, guillemets corrects)
- [ ] Chaque élément a `id` et `type_element`
- [ ] Tous les types sont présents dans `%SLOTS_REQUIS` de `Feed.pm`
  (ou vérifier dans le `Catalogue des Frames` de la KB — source équivalente)
- [ ] Aucun slot calculé par le pipeline (slots résultats, statuts de qualification, d'évaluation) n'est fourni
- [ ] Les valeurs non-conformes franchissent effectivement le seuil (recalculer si doute)
- [ ] ⚠️ **Pour les cas CONFORME : vérifier TOUS les critères de toutes les règles** qui
  s'appliquent au type — pas seulement le critère principal.
  Un élément peut passer le premier critère et échouer un critère secondaire de la même règle.
  Pour chaque type, lister tous les critères de la KB et les vérifier un par un.
  Annoter chaque critère vérifié dans `_note_calc` du JSON.

---

## Phase 5 — Exécuter et vérifier

```bash
perl $SANDBOX/run.pl $SANDBOX/<fichier.json>
```

Vérifier :
- [ ] Aucun crash Feed (type inconnu, slot manquant)
- [ ] `Non traités : 0` — tout élément doit atteindre le statut final de conformité
- [ ] Les éléments KO attendus sont bien `NON_CONFORME` avec le bon motif
- [ ] Les éléments OK attendus sont bien `CONFORME`
- [ ] `Pipeline : SOLVED ✅`

Si un élément KO attendu est CONFORME → investiguer :
1. La CONDITION de la règle ciblée exclut-elle ce type ? ← pitfall le plus fréquent
2. L'EXCEPTION court-circuite-t-elle la règle ? (slot déjà posé par une règle précédente)
3. La valeur fournie franchit-elle vraiment le seuil ? (recalculer)

---

## Séparation des responsabilités

| | `chorus-feed` | `chorus-create-project` | `chorus-check` |
|---|---|---|---|
| **Lit** | corpus de normes | KB org du sandbox | KB org + YAML |
| **Produit** | KB org, YAML, Helpers.pm | fichier `projet-*.json` | Feed.pm, Agent shells, Expert.pm, run.pl |
| **Source des seuils** | corpus | KB org (section Helpers Perl) | KB org |
| **Ne lit jamais** | — | Helpers.pm, Feed.pm, *.pm | — |
