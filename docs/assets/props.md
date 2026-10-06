# World prop kit: design brief and review notes

Owner ask (2026-10-06): the map "needs some objects and more that you can
decide upon" (the world reads empty and flat).

## What changed

| | Before | After |
|---|---|---|
| Lane edges | Bare rails and parapets. | Street lamps every ~20 m on each edge of every lane and plaza; clusters (a head piece + up to 3 companions) every ~14 m per edge in lanes, ~9 m on plaza rims, ~6 m in HQs. |
| HQ courtyards | Two greybox crates. | Planters, benches, kiosks and cargo piles with team accents along the walls. |
| Flank paths | Bare. | Pipe clusters, cable runs, barrels, debris, drain puddles. |
| Roofs | Bare. | Almost unchanged: see "Still weak". |

All props are visual only (no collision); the navmesh is unchanged.

## Brief

| | |
|---|---|
| Kit | `world_props`, 17 pieces on one shared painted atlas (2048), hero pipeline (toon + ink hull, baked AO / edges / hatching): crate, crate_stack, barrel, debris, puddle, ac_unit, cable_run, pipe_cluster, barrier, bench, planter, street_lamp, holo_sign, antenna, roof_vent, kiosk (HQ), cargo (HQ). |
| Budget (art bible §10.6, env piece 200-5k) | 470-2,912 tris per piece, 29,674 for the whole kit. |
| Colour | Neutral stone / iron / chrome / brass plus olive, plum and slate paint. City neon only `sign_teal`, `sign_pink`, `holo_white`; lamp heads and sign boards above 4 m (§4.6 rule 3); teal hazard strips instead of amber. Team colour only on `kiosk` / `cargo`, which are placed only inside an HQ with that HQ's material (§4.6 rule 1). |
| Scale | Placement scale per piece (`WorldPropsDef.piece_scale`) against a 1.8 m hero: crate 1.1 m, barrel 1.1 m, barrier 1.0 x 2.3 m, AC unit 1.7 m, lamp 4.9 m, kiosk 2.15 m. |
| Built by | `tools/art/world/props_kit.py` (seed 7301, ~13 min bake). Long tubes and posts are built in short sections: the first bake laid one 3 m conduit island across the atlas diagonal and lost half the sheet (49.5 % used, then 65.1 %). |
| Runtime | `src/gameplay/views/world_props.gd` (`WorldProps.spawn(parent, map_def)`), rules in `assets/data/world/world_props.tres` (`WorldPropsDef`). Client only, not on headless clients; only on `map_front`. |

## The walk guarantee (props have no collision)

A wall prop is placed only when all of these hold (`WorldProps._fit_wall`):

1. It starts from a point on the border of the walkable navmesh (agent radius 0.5 m).
2. A horizontal ray from the floor at 0.6 m along the border's outward normal hits a vertical collision face within 1.6 m (the "edge": wall, railing, kerb, parapet, deck lip), and the same face is hit at 0.5 m height (`min_wall_h_m`) and straight for at least 1.6 m around the prop (`min_anchor_len_m`; a lone crate or post in the open is never an anchor). Invisible rail edge-blockers are ignored.
3. The prop's back goes on that face; its floor footprint is at most 1.2 m deep from it (`max_wall_depth_m`). Lamp and sign posts use their 0.5 m base as footprint (their arm / board is above head height).
4. The floor under every footprint corner exists, varies by at most 0.45 m (slopes), and the box over the whole mesh bounds overlaps no collision.
5. Final check, the rule itself: from every footprint corner a ray towards the wall hits it within 1.2 m.
6. Keep-out (`WorldProps.excluded`): hardpoint zones + 3 m, Armory pad 7 m, spawns 3 m, Sanctum + 2 m, Uplink 9 m, Foundry 6 m, lane gates 9 m, side / flank doors 5 m, Barricade sockets 7 m, Cell Cradles, Supply Caches, Garrison posts 4 m, and the **lane corridors**: no footprint corner within 4 m of a lane's polyline (HQ A gate -> its five hardpoints -> HQ B gate).

So a prop only ever fills the strip along an edge that the navmesh's 0.5 m agent radius and the edge already make awkward to walk. Heroes brushing along a wall can clip through the outer 0.7 m of a prop (no collision); bots path on the navmesh centre lines and do not.

Roof props stand on flat tops at 7.5 m and up that lie on no walkable navmesh polygon (main + jungle), with the roof extending 0.4 m past the footprint. The navmesh includes most wall tops, so this places only 3 props (see "Still weak").

Determinism: every random choice is seeded by `placement_seed` and the spot's position; the piece weights are walked in alphabetical order (they were walked in StringName pointer order, which changed from process to process; caught when two renders disagreed; regression test below). Three separate processes give the same placement fingerprint.

## Tests (`tests/unit/views/world_props_test.gd`, on the real map and its collision)

| Test | Watched fail by |
|---|---|
| `test_placement_same_seed_same_props` | seeding with `randi()` |
| `test_count_within_budget` (300..800) | capping placement at 40 |
| `test_no_footprint_in_hardpoint_zone_armory_or_spawn` | `excluded()` returning "" |
| `test_footprints_off_lane_corridors` | same |
| `test_excluded_spots_return_rule_name` | same |
| `test_wall_props_stay_in_the_wall_strip` (re-measures every footprint corner against the geometry) | pushing props 1 m off the wall; it also caught a real bug: on slopes, footprint corners had no wall within 1.2 m (fixed with check 5) |
| `test_roof_props_off_walkable_navmesh` | dropping the navmesh check |
| `test_team_pieces_only_in_own_hq` | giving team pieces the neutral team |
| `test_other_map_spawn_returns_null` | dropping the `map_id` guard |
| `test_pick_walks_weights_alphabetically` | the old StringName sort |
| `test_kit_and_rules_load_present` | (presence check) |

## Perf

Whole map: 623 props (171 lamps, 102 barrels, 79 planters, 77 crates, 63 benches, ...; lane 171, plaza 301, HQ 97, flank 51, roof 3), 865k tris in total, placement 0.3-0.75 s once at match load (border walk + about 30k physics rays and shape queries).

Rendering: one `MultiMeshInstance3D` per (piece, team, 40 m cell), toon material + ink hull (2 passes), visibility range 80 m for pieces under 1.5 m (no shadow casting) and 220 m for tall ones (lamps, signs, antennas cast shadows).

Lane view (`fp-lane-center`: 80 m ahead, 80 m wide): **64 instances, 92.5k tris, 26 batches** (about 52 draw calls with the hull pass, plus shadow passes for the tall batches). Against the §10.6 scene budget (2,000 draw calls, 3.5 M visible tris) that is about 2.6 % of draw calls and 2.6 % of tris. Unmeasured on a real GPU (software Vulkan only).

## Review log

### Iteration 1 (2026-10-06): first bake + first placement

Opened `p7-props/after/fp-lane-center.png`, `base-a.png`, `fp-lane-south.png`, `mid-hardpoint-mid.png`; compared with `p5-world/before/`.

- `base-a`: lamps stood next to the greybox crates in the HQ courtyard: a crate counted as a "wall". Fixed (edge height + straight run).
- `fp-lane-center`, `fp-lane-north`: no props near the camera. Cause: wall probes started at the navmesh height (about 0.5 m over the floor), i.e. at 1.1 m, over the top of the 1.1 m rails. Fixed (measure from the floor).
- Atlas: first bake 49.5 % used (one long conduit island on the diagonal); re-baked with sectioned tubes, 65.1 %, islands spread over the sheet.

### Iteration 2 (2026-10-06): lead review (lanes, density, scale)

Lamp pass, clusters, slopes, placement scale. Opened `fp-lane-center`, `fp-lane-north`, `fp-lane-south`, `fp-spawn-a`, `base-a`, `mid-hardpoint-mid`, `hold-approach`, `topdown` (all in `production/qa/evidence/p7-props/after/`).

- `hold-approach`: reads as a street: lamps on both sides at a steady rhythm. Clusters are thin in this stretch (a barrier at the right edge, small pieces further down); the lamps carry it. Best frame of the set.
- `mid-hardpoint-mid`: plaza rim dressed (lamps, crates, benches, planter, kiosk-sized pieces) while the zone itself stays clear.
- `fp-lane-center`: crates and barrels at the right parapet, lamps along the left edge into the distance. The near-left of the camera stays bare: that stretch is the Barricade-socket keep-out of the Mid.
- `fp-lane-north`: one crate cluster and a lamp near the camera; the bridge stretch is sparse because the Outer's zone and socket keep-outs cover it.
- `fp-lane-south`: one lamp only near the camera (keep-outs again); the south lane's pipe / barrel identity does not show in this preset.
- `base-a`, `fp-spawn-a`: kiosks, planters, cargo with team trim along the HQ walls; the two big brown crates in the courtyard are the map's greybox, not this kit.
- `topdown`: props are too small to read at 520 m (expected).

### Still weak

- Roofs: 3 props. Most building and wall tops are part of the baked navmesh, so the "off every walkable surface" rule rejects them. A roof pass needs a list of truly unreachable tops from the map generator.
- Props beyond railings on non-walkable ledges (lead suggestion) are not done.
- `cable_run` (8) and `holo_sign` (8) are rare: they need a 2.4 m wall / a long straight edge.
- Lamp heads are emissive but cast no light (no `OmniLight3D`); a light per lamp would cost far more than the props.
- The near field of the `fp-lane-*` presets lies in keep-out zones (hardpoint + socket), so those frames understate the lane dressing; `hold-approach` shows it better.

## Part 4 finish (2026-10-06)

- Placement goes through the shared validator (docs/placement.md): 444 props
  after the gate (lane 140, plaza 201, HQ 95, flank 5, roof 3; was ~620 before
  the gate, the rest stood on slopes or overlapped). Rejections are logged per
  rule (`WorldProps.rejects`, `implausible_<rule>`).
- LODs: engine-generated mesh LODs (`generate_lods`), plus range culling per
  40 m chunk (small 80 m, tall 220 m). MultiMesh per piece / team / chunk.
- Collision: none on dressing props (they stand in the wall strip, off routes);
  the map's cover boxes keep their collision and get kit crates
  (CoverDressing).
- Outlines x0.6 of the hero width (docs/shading-audit.md).

