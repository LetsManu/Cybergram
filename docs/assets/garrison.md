# Garrison Sentinels: design brief and review notes

Owner decision 2026-10-06: Garrison and Supply Cache ship in the first release.
Rules: wardlings-and-economy.md §11 (C5), match-flow-and-map.md §3.5. Art bible
§6.4: "placed on raised sockets at the hardpoint's corners; their sockets stay
visible (empty, dim) while a Sentinel respawns".

## Brief

| | |
|---|---|
| Rules (server) | `WardlingWorld._garrison_rules` with a `Garrison` blackboard per held hardpoint: 2 Sentinels (24 at the start of Shardline Front; Mids are neutral), the new owner's 10 s after a capture, the old owner's dissolve over 2 s with no bounty, a dead one respawns after 45 s. HP 450 / 590 / 740 and DPS 30 / 37 / 44 by Surge tier (living ones morph, HP fraction kept), range 26 m. Mints wait while the AI budget (110 Wardlings) is full. Knobs: `WardlingRulesDef` (Garrison group). |
| Brain | `WardlingBrain`: GARRISONED (stand on the post) / ENGAGE (shoot the Garrison's threat, picked at 2 Hz: the nearest enemy hero or Wardling within 26 m of the zone centre; the hero gate is off) / DISSOLVING. The leash is the zone: they never leave it. |
| Economy | Bounty 1.5 x the squad Wardling, x0.5 when another Sentinel died at the same hardpoint within 180 s (`ProgressionSystem.sentinel_bounty_mult`, `EconomyRulesDef`). Presence 0.5 like any Wardling. |
| Wire | Snapshot Wardling state code 6 (`WardlingWorld.GARRISON_STATE`, a free command value) marks a Sentinel; no protocol bump. |
| Look | Sentinel = the Picket body with the shoulder plates at every tier, 1.12 x scale, no sash or pennant (`WardlingRig.set_marks` kind 3). Sockets (`tools/art/world/garrison_socket.py`, 1.7k tris): low stone hex, iron rim, brass studs, a lens ring in team colour: OFF (nobody holds the hardpoint), WAITING (dim: settling or respawning), MANNED (lit). `GarrisonSocketView`, lit by ClientWorld from the replicated Sentinels. |
| Audio | `garrison_post` when a Sentinel takes its post (socket WAITING -> MANNED), 3D, 30 m. Sentinels use the Wardling fire / hit / death sounds. |
| Posts | The map builder's formula put 12 of the 30 used posts on pad kerbs (20 % of a socket on the floor) and two next to Forward Beacon pads. `tools/maps/level_garrison_posts.gd` moved them (<= 1.5 m) to the nearest level spot clear of the beacon spots and the cache, and wrote `map_front.tres` (data only). Re-run it after rebuilding the map; the CI placement gate (30 sockets, flat) catches a regression. |
| Built by | Shots `tools/shot.gd --only garrison-close,garrison-mid --garrison off|waiting|manned`. |
| Tests | `tests/integration/wardlings/garrison_test.gd` (start count, flip / dissolve / settle, respawn, shooting a hero inside the zone, tier morph, AI budget, bounty), `tests/unit/views/garrison_view_test.gd` (socket stages, manning, the Sentinel look; fails without the asset, watched), placement gate, asset spec row. |

## Review log

### Iteration 1 (2026-10-06)

Opened `production/qa/evidence/garrison/`: before (no sockets), after-off /
after-waiting / after-manned, close + mid.

- Before: the posts were hidden markers; nothing showed where defenders stand.
- After: two sockets on the Outer pad read as stations; manned ones carry a
  plated Sentinel, waiting ones a dim ring, off ones no light.
- At mid range a Sentinel is only a little different from a squad Picket
  (plates + size): the socket under it carries the read (polish backlog).
- The shot poses the models; in the game the brain turns them to their target.
