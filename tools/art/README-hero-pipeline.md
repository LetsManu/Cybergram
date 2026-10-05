# Hero pipeline (W16): bespoke bodies, painted textures, baked cloth

Rebuild guide for the seven heroes. Vesper Loom is the reference hero: her definition is
`hero_defs_gen.py` and her output is `assets/models/heroes/vesper/`. The other six still
build on the old MakeHuman path until their entry gets `"pipeline": "gen"`.

## Setup and commands
```bash
python3.11 -m venv /tmp/venv && /tmp/venv/bin/pip install bpy pillow    # Blender 5.0 as a module
tools/art/fetch_mocap.sh            # CMU BVH -> tools/art/.cache/cmu (the gen path needs no MakeHuman)
tools/art/fetch_base.sh             # only for heroes still on the old path / --legacy
/tmp/venv/bin/python tools/art/build_hero.py vesper          # -> assets/models/heroes/vesper/*
#   --notex     no texture bake (fast geometry iteration, ~20 s)
#   --nocloth   skip the cloth bake (garments stay rigid on their bones)
#   --legacy    build the hero's old MakeHuman entry (before/after renders)
#   --scripted  no mocap;  --out <dir>  another output root
#   HERO_DEBUG=<dir>  dumps the bake passes (<key>_w16_passes.npz) for paint look-dev
godot --headless --path . --import && tools/art/tex_import.sh && godot --headless --path . --import
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
  -s res://tools/art/render_turntable.gd -- --hero vesper --out production/qa/evidence/<dir>
#   -- --strip res://assets/models/heroes/vesper/vesper.glb --clip run --tag vesper_strip
#   -- --map res://assets/maps/slice/shardline_causeway.tscn --at 0,-118
```
The build prints a timing line per hero, for example
`timing vesper: body 0 s, paint 0 s, parts 0 s, rig 0 s, texture 199 s, anims 6 s, cloth 54 s, export 5 s, total 265 s`
(4-core CPU, Cycles on CPU). Texture and cloth are almost all of it. Iterate with
`--notex --nocloth` and use `hero_paint.recompose(npz, key)` to re-paint without
re-baking.

## Defining a hero (`hero_defs_gen.py`)
Copy the Vesper entry. Same keys as the old path, plus `pipeline`, `body`, `paint`,
`cloth`, `idle` and `legacy`:

| Key | What |
|---|---|
| `pipeline` | `"gen"` selects `hero_gen.build` |
| `legacy` | the old entry (`hero_defs.HEROES[key]` before the override) for `--legacy` |
| `height` | metres; every body length scales by height / 1.85 |
| `body` | body params (below) |
| `palette` | name -> hex; keep <= 5 colours + team + chrome; bright, saturated |
| `cuts`, `regions`, `shells` | colour blocks on the body: bisect planes, a region painter per face (bone, centre, normal), armour shells offset from picked faces. Same API as the old path; body faces under a shell are culled. |
| `parts(h)` | mask/helmet, hair, gear: `h.box/cyl/sphere/torus`, `h.surface()`, `hero_hd.ring/strap/piece/BodySkin` for body-hugging pieces. **Every hero wears a mask or helmet: never a face.** |
| `weapon` | key into `WEAPONS`; write the hero's own builder (weapon space: origin = right grip, +Y barrel, +Z up). The gen path does **not** add the generic `hero_hd.weapon_detail` kit. |
| `cloth` | garments (below) |
| `stance` | grips, poles, `two_handed`, `left_free` (pos, finger dir, palm normal) |
| `idle` | optional `fn(poser, phase, frame)` personal idle. Only legs, hips, spine and chest show in game, because the upper body is the aim layer. |
| `gait`, `casts` | as before |

`Sec_` springs on the gen path: call `_springs(h, specs)` from the parts function (see
`hero_defs_gen_a.py`). Mask close-ups and lane shots: `tools/art/render_hero_closeup.gd`
(`-- --hero ryker [--lane res://assets/maps/slice/shardline_causeway.tscn]`).

The hero key must be in `ModelCatalog.HERO_KEYS`. No game code changes.

## Body params (`body_gen.DEFAULT_BODY`, metres at 1.85 m)
- **Lengths:** `leg` (hip-joint height), `thigh_frac`, `ankle`, `torso` (hip joint to
  neck base), `neck`, `upper_arm`, `forearm`.
- **Head:** `head_h/w/d` (hidden by the mask, but it sets the mask size).
- **Widths and depths (full):** `shoulder_w` (joint to joint), `chest_w/d`, `waist_w/d`,
  `hip_w/d`, `hip_joint_w`.
- **Radii:** `neck_r`, `arm_r`, `forearm_r`, `wrist_r`, `thigh_r`, `knee_r`, `calf_r`,
  `ankle_r`.
- **Borderlands chunk:** `hand` (mitt scale, 1.25-1.4), `foot` (boot scale), `boot_r`
  (shaft girth).
- **Sculpt (0..1 blobs along the normal):** `deltoid`, `pecs`, `bust`, `glutes`,
  `calves`, `forearms`, `traps`; `muscle` scales them all.
- **Shape:** `boxy` (superellipse exponent, 2 = round, 2.6 default = slightly square).
- **Posture:** `arm_angle` (A-pose, degrees below horizontal), `chest_lean`, `chest_lift`,
  `shoulder_raise`, `stance` (foot spread), `head_fwd`.
- **Density:** `subdiv` 1 (default, body ~4.4k tris) or 2 (~17.6k, too heavy with gear).

How it works: 8-vertex superellipse rings, lofted into one quad cage. Limbs join through
sockets cut in the torso and crotch loops, so there are no intersecting primitives. Then
Catmull-Clark subdivision, flat soles, and gaussian proportional edits. Weights are heat
weights on a temporary armature with GAME_BONES names, then smoothstep re-blends across
the shoulders, elbows, wrists, hips, knees and ankles, capped at 4 influences. UV seams
are placed on the cage (torso front/back halves, under the arms, inner legs, wrists,
ankles, soles, back of the head).

## Texture paint controls (`hero_paint.DEFAULT_PAINT`, per hero in `paint`)
- **Painted light:** `key_dir` (top-down front key), `terminator`, `soft`, `lit`,
  `shadow`, `warm`, `cool`, `top` (height falloff).
- **Creases:** `ao`, `ao_dist` (keep it short: 2.5 cm; long reach darkens garment gaps
  in blotches), `crease_ink`.
- **Hatching (sparse, shadow side only):** `hatch`, `hatch_threshold` (N.L where it starts;
  keep it below `terminator - soft`), `hatch_fade`, `hatch_density` (share of the zone in
  stroke clusters), `hatch_spacing` (2.4 cm), `hatch_width`, `cross`.
- **Runtime shader overrides:** `paint.shader` = {uniform: value}. It is written to
  `<id>_anim.tres` and applied by `RiggedHeroModel` for this hero only (Vesper:
  `hatch_strength` 0.1, because the hatching is painted).
- **Painted mask / helmet detail (W16-HERO-A):** `paint.post` = `fn(ctx) -> (albedo, spec, emit)`,
  run at the end of the composite. `hero_decals.py` gives `region`, `bounds`, `wear` (edge
  chips), `scratches`, `decal` (planar stencils: digits, chevrons, tally, holes, dents,
  pixel faces) and `gloss` (mask G). Examples: `hero_defs_gen_a.py` (Ryker, Brannoc, Hex).
- **UV packing:** `uv_max_tries` (default 30) raises the pack attempts for gear-heavy heroes.
  Full ring bands from clipped spheres unwrap fine, but a clipped dome can collapse to a
  zero-area island and drop the atlas to ~14 %: use a bevelled box cap instead.
- **Highlights and ink:** `edge` (convex edge strokes), `ink`, `ink_border`, `ink_px`
  (colour-block borders), `grit`.
- **Normals and UVs:** `normal_bump` (detail-only normal map), `uv_margin`.
- **Masks and helmets (W16-B):** `uv_head` scales the Head-bone UV islands before the pack
  (1.6 = 2.6x the texels on the mask); `detail` is a `fn(ctx)` hook that paints markings,
  wear, scratches, sheen (mask G) and emissive lines onto the flat colours before the
  painted light, using `tools/art/mask_paint.py` (Region, line, blob, edge_wear,
  scratches, crack). Colour-border ink follows the modelled colour blocks, never the
  painted detail. Examples: `vesper_mask_paint`, `liora_paint`, `sable_paint`,
  `juniper_paint` (`hero_defs_gen_b.py`). Close-ups: `render_hero_extra.gd -- --close`.

The output keeps the W14 contract (`<key>_albedo/_normal/_mask.png`, mask R AO, G spec,
B emissive, A team), so `spatial_char_toon_rigged` and `RiggedHeroModel._bind_maps` are
unchanged. A lite install without the `heroes_hd` pack still falls back to flat colours.

## Cloth parts (`cloth` list; contract: design/art/baked-cloth.md)
`{"part", "kind": "skirt", "top", "hem", "offset", "flare", "clear", "open_front",
"slits": [(deg, frac)], "chains": [(name, deg)], "bones", "rows", "col_deg", "thick",
"colors": {outer, inner, hem, trim}, "sim": {...}}`. Angles: 0 = front, +90 = the hero's
right. Capes, mantles and scarves: `"parent": "UpperChest"` and `"around"` (the torso bones the
clearance rays hit; leave the shoulders out or the top rows fold). Closed rings
(`open_front` 0) can take `"convex": True` (no dent between the legs) and get four UV
seams automatically. Chains must not sit on a slit. Keep the total at 42 bones or fewer (20 body +
Weapon + chains x bones). A part is cloth OR `Sec_` spring, never both.

## Budgets and checks (Vesper)
| | Budget | Vesper W16 | Vesper v0.10 |
|---|---|---|---|
| Tris in view | <= 30k | 18.3k | 25.9k |
| LOD | ~8k | 8.0k | 8.0k |
| Bones | <= 42 | 42 (21 cloth) | 30 |
| glb + maps | < 8 MB | 2.3 + 1.8 MB | 2.9 + 2.3 MB |
| UV atlas used | >= 75 % | 76.6 % | 46 % |
| Build time | | 4.5-7.5 min | 2.3 min |

The build prints all of these. Run `tools/ci/run_tests.sh` (the rigged-hero suite checks
the tri budget, clips, cloth bones and death_back).

## Pitfalls
- **Objects removed in bpy stay in the view layer until `view_layer.update()`.**
  `_activate` now updates first. Do the same after your own removals.
- **Never leave a coincident copy of the body in the scene during the texture bake.**
  The cloth collider is unlinked until `cloth_bake.bake`; AO rays hit a coincident
  copy and paint blocky camouflage.
- **Unwrap on quads and triangulate after.** Triangulating first drops the atlas from
  76 % to 58 %.
- **Blender's UV packer is not deterministic.** `unwrap_pack` keeps the best of 10
  packs, so the reported use varies by about 1 % between builds.
- **Annulus and C-shaped islands (straps, collars, the coat bell) waste atlas space.**
  `_part_seams` cuts non-disk islands and `_split_low_fill` halves islands that fill
  less than 65 % of their box.
- **Only the Hips and the Weapon get location keys.** Anything else you `set_M` keeps
  only its rotation.
- **The idle's upper body never shows in game** (aim layer). Put the personality in the
  hips, legs and chest, and in the stance (`left_free`, `twist`, `grip_r`).
- **Strap colour picks the bake class.** `hero_hd.strap` with a palette colour is a
  "soft part"; gold reads as metal (spec band) through `hero_hd.METAL`.
- **`subdiv: 2` breaks the 30k budget once gear is added.** Add detail as parts instead.
- **Thin clipped-sphere rings and folded garment rows unwrap into giant UV islands** (one
  took Sable's atlas to 51 %). Use a torus for rims; degenerate garment faces are dissolved
  before the unwrap.
- **Big flat dark areas break the art-bible value rule.** Keep the bodysuit mid-dark and
  saturated (Vesper `#3D2C5F`), never ink black.
