# Placement rules (physical plausibility)

Owner rule (2026-10-06): every placed world object must look like it could
really stand there. One shared helper places things, one validator checks
them, and CI fails on any violation without a written waiver.

| Piece | Where |
|---|---|
| Helper (snap, align, support, overlap, footprint, OBB) | `src/gameplay/world/placement/placement_kit.gd` |
| Validator (rules below) | `src/gameplay/world/placement/placement_validator.gd` |
| Numbers (tolerances) | `assets/data/world/placement_rules.tres` (`PlacementRulesDef`) |
| Map audit + waivers | `src/gameplay/world/placement/map_placement_audit.gd` (`WAIVERS`) |
| CI gate | `tests/integration/world/placement_map_test.gd` |
| Report | `godot --headless --path . -s res://tools/validate_placement.gd -- --out reports/placement.txt` |
| Close-ups of a spot | `tools/shot.gd -- --out <dir> --at x,y,z` (low camera, 3.5 m away) |

## Rules

| Rule | Meaning |
|---|---|
| `grounded` | Base within 8 cm of the surface under its centre. |
| `supported` | At least 4 of 5 base probes (corners + centre) on that surface; for a lamp the real base, not the arm's bounds. |
| `mounted` | Wall-hung items: wall within 12 cm behind them at 1/4 and 3/4 height. |
| `upright` | Tilt at most 10 degrees. |
| `no_overlap` | Bounds (shrunk 5 cm a side) clear of level collision and of every other prop. |
| `scale` | Height between 0.08 and 3.2 hero heights (1.8 m hero). Flat sheets (puddles) are exempt. |
| `faces_floor` | Kiosks, terminals, signs: open floor 0.8 m in front of their face. |
| `keep_out` | Not in hardpoint zones, Armory pad, spawns, Sanctum, Uplink, gates, sockets, lane corridors (`WorldProps.excluded`). |
| `decal_surface` | A floor under the decal. |
| `decal_clear` | Inside the decal's box: no ledge or step above its floor, no drop below it, no prop; a wall only if the decal fades on steep surfaces (`normal_fade` >= 0.3). |

## How placement uses it

`WorldProps.place` runs every candidate through `PlacementValidator.check_item`
and the prop-vs-prop test before accepting it, and keeps props off the decals'
boxes; `WorldDecals` builds only decals that pass. So the shipped map has zero
violations by construction, and the CI gate proves it stays that way.

## Waivers

Add `"<id prefix>": "<reason>"` to `MapPlacementAudit.WAIVERS`. Waived items stay
in the report marked `(waived: reason)`. Today there are none.

## Not covered yet

Functional logic beyond mounting (lamps wired to a power source, cables between
two real anchors), objective dressing (it lands with Part 6), and props on the
map scene itself (greybox crates in the HQs). Tracked in PROGRESS.md.
