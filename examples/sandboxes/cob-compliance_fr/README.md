# cob-compliance_fr

Exemple introductif complet de la chaîne Chorus + ECA.  
Domaine : **Construction Ossature Bois (COB)** — DTU 31.2 / NF EN 338 / EC5 / NF EN 13162.

## Lancer l'exemple

```sh
perl run.pl project-demo.json
```

## Régénérer l'infrastructure depuis la KB

```sh
# Depuis ECA, dans le contexte Chorus :
chorus-check cob-compliance_fr project-demo.json
```

## Enrichir la base de connaissance

```sh
# Ajouter un corpus complémentaire :
chorus-feed cob-compliance_fr <nouveau-corpus.txt> --enrich
```

## Corpus

| Num | Fichier | Source | Date |
|---|---|---|---|
| 1 | `corpus/dtu-intro-simul.txt` | DTU 31.2 / NF EN 338 / EC5 / NF EN 13162 | 2025-07-07 |

## Pipeline

| Pos | Agent | Slug | Slot entrant | Slots produits |
|---|---|---|---|---|
| 1 | Qualification | `qualification` | `besoin_qualification` | `qualifie`, `besoin_ossature` |
| 2 | Ossature | `ossature` | `besoin_ossature` | `ossature_ok`, `besoin_thermique` |
| 3 | Thermique | `thermique` | `besoin_thermique` | `thermique_ok`, `besoin_securite` |
| 4 | SecuriteFeu | `securite-feu` | `besoin_securite` | `feu_ok`, `besoin_conformite` |
| 5 | Conformite | `conformite` | `besoin_conformite` | `statut_conformite` |

## Statut des agents

| Agent | KB | YAML | Helpers |
|---|---|---|---|
| `qualification` | ✓ | 7 | ✓ |
| `ossature` | ✓ | 7 | ✓ |
| `thermique` | ✓ | 4 | ✓ |
| `securite-feu` | ✓ | 5 | ✓ |
| `conformite` | ✓ | 2+1P | ✓ |

## Artefacts ECA

- `corpus/` — corpus source ayant servi à `chorus-feed`
- `eca/agents/*.org` — base de connaissance par agent (lue par `chorus-check`)
- `eca/agents/index.org` — index du pipeline global
- `rules/**/*.yml` — règles YAML générées par `chorus-feed`
- `lib/COB/` — infrastructure Perl générée par `chorus-check`
- `run.pl` — point d'entrée généré par `chorus-check`
