# Ambient world (W18-LIFE): background life on Shardline Front

Client presentation only. Code: `src/gameplay/views/ambient/`, shaders
`assets/shaders/spatial_env_ambient_*.gdshader` and `env_ambient_path.gdshaderinc`.
Hooked from `MapVisuals._ready()` (marked `W18-LIFE` block) via
`AmbientWorld.create_for()`.

## Never affects gameplay
- Not built when headless / dedicated (`GfxQuality.is_headless()`), not inside the
  offline `ServerWorld` map copy, not with `--ambient-off`.
- No collision shapes, no physics layers, nothing in the navigation group.
- Traffic, drones, birds and the sky-train stay outside the playable box
  (x -100..100, z 10..-430); drones are never over it at any height
  (`TrafficPaths.never_over_play`, unit-tested for every fallback route).
- The only items inside the box are fallback shop signs: flush at the centre
  lane edges (x ±9.6), 6.5 m up (above head height on the 3 m decks).
- Cargo drones are amber boxes 30+ m up with a slow nav blink; dust motes are
  5 cm and dim, so neither reads as a Wardling or a Lumen Mote.

## Anchor contract (for the map builder)
`AmbientWorld` consumes these when present, else uses its fallbacks. A node
counts if it is in the group, or if it sits under a map child named
`AmbientAnchors` with the name prefix.

| Group | Name prefix | Node | Meaning |
|---|---|---|---|
| `ambient_billboard` | `Billboard` | Node3D | Holo ad panel centre; panel faces +Z. Optional meta `size` (Vector2, default 32x12 m). |
| `ambient_shop_sign` | `ShopSign` | Node3D | Market shop sign slot; text faces +Z. |
| `ambient_neon` | `Neon` | Node3D | Other neon sign mount; text faces +Z. |
| `ambient_traffic_path` | `TrafficPath` | Path3D | Closed skyline traffic loop (one lane each). |
| `ambient_drone_path` | `DronePath` | Path3D | Closed drone weave loop. |
| `ambient_skytrain` | `SkyTrain` | Path3D | Open sky-train track (first one is used). |

Paths are resampled to 64 even points; keep them outside the playable box.

## Determinism
- Mood (dusk / night / overcast) and weather (clear / fog / rain) are
  `AmbientMood.pick_*(match_seed)` (integer hash).
- Seed: `--ambient-seed`, else `LaunchConfig.match_seed` (offline / local), else
  for online clients `seed_from_match_clock()`: the match start tick (snapshot
  tick minus match clock) in 30 s buckets. A protocol-sent seed would be exact.
- Sky-train: `SkyTrainSchedule`, gaps 60..120 s from the seed, on the shared
  clock (`server_tick_estimate / tick_rate_hz`).

## Settings and comfort
- Video tab: **World ambience** Low / Medium / High (`ambient_level`, capped by
  graphics quality: Low quality gives Low, Medium gives at most Medium) and
  **Rain in matches** (`ambient_rain`; rain becomes fog when off).
- `comfort_fx_intensity`: neon / holo flicker only at 50 % or more (deepest dip
  22 %); emissives dim to 60 % at 0 %; light shafts and rain are off below 25 %.
- `reduce_motion`: steady neon, frozen holo animation and searchlights,
  traffic at half speed.

## Budgets (per frame, High / Low)
| Item | High | Low |
|---|---|---|
| Draw calls added (lane view, measured) | +22..24 | +10..12 |
| CPU (`_process`, measured) | 0.04 ms | 0.02 ms |
| Movers | 7 lanes x 22 cars, 12 drones, 14 birds, 6 train cars | 3 x 10 cars, train |
| Particles | 260 motes, 1600 rain | 60 motes, 300 rain |
| Transparent fill | 6 shafts, 10 fog cards, 6 billboards | 2 billboards |

Every mover kind is one MultiMesh draw placed by the vertex shader from a
baked route texture; the CPU feeds one `anim_time` uniform per material.
GPU time could not be measured meaningfully on llvmpipe; overdraw from the
shafts and fog cards is the main GPU risk and should be checked on target
hardware.

## Debug args (evidence)
`--ambient-time dusk|night|overcast`, `--ambient-weather clear|fog|rain`,
`--ambient-level low|medium|high`, `--ambient-fx <0..1>`,
`--ambient-reduce-motion`, `--ambient-seed <n>`, `--ambient-train-at <0..1>`,
`--ambient-off`. Preview scene: `tools/maps/ambient_preview.tscn` with
`--ambient-cam skyline|market|train|lane|wide`. Perf probe:
`tools/maps/ambient_probe.gd`.
