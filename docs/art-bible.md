# World art bible (fidelity rules for objectives, structures, props, terrain)

The visual identity, palette, shape language, environment design and VFX
language live in **`design/art-bible.md`** (binding; section numbers below point
there) and the hero rules in `design/art/hero-art-bible.md`. This page adds the
**production rules that make the world match the heroes**, measured against
them (`docs/fidelity-baseline.md`). Owner decision 2026-10-06: the world uses the
heroes' painted toon language, not realistic PBR.

## 1. One pipeline, one material

- Every world asset is built by the hero pipeline (`docs/model-pipeline.md`,
  `tools/art/world/`): Blender `bpy`, painted-light bake, glTF.
- Runtime material: `spatial_char_toon_rigged` with maps (+ the
  `spatial_char_outline_hull` ink pass), like the heroes. No unshaded materials
  on solid world geometry; unshaded is for holograms, beams and UI-like markers only.
- Texture contract (same as heroes): `<asset>_albedo.png`, `_normal.png`,
  `_mask.png` (R AO, G spec / chrome glint, B emissive, A team-colour zone).
  Painted light, AO, curvature edge highlights, crease ink, hatching (shadow
  side only) and wear are baked into albedo.

## 2. Texel density and texture sets

| Class | Target px/m (at the 1024 map scale) | Texture set | Why |
|---|---|---|---|
| Hero (reference) | 256-493 (typ. 350) | 1024 / 1024 / 512 per hero | measured |
| Hero-scale objects seen up close (Cell, Cradle, Supply Cache, Garrison socket, Barricade, Generator core) | 256-400 | own 1024 / 1024 / 512 | read like gear next to a hero |
| Landmarks (Uplink, Holdstone, Ward Generator dome frame, Foundry, Armory) | 128-256 on the large forms, 256+ on the eye-level parts (base, plinth, controls) | own 2048 albedo / 2048 normal / 1024 mask, or 1024 + a shared trim sheet | large; detail where the player stands |
| Modular kit (walls, floors, cover, stairs, rails, ruins) | 128-200 | shared trim sheets per faction + neutral, 2048 (design §10.6) | instanced; texture memory |
| Terrain / plaza floors | 64-128 + tiling detail | shared tiling set | big flat areas stay calm (§6.1 two-layer rule) |

## 3. Detail rules (beyond primitives)

- **Layered forms:** each asset reads at 3 scales: primary silhouette (30 m),
  secondary masses (10 m: plates, rings, braces), tertiary detail (2 m: rivets,
  seams, vents, cables, wear). No asset ships with only primary forms.
- **Bevels:** every hard edge gets a bevel or chamfer (`hero_hd.piece(bevel=)`):
  0.3-0.4 of the edge on small parts, 2-4 cm on large forms. Bevels catch the
  baked edge highlight; this is the single biggest cue that separates the heroes
  from the world today.
- **Asymmetry and wear:** seeded variation (no two crates alike), edge chips and
  scratches from `hero_decals.wear/scratches`, grime in creases, stronger on the
  Syndicate side (riveted, scuffed) than on Concord (clean, flush seams), design §3.2.
- **Grounding:** every object sits in the floor: a footing, a trim ring, rubble
  or a decal. Nothing floats; nothing stands on a flat floor without a base.
- **Damage stages:** swappable meshes per stage (intact / cracked / failing /
  destroyed rubble) baked in the same build, same UV layout where possible.

## 4. Silhouette, scale, readability

- Scale reference: the 1.85 m hero (Ryker), Brannoc 2.2 m. Doors >= 3 m, cover
  1.1-1.3 m (crouch cover) or 2.2 m+ (full), steps 0.2 m.
- Task objects: unique skyline silhouette readable at 80 m (design §6.3: Hold =
  vertical beam, Plant = "Y" pylon, Breach = dome). Keep these silhouettes; add
  fidelity inside them.
- The playable layer (floor to 4 m) stays calm: big readable masses, neutral
  `halcyra_stone` floors, detail at cover edges and eye level (design §6.1).
- Readability checks: `tools/shot.gd` presets `-far` (35 m) and `-approach`
  (first person 18-25 m) must show the object's kind and owner.

## 5. Colour, emissive and VFX ranges

- Palette, team colours and hue exclusion bands: design §4.1-4.3 (Concord
  `azure_core #2E86FF`, Syndicate `ember_core #FF5A1F`, neutral `leyfall_violet
  #8E5CFF`, floors `halcyra_stone #B9B2A6`). No world decoration in the team hue bands.
- **Reserved danger colour:** `warning_white #FFFFFF` with a dark stroke for
  danger telegraph cores (design §4.2); never decoration.
- Team-colour coverage on objectives: owner colour only on emissive parts
  (mask A = team zone, B = emissive), so ownership swaps by uniform (design §6.1:
  1.5 s swap on flip).
- Emissive tiers (design §4.6): Signal (objective state, may bloom) > Accent
  (trim, capped) > Set-piece (HQ, always truthful). World emissive values: albedo
  value 0.85-1.0, mask B 1.0, shader `map_emission` 1.6; no surface above the
  glow HDR threshold (1.1) except Signal-tier cores.
- Ally vs enemy effects, telegraph rules, glitch vocabulary: design §8.1-8.2.
- Effect timing stages for objective events: anticipation 0.3-0.6 s (wind-up,
  telegraph on the hitbox), cast/trigger 0.1 s, travel by speed, impact <= 0.2 s
  peak, fade 0.4-1.0 s. Hit effects <= 1.0 s (design §8.3).

## 6. Budgets and LOD tiers

| Class | LOD0 tris | LOD1 (~25 m) | LOD2 (~60 m) | Materials |
|---|---|---|---|---|
| Uplink | <= 80k (design §10.6) | 40% | 10% / impostor beyond 150 m | <= 4 incl. holo bands |
| Landmark (Holdstone, Generator, Cradle, Foundry, Armory) | 8k-25k | 40% | 10% | 1 + holo |
| Hero-scale prop | 1k-6k | 50% | 15% | 1 |
| Modular kit piece | 200-5k | 50% | 15% | 1 (trim sheet) |

LODs are built in the same bpy run (decimate) and exported as `<asset>_lod1/2`
meshes; Godot `visibility_range` switches them. Collision: `-col` / `-colonly`
nodes, convex where possible. Particles: <= 64 per effect, <= 2 overdraw layers,
<= 1 light without shadows (design §8.3).

## 7. Review rule

An asset is done when its `tools/shot.gd` presets were rendered (Forward+,
lavapipe) and looked at next to `hero-ref`, findings are in
`docs/assets/<asset>.md`, and the asset validator passes (scale, pivot, tris,
maps, LODs, collision). What a virtual display cannot judge goes to
`docs/visual-review-checklist.md`.
