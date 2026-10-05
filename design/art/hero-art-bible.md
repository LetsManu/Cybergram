# Hero Art Bible — Toon Rigged Heroes (W13 pilot)

Status: PILOT (Ryker Vance, Vesper Loom). Owner reviews before the other 5 heroes.
Parent docs: `design/art-bible.md` (§3.3 role shapes, §4.7 signature colours, §5.2
silhouettes), `design/gdd/heroes.md`, `design/ux/mockups/v0.9/README.md` (UI palette).
This document replaces the "box model" look of `HeroModelBuilder` for heroes that have a
rigged `.glb`; it does not change any gameplay rule.

## 1. Style rules (toon / cel)

| Rule | Value | Why |
|---|---|---|
| Cel bands | 3 tones: shadow (x0.55), mid (x0.85), lit (x1.0); hard steps, 0.04 smoothing | Comic read, no muddy gradients at range |
| Specular | none on cloth/skin; one hard 2-tone glint band on chrome only (vertex channel) | Chrome is the one "shiny" read (art-bible §3.1) |
| Rim light | view-space fresnel, power 3, 0.35 strength, tinted by team colour | Separates the hero from dark ground ink `#0B1015` |
| Outline | inverted hull (`next_pass`), 1.4 mm world grow + small distance term, colour `#14161C` | Works on skinned meshes; no post-process cost; per-hero toggle |
| Team colour | ONE accent stripe system per hero (vertex channel `team`), replaced at runtime by `team_color` shader param; emissive variant for visor/thread glow | 15-25% coverage rule (art-bible §4.3) without per-team assets |
| Palette | <= 5 flat colours per hero + skin + team: signature (<= 30%), secondary, two neutrals, one chrome | Limited palette = comic read; repeats art-bible §4.7 |
| Value contrast | lit body mean value 0.35-0.65; never darker than the UI rail `#0D1318` + 0.15 | Heroes must read on the premium-dark UI and on night lanes |
| Readability at 30 m | silhouette hook visible as >= 6 px at 1080p / 90 deg FOV; team stripe >= 4 px | The 30 m check is done in the turntable "far" shot |

UI fit (v0.9 premium-dark): ground ink `#0B1015`, brass accent `#C2A267`, text ivory
`#ECE6D6`. Hero portraits sit on ink, so every hero needs one light value block (bone, gold,
chrome) in the upper third and the rim light; no hero uses ink-black as a large area.

### 1.1 Owner direction (2026-10-05) — "shell" look and masks

- **No visible faces.** Every hero wears a stylised mask or helmet that is part of the
  silhouette: Ryker tactical helmet + visor + balaclava; Vesper ornate porcelain commander
  mask with marionette hinge lines; Brannoc heavy closed helm; Liora smooth medic visor with
  the halo ring; Sable hood with a blank/slit mask; Juniper goggles + rebreather; Hex cat-ear
  hood with a screen face showing a glyph. Emissive eye slits / visor glow are encouraged.
- **Borderlands-style ink:** thick inverted-hull outline (2.8-3.2 px near, never below 60%
  at range), inner contour ink where the surface turns away (`inner_line`), hard 2-band cel
  (terminator smoothing 0.004) + a narrow highlight band, and object-space triplanar diagonal
  hatching **in the shadow band only**, faded out by 14 m so it never shimmers at 30 m.
- **Bold, saturated base colours**, brighter than the v1 pilot: shader saturation x1.08 on top
  of the palette; shadow value 0.62.
- Screen-space crease lines (depth/normal edge post-process) are feasible but would apply to
  the whole frame (environment included); deferred to art-director / technical-director.

## 2. Proportions

- ~7.5 heads, slightly heroic: shoulders 2.1 heads wide (male) / 1.8 (female), hands and
  feet +10%, head -5% from the base, legs = half the height.
- Heights follow the art bible (Sable 1.70 m smallest, Brannoc 2.2 m tallest); Ryker 1.85 m,
  Vesper 1.88 m (tall, slender).
- Pose language: upright V for soldiers, lifted chin and open chest for commanders.

## 3. Budgets

| Budget | Value | Source |
|---|---|---|
| Hero tris in view (LOD0, incl. 3P weapon) | 8k-15k (hard cap 30k, `ModelCatalog.HERO_TRI_BUDGET`) | this brief / art-bible §10.6 |
| Skeleton | <= 32 bones (fingers merged to the hand, face merged to the head) | skinning cost x 6-12 heroes |
| Surfaces per hero | 1 (one toon material + outline pass) | draw calls: 2 per hero |
| Textures | none: flat vertex colours + a per-vertex channel id in UV0 | no photo textures; zero texture memory |
| glb size | <= 3 MB each | repo size |
| Frame time | 6 rigged heroes must stay within +1 ms of the box models | measured in the pilot report |

### Vertex channel convention (UV0.x)
`channel = floor(UV.x * 8)`: 0 flat cel, 1 team accent (cel), 2 emissive (vertex colour),
3 team emissive (visor, threads), 4 skin (softer shadow band), 5 chrome (cel + glint).
UV0.y is unused (0.5). Colour lives in `COLOR_0`.

## 4. Pilot heroes

### Ryker Vance — Soldier (baseline)
- **Silhouette:** upright V-taper; the one oversized LEFT pauldron with a rising antenna fin
  is the hook (asymmetric read from front and side); closed helmet with a horizontal visor bar.
- **Palette:** field olive `#4E5A45` (signature, armour), bone `#E3DCC8` (secondary, pauldron
  face, helmet top), gunmetal `#2F333B` (suit), rubber `#232428` (boots/gloves), chrome
  `#C9D4E2` (right forearm stim port). Team: visor bar (emissive) + chest/pauldron stripe.
- **Gear:** diagonal grenade bandolier, chest plate, belt pouches, knee pads, chrome right forearm.
- **Weapon:** Breakline AR-7 — bulky full-auto rifle, top rail, big receiver, straight mag.
- **Body language:** compact, weight forward, rifle at low-ready in idle.

### Vesper Loom — Commander / Minionmancer
- **Silhouette:** inverted triangle (high wide collar, narrow waist), long legs, long
  asymmetric coat split into ribbon tails at the back; the hook is the **Loom halo**: four
  chrome spindle arms behind the shoulders in a semicircle with violet crystal tips, linked by
  glowing threads to her fingertips.
- **Palette:** plum `#5B2A6E` (signature, coat), spool gold `#D9A441` (secondary: braid wrap,
  coat trim, spindles), ink-plum `#2A1E33` (bodysuit), chrome `#C9D4E2` (thimbles, spine rig),
  violet mana `#B07CFF` (crystals, emissive). Team: collar lining + thread glow.
- **Hair:** sharp bob with one long gold-wrapped braid.
- **Weapon:** Threadcaster — long-barrel semi-auto mana carbine, chrome receiver, spindle drum.
- **Body language:** tall, chin up, off hand free and open (conductor gesture) in idle and casts.

## 5. Animation set

`idle, walk, run, strafe_l, strafe_r, run_back, crouch, jump, fall, aim (upper), shoot (upper
one-shot), reload (upper one-shot), cast_0..cast_3 (one-shot per skill slot), hit, death`.
Driven by `RiggedHeroModel` through an `AnimationTree` (see §6): locomotion blend by
replicated speed / direction, airborne from `grounded`, upper-body aim always on (pitch
additive via spine bones), shoot from `shot_received`, cast from `skill_cast_received`,
death from `dead`.

## 6. Runtime

`HeroModelLoader.build(key, team)` returns a `RiggedHeroModel` when
`assets/models/heroes/<key>/<key>.glb` exists, else the procedural `HeroModelBuilder` model
(`-- --box-heroes` forces the box models). The loader is used by `HeroView`, the portrait tool,
the turntable and the perf tools. The own player has no HeroView (first person is unchanged).
AnimationTree: `loco_bs` (BlendSpace2D idle/walk/run/run_back/strafe_l/r, points at the mocap
clip speeds) -> `loco` TimeScale (up to x2.2 above the run clip speed) -> `crouch_mix` ->
`air` (Transition: jump) -> `upper` (Blend2, filter UpperChest+arms+head+Weapon <- aim
BlendSpace1D down/mid/up by pitch) -> OneShots `reload`, `cast` (clip cast_<slot>), `shoot`
and `hit` (Chest only) -> `life` (Transition: death). Mapping: `RiggedHeroModel.map_state()`.
Outline LOD: the hull pass is dropped beyond 30 m.

## 7. Pipeline (rebuild)

```bash
python3.11 -m venv /tmp/venv && /tmp/venv/bin/pip install bpy pillow   # Blender as a module
tools/art/fetch_base.sh          # CC0 MakeHuman base -> tools/art/.cache/makehuman (gitignored)
tools/art/fetch_mocap.sh         # CMU BVH trials -> tools/art/.cache/cmu (gitignored)
/tmp/venv/bin/python tools/art/build_hero.py ryker vesper   # -> assets/models/heroes/<id>/<id>.glb
#   flags: --scripted (no mocap), --out <dir>
godot --headless --path . --import
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
    -s res://tools/art/render_turntable.gd -- --hero ryker          # turntable + poses + vs-old + 30 m
#   -- --map res://assets/maps/slice/shardline_causeway.tscn --at 0,-118   (in-map lane shot)
#   -- --strip res://.../x.glb --clip run --tag x                          (clip frame strip)
python tools/art/contact_sheet.py out.png 4 420 a.png b.png ...       # evidence sheets
xvfb-run ... godot --path . -s res://tools/art/perf_heroes.gd [-- --box-heroes]   # 6-hero A/B
xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . --rendering-driver opengl3 \
    -s res://tools/art/render_hero_portraits.gd && bash launcher/tools/sync_shared.sh
```

Files: `build_hero.py` (base, rig collapse, decimate, colour cuts, shells, parts API, export),
`hero_defs.py` (Ryker, Vesper + shared helpers), `hero_defs_more.py` (the other five, generic
zone painter), `hero_anims.py` (scripted clips + IK), `mocap.py` (CMU retarget).

### Adding a hero
1. Add an entry to `HEROES` (in `hero_defs_more.py` use `_hero(...)`): height, MakeHuman macro
   `targets`, `palette` (names -> hex), `generic({...})` zone spec (paint per zone, sleeve /
   glove / boot / shorts cut fractions, torso / thigh / boot shells), `parts(h)` (mask, hook,
   gear via `h.box/cyl/sphere/torus`, `h.surface()` to stick to the body, `weights=` for
   skinned pieces), the weapon builder in `WEAPONS` (weapon space: origin right grip, +Y
   barrel), `_stance(...)` (grip positions, twist, poles) and four `casts` gestures.
2. Build, import, render the turntable, look, iterate; keep 8-15k tris and < 3 MB.
3. The key must match `ModelCatalog.HERO_KEYS`; nothing else changes in the game code.

### Pilot perf note
On the xvfb llvmpipe software renderer the inverted hull is the dominant per-hero cost
(see the W13 report); it is LOD-ed out beyond 30 m. Re-measure on real GPU hardware.

## 8. W14 HD layer (detail, texture set, secondary bones)

`tools/art/hero_hd.py`, called by `build_hero.py` (`--lowpoly` = the W13 build without it):

- **Budget:** body decimation x1.5 of the W13 ratio; ~26-33k tris per hero in view. Godot's
  importer LODs (`meshes/generate_lods`) supply the distance LOD (measured in §8 perf note).
- **Detail kit** (per-hero switches in `HD`): surface-fitted belt with buckle + team light,
  pouches with flaps and snaps, bandolier with clips, thigh holster or straps, metal bracers
  with rivets and a team plate, arm bands, collar, back power cell with vents and cables, ear
  vents (helmet). Pieces are skinned from the 3 nearest body vertices.
- **Weapons:** receiver rail with teeth, iron sights, side plates with rivets and team
  energy strips, trigger guard/trigger, bolt handle, muzzle device with ports. Energy weapons
  (Vesper, Liora, Hex) keep their emitter tips (`rail`/`muzzle` off).
- **Hard-surface pass:** Bevel (1.8 mm chamfer, angle 40) + Weighted Normal on the parts;
  armour shells relaxed with a volume-preserving Laplacian smooth so the cel bands stay clean.
- **Texture set** (Smart UV, Cycles bakes at 2x then filtered):
  `<key>_albedo.png` 1024 RGB: flat palette x top-to-bottom gradient x painterly value noise x
  baked AO, curvature edge highlights (Bevel-node normal vs geometric normal, convex only via
  Pointiness), edge wear + scratches on metal, cloth weave. Team faces stay neutral-valued.
  `<key>_normal.png` 1024 OpenGL tangent: selected-to-active from a high-poly copy (Bevel 3
  segments on hard parts, Simple subdivision, cloud Displace folds on cloth) carrying a
  panel-line / rivet / seam / weave bump. `<key>_mask.png` 512 RGBA: R AO, G spec/glint
  (metal), B emissive, A team. The channel id moves from UV0.x to `COLOR.a`.
- **Shader** (`spatial_char_toon_rigged`): `use_maps` + `albedo_map`/`normal_map`/`mask_map`,
  a hard isotropic spec band on metal (`spec_threshold`, `spec_strength`), `ao_strength`,
  `team_value_boost`, `map_emission`. All W13 uniforms are unchanged; without maps the W13
  flat path runs. `RiggedHeroModel.material(team, enemy, far, key)` binds the maps per hero.
- **Import:** run `tools/art/tex_import.sh` after the first import (VRAM compressed, mipmaps,
  normal-map flag, no alpha-border fix on the mask), then import again.
- **Secondary bones:** `Sec_<part>_<n>` chains per `design/art/secondary-motion.md`, fitted to
  whole part islands and re-skinned along the chain with a soft root; never keyed.
- **Clips added:** `death_back` (second death; mocap `death` falls forward), `showcase` (menu
  idle, per-hero `SHOWCASE` pose), casts with anticipation / snap / overshoot / settle,
  `shoot` with a weapon kick (runtime filter is Chest only, see report).
- **Look-dev loop:** `HERO_DEBUG=<dir> build_hero.py <key>` saves the Cycles passes;
  `tools/art/recompose.py <dir>/<key>_passes.npz <key>` re-runs only the albedo composite.
- Size rule: glb + textures <= 6 MB per hero. Build time ~2 min per hero (4-core CPU).

## 9. W16 pipeline (bespoke bodies, painted textures, baked cloth)

Owner direction (2026-10-05): Borderlands look on bespoke bodies, no MakeHuman base. Masks or
helmets on every hero, thick ink, hard two-band cel, hatching, bright colours.

- **Body:** `tools/art/body_gen.py` builds a parametric quad cage (socketed limbs, mitt
  hands with a thumb, chunky boots) on the same GAME_BONES skeleton, subdivides, sculpts,
  then heat-weights it with explicit joint falloffs. Mocap and the game code are unchanged.
- **Texture:** `tools/art/hero_paint.py`. The light is painted into the albedo (top-down
  key, warm lit / cool shadow, crease AO, hatching in the shadow zone, edge strokes, ink on
  colour borders); the normal map carries small detail only. The atlas is >= 75 % used.
  Same file names and shader contract as §8.
- **Cloth:** `tools/art/cloth_bake.py`, contract in `design/art/baked-cloth.md`.
- **Death direction:** `death_back` plays when the killing blow comes from the front
  (KILL event -> HeroView -> `RiggedHeroModel.set_death_dir`).
- **How-to:** `tools/art/README-hero-pipeline.md`. Selected per hero by
  `"pipeline": "gen"`; Vesper is the reference.
