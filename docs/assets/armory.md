# Armory stall: design brief and review notes

Owner ask (2026-10-06): "is there now a way to see where the armory is? it
should be like the LoL shop at the spawn".

## What changed

| | Before | After |
|---|---|---|
| Where you can buy | Inside a 6 m ring around the Armory pad, 23 m from the spawn, off to the side (not in view from the spawn). | Anywhere in the **Sanctum** (the 10 m spawn zone; `EconomyRulesDef.shop_in_sanctum`, data-driven) **and** on the Armory pad. A fresh spawn can open the shop at once, like the LoL fountain. |
| Where the pad is | (19, -17) next to the old Armory building. | (8, -12): at the Sanctum's edge, about 45 degrees right of a fresh spawn's view (`ARMORY_X / ARMORY_L` in `tools/maps/build_shardline_front.gd`, `HqDef.armory` in `map_front.tres`). |
| What you see | A blue box, a light column and an "ARMORY" label. | A **neon gun shop stall** on the hero pipeline (art bible §6.5): counter with display windows of crystals and chips, cash terminal, weapon racks, a holo display wall, workbench with a gun in a vice, crates, a canopy with a team neon fringe and a sign board carrying the "ARMORY" label. The pad ring, the light column, the HUD prompt and the off-screen waypoint stay. |

The stall is visual only (no collision), so the navmesh is unchanged. The old
Armory building and its counter stay as HQ structure until the HQ set pass.

## Brief

| | |
|---|---|
| Read | "Shop": guns on racks, glowing goods in display windows, a sign. Team neon on the fringe, sign frame, strips. |
| Scale | Counter 5 m x 1.2 m high, canopy 3.6 m, sign board top at 4.95 m; with the workbench and crates 7.6 m wide. |
| Built by | `tools/art/world/armory_stall.py` (seed 4401), one piece. |
| Runtime | `ArmoryMarkerView`: the stall 2.5 m behind the pad centre, counter facing the Sanctum. |

## Review log

Findings per iteration are appended below.

### Iteration 1 (2026-10-06): first bake

Build: 9,652 tris, 1024 maps. Opened `production/qa/evidence/p6b/after/
fp-spawn-a, armory-mid, armory-approach.png`.

- `armory-mid`: reads as a shop: racks, glowing display wall, counter,
  workbench, sign board with the ARMORY label, the beacon column and the pad
  ring in front.
- `fp-spawn-a`: from a fresh spawn the stall is at the right edge of the view
  (about 45 degrees off the spawn's facing): you see part of it and the beacon,
  not the whole stall. Further into the view would put it on the path to the
  South gate; kept here. The HUD Armory prompt shows at the spawn because the
  Sanctum is now the buy zone (covered by `armory_reach_test.gd`; the HUD frame
  itself was not captured).
- The stall is small next to the HQ walls (human scale counter); the old Armory
  building still stands behind it as plain structure.
