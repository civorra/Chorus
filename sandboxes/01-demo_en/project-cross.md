chorus-create-project 01b-demo_en --strategy cross

Thought 48s

Contexte KB disponible dans `.chorus-batch-ctx.md` — Phase 0+1 skippée.

**Plan cross — 16 éléments :**

| #  | Type de croisement   | Règles activées                             | Verdict                        |
|----|----------------------|---------------------------------------------|--------------------------------|
| 1  | Positif global (LBS) | qual-R01+R02+R03, geo-R01+R02, fire-R01+R03 | CONFORME                       |
| 2  | Positif global (RAF) | qual-R01+R03, geo-R01+R02, fire-R01         | CONFORME                       |
| 3  | Qual double KO       | qual-R01 (class) + qual-R02 (moisture)      | KO                             |
| 4  | Qual double KO       | qual-R01 (class) + qual-R03 (deflection)    | KO                             |
| 5  | Geo double KO        | geo-R01 (spacing) + geo-R02 (section)       | KO                             |
| 6  | Geo double KO        | geo-R02 (section) + geo-R04 (splice)        | KO                             |
| 7  | Geo double KO        | geo-R01 (spacing) + geo-R04 (splice)        | KO                             |
| 8  | Fire double KO       | fire-R01 (rei) + fire-R03 (pb)              | KO                             |
| 9  | Fire double KO       | fire-R02 (lining) + fire-R03 (pb)           | KO                             |
| 10 | Fire triple KO       | fire-R01+R02+R03 tous                       | KO                             |
| 11 | Qual + Fire croisés  | qual (C16<C24) + fire (rei<30)              | KO                             |
| 12 | Moisture + Fire      | qual-R02 (mc<10%) + fire-R01 (rei)          | KO                             |
| 13 | Qualification gate   | qual KO (C16) masque geo KO (section)       | KO — seul qualified=NO visible |
| 14 | Spacing ↔ section    | s=600 h=2700 → min 38×140 exactement        | CONFORME                       |
| 15 | INS à seuil exact    | R = 6.5 exactement (zone A)                 | CONFORME                       |
| 16 | VCL frontière        | Sd=17 SC2 (min=18)                          | KO                             |
Creating projet-cross.json +202 -0 ✅ 0s view diff

$ python3 -c "import json; data=json.... ✅ 0s

**Pipeline SOLVED ✅** — tous les verdicts conformes aux attentes.

---

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-create-project  01b-demo_en  --strategy cross
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Fichier        : projet-cross.json
  Éléments       : 16  (4 CONFORME / 12 NON_CONFORME)
  Unprocessed    : 0
  Pipeline       : SOLVED ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Interactions couvertes :
    Positif multi-règles (LBS toutes règles)       ✅
    Positif multi-agents (RAF qual+geo+fire)        ✅
    Dual KO qual-R01+R02 (class + moisture)         ❌
    Dual KO qual-R01+R03 (class + deflection)       ❌
    Dual KO geo-R01+R02 (spacing + section)         ❌
    Dual KO geo-R02+R04 (section + splice)          ❌
    Dual KO geo-R01+R04 (spacing + splice)          ❌
    Dual KO fire-R01+R03 (rei + pb)                 ❌
    Dual KO fire-R02+R03 (lining + pb)              ❌
    Triple KO fire R01+R02+R03                      ❌
    Cross-agents qual+fire (SP)                     ❌
    Cross-agents moisture+fire (JOI)                ❌
    Gate effect qual masque geo                     ❌
    Frontière spacing×section (s=600, 38×140)       ✅
    Thermique seuil exact R=6.5 (INS zone A)        ✅
    Frontière VCL Sd=17 SC2 (min=18, border−1)      ❌
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Prochaine étape :
    chorus-create-project 01b-demo_en --strategy edges
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
