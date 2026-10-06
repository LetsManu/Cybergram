# Holdstone (Hold hardpoint): design brief and review notes

## Brief

| | |
|---|---|
| Purpose | The machine of a **Hold** hardpoint (C4): stand in the zone and out-number the enemy to progress. The plinth is chest-high cover on purpose (W18-GEO: no single raised spot sees the whole ring). |
| Story | A dormant mana crystal held in a chrome-ring plinth on an old Halcyra stone dais; when held, it lights a 12 m pillar of light in the owner's colour (design/art-bible.md §6.3). |
| Silhouette | 80 m read: the vertical light pillar (HardpointView hologram). 20 m read: a squat 12-sided plinth with a crystal cluster and curling claws on a wide round dais. |
| Scale | Dais r 8.0 -> 7.0, 0.3 m; plinth r 2.8 -> 2.4, 1.8 m on the dais (both = the map's collision, so cover heights are unchanged). Crystal tip ~4.4 m. |
| States | Neutral (violet), owned (team colour), capturing (HardpointView segments fill), contested / overtime (label). Ownership swaps the asset's material (team uniform) and the pillar colour. |
| Layers | Primary: dais, plinth, crystal. Secondary: plinth bands, chrome ribs, collar, claws, rim steps. Tertiary: brass inlay ring, 12 radial seams + floor emitters (one per progress sector), vents, bolts, rubble. |
| Team colour | `team_emit`: crystal, rib slits, collar line, claw tips, floor emitters. |
| Built by | `tools/art/world/holdstone.py` (seed 2207). Pieces: `main`, `crystal`. |
| Budget | Landmark class 8k-25k (docs/art-bible.md §6): 18,574 tris. |

## Review log

### Iteration 1 (2026-10-06): first bake, 1024 maps

Build: 18,574 tris, 2 pieces, UV atlas 85.2 %, bake 237 s. Opened
`production/qa/evidence/p6-holdstone/after/hero-ref, hold-close, hold-mid,
mid-hardpoint-approach.png` (plus hold-far / -approach, mid-hardpoint-close /
-mid / -far, fp-lane-center on the contact sheet), compared with
`p5-world/before/` and the heroes.

- Holds up next to the hero: in `hero-ref` Vesper and a Picket stand on the dais
  and share its language (ink outline, painted light, edge highlights). The
  neutral Mid glows `leyfall_violet`, owned ones in team colour.
- Reads at every distance: ribs, collar, claws, vents and the faceted crystal
  at `-close`; the dais with rim steps, brass inlay, 12 seams and floor emitters
  at `-mid`; the holo light pillar from 35 m (`-approach`) like the brief's
  "single vertical beam".
- Grounded: rim steps and rubble sit in the plaza floor; no floating parts seen.
- Still below standard (not this asset): the Garrison markers (flat hexagon
  discs, blue / orange) and the Supply Cache (cyan box) on and next to the dais;
  the map's zone torus and HardpointView's dark progress tiles (flat
  primitives); the surrounding lane geometry. Ownership swap and capture
  progress were not captured as frames (code path covered by tests, visuals
  unverified).
