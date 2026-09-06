chorus-create-project 01b-demo_en --strategy edges

Thought 40s

Contexte KB disponible dans `.chorus-batch-ctx.md` — Phase 0+1 skippée.

**Plan edges — seuils continus à couvrir (ε=1 int, ε=0.1 float) :**

| Slot                        | Seuil(s)                | Éléments                               |
|-----------------------------|-------------------------|----------------------------------------|
| `moisture_pct`              | lo=10, hi=18            | exact-lo, below-lo, exact-hi, above-hi |
| `spacing_mm`                | lo=300, hi=600          | exact-lo, below-lo, exact-hi, above-hi |
| `deflection_mm`             | L/300 (L=3000 → T=10.0) | exact, above, below                    |
| `R` insulation zone A       | 6.5                     | exact, below, above                    |
| `R` insulation zone B       | 4.5                     | exact, below                           |
| `R` insulation zone C       | 3.5                     | exact, below                           |
| `sd_value` SC1/SC2/SC3      | 5/18/50                 | exact+below × 3                        |
| `rei_period`                | 30 (collective=0)       | exact, below, above                    |
| `surface_mass_kg_m2`        | 8.0                     | exact, below                           |
| `plasterboard_thickness_mm` | 12.5 (collective=0)     | exact, below                           |

→ **33 éléments**
Creating projet-edges.json +327 -0 ✅ 0s view diff

$ python3 -c "import json; data=json.... ✅ 0s

**Pipeline SOLVED ✅** — 31/31 verdicts conformes aux attentes.

---

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-create-project  01b-demo_en  --strategy edges
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Fichier        : projet-edges.json
  Éléments       : 31  (17 CONFORME / 14 NON_CONFORME)
  Unprocessed    : 0
  Pipeline       : SOLVED ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Seuils couverts (10 slots, 14 frontières) :
    moisture_pct    lo=10  exact✅  below❌  hi=18  exact✅  above❌
    spacing_mm      lo=300 exact✅  below❌  hi=600 exact✅  above❌
    deflection_mm   T=L/300 below✅  exact✅  above❌
    R zone A        6.5    exact✅  below❌  above✅
    R zone B        4.5    exact✅  below❌
    R zone C        3.5    exact✅  below❌
    sd_value SC1    5      exact✅  below❌
    sd_value SC2    18     exact✅  below❌
    sd_value SC3    50     exact✅  below❌
    rei_period      30     below❌  exact✅  above✅
    surface_mass    8.0    exact✅  below❌
    pb_thickness    12.5   exact✅  below❌
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Suite batch 01b-demo_en — état final :
    projet-rules-iso.json  ✅  24 éléments
    projet-edges.json      ✅  31 éléments
    projet-cross.json      ✅  16 éléments
    projet-scale.json      ✅ 111 éléments
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Suite complète — prochaine étape :
    chorus-check 01b-demo_en --all
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

La suite batch `01b-demo_en` est maintenant **complète** (4/4 fichiers générés, tous SOLVED). Le fichier `.chorus-batch-ctx.md` peut être supprimé si vous le souhaitez.
