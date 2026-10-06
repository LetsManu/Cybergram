# Ward Generator: design brief and review notes

Owner plan Part 6 (2026-10-06): Ward Generator with a shield and three crack
stages. Breach hardpoint machine (match-flow-and-map.md §3.4): attackers shoot
it once its shield is down; at 0 HP the hardpoint is breached.

## Brief

| | |
|---|---|
| Read | A hexagonal power column on a stepped hex plinth: iron housing clad in stone plates, a team crystal glowing through brass-framed windows, a crown of six chrome blades leaning out (art bible §3.1: triangles = breach), emitter rings that project the shield. |
| Fits | The map's collision (GeneratorCore, hex column r 1.2 m, h 2.4 m): every solid part stays inside it except the 0.3 m plinth lip and the crown above 2.4 m. Collision unchanged. |
| States | NEUTRAL (neutral colours) / SHIELDED (hex-lattice dome, Fresnel rim, pulse, fades in / collapses in 0.45 s) / EXPOSED / CRACK 1 < 75 % / CRACK 2 < 50 % (+ a slipped plate) / CRACK 3 < 25 % (torn, glowing seams) / BREACHED (wreck on the plinth, core gone, smoke). Pure `WardGeneratorView.stage_of`, shared with the sounds. |
| VFX | Team sparks on every stage increase (bigger on breach), smoke column while breached, shield shader `spatial_fx_ward_shield.gdshader` (additive, no depth write). |
| Audio | `generator_shield_down`, `generator_crack` (2 variants), `generator_breach`: rendered by `tools/audio` (recipe `generator`), 3D, 70 m. |
| Budget | 17.1k tris (main 8.0k, core 0.3k, crack 1.7 / 2.3 / 3.9k, wreck 1.0k), 1024 maps; spec row in `world_assets_test` (<= 20k). |
| Built by | `tools/art/world/ward_generator.py`; runtime `WardGeneratorView` (in `HardpointView._build_breach`); screenshots `tools/shot.gd --only breach --gen shielded|<hp>|breached`. |
| Tests | `tests/unit/views/ward_generator_test.gd` (stages, pieces, sounds, the real asset through every stage; fails without the asset, watched), `world_assets_test` row. |

## Review log

### Iteration 1 (2026-10-06)

Opened `production/qa/evidence/ward-generator/` close-shielded, close-0.7,
close-0.2, close-breached, mid-breached; before: before-greybox-close.

- Reads as a machine you attack: the blade crown and the glowing core read from
  the close and mid presets; the shield reads as a shield (hex lattice + rim),
  the greybox was a flat tinted sphere.
- Cracks are clearly progressive (0.7: a few; 0.2: all faces split, seams).
- Breached: first pass still glowed team colour (looked powered). Fixed in the
  same iteration: breached uses `WardGeneratorView.dead_material` (emission
  off); the new close-breached frame shows dark, unlit trims (test guards it).
- Smoke is faint in a still (captured 8 frames after the state change).
- Atlas opened: clean, no slivers.
