
chorus-check 01b-demo_en --all

Thought 0s

Reading chorus-check.md (0-2000) ✅ 0s

Thought 0s

Listing tree: Chorus/sandboxes/01b-demo_en ✅ 0s

Thought 0s

$ cat /home/civorra/Chorus/sandboxes/... ✅ 0s

$ ls /home/civorra/Chorus/sandboxes/0... ✅ 0s

Thought 7s

$ sha256sum /home/civorra/Chorus/sand... ✅ 0s

Thought 0s

✅ Hash identique — **FAST PATH** activé. Infrastructure déjà à jour, pas de régénération.

Passage direct à Phase 6-all. Je découvre les fichiers projet :
$ ls /home/civorra/Chorus/sandboxes/0... ✅ 0s

Thought 3s

88 fichiers projet trouvés. Je vais lancer les runs en groupes parallèles via sous-agents.
general: run project-*.json (1 steps, 34.4K / 200K) ✅ 24s

general: run stress-boundary batch A (2 steps, 22.9K / 200K) ✅ 50s

general: run stress-boundary batch B (3 steps, 25.9K / 200K) ⏳ 1m 1s

general: run stress-boundary batch C (4 steps, 29.8K / 200K) ⏳ 1m 1s

general: run stress-edge + cascade (2 steps, 17.6K / 200K) ⏳ 1m 1s

general: run stress-missing (2 steps, 22.2K / 200K) ✅ 32s


Thought 11s

Tous les sous-agents ont terminé. Passage à la synthèse.
Thought 33s

J'ai tous les résultats. Assemblage de la synthèse et écriture du cache.

Creating .last-check-results.json +99 -0 ✅ 0s view diff


---

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-check --all  01b-demo_en
  Mode: run.pl (MCP unavailable)  |  Fast Path ✅ (hash OK)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Project file                                    │ Status    │ CONF │ NON  │ Unpr │ Disc │ Unc⁺
  ──────────────────────────────────────────────  ┼───────────┼──────┼──────┼──────┼──────┼─────
  project-cross                                   │ SOLVED ✅ │   4  │  12  │  0   │  0   │  —
  project-edges                                   │ SOLVED ✅ │  17  │  14  │  0   │  0   │  —
  project-rules-iso                               │ SOLVED ✅ │  12  │  12  │  0   │  0   │  —
  project-scale                                   │ SOLVED ✅ │  54  │  57  │  0   │  0   │  —
  ─ stress-boundary-deflection_mm-10-above        │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-deflection_mm-10-below        │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-deflection_mm-10-exact        │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-depth_mm-lb-89-above          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-depth_mm-lb-89-below          │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-depth_mm-lb-89-exact          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-depth_mm-nlb-63-above         │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-depth_mm-nlb-63-below         │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-depth_mm-nlb-63-exact         │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-moisture_pct-10-above         │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-moisture_pct-10-below         │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-moisture_pct-10-exact         │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-moisture_pct-18-above         │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-moisture_pct-18-below         │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-moisture_pct-18-exact         │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-plasterboard_...-coll0-125-↑  │ SOLVED ✅ │   1  │   0  │  0   │  0   │  1
  ─ stress-boundary-plasterboard_...-coll0-125-↓  │ SOLVED ✅ │   0  │   1  │  0   │  0   │  1
  ─ stress-boundary-plasterboard_...-coll0-125-=  │ SOLVED ✅ │   1  │   0  │  0   │  0   │  1
  ─ stress-boundary-plasterboard_...-coll1-25-↑   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  1
  ─ stress-boundary-plasterboard_...-coll1-25-↓   │ SOLVED ✅ │   0  │   1  │  0   │  0   │  1
  ─ stress-boundary-plasterboard_...-coll1-25-=   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  1
  ─ stress-boundary-rei_period-coll0-30-above      │ SOLVED ✅ │   1  │   0  │  0   │  0   │  1
  ─ stress-boundary-rei_period-coll0-30-below      │ SOLVED ✅ │   0  │   1  │  0   │  0   │  1
  ─ stress-boundary-rei_period-coll0-30-exact      │ SOLVED ✅ │   1  │   0  │  0   │  0   │  1
  ─ stress-boundary-rei_period-coll1-60-above      │ SOLVED ✅ │   1  │   0  │  0   │  0   │  1
  ─ stress-boundary-rei_period-coll1-60-below      │ SOLVED ✅ │   0  │   1  │  0   │  0   │  1
  ─ stress-boundary-rei_period-coll1-60-exact      │ SOLVED ✅ │   1  │   0  │  0   │  0   │  1
  ─ stress-boundary-sd_value-sc1-5-above           │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-sd_value-sc1-5-below           │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-sd_value-sc1-5-exact           │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-sd_value-sc2-18-above          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-sd_value-sc2-18-below          │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-sd_value-sc2-18-exact          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-sd_value-sc3-50-above          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-sd_value-sc3-50-below          │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-sd_value-sc3-50-exact          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-spacing_mm-300-above           │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-spacing_mm-300-below           │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-spacing_mm-300-exact           │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-spacing_mm-600-above           │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-spacing_mm-600-below           │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-spacing_mm-600-exact           │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-surface_mass_kg_m2-8-above     │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-surface_mass_kg_m2-8-below     │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-surface_mass_kg_m2-8-exact     │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneA-195-above   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneA-195-below   │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneA-195-exact   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneB-135-above   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneB-135-below   │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneB-135-exact   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneC-105-above   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneC-105-below   │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-thickness_mm-zoneC-105-exact   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-width_mm-lb-38-above           │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-width_mm-lb-38-below           │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-width_mm-lb-38-exact           │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-width_mm-nlb-38-above          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-boundary-width_mm-nlb-38-below          │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-boundary-width_mm-nlb-38-exact          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-cascade-qualified                       │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-edge-geometry-ok-splice-present         │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-edge-pb_thickness-15-collective-1       │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-edge-reaction_class-a1-surface_mass-low │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-edge-rei_period-30-collective-1         │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-edge-strength_class-c16-on-load-bearing │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-edge-surface_mass-ok-reaction_class-c   │ SOLVED ✅ │   0  │   1  │  0   │  0   │  —
  ─ stress-missing-clear_height_mm                 │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-climate_zone                    │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-collective                      │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-deflection_mm                   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-depth_mm                        │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-has_longitudinal_splice         │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-lambda                          │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-moisture_pct                    │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-plasterboard_thickness_mm       │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-reaction_class                  │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-rei_period                      │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-sd_value                        │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-service_class                   │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-spacing_mm                      │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-span_mm                         │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-strength_class                  │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-surface_mass_kg_m2              │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-thickness_mm                    │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
  ─ stress-missing-width_mm                        │ SOLVED ✅ │   1  │   0  │  0   │  0   │  —
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Overall: SOLVED ✅   88 fichiers   Discordances: 0 / 0
  ⁺ Uncertain: 12 éléments avec _expected_uncertain=true (plasterboard + rei_period coll.)
    — exclus du comptage Disc. Voir stress-manifest.org pour revue manuelle.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  CONVERGED ✅  — all 88 projects SOLVED, 0 discordances, 0 unprocessed
```

**Résumé :** Le sandbox `01b-demo_en` est parfaitement convergé. Les 88 fichiers projet (4 nominaux + 84 stress) passent tous avec `SOLVED` et zéro discordance. Les 12 éléments `_expected_uncertain=true` (frontières `plasterboard_thickness_mm` et `rei_period` en collectif) sont correctement filtrés et documentés dans `stress-manifest.org`.

`.last-check-results.json` écrit.

