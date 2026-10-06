# Wardling v2: design brief and review notes

Owner ask (2026-10-06): "we need to redesign the wardlings in general with
movement and such and a new model". Owner answers: **rigged mini-soldier**; what
was wrong: look / silhouette, movement, too small / samey, feel in combat.
Supersedes the hover Picket (`docs/assets/picket.md`).

## Brief

| | |
|---|---|
| Read | A knee-to-chest-high armoured construct soldier (1.05 m; heroes are 1.70 m+), toy-soldier proportions: oversized helmet with ONE holo-LED visor eye, broad chest, short legs, chunky boots and gloves, a compact two-hand mana blaster. Never reads as a hero (art bible V4): smaller, rounder, a single eye, no face, identical squad mates. |
| Team | Mana core in a chrome cage on the chest, a team band on both pauldrons (read from the front, where the gun hides the core), team rings on the helmet ear housings, the back reactor window, the blaster emitter. |
| Faction | `wardling_c` Concord: white porcelain shell, gold trim, slate suit. `wardling_s` Syndicate: gunmetal shell, brass trim and rivets, rust suit (lightened after the first frames: black iron vanished on the dark floor). |
| Tiers | I: base. II: layered shoulder plates + helmet crest. III: + crown of three team crystal shards. Scale 1.0 / 1.08 / 1.15 (unchanged). |
| Classes | Personal squad: team sash across the chest; own squad: gold knot + ground ring. Vanguard: pennant pole with team flag off the back reactor. Elite (Vesper): gold halo + floating spindle, x1.3. Turned: violet ring. |
| Movement | Hero rig and AnimationTree (RiggedHeroModel): mocap walk / run / strafe blended by the smoothed interpolated velocity, a ready stance idle, shoot one-shot on each bolt the Wardling fires, additive hit reaction when its HP drops, a death fall (forward / backward) when it is removed, then a fade. Locomotion playback may run up to 5.5x (short legs at 6.5 m/s). No protocol change: all of it comes from the replicated position, HP and bolts. |
| Budget | Near (within 25 m): body ~13k tris + visible props; far: ~2.5k LOD only, no ink hull. `ModelCatalog.WARDLING_TRI_BUDGET` 16k / `WARDLING_FAR_TRI_BUDGET` 3k (the art bible's 4k was for the hover Picket). 1024 maps per faction, props one 512 atlas. |
| Built by | `tools/art/hero_defs_wardling.py` (`build_hero.py wardling_c / wardling_s`), props `tools/art/world/wardling_props.py`, runtime `WardlingRig` (in `WardlingModel`), look-dev `tools/art/render_wardling.gd`. |

## Review log

Findings per iteration are appended below.

### Iteration 0 (2026-10-06): geometry only (no maps)

Opened `/tmp` look-dev frames (front, three-quarter, side, close; idle, walk,
run, shoot; Vesper for scale).

- Reads as a squad of small armoured soldiers with guns, clearly not heroes;
  walk and run poses read from the side.
- Fixed before the bake: Syndicate skin too dark (vanished on the floor) ->
  lighter gunmetal + rust suit; helmet enlarged (chibi read); team bands added
  on the pauldrons (the core is hidden by the arms from the front); far LOD
  2.5k (was the heroes' 8k).

### Iteration 1 (2026-10-06): painted bake + props, in game

Builds: wardling_c 13,096 tris (atlas 62 %), wardling_s 13,306 (71 %), far LOD
~2.5k each; props 2,318 tris (8 pieces, 512 atlas). Opened
`production/qa/evidence/wardling-v2/wardling-front|three-quarter|side|close.png`
(look-dev: idle / walk / run / shoot next to Vesper) and `wardlings.png` (the
game's WardlingModel: Concord I, II, III + own sash, Elite; Syndicate Vanguard
I-III).

- Reads as a squad of small soldiers at every distance tried; walk and run poses
  differ clearly from idle; the team reads from the pauldron bands and the core.
- Tiers read by silhouette: plates + crest (II), crystal crown (III). Vanguard
  pennants, the sash, the own-squad ring and the Elite halo all show.
- Fixed in this iteration: the shoulder plates stuck out flat like wings ->
  draped 55 degrees over the pauldrons; the own-squad ring took most of the props
  atlas -> runtime torus; a zero-area face from the Syndicate rivets wrecked the
  wardling_s atlas -> degenerate faces are now dropped in `build_hero.Hero._add`
  (all heroes benefit on their next rebuild).
- Still below standard: the Syndicate skin is muted (gunmetal + rust) next to the
  bright Concord porcelain; animation in motion was not captured as video (poses
  only); death and hit reactions are covered by tests, not frames.
- Cost: measured CPU numbers were unreliable (a parallel Blender bake shared the
  CPU, identical runs varied 2x). Animation LOD (tree stride 1 / 2 / 4 / 8 by
  camera distance) is in place; a clean measurement with `tools/perf_wardlings.gd`
  is still to do.
