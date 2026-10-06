# Polish backlog

Known issues below the hero standard, found while working. Each line: what,
where, how it was found, and what would fix it. Newest at the bottom of each
section.

## World / map

- **Navmesh slivers past ramp side edges.** 4 polygons (mirrored pairs at
  x≈93.4, z -324.5 / -95.6 and -219.4 / -199.8) reach ~0.3 m past the
  `Ramp` / `RampB` side edges over a 1.4 m drop. Found by
  `scene_validator_test` (waived there). Fix: re-bake the Shardline Front
  navmesh with a larger edge erosion, or a low kerb on those ramp sides.
- **Cover boxes overhanging edges.** 6 low cover boxes (mirrored: -4/-58 and
  -4/-362 on a step edge; ±42/-98 and ±42/-322 ~0.6 m over a ledge) hang off
  their floor; the new kit crates show it as plainly as the greybox did. Waived
  in `MapPlacementAudit.WAIVERS`. Fix: move them inward in
  `tools/maps/build_shardline_front.gd` and rebuild the map (cover gameplay:
  check sightlines after).
- **Thin 0.4 m cover walls stay greybox** (16 boxes, 0.4 x 1.0 x 4.0): no kit
  piece fits without distortion. Needs a low-wall / sandbag kit piece.
- **Mana Uplink legs look streaky** at mid range (owner note).
- **Floor parallax** streaks on grates and trenches at mid range; busy from
  above; hazard stripes alias (docs/assets/floor.md review log).
- ~~Map-scene greybox crates~~ dressed with kit crates (CoverDressing, Part 4);
  their boxes are in the placement gate.
- **Props sparser after the placement gate**: ~180 implausible props were
  dropped (mostly on ramps / slopes). Lanes need slope-aware pieces or more
  wall-strip candidates (Part 4).
- **Lamps cast no light**; cable runs and holo signs are rare; few roof props.

- **Leap can land on roofs.** Earthbreaker's leap (`AbilityWorld.start_leap`)
  targets any surface the aim ray hits, not only walkable ground, so a hero can
  reach rooftops. Roof props have no collision (visual only), so the roof limit
  stays at 7.5 m (only 3 roof props today). Fix: clamp leap targets to the
  walkable navmesh, then roof props can go lower and denser.
- **Forward Beacon banner weak at mid range** (Part 6, `beacon-mid` shots): at
  17 m the 1.5 m banner is thin and stands next to the Holdstone's light
  pillar on the Spindle. Fix: wider banner or a second banner on the crossbar,
  a different silhouette (rings instead of a column), or place the pad off the
  pillar's line of sight. Motion (blink, build-up) still needs a look in a
  running client (docs/manual-checklist.md).
- **Beacon spawn height**: `ProgressionSystem.beacon_point` spawns at the
  Mid's floor height + 5 cm; on the Spindle the spot is on the 0.3 m Holdstone
  dais, so the hero starts inside the dais lip and is pushed up by the
  physics. Harmless today; better: spawn at the pad (ground ray) position.
- **Supply Cache vs kit crates** (Part 6, `supply-mid`): at mid range the
  cache crate resembles the cover-dressing crates beside it; the label carries
  it. Fix: a taller silhouette (ammo rack / belt arch) or keep cover dressing
  away from cache spots.
- **Supply Cache colliders are not in the navmesh**: bots rely on stuck
  recovery near the 15 crates. Fix: add the colliders to the map build and
  re-bake `shardline_front_navmesh.res`.
- **Bots do not seek Supply Caches** for ammo yet (`bot_brain.gd`).
- **Props on slopes are skipped**: ~250 candidates a run sink 8-12 cm into ramps
  and are rejected (correctly). Slope-aware pieces (wedged crates, ramp rails)
  would fill the ramps; today the props sit on the flat parts.

## Characters

- **Syndicate Wardling colours** read muted next to Concord (gunmetal + rust).
- Wardling animation not captured in motion (poses only); perf numbers still to
  measure cleanly (Part 5).

## Engine / tooling

- Godot warns "AnimationNodeBlendSpace*::add_blend_point: No name provided" for
  every rigged model (hundreds of lines per match in the player log). Pass point
  names in RiggedHeroModel's blend space setup.
- "It's not expect to not find the most reachable polygons" navigation errors
  in bot matches (player log 2026-10-06): bot path queries from off-navmesh
  points. Snap query start / end to the navmesh first.
- "Invalid polygon data, triangulation failed" (canvas) in matches: a HUD
  polygon with degenerate points (minimap or ability arc).
