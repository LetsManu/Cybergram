# Forward Beacon: design brief and review notes

Owner plan Part 6 (2026-10-06). A held Mid hardpoint becomes a spawn point for
its owner after a 15 s attunement and stops being one while it is under attack
(enemy capture progress, or an enemy hero within 25 m): match-flow-and-map.md
§3.5, `ProgressionSystem`. Art bible §6.4: "a tall team-coloured banner-mast
with a holographic spawn halo on the ground; the halo dims and strobes when
under attack".

## Brief

| | |
|---|---|
| Read | Per side, a flush spawn pad at the spot that side's heroes appear (`ProgressionSystem.beacon_spot`, half way to the zone edge toward the side's Sanctum): stone disc, iron rim, chrome ring, six hex emitter lenses with outward chevrons, a projector lens in the middle. From the projector a hard-light mast (9 m) with a crossbar and a team banner (down chevron + two bars, frayed hem, sways), and a segmented halo ring (r 2 m) on the floor. |
| Assumption | The mast is **hard light, not geometry**. A solid mast would need new collision in both maps and a navmesh re-bake at every Mid, and would block shots at a contested spawn. A projection also lets the "under attack" state dim and blink, which the art bible asks for. The pad itself is 0.11 m (walkable lip): no collision change. |
| States | DORMANT (the side does not hold the Mid: lenses dark, no hard-light) / ATTUNING (lenses light one per 1/6 of the 15 s, the mast builds bottom-up, the halo arc fills) / READY (full strength, rising motes burst on arrival) / UNDER_ATTACK (hard-light at 70 %, blinks at 2 Hz; reduce motion: steady at ~40 %). Pure `ForwardBeaconView.stage_of` / `lamps_lit`, shared with the sounds. |
| Wire | `HardpointState.beacon` (2 bits) + `beacon_attune` (4 bits, 1/15 steps) in byte 6 of the hardpoint record, which had free bits: no record size change, no protocol bump (an older client ignores the bits). Filled by `ServerWorld` from `ProgressionSystem.beacon_state / beacon_attune` for Mid hardpoints. |
| VFX | `spatial_fx_beacon_holo.gdshader` (mast / banner / halo parts, scanlines, build-up, strobe <= 3 Hz for photosensitivity), team OmniLight (no shadows), mote burst. |
| Audio | `beacon_attune` (rising hum), `beacon_ready` (three-note chime), `beacon_threat` (warble, 2 s cooldown): `tools/audio` recipe `beacon`, 3D at the owner's pad, 60 m. |
| Data | `assets/data/world/forward_beacon.tres` (`ForwardBeaconDef`): mast, banner, halo, strengths, strobe rate, fade, light. Gameplay values stay in `EconomyRulesDef`. |
| Placement | `ForwardBeaconView.place` puts the pad on level floor under the spot, or moves it up to 2 m toward / away from the Mid centre until the pad **and** its halo lie level (the Spindle's spot sits on the Holdstone dais edge: moved 0.5 m inward). Same check as `PlacementValidator`; the six pads are in `MapPlacementAudit.objective_items` and the CI placement gate (no waiver). |
| Budget | 9.3k tris (main 7.8k, 6 lamps 0.25k each, core 0.07k), 512 maps; spec row in `world_assets_test` (<= 10k). |
| Built by | `tools/art/world/forward_beacon.py`; runtime `ForwardBeaconView` (two per Mid, `HardpointView.add_beacons`); screenshots `tools/shot.gd --only beacon-close,beacon-mid --beacon none|attuning:<f>|ready|attack`. |
| Tests | `tests/unit/views/forward_beacon_test.gd` (stages, lenses, sounds, wire bits, spots, the real asset through every stage; fails without the asset, watched), `economy_loop_test.test_mid_beacon_state_replicates_to_the_client` (server -> client: none, attuning 0 / 0.5, ready, under attack), `placement_map_test` (six pads, no violations), `world_assets_test` row. |

## Review log

### Iteration 1 (2026-10-06)

Opened `production/qa/evidence/forward-beacon/`: before (no pad, Center Mid,
close + mid) and after-none / after-attuning_0.5 / after-ready / after-attack.

- Before: nothing marks where a Beacon spawn happens; the spawn choice exists
  only on the HUD (art bible V2: "if a state exists only on the HUD, add a
  world tell").
- After, close: pad, lit lenses, halo segments and the mast read clearly; the
  pad sits level on the dais (the first render had the halo hanging 1 m over
  the dais edge: the halo radius now counts in the placement check, halo
  2.6 -> 2.0 m).
- After, 17 m: the banner is thin and stands near the Holdstone's light pillar;
  the two can be confused (polish backlog).
- The blink under attack and the build-up are motion: not judged from stills.
