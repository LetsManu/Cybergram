# Shading audit (2026-10-06)

Owner plan Part 3: audit every shader against the hero look, unify on one
shared toon model, set outline rules. Evidence frames:
`production/qa/evidence/shading/` (all opened; findings below).

## Assumption checked: the hero look is cel / toon

Yes. `spatial_char_toon_rigged.gdshader` (every hero, Wardling v2 and every
baked world asset through `WorldModel.material`) lights with a 3-tone cel ramp
(shadow / lit / narrow highlight band, softness 0.004), a lit-side team-tinted
rim, crisp metal highlights and an inverted-hull ink outline
(`spatial_char_outline_hull`, 2.8 px Concord / 3.2 px Syndicate).

## Inventory (what renders the frame)

| Class | Shader | Where | Before | Now |
|---|---|---|---|---|
| Opaque lit, characters + baked assets | `spatial_char_toon_rigged` | heroes, Wardlings, Uplink, Holdstone, Plant kit, Armory stall, props | cel ramp | cel ramp via `toon_common.gdshaderinc` (same math) |
| Opaque lit, map | `spatial_env_panel` | 2,128 map surfaces (floors, walls, decks) | smooth Burley diffuse: the map was the only lit surface not cel-shaded | cel ramp via `toon_common`, same defaults as the heroes |
| Opaque lit, procedural | `spatial_char_toon` | procedural fallback models (no glb) | own semi-cel | unchanged (fallback only) |
| Emissive / unlit | StandardMaterial3D unshaded, `spatial_env_ambient_neon`, `_skyline`, `_holo` | 1,080 map surfaces (skyline blocks, glow strips, trims, zone discs) | unshaded | unchanged: unlit is the emissive class |
| Alpha / FX | `spatial_fx_toon_cel`, `_holo`, `_crystal`, `armory_beacon`, `spatial_env_ambient_*` | ability FX, beacons, shields, fog, shafts | unshaded, banded | unchanged |
| Screen | `spatial_fx_ink_edges` | High / Ultra post pass | depth + crease ink | unchanged |

## Unified model

- **One cel function, one set of values:** `assets/shaders/toon_common.gdshaderinc`
  (`toon_shadow`, `toon_shade`, `toon_rim`; `TOON_*` defaults). The hero shader
  and the map panels call it; `tests/unit/models/shading_unified_test.gd` fails
  if their defaults drift (watched failing with a changed value).
- Factions keep their per-material shadow tint (ModelMaterials), as before.
- Classes: **opaque** = toon_common ramp; **emissive** = unshaded (team neon,
  trims, signage; brightness by the art bible's Accent / Signal tiers);
  **alpha** = the FX shaders (unshaded, banded).

## Finding fixed during the audit

A custom `light()` in Godot 4 must not multiply by `ALBEDO`: the engine
multiplies DIFFUSE_LIGHT by the albedo afterwards. The first panel version did,
and the whole map went dark (albedo squared; seen side by side in
`fp-lane-center`, old vs new render). The panel shader no longer does; a test guards it.
**The hero shader still does** (`ALBEDO * lc * shade`): heroes have been tuned
with that darker response since W13, so it stays as the approved look and is
noted here instead of "fixed" silently. Changing it means re-tuning every hero.

## Outlines

| Group | Width | Members |
|---|---|---|
| Heroes | 2.8 / 3.2 px (team) | all heroes; Wardlings and their props match |
| Gameplay-critical | hero width x 1.25 | Uplink, Holdstone, Cell Cradle, Mana Cell, Charge Cradle, Armory stall (`WorldModel.OUTLINE_CRITICAL`) |
| Dressing | hero width x 0.6 | world props (`WorldModel.OUTLINE_DRESSING`) |
| Map geometry | none (hull); ink edges post pass on High / Ultra | panels, walls |

## Seen in the frames (production/qa/evidence/shading)

- `fp-lane-center`, `fp-spawn-a`: walls now flat lit with crisp cast shadows,
  same shadow tone as the heroes. Floor mean brightness 92 (was 80; plain Lambert through the new path: 76): a bit
  lighter, pastel on large sunlit walls in `base-a`. Acceptable; if it reads
  washed in play, lower `highlight_boost` on the panel only.
- `armory-close`, `plant-mid`: objective outlines read first; props behind.
- Map-scene greybox crates have no outline (not WorldModel assets): backlog.
- `topdown`: no change in readability.

## Not done here

Procedural fallback shader (`spatial_char_toon`) still has its own ramp (only
used without the glb packs). Emissive tier brightness is not measured per
surface yet (Part 4 paint pass).

## Look-dev follow-up (2026-10-07, docs/lookdev.md)

- The panel shader gained look uniforms (wall value / saturation, albedo
  breakup, edge wear, contact AO + grime, a cel specular band, floor env
  specular); all default to the panel above, so the shared cel ramp and the
  hero-equal `TOON_*` defaults are unchanged (`shading_unified_test` still
  holds). The default `LookProfile` sets them per material at runtime.
- Panel shadow tone in the default look: value 0.45, tint (0.38, 0.42, 0.74)
  mixed 0.55: the same cool blue-violet family as the heroes' shadow tint,
  deeper value for light / shadow contrast. The hero shader is untouched.
- `specular_disabled` was removed from the panel's render mode: `SPECULAR` is
  written explicitly (0 except floors with `floor_env_specular`), and the cel
  spec band writes `SPECULAR_LIGHT` itself.
- Shadow casting: opaque panel meshes now all cast (Medium+), small world
  props cast on High+; Low gets blob shadows under characters.
