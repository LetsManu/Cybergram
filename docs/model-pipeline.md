# Model pipeline

One pipeline for everything with hero fidelity: **Blender 5.0 as a Python
module (`bpy`) under `tools/art/`**, painted-light texture bakes in Cycles, glTF
export, the `spatial_char_toon_rigged` material at runtime. Heroes use it today.
World assets (objectives, structures, props) move onto it in Phase 6
(`tools/art/world/`), sharing its bake and export code. Hero details:
`tools/art/README-hero-pipeline.md`.

## Setup (cloud VM or local)

```bash
tools/art/setup_pipeline.sh            # venv at $CYBERGRAM_VENV (default /tmp/venv): bpy 5.0.1, numpy, pillow
tools/art/setup_pipeline.sh --mocap    # + CMU BVH clips (heroes only), tools/art/.cache/cmu
```
Needs `python3.11` (the bpy 5.0.1 wheel is cp311) and network for the first
install. Idempotent. Verified in this cloud VM on 2026-10-06.

## Flow (heroes)

```
hero_defs*.py (body, palette, parts, cloth, weapon, idle)
  -> build_hero.py <key>
       body_gen.py    superellipse loft cage -> Catmull-Clark -> weights
       hero_hd.py     parts: box/cyl/sphere/torus + bevels, straps, rings
       cloth_bake.py  garment sim baked to bones
       mocap.py, hero_anims.py  22 clips (CMU BVH + authored)
       hero_paint.py  unwrap_pack (best of N packs) -> bake_textures (Cycles:
                      AO, curvature, painted key light, hatching) -> composite
       hero_decals.py, mask_paint.py  wear, scratches, decals, emissive lines
       glTF export (+ 8k-tri LOD mesh)
  -> assets/models/heroes/<key>/<key>.glb, <key>_albedo.png (1024),
     <key>_normal.png (1024), <key>_mask.png (512: R AO, G spec, B emissive, A team),
     <key>_anim.tres, <key>.anim.json
  -> godot --headless --import ; tools/art/tex_import.sh ; godot --headless --import
  -> runtime: RiggedHeroModel binds the maps to spatial_char_toon_rigged.gdshader
     (+ spatial_char_outline_hull ink pass)
```

## Verified run (this VM, 2026-10-06)

`/tmp/venv/bin/python tools/art/build_hero.py vesper --out <scratch>`:

| | Result |
|---|---|
| Output | `vesper.glb` 21,492 tris + 8k LOD, 42 bones, 22 clips, 2.54 MB; albedo 1.02 MB, normal 0.68 MB, mask 0.22 MB |
| Matches the committed asset | yes: committed vesper.glb has 21,500 tris, 42 joints, 22 clips (the UV packer is not deterministic, so maps differ slightly between builds) |
| Time | 296 s total (texture bake 230 s, cloth 53 s, anims 6 s, export 7 s); 4 cores, Cycles CPU |

## World assets (Phase 6, `tools/art/world/`)

Same code, different front end:

```
tools/art/world/<asset>.py   design brief -> parametric, seeded geometry
                             (hero_hd primitives + bevels, layered forms,
                             damage-stage variants)
  -> hero_paint.unwrap_pack -> bake_textures -> composite   (same as heroes)
  -> glTF export with LOD meshes and -col collision nodes
  -> assets/models/world/<asset>/<asset>.glb + _albedo/_normal/_mask.png
  -> runtime: the same spatial_char_toon_rigged material + ink hull
```
Rules for these assets: `docs/art-bible.md`. Baseline numbers: `docs/fidelity-baseline.md`.
