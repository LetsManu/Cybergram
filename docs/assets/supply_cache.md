# Supply Cache: design brief and review notes

Owner decision 2026-10-06: Garrison and Supply Cache ship in the first release.
Rules: match-flow-and-map.md §3.5 (C5), weapons-and-mods.md §3.5. Art bible
§6.4: "a squat mechanical crate with an ammo-belt icon, brass trim and a small
holo label, always mechanical in style regardless of faction".

## Brief

| | |
|---|---|
| Rules (server) | `SupplyCacheSystem`: one Cache per hardpoint with a cache spot (`HardpointDef.supply_cache`, 15 on Shardline Front). It serves the hardpoint's holder 10 s after a flip; nobody while neutral. Mechanical heroes of that team within 3 m refill 25 % of max reserve per second (full in 4 s). Mana heroes who touch it (1.5 m) get the regen delay cut 50 % for 10 s, once per 8 s (new hero stat `REGEN_DELAY_MULT`). Dead heroes get nothing. Knobs in `MatchRulesDef` (`supply_*`). |
| Wire | No protocol change: the client derives the Cache's team from the replicated hardpoint owner with the same rule (`SupplyCacheSystem.owner_at`). A client joining mid-switch may show "serving" up to 10 s early; the server stays authoritative. |
| Solid | The map marker had no collision. `SupplyCacheSystem.add_bodies` adds a 1.3 x 0.95 x 1.0 m box collider on the world layer, on the server and on the client (prediction agrees). Not in the navmesh: bots use their stuck recovery (polish backlog: re-bake). |
| Read | Iron-olive ammo crate with ribs, brass corner caps and trim, side handles, skids, an open tray with three brass cartridge belts, a stencil plate with a cartridge-row icon; team light strips on the lid edges. Holo label "SUPPLY" (team colour while serving, up to 25 m). |
| States | NEUTRAL (no glow) / SWITCHING (lamps blink at 2 Hz in the new owner's colour; reduce motion: steady) / SERVING (lamps, icon, label lit). Brass motes rise from the tray while it refills the own hero. Pure `SupplyCacheView.stage_of`. |
| Audio | `supply_online` (latch clank, servo) when it switches to serving; `supply_use` (belt rattle + brass chime) when the own hero starts using it. `tools/audio` recipe `supply`, 3D, 40 m. |
| Budget | 6.0k tris (main 5.3k, lamps 0.2k, icon 0.5k), 512 maps; spec row in `world_assets_test` (<= 8k). |
| Placement | The 15 crates are `cover` items in `MapPlacementAudit.objective_items` and the CI placement gate (grounded, supported, upright; no waiver). |
| Built by | `tools/art/world/supply_cache.py`; runtime `SupplyCacheView` (in `HardpointView`); shots `tools/shot.gd --only supply-close,supply-mid --supply neutral|switching|serving`. |
| Tests | `tests/unit/objectives/supply_cache_test.gd` (rules, 8), `tests/unit/views/supply_cache_view_test.gd` (stages, pieces, sounds, collider; fails without the asset, watched), placement gate, asset spec row. |

## Review log

### Iteration 1 (2026-10-06)

Opened `production/qa/evidence/supply-cache/`: before (marker hidden: nothing),
after-neutral / after-switching / after-serving, close + mid.

- First render: the refill motes drew as one big cream block (quads 1 m, scale
  ignored); fixed with 6 cm quads. The holo label did not show (world labels
  start hidden); now visible with a 25 m fade.
- Close: reads as an ammo crate (cartridge tray, brass trim, icon plate).
- Mid (8 m): readable with the label; without it the crate is close to the
  kit crates of the cover dressing next to it (polish backlog).
- Blink and motes are motion: not judged from stills.
