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
