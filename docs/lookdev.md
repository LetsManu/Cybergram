# Look development (2026-10-07)

Owner request: "we need shaders and lighting so the game looks better". The
current frames read flat and washed out: a lavender haze everywhere, large pale
pastel walls, weak light / shadow contrast, little depth, neon that does not
pop. Heroes already look right and keep their shader untouched.

Phase 1 builds three complete looks as data and shows them side by side; the
owner picks one; Phase 2 makes it the default and tunes the tiers.

## How it works

- **`LookProfile`** (`src/gameplay/views/fx/look_profile.gd`), one `.tres` per
  look in `assets/data/look/`: sky, ambient, tonemap + grade LUT, glow, SSAO
  (SSIL on Ultra for C), fog + volumetric fog, sun (key) + a shadowless fill,
  practical-light gains + extra HQ practicals, reflection probes, emissive
  gains (capped at the Set-piece tier 1.5), skyline colours and the panel
  material params.
- **Selection:** `--look a|b|c` on the command line (game, `tools/shot.gd`,
  `tools/lookdev_bench.gd`). No flag = no profile = the baked look, unchanged.
- **Applied by** `MapVisuals` (environment, sun, fill, materials, lights,
  probes) and `AmbientWorld` (skips its per-mood sky / sun override when a
  profile is active and scales its neon / shafts by the profile).
- `LookProfile.validate()` enforces the art bible floors: key + fill + ambient
  >= 70 % of the current Skirmish light (§2.3 exposure floor), glow threshold
  >= 1.1 (§10.3), emissive cap <= 1.5 (§4.6), shadow value >= 0.2 (shadows
  never black, §4.5). `tests/unit/models/look_profile_test.gd`.

## Shared shader work (all three looks)

`spatial_env_panel.gdshader` gained look uniforms; every default equals the old
panel, so without a profile nothing changes (test-guarded):

| Uniform | What it does |
|---|---|
| `wall_value`, `wall_saturation`, `floor_value` | deeper wall blocks instead of pale pastel planes |
| `albedo_noise` | large-scale world-space value breakup (two octaves of value noise) |
| `edge_wear` | ~2 px light wear line on mesh face borders (BoxMesh 3 x 2 UV cells), broken up by noise, near only (< 40 m) |
| `contact_ao_min`, `contact_grime` | stronger painted contact AO + grime at the foot of walls |
| `spec_wall`, `spec_floor`, `spec_threshold`, `spec_tint` | one hard-edged cel specular band (thresholded Blinn) in `light()`, no PBR |
| `floor_env_specular`, `floor_roughness` | floor-only sky / probe reflection: the "wet floor" of A (no SSR: art bible §2.1, §10.3) |

`spatial_env_skyline.gdshader`: a height gradient (`top_color`) so towers fade
into the sky instead of reading as flat cut-outs.

## Shadows (all looks, all tiers)

| | Low | Medium | High | Ultra |
|---|---|---|---|---|
| Sun shadows | off | PSSM 2 splits, 120 m | PSSM 4 splits, 200 m, blended | PSSM 4, 300 m, blended |
| Splits (fraction of max) | - | 0.05 / 0.15 / 0.40 (10 m / 30 m / 80 m at 200 m): FP-tuned | same | same |
| Directional atlas | 2048 | 4096 | 4096 | 8192 |
| Soft filter (dir / local) | hard / hard | soft low / very low | soft medium / low | soft high / medium |
| Normal bias / bias | 2.0 / 0.05 | 2.0 / 0.05 | 1.8 / 0.05 | 1.6 / 0.05 |
| Shadowed local lights | 0 | 2 | 4 | 8 |
| Positional atlas | 0 | 2048 | 4096 | 4096 (quadrants 1 / 16 / 16 / 16) |
| Map panels cast (decor pieces were off) | - | yes | yes | yes |
| Small world props cast | no | no | yes | yes |

Local shadows go to the map's lights by priority: Sanctum (spawn) accent, the
look's HQ practicals (spawn / Armory), HQ accents, Mid plaza, market street,
Uplink. SSAO (High / Ultra) is retuned per look for contact grounding.

Low tier: sun shadows stay off; heroes and Wardlings get a blob contact shadow
(`GfxQuality.make_blob_shadow`, one shared material).

## The three looks

| | A "Neon Night" | B "Golden Hour Cyber" | C "Clean Stylized" |
|---|---|---|---|
| Art-bible state | Surge II blue hour | Deploy / Surge I sunset | Skirmish |
| Sky | near-black indigo, dim horizon violet | blue zenith, orange-peach horizon | clear blue |
| Key | cool moon key 1.15, side angle | warm low sun 1.6 at 16 deg (long shadows) | white high sun 1.3 |
| Fill | warm pink-red rim fill 0.3 | teal sky fill 0.2 | warm ground bounce 0.25 (from below) |
| Ambient | 0.42 blue | 0.5 teal | 0.5 cool |
| Grade | cool shadows, warm highlights, strong S-curve | teal shadows / orange highlights split | almost neutral, saturation 1.3 |
| Fog | thin dark navy + light volumetric (High+) | warm aerial haze | minimal, light-blue aerial |
| Neon / emissive | x1.5 (capped 1.5), neon signs x1.8, shafts x1.6, skyline windows 1.6 | x1.15, moderate | x1.2, shafts low |
| Practicals | map lights x2.2, range x1.3 + 4 warm HQ practicals (spawn, Armory), shadowed by budget | as baked | x0.8 |
| Floors | wet: floor cel spec band + sky / probe reflection (reflection probes at both spawns and Armories, High+) | cel spec band on walls + floors (warm) | no spec, strongest edge wear |
| Walls | value 0.62 | value 0.75 | value 0.74, saturation 1.25 |
| Shadow tone | 0.42, blue tint 0.5 | 0.45, teal tint 0.55 | 0.55, blue tint 0.45 |

Readability: team azure / ember trims, enemy outlines and pickups were looked at
in every frame (hero-ref, base-a, uplink-close, armory-close). Azure trims and
the Sanctum disc read in all three; in A the azure neon is the brightest thing
in the HQ (by design, Set-piece tier, HQ ownership is permanent). Hero colours
are untouched (hero shader unchanged); lighting changes their exposure.

## Evidence

`production/qa/evidence/lookdev/`: `<view>_<current|A|B|C>.png` for
fp-lane-center, fp-spawn-a, base-a, uplink-close, armory-close, hero-ref and
shadow-spawn (new shot preset: Vesper + Wardling in the sun by spawn A),
`sheet_<view>.png` (current | A | B | C) and `overview.png`. Made with
`tools/shot.gd --look <x>` at 1920x1080 on High, and
`python3 tools/art/lookdev_sheet.py production/qa/evidence/lookdev`.
The `current` frames are the pre-look-dev renders (from before any change of
this pass), except `shadow-spawn_current`, which is new and already includes
the shadow-tier changes (casters, splits, atlas).

## Performance (dev container, lavapipe software Vulkan, 1920x1080)

`tools/lookdev_bench.gd`, mean of fp-lane-center / fp-spawn-a / base-a, 12
frames each. **Software rasterisation:** a frame is ~1.5 s on 4 shared cores, so
the absolute numbers mean nothing for a GPU, and the machine was shared with
other render jobs (+-10 % noise). Read them as relative cost only. Draw calls
and primitives are exact. "current" here already includes this pass's shadow
tiers (casters on, splits, atlas).

| Look | Tier | Frame (ms, rel.) | vs current | Shadow cost (ms, rel.) | Draw calls (lane / spawn / base) | Primitives k |
|---|---|---|---|---|---|---|
| current | Medium | 1571 | - | 154 | 2593 / 3927 / 3675 | 312 / 367 / 338 |
| A | Medium | 1670 | +6 % | 220 | 2952 / 4385 / 4218 | 327 / 403 / 385 |
| B | Medium | 1742 | +11 % (noise: same light rig as current) | 187 | 2646 / 3924 / 3658 | 306 / 366 / 338 |
| C | Medium | 1731 | +10 % (noise) | 243 | 2570 / 3927 / 3691 | 303 / 367 / 341 |
| current | High | 1583 | - | 475 | 3802 / 5022 / 4926 | 519 / 733 / 711 |
| A | High | 1738 | +10 % | 493 | 3800 / 6303 / 5965 | 525 / 727 / 686 |
| B | High | 1647 | +4 % | 429 | 4029 / 5020 / 4858 | 535 / 738 / 688 |
| C | High | 1874 | +18 % (base-a outlier 2584 ms; lane / spawn are -1 % / -6 %) | 381 | 3714 / 5013 / 4979 | 514 / 719 / 721 |

Reading:
- B and C add no draw calls (same light rig, materials only): their cost is
  shader ALU (albedo noise, edge wear, spec band) and is within the noise here.
- A adds ~360-460 draw calls on Medium and ~1,000-1,300 on High at the HQ
  (shadowed practical lights re-render casters into the positional atlas;
  4 extra HQ practicals). Cut options: fewer shadowed practicals on High
  (LOCAL_SHADOWS 4 -> 2), HQ practicals unshadowed, probes off on High.
- Shadows are the biggest single cost on High in every look (~25-35 % of
  the software frame).
- **Budget conflict (pre-existing):** art bible §10.6 sets <= 2,000 draw calls
  in the worst view; the baked look is already at 2.6-3.9 k on Medium and
  3.8-5.0 k on High in these views. Not caused by this pass; flagged for
  technical-director.
- **N5 gate:** the CI regression gate (`wardling_perf_gate_test`) measures the
  headless server tick, which builds no visuals: none of this touches it. No
  GPU gate exists in CI (no GPU here); a real-GPU check stays a manual item.

## Art-bible deviations to decide (art-director)

- A is night-like; §2.1 says "never night-time darkness in gameplay" and §2.3
  sets an exposure floor. A keeps key + fill + ambient at 1.87 (floor 1.12) and
  heroes read, but the sky is darker than §2.3's Surge II blue hour.
- Neon pops through emissive gain up to the Set-piece cap 1.5: trims in lanes
  are Accent tier (no bloom) in §4.6; A lets lane trims at 9 m bloom slightly.
  The §4.6 coverage cap (<= 6 % of pixels above the glow threshold) is not
  measured yet (needs an HDR readback).
- SSR is not used (§10.3); A's wet floor is a cel spec band + probe reflection.
  SSAO stays on High (already the case; §10.3 says off). C enables SSIL on Ultra
  only.
- Lane lamps with shadows (owner's shadows note) conflict with §10.4 "lanes get
  no neon lights": shadowed lights here are HQ / plaza / market lights the map
  already had; no new lane lights were added.

## Phase 2: the owner's pick (2026-10-07)

**B "Golden Hour Cyber" as the base plus A's stronger neon** ->
`assets/data/look/look_default.tres` ("Golden Hour Neon"), active with no flag
(`LookProfile.DEFAULT_ID`; `--look current` gives the old baked look,
`--look a|b|c` the variants). Changes over B, from the owner review:

| Review item | Change |
|---|---|
| 1. cloud-like blotches on the lane floor | Not shadows (they stayed put when the sun moved; the exact-triangle probe `tools/lookdev_shadow_probe.gd` found no caster). Cause: the new panel `edge_wear` finds face borders from BoxMesh UV cells; the rolling lane floors are ArrayMeshes without those UVs, so the whole floor counted as "border" and got the noise-modulated wear lightening. Edge wear is now walls-only and skipped where UVs are degenerate; albedo noise is walls-only too. Sun bias also raised (0.05 / normal 2.0-1.6). Real cast shadows (lamp posts, cover) stay. |
| 2. floor detail flat | cel highlight band 0.2, floor value 0.9, SSAO 2.6 / 1.5 m for contact darkening where floors meet walls; painted grime gradient stays on wall feet only |
| 3. walls dark brown-grey in shadow | sky ambient (0.42, 0.47, 0.74) x0.58, violet fill (0.48, 0.52, 0.9) x0.35, shadow tint (0.38, 0.42, 0.74), wall value 0.86: warm light / cool shadow |
| 4. A's neon, signal tiers | glow x1.4, bloom 0.1 (Signal emissives: Uplink core, hardpoint holo, crystals, team telegraphs already sit above 1.1); map neon / trims x1.5 but capped at Accent 1.0 (no lane bloom); city signs x1.8, skyline windows x1.4 (Set-piece); horizon softened to (0.98, 0.72, 0.6) so `ember_core` enemies separate from the sky |
| sun | raised from B's 16 deg to 22 deg: still golden, shorter shadows of the Garrison Sentinels / props across the lanes |
| 5. default + tiers | see the shadow table above; Low: blob shadows, no glow; Medium: PSSM 2, 2 shadowed practicals, glow 0.63; High: PSSM 4 blended, 4 shadowed, grade LUT, SSAO; Ultra: 8192 atlas, 8 shadowed, volumetric off for this look |

Final evidence: `production/qa/evidence/lookdev/fp-lane-center_final.png`,
`base-a_final.png` (owner asked for two views only).

Perf: the default look uses B's light rig (no extra lights, no probes,
no volumetric), so its draw calls equal B's (Medium 2.6-3.9 k, same as
current); the extra cost is material ALU and the glow intensity, inside the
software-render noise. The N5 CI gate (server tick) is unaffected.

## Still open

- AmbientWorld's per-match moods (dusk / night / overcast) are bypassed while a
  profile is active; folding them into profiles (or per-phase LUTs, §10.3) is
  the next step.
- §4.6 bloom coverage (<= 6 % of pixels above threshold) still needs an HDR
  readback measurement.
- Draw calls above the §10.6 2,000 budget are pre-existing (technical-director).
