# Floor tiles and world decals (P7)

Owner ask: "we need a better floor with some decals and such". Then, after the
first frames: "it is not 3D, it looks just like painted on" (depth, smaller and
less regular tiles).

## What was built

| Piece | File | Notes |
|---|---|---|
| Floor trim sheet generator | `tools/art/world/floor_kit.py` | 8 tiles modelled in Blender (bevelled slabs, bolts, bars, rings), baked selected-to-active onto a plane, painted in numpy in the hero language (crease AO, edge strokes, ink, shadow-side hatching, grit, wear, cracks). |
| Floor maps | `assets/textures/world/floor/floor_tiles_{albedo,normal,mask,height}.png` | 2048 x 1024, 4 x 2 slots of 512 px, tile modelled at 2 m: **256 px/m** at the default 2 m tile, 128 px/m on 4 m feature plates (art bible §2: terrain 64-128 + tiling detail, kit 128-200; the near-camera detail is the point). Albedo = greyscale value (0.5 = base_color). Mask R cavity AO, G edge highlight, B grime, A = 1. Height 1 = +6 cm (bolt heads), 0 = -42 cm (pits). Every tile sits 2.5 cm inside its slot over a dark bed: a 5 cm joint between tiles. |
| Decal atlas | `assets/textures/world/decals/world_decals_albedo.png` (`floor_kit.py --decals`) | 2048 x 512, 16 cells of 256 px: arrow, double arrow, hazard chevrons, Concord / Syndicate glyphs (white, team-tinted at runtime), 3 crew tags (`sign_pink`, `sign_teal`, `holo_white` only, §4.6 rule 2), 3 cracks, 2 grime, oil, puddle, scorch (no ember hue). Imported as an `Image` and cut into cell textures at runtime. |
| Shader v2 | `assets/shaders/spatial_env_panel.gdshader` | See below. Walls unchanged. |
| Runtime | `src/gameplay/views/world_decals.gd` (`WorldDecals`), `src/gameplay/data/world_decals_def.gd` (`WorldDecalsDef`), `assets/data/world/world_decals.tres` | Installs the floor maps as the shader's default textures (no map-scene change), places the decals. Client only. |

### Shader v2 (floors)

- **Layout** in world space, independent of the panel grid: 2 m tiles
  (`tile_target_m`), running bond (odd rows offset half a tile, row pairs offset
  a whole tile), 10 % of 2 x 2 blocks are one 4 m feature plate (inset panel,
  tread plate or cable trench, never the drain). Weighted variants keep the
  playable layer calm (§6.1): plain 34 %, inset 20 %, tread 12 %, cracked 12 %,
  grate 6 %, drain 4 %, trench 7 %, hazard kerb 5 %. Random 90-degree rotation.
- **Depth**: parallax occlusion on the height map, 16 steps near, 8 at 25 m, off
  beyond `tile_pom_end` (25 m), faded out at grazing angles (`tile_pom_grazing`)
  and clamped at half the range (`tile_pom_max_depth`) so pits bottom out instead
  of streaking. 30 % of tiles are sunk (`tile_sink_*`): parallax-shifted and 8 %
  darker. Normal strength 1.4, cavity AO 0.9, edge highlight 0.55.
- **Seams**: the v1 panel seam is no longer drawn over tiled floors
  (`tile_panel_seam` = 0); the tiles' own joints (dark bed + lit chamfer lip) do it.
- **Fade** to the flat v1 look between 28 and 65 m.
- **Switch**: `use_tiles = false` gives the v1 floor with no texture samples
  (low quality). Unbound maps also give exactly v1 (mask alpha = 0).

**Cost per fragment** (Forward+): walls / `use_tiles` off: 0 samples (v1).
Tiled floor beyond 25 m: 3 samples (albedo, normal, mask). Tiled floor near:
+ 9-17 height samples (8-16 march steps + 1). Texture memory of the floor set
(VRAM-compressed, mipmapped): about 8 MB. Decal cells: 16 x 256 px RGBA8 with mips
(about 5.5 MB) plus the engine's decal-atlas copy.

### Decals

- Lane arrows every 16 m on the lane path (A gate -> hardpoints -> B gate, with an
  L-shaped approach from the side gates), pointing toward the enemy side in each
  team's half (toward Mid from both ends); every third is a double chevron.
  Flank-loop arrows every 8 m toward the Mid door (§6.2). White, emission 0.6
  (Accent tier, no bloom). No arrows inside hardpoint zones or the Mid plaza.
- HQ: team glyph (6 m) between Sanctum and Uplink in the team colour (emission
  0.8), hazard chevrons inside each lane gate pointing out.
- Hardpoints: 3 cracks, 1 scorch, 1 oil each, in the annulus 5 m .. zone + 2 m.
- Lanes: grime along both edges, crew tags, puddles / oil.
- Floors found by a physics ray (walkable hit with 2 m headroom, nearest the
  MapDef height), so flank arrows land in the Undercroft, not on the lane above;
  decals align to the floor normal (ramps).
- **Cap (art bible §10.6, <= 48 visible per view)**: every decal fades out by 30 m
  (`distance_fade`, begin 22 + length 8) and is not drawn beyond. `apply_cap()`
  accepts a decal only if no point of a 4 m check grid would have more than 48
  decals within 30 m + half the grid diagonal; any camera is within half a
  diagonal of a grid point, so no camera position (at any height) sees more
  than 48. Candidates are taken in priority order (arrows, flank arrows, glyphs,
  chevrons, wear, tags, grime), so the cap cuts dressing first. On the shipped
  map: 373 decals planned in 37 ms, worst 2 m-grid view 27 (cap not binding);
  grounding only removes decals. Not measured: the number actually placed after
  grounding at runtime, and the clustered decal cost on a real GPU (§10.6 "measure").

## Review log

Render path: `tools/shot.gd`, xvfb + lavapipe (Forward+), 1600 x 900.
Sets: `production/qa/evidence/p7-floor/before/` (current branch before this work),
`after-v1/` (first iteration: tiles split per panel, no parallax), `after/` (final).

**Opened:** before `fp-lane-center`; after-v1 `fp-lane-center`; final `after/`:
`fp-lane-center`, `fp-lane-north`, `fp-lane-south`, `fp-spawn-a`, `fp-spawn-b`,
`base-a`, `hold-approach`, `plant-approach`, `breach-approach`,
`mid-hardpoint-mid`, `topdown`, plus `before/topdown` for comparison. Also the
first after render (one tile per 4 m panel), which was overwritten and is not retained.
Not opened: `before/` frames other than the two named (the p5/p6 before sets were
used for context only).

### What reads better

- **Floors are tiles, not flat colour** in every first-person frame: slabs, inset
  panels, tread plate, cracked tile fields, grates, drains, trench covers, hazard
  kerbs, all in the hero ink / edge-highlight style, tinted by each material's
  base_color (blue HQ A, ember-dark HQ B, violet Mid).
- **Depth** (owner feedback): joints are 5 cm recesses with a lit lip; tread
  bumps, bolts and drain rings stand up; pits recess with parallax
  (`fp-lane-center` tread plate, `hold-approach` drain).
- **Scale**: 2 m tiles; a full-screen drain (after-v1 / first render) is gone; the
  4 m plates are tread or panel only.
- **Less regular**: running bond + feature plates break the grid from above
  (`base-a`, `mid-hardpoint-mid`); no panel seams cut through tiles.
- **Decals**: double arrows toward Mid on all three lanes (`fp-lane-*`), a crew
  tag (`fp-lane-north`), puddle (`hold-approach`), Concord glyph in blue at spawn A
  and Syndicate glyph in ember at spawn B, grime by the crates (`base-a`).

### Still below standard

- **POM stepping** on the deepest tiles at mid range: the grate at
  `hold-approach` (left) and the trench at `fp-spawn-a` (right) show layered
  streaks. Options: shallower pits in the bake, more steps, or self-shadowed
  relief; not done.
- **Busy from above**: `base-a` and `mid-hardpoint-mid` are much richer but read
  noisier than §6.1 "calm colour blocks"; the art director should judge the
  variant weights (`CUM` in the shader) at a real monitor.
- **Hazard kerb stripes** alias at a distance (`fp-lane-north`, bottom left).
- **Topdown** is unchanged (330 m: past the tile and decal fades), as intended.
- **Decals over parallax**: decals sit on the geometric surface; on a sunk or
  recessed tile they are a few cm above the visual surface. Not visible in these frames.
- Decals also project onto feet that stand in their 1 m box (heroes share render
  layer 1 with the map); `normal_fade` 0.5 limits it to up-facing parts. Not
  visible in these still frames; needs a moving-hero check.
- Real-GPU cost of POM + 48 clustered decals not measured (lavapipe only).
- Cover tops >= 1.25 m panels (crates, low cover) also get tiles (`breach-approach`):
  acceptable but not designed for.

## Tuning knobs

Shader `floor_tiles` group (per material or as defaults): `use_tiles`,
`tile_strength`, `tile_variety`, `tile_rotate`, `tile_target_m`,
`tile_feature_chance`, `tile_sink_*`, `tile_normal_strength`, `tile_ao`,
`tile_edge`, `tile_grime`, `grime_color`, `tile_panel_seam`, `tile_pom_*`,
`tile_min_panel`, `tile_fade_*`. Decals: every value in
`assets/data/world/world_decals.tres`.

## Needed outside this chunk

- Optional: project-wide **global shader uniforms** (`project.godot`
  `[shader_globals]`) would let the editor and the overview scene show the tiles
  too; today the maps are installed at runtime by `WorldDecals`.
- A quality preset should set `use_tiles = false` (or `tile_pom_depth_m = 0`) on
  low settings; the GfxQuality hook is not in this chunk.
