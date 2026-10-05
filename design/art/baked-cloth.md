# Baked cloth: bone contract for the glb builder (W16)

Builder: `tools/art/cloth_bake.py` (called by `tools/art/hero_gen.py` for heroes on the
`"pipeline": "gen"` path). Runtime: nothing new. The glb carries plain bone animation, so
`RiggedHeroModel` plays the cloth like any other track: no simulator, no per-tier cost,
identical on every machine.

## Naming
`Cloth_<part>_<chain>_<n>`, n = 1.. from the garment's top row to its hem; `chain` is the
name given in the hero's `cloth` spec (Vesper: `FR, BR, B, BL, FL`). The root (n = 1) is
parented to the spec's `parent` bone (default `Hips`). Chain bones are connected head to
tail and keyed with **rotation only**.

## How a garment is made and baked
1. **Geometry.** A skirt garment is a grid around the hips (rows from `top` to `hem`,
   columns every `col_deg`, an open front and slits as specified). It is emitted as a
   *thick, layered* solid: main shell (`thick`, outer colour / inner lining / rim), a
   raised hem band and front-edge trims. Every vertex is skinned from its grid cell: two
   chains across (linear by angle, never across an open slit), two bones along (soft
   blend at the joints), and a soft root blended into the parent bone over the top rows.
   At most 4 influences.
2. **Simulation.** Per clip, a single-layer proxy of the grid (top row pinned and
   skinned to the parent bone) runs a Blender cloth sim against a ~3k-tri copy of the
   skinned body (shells included). The body is driven per frame from the clip's sampled
   pose (a `frame_change_pre` handler), after a 24-frame pre-roll on the first pose.
3. **Bake to bones.** Every frame each chain bone is aimed at the simulated proxy node
   below it; its twist follows the proxy tangent across the columns. The rotation is
   keyed into the clip.
4. **Loops** (`LOOP_CLIPS`: idle, walk, run, run_back, strafes, crouch idle/walk,
   showcase) simulate two passes after the pre-roll and keep the second. The last 8
   frames are blended toward the first frame (a quaternion offset with smoothstep
   weight), so frame N equals frame 0 and the loop has no pop.
5. **One-shots** (casts, shoot, hit, reload, jump, death, death_back) keep the pre-roll
   and the single pass. Aim clips are 1-frame poses and are simulated anyway (cheap).

## Relation to `Sec_` spring bones (design/art/secondary-motion.md)
**A part is either baked cloth or spring, never both.** Use baked cloth for large,
body-hugging garments that must collide with the legs (coat skirts, long tails, capes).
Use `Sec_` springs for small danglers whose motion depends on runtime movement (antennae,
straps, halo rings, packs). The gen pipeline never builds `Sec_` chains for a part listed
in `cloth`, and the unit test `test_gen_pipeline_vesper_has_baked_cloth_bones` fails if
a gen hero carries both kinds.

What baked cloth gives up: it is authored per clip, so blends between clips (AnimationTree
crossfades, the loco blend space) blend bone rotations, not a live simulation. It never
reacts to knockback, wind or speed changes beyond the clip. In return it costs nothing at
runtime and always looks the same as in the evidence renders.

## Budget
- Skeleton: GAME_BONES (20) + Weapon + cloth bones. **Cap 42 bones**, as in
  secondary-motion.md. Vesper: 5 chains x 3 = 15 -> 36 bones.
- Bake time: about 1 min per hero for 22 clips (Vesper, 4-core CPU). It is printed as
  `cloth: baked N clips in S s (per clip)` and in the `timing` line.
- glb size: about +0.2 MB for 15 keyed rotation tracks over all clips.
