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
