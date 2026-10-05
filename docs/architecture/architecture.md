# Cybergram — Technical Architecture

## Document Status

- **Version**: 1.0 (Draft, written autonomously, `modes.automation: autonomous`)
- **Last Updated**: 2026-10-02
- **Authors**: technical-director (owner), network-programmer, lead-programmer
- **Implements**: `design/gdd/game-concept.md` (Canon C1–C18 incl. the 2026-10-02 C15 revision: Vanguard waves, 4 squad commands; C1 AI budget ≤110 agents after the 2026-10-02 consistency pass; Scope Tiers 0–2)
- **ADRs**: `docs/architecture/adr/ADR-0001` … `ADR-0006`
- **Registry**: stances mirrored in `docs/registry/architecture.yaml`

## Engine API Surface

| Field | Value |
|---|---|
| **Engine** | Godot 4.7 stable, GDScript, Forward+, Jolt 3D physics |
| **APIs depended on** | `ENetMultiplayerPeer` (as a raw `MultiplayerPeer` packet API), `CharacterBody3D.move_and_slide()`, `PhysicsDirectSpaceState3D.intersect_ray()`, `Geometry3D.segment_intersects_sphere/cylinder()`, `NavigationServer3D` + `NavigationAgent3D` (avoidance), `SubViewport.own_world_3d`, `Resource`/`.tres`, `PackedByteArray.encode_*/decode_*`, SceneTree physics interpolation, Movie Maker (`--write-movie`) |
| **References consulted** | `docs/engine-reference/godot/VERSION.md`, `modules/networking.md`, `modules/physics.md`, `modules/navigation.md`, `breaking-changes.md`, `current-best-practices.md` |
| **Post-cutoff features used** | Jolt as default 3D engine (4.6), SceneTree-side 3D physics interpolation (4.5), `@abstract` (4.5), `Resource.duplicate_deep()` (4.5) |
| **Unverified on 4.7** | See §15 "Verification list". The engine reference is verified for **4.6 only**; nothing in this doc relies on a 4.7-only API. |
| **Engine upgrade risk** | MEDIUM: the netcode uses only the low-level packet API, but physics replay and navigation avoidance timing are behaviour-sensitive. |

---

## 1. Principles

1. **One code path for every mode.** Offline, LAN, listen server and dedicated server all run the same `ServerWorld` simulation. Clients exchange the same versioned byte messages with it. Offline play is a client connected to an in-process server over a `LoopbackTransport`. **There is no path where gameplay code runs "locally" without a server**, so netcode is never retrofitted (owner decision; ADR-0002).
2. **Sim and view are separate scenes.** Server-side `*_sim.tscn` scenes own state and rules. Client-side `*_view.tscn` scenes only render replicated state. The one exception is the local hero's motor, which runs the same `HeroMotor` code for prediction.
3. **All tunables are Resources.** Every gameplay number lives in a `.tres` under `assets/data/`. Code has no magic numbers (ADR-0003).
4. **Everything that grows is a modifier.** Levels, skill-tree nodes, Crystals/Chips and statuses all write `Modifier`s into one `StatBlock` pipeline (ADR-0004).
5. **Bots are players without a keyboard.** Bot brains emit the same `InputCommand` a human client sends (ADR-0005).
6. **The tick is the unit of time.** Simulation time is an integer tick and durations are stored as end ticks. No `Time.get_ticks_*` and no unseeded RNG in sim code.
7. **Dependencies point one way:** `core` ← `networking` ← `gameplay` ← `ai` ← `ui`. `gameplay` never references `ui`; `core` never references anything above it. The exception is `networking/codec`, which depends on gameplay *state structs* through `core/content`. See §3.

---

## 2. System Overview

```
                        ┌──────────────────────── CLIENT PROCESS (or same process when offline/listen) ───────────────────────┐
  Mouse/KB ──► PlayerInputSource ──► InputCommand(tick N) ──┬──► Predictor (HeroMotor replay, own hero only)                    │
                                                           │        │ predicted pose                                          │
                                                           │        ▼                                                         │
                                                           │   ClientWorld ──► *_view.tscn (heroes, Wardlings, hardpoints)   │
                                                           │        ▲  interpolated remote state (100 ms buffer)              │
                                                           │        │                                                         │
                                                           │   SnapshotReceiver ◄── delta decode ◄── Transport.receive()      │
                                                           │        │ events                                                  │
                                                           │        ▼                                                         │
                                                           │   MatchViewModel ──► src/ui (HUD, shop, minimap) ──► UiCommand   │
                                                           ▼                                                                  │
                                              ClientSession.send(InputBatch / Command) ──► Transport ───────────┐             │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────────┘
                                         LoopbackTransport (offline / host's own client) or ENetTransport (UDP) │
┌──────────────────────────────────────────── SERVER (ServerWorld, own World3D) ───────────────────────────────▼─────────────┐
│  Transport.poll ─► MessageRouter ─► InputBuffer[player] ◄── BotDirector (src/ai) emits InputCommand for bot slots         │
│        │                                                                                                                  │
│        ▼  TickRunner.step(N)  (fixed 30 Hz, explicit order, §8.3)                                                         │
│  HeroSim×10 ─ AbilityRunner ─ WeaponSim ─ LagCompensator(HitboxHistory) ─ ProjectileSystem ─ EffectExecutor              │
│  WardlingDirector (src/ai, LOD buckets) ─ WardlingSim×≤120 ─ NavigationServer3D (avoidance)                               │
│  ObjectiveSystem (HardpointSim×5/15, UplinkSim×2) ─ MatchRules ─ Economy ─ SimEventQueue                                  │
│        │                                                                                                                  │
│        ▼                                                                                                                  │
│  InterestManager(per client) ─► SnapshotBuilder(delta vs acked baseline) ─► Transport.send                                │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
          Content: ContentDB (immutable, loaded from assets/data/*.tres; hashed for handshake) ── read by both sides
```

### 2.1 Session modes

| Mode | Launch | Processes | Transport for the local player | Milestone |
|---|---|---|---|---|
| `OFFLINE` | `godot --path .` → Practice | 1: `ServerWorld` in a `SubViewport(own_world_3d)` plus `ClientWorld` | `LoopbackTransport` (optional `--net-sim` latency/loss) | M1 |
| `LISTEN_HOST` | Host LAN game | 1: the same, plus ENet for remote peers | Loopback for host, ENet for others | M2 (M1 is offline only, per the owner decision in the roadmap) |
| `CLIENT` | `--connect ip:port` | 1: `ClientWorld` only | `ENetTransport` | M2 (LAN and online) |
| `DEDICATED` | `godot --headless --path . -- --server --port 7777` (later a dedicated-server export) | 1: `ServerWorld` only, as the root world | none | M2 |
| `SIM_TEST` | `godot --headless --path . -- --sim-test <scenario.tres>` | 1: `ServerWorld` plus N headless bot clients over loopback, stepped as fast as possible | Loopback | M1 (CI) |

`AppRoot` (main scene) parses `OS.get_cmdline_user_args()` into a `LaunchConfig` and builds the session graph. Nothing else reads command-line args.

---

## 3. Folder Layout

```
src/
├── core/                         # engine-agnostic, depends on nothing above it
│   ├── app/                      app_root.gd (AppRoot), launch_config.gd, session_factory.gd
│   ├── sim/                      tick_runner.gd (TickRunner), sim_clock.gd, sim_rng.gd (SimRng), sim_event_queue.gd
│   ├── stats/                    stat_block.gd (StatBlock), modifier.gd (Modifier), stat_catalog.gd
│   ├── content/                  content_db.gd (ContentDB), content_id.gd
│   ├── util/                     ring_buffer.gd, spatial_hash.gd (SpatialHash), bit_writer.gd, bit_reader.gd, quantize.gd, object_pool.gd
│   └── log/                      log.gd (rate-limited channels)
├── networking/
│   ├── transport/                transport.gd (abstract), loopback_transport.gd, enet_transport.gd, net_sim_conditioner.gd
│   ├── protocol/                 msg_type.gd, protocol_version.gd, input_command.gd, codecs/*.gd
│   ├── server/                   server_session.gd, client_connection.gd, input_buffer.gd, interest_manager.gd,
│   │                             snapshot_builder.gd, baseline_store.gd, lag_compensator.gd, hitbox_history.gd
│   └── client/                   client_session.gd, snapshot_receiver.gd, interpolation_buffer.gd, predictor.gd, clock_sync.gd
├── gameplay/
│   ├── world/                    server_world.gd (ServerWorld), client_world.gd (ClientWorld), entity_registry.gd (NetId ↔ node)
│   ├── data/                     ALL Resource class definitions (HeroDef, SkillDef, … §6)
│   ├── heroes/                   hero_sim.tscn/.gd, hero_motor.gd (HeroMotor), health_component.gd, hitbox_rig.gd
│   ├── weapons/                  weapon_sim.gd, ammo_feed.gd (ManaPoolFeed, MagazineFeed), projectile_system.gd
│   ├── abilities/                ability_runner.gd, skill_instance.gd, targeting/*.gd, effect_executor.gd, effects/*.gd, status_component.gd
│   ├── wardlings/                wardling_sim.tscn/.gd, squad.gd (Squad), garrison.gd, vanguard_spawner.gd (VanguardSpawner),
│   │                             vanguard_wave.gd (VanguardWave)                        # bodies + rules, NOT the brains
│   ├── objectives/               lane_front_resolver.gd (LaneFrontResolver), hardpoint_sim.tscn/.gd, tasks/(hold_task, plant_task, breach_task).gd, uplink_sim.tscn/.gd, barricade.gd, supply_cache.gd
│   ├── match/                    match_rules.gd (MatchRules), respawn_system.gd, spawn_points.gd, sudden_death.gd
│   ├── economy/                  economy.gd (Lumen, Resonance, levels), shop.gd (Armory, Foundry)
│   └── views/                    hero_view.tscn, weapon_view.tscn, wardling_view.tscn, hardpoint_view.tscn, uplink_view.tscn
├── ai/
│   ├── input/                    input_source.gd (abstract), player_input_source.gd, bot_input_source.gd
│   ├── bots/                     bot_director.gd, bot_brain.gd, goals/*.gd, aim_humanizer.gd, bot_sensor.gd
│   ├── wardlings/                wardling_director.gd, wardling_brain.gd (FSM), wardling_targeting.gd, wave_brain.gd (WaveBrain)
│   ├── lod/                      ai_lod_scheduler.gd
│   └── debug/                    ai_debug_draw.gd (paths, perception, FSM state)
└── ui/
    ├── view_models/              match_view_model.gd, hero_view_model.gd
    ├── hud/  menus/  shop/  minimap/
    └── debug/                    net_graph.gd, tick_profiler_overlay.gd

assets/
├── data/                         (.tres only; one Resource per file; ids = file stem)
│   ├── stats/stat_catalog.tres
│   ├── heroes/        hero_ryker_vance.tres, hero_liora_vale.tres, …
│   ├── skills/        skill_ryker_frag_grenade.tres, …   (skill-tree nodes embedded as sub-resources)
│   ├── weapons/  ammo/  mods/        (mod_crystal_*.tres, mod_chip_*.tres)
│   ├── statuses/  wardlings/  economy/  (economy_rewards.tres, economy_level_curve.tres, shop_catalog.tres)
│   ├── match/         match_rules_standard.tres, match_rules_slice.tres, map_slice_lane.tres
│   ├── net/           net_config.tres
│   └── ai/            bot_profile_*.tres, bot_role_*.tres, wardling_ai_*.tres, ai_lod_config.tres
├── maps/  models/  textures/  audio/  vfx/  shaders/
tests/
├── unit/[system]/        gdUnit4, pure logic
├── integration/[system]/ ServerWorld + loopback clients
├── sim/                  scenario .tres + match-sim harness runner
└── fixtures/             factory functions + fixture .tres
tools/ci/                 capture_scenes.sh, run_sim_suite.sh, godot install script
```

**Dependency direction** is enforced by review and by a CI grep (`tools/ci/check_deps.sh`). A file under `src/core` must not `preload` or name a class from `src/gameplay|ai|ui|networking`. A file under `src/gameplay` must not reference `src/ui` or `src/ai`. `src/ai` may read gameplay sim state and write only `InputCommand`s (bots) or `WardlingSim` intents (§10).

---

## 4. Autoloads (kept to three)

| Autoload | Class | Holds | Why it is allowed |
|---|---|---|---|
| `Log` | `Log` | Rate-limited, channelled logger (`Log.net`, `Log.ai`, `Log.sim`), ring-buffered for crash dumps | Stateless with respect to gameplay; the network rules require rate-limited logging |
| `UserSettings` | `UserSettings` | Mouse sensitivity, FOV, key binds, video and audio prefs, colourblind mode | Client preferences only, never game state |
| `ContentDB` | `ContentDB` | Immutable index of every `assets/data` Resource: `get_def(id: StringName) -> Resource`, `index_of(id) -> int` (stable uint16 net index), `content_hash() -> int` | Read-only after boot. Gameplay classes receive it **by injection** (`ServerWorld.new(content_db, rules, seed)`) and never name the autoload, so tests can pass a fixture DB. |

**Forbidden:** autoloads that hold match state (`GameManager`, `EventBus`, `PlayerData`). Match state lives in `ServerWorld` and, on clients, in `ClientWorld` and its view models. Gameplay code may not call `get_node("/root/...")`.

---

## 5. Scene Composition

Every networked entity has a **`NetId`** (uint16, allocated by `EntityRegistry`, recycled after 2 s) and an **entity kind** (uint8). Server sim scenes live under `ServerWorld`. View scenes live under `ClientWorld`, are spawned by `ClientWorld.on_entity_created(kind, net_id, def_index)` and are pooled.

### 5.1 Hero

```
hero_sim.tscn  (HeroSim : CharacterBody3D)            hero_view.tscn  (HeroView : Node3D)
├── CollisionShape3D (capsule, from HeroDef)          ├── Model (glTF instance, cel material, team tint)
├── HeroMotor        (Node; pure step function)       ├── AnimationTree (locomotion from replicated vel/state)
├── StatBlock        (RefCounted, held by HeroSim)    ├── WeaponView (3P) / FirstPersonRig (local: camera + viewmodel)
├── HealthComponent  (Node)                           ├── LevelGlyph, NameplateAnchor (Pillar 4 tells)
├── StatusComponent  (Node)                           └── VfxSockets
├── AbilityRunner    (Node) → SkillInstance×4
├── WeaponSim        (Node) → AmmoFeed (ManaPoolFeed | MagazineFeed)
├── HitboxRig        (Node; head/body capsules as data, NOT physics bodies)
└── SquadLeader      (Node; ref to Squad)
```

- `HeroSim` signals: `died(killer: int, assists: PackedInt32Array)`, `respawned(spawn_id: StringName)`, `level_changed(level: int)`.
- `HeroMotor.step(body: CharacterBody3D, state: MotorState, cmd: InputCommand, stats: StatBlock) -> void` is the **only** movement code, and runs identically on the server and in the client `Predictor`. `MotorState` holds velocity, grounded, crouch, `motion_effect` (dash/leap), and coyote and jump-buffer ticks.
- The client's local hero is a `PredictedHero` (`CharacterBody3D` + `HeroMotor`) in the client world, colliding with the client copy of static map geometry. `HeroView` follows it through physics interpolation.

### 5.2 Weapon

`WeaponDef` (`.tres`) → `WeaponSim` (server) + `WeaponView` (client).
- `WeaponSim.try_fire(cmd: InputCommand, tick: int) -> void` checks the fire interval (end tick), the `AmmoFeed`, and spread from stats. For hitscan it calls `LagCompensator.trace(shooter, origin, dir, range, cmd.view_tick, cmd.view_alpha)`. For projectiles it calls `ProjectileSystem.spawn(...)`.
- `AmmoFeed` is abstract (`@abstract`) and has two implementations. `ManaPoolFeed` (C16: regen after a delay, no reload) and `MagazineFeed` (magazine plus reserve, refilled by Armory, Supply Cache and drops) are both selected by `WeaponDef.feed_kind`.
- `WeaponView` has `ModSocket` nodes (`socket_0..n`) where Crystal/Chip meshes from `ModDef.visual_scene` attach (Pillar 4). The local client predicts muzzle flash, tracer, recoil and the ammo counter. Server hits arrive as `HitConfirm` events for hit markers.

### 5.3 Wardling

```
wardling_sim.tscn (WardlingSim : CharacterBody3D)     wardling_view.tscn (WardlingView : Node3D)
├── CollisionShape3D (small capsule; blocks heroes)   ├── Model (tier variant, team colour, silhouette per variant)
├── NavigationAgent3D (avoidance on, radius from def) ├── StateTell (icon / emissive by FSM state)
├── HealthComponent, StatusComponent                  └── AnimationPlayer
├── StatBlock (from WardlingDef + WardlingTierDef)
└── HitboxRig
```

- `WardlingSim` exposes **intents** only: `set_move_target(pos)`, `set_attack_target(net_id)`, `stop()`. The brain lives in `src/ai/wardlings/WardlingBrain` and is held by `WardlingDirector`, not by the node (§10).
- Every `WardlingSim` has an `allegiance`: `SQUAD(owner_net_id)`, `GARRISON(hardpoint_index)` or `VANGUARD(wave_id)`. The body, stats, hitboxes and replication are identical for all three; only the brain's state table and the owning rule object differ.
- `Squad` (gameplay) owns membership and C15 rules: base 3, upgradable to 5, +2 for Vesper; replaced only at the Foundry; dissolves 10 s after the owner dies. It holds the current `SquadCommand {kind: FOLLOW | HOLD | ATTACK_TARGET | GO_CAPTURE, pos: Vector3, target_net_id: int, hardpoint_index: int}` (4 commands, C15). `ATTACK_TARGET` is validated server-side: the target must be an enemy entity within `SquadDef.command_range_m` and in the owner's LOS at the issuing tick (rewound like a shot). Signals: `member_lost(net_id)`, `dissolved()`, `command_changed(cmd: SquadCommand)`.
- `Garrison` spawns 2 Sentinels per held hardpoint (C5) with a respawn timer taken from `GarrisonDef`.
- `VanguardSpawner` (one per team) runs every `VanguardDef.interval_s` (60 s) per lane. It spawns `VanguardDef.wave_size` (4) Tier-matched Wardlings at the Foundry **only if** that lane's previous `VanguardWave` has `≤ VanguardDef.respawn_threshold_alive` (1) members alive. That gives a hard cap of 1 live wave per lane per team, i.e. ≤ 24 Vanguard on the full map. Waves are ownerless and uncommandable. The exception is Vesper, whose skill effects may issue a `SquadCommand` to a wave through an `EffectDef`, never through player `Command`s. Signals: `wave_spawned(team, lane, wave_id)`, `wave_depleted(wave_id)`.
- `LaneFrontResolver.front_for(team, lane) -> int` (hardpoint index) implements the C15 target rule: the nearest contested hardpoint, else the next enemy hardpoint attackable per C3, else the team's own front-most held hardpoint. It is recomputed only on `ownership_changed`/`contested_changed`, and waves read it each decision.

### 5.4 Hardpoint

```
hardpoint_sim.tscn (HardpointSim : Node3D)
├── ZoneShape (radius/box as data; presence counted via SpatialHash, not Area3D signals)
├── Task (HoldTask | PlantTask | BreachTask, chosen by HardpointDef.task_kind)
│     └── BreachTask → WardGenerator (HealthComponent + shield StatBlock)
├── Garrison, SupplyCache (Area-free proximity check), Barricade (StaticBody3D; team collision layer swap)
└── ForwardBeacon (Mid only; SpawnPoint provider)
```

- Signals: `task_progressed(team: int, progress: float)`, `ownership_changed(old_team: int, new_team: int)`, `contested_changed(is_contested: bool)`.
- `HardpointSim.can_be_attacked_by(team)` asks `ObjectiveSystem.lane_prereq_held(lane, index, team)` (C3 adjacency rule). Ownership flips straight to the capturing team.
- Presence weights come from `HardpointDef`/`MatchRulesDef` (C4: Wardling = 0.5 player, AI presence capped at 3.0 per team per hardpoint; heroes uncapped). Surge scaling of task duration is read from `MatchRules.current_task_duration_scale()`.

### 5.5 Uplink

`uplink_sim.tscn (UplinkSim : StaticBody3D)` contains `IntegrityComponent` (no regen, and heal effects are rejected by a `heal_immune` tag) and an `exposed: bool` that `ObjectiveSystem` recomputes on every `ownership_changed`. The rule is ≥1 enemy-held Inner, or Outer from 45:00 (C7). Damage while not exposed is dropped server-side, and the client gets an `ImmuneHit` cue. Signals: `integrity_changed(value: int)`, `exposure_changed(exposed: bool)`, `destroyed()`. Wardling damage is scaled by `UplinkDef.wardling_damage_scale` (C7: 0.5).

---

## 6. Data-Driven Design

Every tunable is a typed custom `Resource` (`class_name … extends Resource`, `@export` fields with `@export_range` hints) saved as `.tres` in `assets/data/`. The JSON rule in `.claude/rules/data-files.md` applies only to JSON. We use JSON only for CI scenario output and telemetry (ADR-0003).

| Resource class | Key fields (abridged) | Canon |
|---|---|---|
| `StatCatalog` | `stats: Array[StatDef]` (`id`, `default`, `min`, `max`, `rounding`) → dense int index | — |
| `HeroDef` | `id`, `display_name_key`, `resource_type` (MANA/MECHANICAL), `base_stats: Dictionary[StringName,float]`, `stat_growth: Array[ModifierDef]` per level, `weapon: WeaponDef`, `skills: Array[SkillDef]` (4), `squad_bonus: int`, `bot_role: BotRoleDef`, `sim_scene`, `view_scene` | C12, C16, C17 |
| `SkillDef` | `id`, `slot`, `is_ultimate`, `base_params: Dictionary[StringName,float]` (damage, radius, cooldown, …), `targeting: TargetingDef`, `cast_ticks`, `effects: Array[EffectDef]`, `tree: Array[SkillNodeDef]`, `predicted_motion: bool` | C12, C16 |
| `SkillNodeDef` | `id`, `kind` (UNLOCK/BOOST/FORK_A/FORK_B/MASTERY/ULT_RANK), `required_level`, `modifiers: Array[ModifierDef]`, `added_effects: Array[EffectDef]`, `excludes: StringName` | C12 |
| `EffectDef` (abstract) | subclasses `DamageEffectDef`, `HealEffectDef`, `ApplyStatusEffectDef`, `ImpulseEffectDef`, `SpawnEntityEffectDef`, `MotionEffectDef`, `AreaEffectDef(child effects)` | — |
| `ModifierDef` | `stat: StringName`, `op` (ADD/PCT/MUL/OVERRIDE), `value`, `scope` (HERO/SKILL_SLOT/WEAPON/SQUAD), `scope_slot`, `tags` | — |
| `StatusDef` | `id`, `duration_s`, `stacking` (REFRESH/STACK/IGNORE), `max_stacks`, `modifiers`, `tick_effects`, `tick_interval_s`, `tags` (stun, silence, reveal, hacked) | — |
| `WeaponDef` | `fire_mode`, `fire_interval_s`, `damage_falloff: Curve`, `range_m`, `spread`, `feed_kind`, `mana_pool`/`mag_size`/`reserve`, `projectile: ProjectileDef`, `mod_sockets: int` | C16 |
| `AmmoTypeDef` | `id`, `modifiers`, `on_hit_effects`, `lumen_cost` | C14 |
| `ModDef` | `id`, `kind` (CRYSTAL/CHIP), `modifiers`, `lumen_cost`, `visual_scene` | C14, C16, Pillar 4 |
| `WardlingDef` / `WardlingTierDef` | variant id, base stats, attack, `presence_weight`, `uplink_damage_scale`, `tiers[3]` modifiers | C4, C15 |
| `SquadDef` / `GarrisonDef` / `VanguardDef` | squad base/max size, command range, focus timeout; garrison size + respawn; Vanguard `interval_s` (60), `wave_size` (4), `respawn_threshold_alive` (1), `formation` offsets | C5, C15 |
| `EconomyRewards` | Lumen/Resonance per Wardling kill, hero kill, assist, capture, defence, trickle per second, share radius 25 m, catch-up bonus per level delta | C13, C14 |
| `LevelCurve` | `resonance_to_level: PackedInt32Array` (15), skill points per level | C12 |
| `ShopCatalog` | Armory and Foundry entries → `ModDef`/`AmmoTypeDef`/squad upgrades/consumables | C14, C15 |
| `MatchRulesDef` | `time_cap_s` 3600, `capture_overtime_s` 30 (C8), `ai_presence_cap` 3.0 (C4), `surge_times_s`, `surge_task_scale`, `drought_time_s`, respawn `base`/`per_min`/`cap`, `sudden_death_*` (incl. `sudden_death_max_restarts` 3, C10), incursion table | C7–C11 |
| `MapDef` | lanes → ordered `HardpointDef`s (task kind, base duration, lane, index), HQ spawn data | C2–C6 |
| `NetConfig` | `tick_rate_hz` 30, `interp_delay_ticks` 3, `max_rewind_ms` 200, `snapshot_budget_bytes`, quantisation steps, relevancy radii | ADR-0002 |
| `BotProfile` / `BotRoleDef` | reaction ms, aim error curves, decision hz, goal weights | ADR-0005 |
| `WardlingAiDef` / `AiLodConfig` | leash, aggro and return-fire radii, LOD distances and decision intervals, per-tick decision cap | ADR-0005 |

Rules:
- **Defs are immutable at runtime.** Per-instance state lives in runtime objects (`SkillInstance`, `StatBlock`, `Squad`). If a Def must be mutated per instance, use `duplicate_deep()` (4.5+), but the design never needs it.
- **Ids** are `StringName`s equal to the file stem. `ContentDB` sorts all ids per type → stable uint16 net index. The handshake compares `content_hash` (a hash of sorted ids plus each file's content), and a mismatch refuses the connection (`Reject(CONTENT_MISMATCH)`).
- **Formulas are code, coefficients are data.** For example, `RespawnSystem.respawn_seconds(minutes) = min(rules.respawn_cap, rules.respawn_base + rules.respawn_per_min * minutes)` (C11). The design doc owns the formula and the `.tres` owns the numbers.
- A `ContentValidator` (`tools/ci/validate_content.gd`, run in CI) loads every `.tres` and checks: required fields present, ranges valid, every skill has an UNLOCK node and, outside the M1 reduced-tree content set (UNLOCK/BOOST/ULT_RANK only, `heroes.md` §11), BOOST, FORK_A/B and MASTERY nodes; FORK_A/B exclude each other, ultimate ranks at levels 6/10/14, no orphan defs.

---

## 7. Stats, Modifiers and the Ability System

### 7.1 StatBlock (src/core/stats, shared by everything)

```gdscript
class_name StatBlock extends RefCounted
signal stat_changed(stat_index: int, new_value: float)
func _init(catalog: StatCatalog, base: PackedFloat32Array, parent: StatBlock = null) -> void
func get_value(stat_index: int) -> float          # cached; recompute on dirty
func add_modifier(mod: Modifier) -> int            # returns handle
func remove_modifier(handle: int) -> void
func remove_by_source(source_id: int) -> void      # e.g. all mods from one Crystal, one status
```

- Evaluation order (fixed, documented in the Stats GDD): `value = clamp(OVERRIDE ?? ((base + ΣADD) × (1 + ΣPCT) × ΠMUL), min, max)`.
- `Modifier` = {`stat_index`, `op`, `value`, `source_id` (uint32: kind<<24 | index), `expires_tick` (−1 = permanent)}.
- Storage is a PackedArray per op per stat. Values are recomputed only for dirty stats. There are **no per-tick allocations**, and modifier objects are pooled.
- **Scopes:** a `SkillInstance` owns a child `StatBlock` (parent = the hero block) seeded from `SkillDef.base_params`. A modifier with `scope=SKILL_SLOT` targets that child, and `scope=HERO` targets the hero. A skill reads hero-wide stats such as `cooldown_reduction` through the parent.

**Modifier sources:**

| Source | When added | Removed | `source_id` kind |
|---|---|---|---|
| Level | on `level_changed` (`HeroDef.stat_growth`) | never (match reset) | LEVEL |
| Skill-tree node | on `Command(LEVEL_SKILL)` accepted | never | SKILL_NODE |
| Crystal / Chip / ammo type | on Armory purchase | on sell/swap | MOD |
| Status | `ApplyStatusEffect` | `expires_tick` reached or cleansed | STATUS |
| Surge tier (Wardlings, garrisons) | on `phase_changed` | on the next tier | SURGE |

### 7.2 Skill → Effect → Modifier pipeline

```
InputCommand.buttons(SKILL_n) ─► AbilityRunner.try_activate(slot, cmd, tick)
   gates: node UNLOCK owned · tick ≥ cooldown_end_tick · !status.has_tag(&"silence") · not casting
   ─► SkillInstance.begin_cast(tick)      (cast_ticks from stats; cancellable by stun)
   ─► TargetingDef.resolve(ctx) → TargetSet   (Hitscan via LagCompensator | Projectile | GroundPlace | Self | SoftAlly)
   ─► EffectExecutor.apply(effects, EffectContext{source, instigator_net_id, skill_index, rank, tick, aim, stats})
         DamageEffect  → target.HealthComponent.apply_damage(DamageInfo)   (amount read from skill StatBlock)
         HealEffect    → HealthComponent.apply_heal()
         ApplyStatus   → StatusComponent.apply(StatusDef, ctx) → adds Modifiers (source STATUS) + tick effects
         MotionEffect  → HeroMotor.state.motion_effect (PREDICTED on owning client)
         SpawnEntity   → traps, drones, shield wall (EntityRegistry.spawn)
   ─► cooldown_end_tick = tick + ceil(cooldown_s × (1 − cdr) × tick_rate)   → AbilityRunner.cooldown_started(slot, end_tick)
```

- **Skill-tree nodes are modifiers, not new skills** (concept risk mitigation). BOOST and MASTERY are `ModifierDef`s on the skill's block. Forks add `ModifierDef`s and/or `added_effects` appended at the end of the skill's effect list. Ultimate ranks are `ULT_RANK` nodes. A node can never replace code; when a fork needs genuinely new behaviour, it adds a new `EffectDef` subclass.
- **Cooldowns are ticks**, replicated as `cooldown_end_tick` in the own-hero block. The client predicts the cooldown start on press and rolls it back if `SkillRejected` arrives.
- **Damage** goes through `DamageInfo {amount, type (WEAPON/SKILL/TRUE), source_net_id, instigator_team, flags (headshot, crit)}` and `HealthComponent.apply_damage()`. That method applies armor/resist stats, Uplink exposure gating, friendly-fire rules, and assist tracking (instigator ring, 10 s from `EconomyRewards`).
- **Aimed damage only** (Pillar 2): `ContentValidator` rejects a `DamageEffectDef` whose skill targeting is `SoftAlly`.

---

## 8. Networking Model

### 8.1 Decisions (ADR-0002)

| Topic | Decision |
|---|---|
| Authority | **Server-authoritative** for all state. Clients send inputs and commands only. |
| Tick | **30 Hz** fixed sim (`Engine.physics_ticks_per_second = NetConfig.tick_rate_hz`). Clients render at 60–144+ fps through physics interpolation, and mouse look is applied per render frame. 60 Hz is a data change re-evaluated after the M1 server-cost benchmark (§12). |
| Transport | `ENetMultiplayerPeer` used as a **raw packet peer** (`put_packet`, `get_packet`, `transfer_mode`, `transfer_channel`, `poll`). **No `@rpc`, `MultiplayerSynchronizer` or `MultiplayerSpawner` in gameplay**, because they cannot do per-client delta baselines, priority or budgets. `LoopbackTransport` implements the same `Transport` interface in memory. |
| Channels | 0 = reliable control (handshake, Reject, Kick), 1 = reliable gameplay events and commands, 2 = unreliable snapshots, 3 = unreliable input batches |
| Prediction | Own hero movement and predicted motion skills; own weapon cosmetics, ammo counter and cooldown start. Everything else is interpolated. |
| Reconciliation | Rewind to the server state at `last_processed_input_seq`, then replay buffered inputs through `HeroMotor`. The visual error is smoothed over 100 ms. |
| Remote entities | Snapshot interpolation, `interp_delay = 3 ticks` (100 ms), extrapolation cap 1 tick |
| Hit registration | Server-side lag-compensated hitscan using a `HitboxHistory` rewind capped at 200 ms. Projectiles are simulated on the server and not rewound. |
| Messages | Hand-written binary codecs (`BitWriter`/`BitReader`), each prefixed with `protocol_version:u16` in the handshake and `msg_type:u8` |

### 8.2 Messages (protocol v1)

| Msg | Dir | Channel | Rate | Content |
|---|---|---|---|---|
| `Hello` | C→S | 0 | once | protocol_version, content_hash, display name, auth token (M2) |
| `Welcome` / `Reject` | S→C | 0 | once | player slot, team, own hero NetId, server tick, match rules id |
| `InputBatch` | C→S | 3 | every tick | `ack_snapshot_tick:u32`, the last **3** `InputCommand`s (redundancy against loss) |
| `Command` | C→S | 1 | on demand | BUY(item idx), SELL, LEVEL_SKILL(node idx), SQUAD_CMD(FOLLOW / HOLD+pos / ATTACK_TARGET+net_id+view_tick / GO_CAPTURE+hardpoint idx), CHOOSE_SPAWN(spawn idx), PING_MARKER |
| `Snapshot` | S→C | 2 | every tick (§8.5) | tick, baseline_tick, last_processed_input_seq, own-hero block, entity deltas, objective block |
| `Event` | S→C | 1 | on demand | KILL, HIT_CONFIRM, CAPTURE, OWNERSHIP, SURGE, PHASE, SHOP_RESULT, SKILL_REJECTED, MATCH_END, ENTITY_DESPAWN |
| `Ping`/`Pong` | both | 0 | 1 Hz | RTT and clock sync |

`InputCommand` (13 bytes packed): `seq:u32` (= client tick), `move:i8×2`, `yaw:u16`, `pitch:i16`, `buttons:u16` (jump, crouch, fire, alt, reload, skill1–4, interact, squad), `view_tick:u32`, `view_alpha:u8`. The server **validates** everything: move magnitude ≤ 1, pitch in range, `view_tick` within `[now − max_rewind, now]` (clamped otherwise), seq monotonic, packet size ≤ the per-type max, and at most 8 inputs consumed per tick (anti speed-hack). Missing inputs are filled by repeating the last command with `fire` cleared.

### 8.3 Server tick order (`TickRunner.step(tick)` from one `_physics_process`)

Individual nodes do **not** use `_physics_process` for sim logic. `TickRunner` calls systems in this fixed order:

1. `ServerSession.poll()` → `Transport.poll()`, decode, route to `InputBuffer[slot]` and the `CommandQueue`.
2. `BotDirector.produce_inputs(tick)` → writes `InputCommand`s into bot slots' `InputBuffer` (based on state at tick−1).
3. `CommandQueue.apply()` → shop, skill points, squad orders, spawn choice (validated against position and state).
4. `HeroSystem.step()` → per hero: pop input → `HeroMotor.step()` (`move_and_slide`) → `AbilityRunner.step()` → `WeaponSim.step()` (hitscan via `LagCompensator`).
5. `VanguardSpawner.step()` and `Garrison.step()` (spawns) → `WardlingDirector.think(tick)` (wave brains, then LOD-bucketed member decisions, §10.2) → `WardlingSystem.step()` (nav + avoidance + attacks).
6. `ProjectileSystem.step()` (swept ray per projectile per tick).
7. `StatusSystem.step()` (expiry, DoT/HoT ticks), then `HealthSystem.resolve()` (deaths → `SimEventQueue`).
8. `SimEventQueue.dispatch()` → `Economy` (Lumen, Resonance, levels), `Squad` dissolve timers, `RespawnSystem`.
9. `ObjectiveSystem.step()` → hardpoint presence/tasks/ownership, Uplink exposure; `MatchRules.step()` → phase, Surges, time-out/Incursion, Sudden Death, end.
10. `HitboxHistory.record(tick)` (post-move poses of heroes and Wardlings).
11. `SnapshotBuilder.build_and_send(tick)` per client (InterestManager → delta → transport); flush reliable events.
12. `SimClock.tick += 1`; `TickProfiler` records the per-stage µs.

`SimEventQueue` is the **only** cross-system channel inside the server sim. It is a typed, ordered, per-tick list of structs (`DeathEvent`, `CaptureEvent`, `DamageEvent`, …), which gives a deterministic order and a single source for replication. Godot signals are used inside an entity and from client state to views/UI.

### 8.4 Client frame

- `_physics_process` (30 Hz): `ClockSync` decides whether to run 0, 1 or 2 prediction ticks. This "tick nudging" keeps the client `ahead = RTT/2 + 1 tick` of the server. Each tick: `PlayerInputSource.sample()` → `InputCommand` → `Predictor.step()` (`HeroMotor` on `PredictedHero`) → store in `PredictionHistory` (ring of 64) → send `InputBatch`.
- On `Snapshot`: `SnapshotReceiver` decodes the delta against the stored baseline → acks → pushes remote states into `InterpolationBuffer`s → `Predictor.reconcile(own_block)`. If the position error exceeds `NetConfig.reconcile_epsilon_m` (0.02), it resets and replays inputs `seq+1..now` (max 16; beyond that it snaps).
- `_process` (render rate): views sample `InterpolationBuffer.sample(render_tick − interp_delay)`. The camera uses the interpolated predicted body plus the live mouse yaw/pitch. `view_tick`/`view_alpha` for the next input are recorded here.

### 8.5 Snapshots, delta compression, bandwidth

> Implemented in protocol 16 (W16-NET): see `docs/architecture/netcode-w16.md` for the as-built layout (velocity i16 at 1/128 m/s and group change masks instead of per-field varints) and the before/after numbers.

- `BaselineStore` per client keeps the last 32 sent snapshots. Each snapshot is delta-encoded against the **newest snapshot the client acked**, or sent in full if none or if it is too old.
- Per entity: `net_id:u16`, `changed_mask` (varint), then only changed fields. Quantisation (in `NetConfig`): position `i16×3` at 1/32 m relative to the map origin (±1024 m), velocity `i8×3` at 0.25 m/s, yaw u8 (Wardlings) / u16 (heroes), HP as u16 (heroes) / u8 % (Wardlings), state enums packed in bits.
- Entity create/destroy is part of the snapshot (a create record carries kind and def index). Despawn is also sent as a reliable `Event` so it is never missed.
- **Budget:** `snapshot_budget_bytes = 1100` per client per tick (fits one MTU-safe packet). Overflow is handled by priority (§8.6). The target is ≤ 256 kbps down and ≤ 48 kbps up per client typical, and ≤ 2.5 Mbps total server egress for 10 clients.

### 8.6 Interest management (≤110 AI agents, Canon C1: squads ≤ 54 incl. 2 Vespers, Garrisons ≤ 30, Vanguard ≤ 24)

`InterestManager` runs on the server per client per tick and uses a `SpatialHash` (16 m cells) that is rebuilt each tick:

| Entity class | Relevancy | Rate |
|---|---|---|
| Own hero, own squad | always | every tick |
| Other heroes | ≤ `hero_full_radius` (80 m) **or** in LOS-revealed set **or** ally | every tick; allies beyond radius at 5 Hz (minimap) |
| Enemy heroes not revealed | not sent (anti-wallhack). The reveal set comes from the server LOS budget (one ray per pair per 3 ticks) | — |
| Own-team squad Wardlings (others') | ≤ 60 m full; beyond: not sent | 30 Hz |
| Wardlings (any allegiance) | ≤ 60 m: full; 60–120 m: low rate; > 120 m: not sent individually | 30 Hz / 6 Hz |
| Vanguard waves, aggregated | every live wave as one `WaveSummary` record (team, lane, alive count, centroid, front target) for the minimap and front display. Individual members follow the Wardling rows. | 2 Hz, always |
| Hardpoints, Uplinks, match block | always (small objective block) | on change, plus a keyframe every 1 s |
| Projectiles / traps | ≤ 60 m; enemy traps only if revealed | every tick |

**Priority accumulator.** Each (client, entity) pair accumulates `priority += base_weight × distance_factor` every tick. The builder writes entities in descending priority until the byte budget is reached, then resets those it sent. This degrades gracefully in big fights instead of exceeding the MTU. All radii and weights are in `NetConfig`.

**Sizing check (worst realistic view):** 10 heroes × ~14 B + 40 Wardlings in the 60 m band × ~6 B + 30 in the 60–120 m band at 6 Hz (~1.2/tick × 6 B) + 6 `WaveSummary` × 2 Hz + objective block ≈ 450–600 B per tick, inside the 1100 B budget. A full keyframe (no baseline) of ~110 Wardlings is ~1.2 KB and is split across two ticks by the priority accumulator.

### 8.7 Lag compensation

- `HitboxHistory`: a ring buffer of `ceil(max_rewind_ms / tick_ms) + 2` ticks of `{net_id, capsule set}` per hurtable entity, stored in a `PackedFloat32Array` (no allocation).
- `LagCompensator.trace(shooter, origin, dir, range, view_tick, view_alpha)`:
  1. Clamp `view_tick` to `[tick − max_rewind_ticks, tick]`.
  2. Run a static-world physics ray (`intersect_ray`, world-geometry layer only) to find the occlusion distance.
  3. Interpolate the history poses at `view_tick + view_alpha`, run a broad phase over the SpatialHash along the segment, and a narrow phase ray-vs-capsule via `Geometry3D.segment_intersects_sphere/cylinder`.
  4. The nearest hit before occlusion wins; the headshot flag comes from the head capsule.
- Barricades, shield walls and other dynamic blockers are recorded in the history too (as boxes), so a rewound shot respects the blocker state at that time.
- Bots fire with `view_tick = tick` (no rewind).

### 8.8 Disconnects and robustness

- On disconnect the slot is handed to a bot on the same tick (C1). Reconnect within the match restores human control (M2: token-based).
- The server rejects malformed packets (size, ranges, unknown type) and drops peers after `NetConfig.max_violations`.
- **Host migration: not supported.** If a listen host leaves, the match ends; dedicated servers are the M2 answer. The network rule is "handle host migration gracefully", and here that means a clean end-of-match with a reason code instead of a migration.
- `net_sim_conditioner.gd` adds latency, jitter, loss and duplication to any `Transport`, for development and tests.

---

## 9. Bot Architecture

```
ServerWorld slot (human | bot) ─► InputBuffer ─► HeroSim         (HeroSim cannot tell the difference)
                                     ▲
             BotDirector ─► BotBrain(slot) ─► BotInputSource.emit(tick) → InputCommand
                              ├── BotSensor     (LOS/FOV-gated perception; no omniscience; hearing via SimEventQueue)
                              ├── Blackboard    (known enemies + last-seen tick, objective state, squad state, own resources)
                              ├── GoalSelector  (utility: PushHardpoint, DefendHardpoint, Fight, Retreat, ReturnToHQ, Shop, EscortSquad)
                              ├── Navigator     (NavigationServer3D.query_path, repath on goal change / 1 Hz)
                              └── AimHumanizer  (reaction delay, tracking error, flick overshoot from BotProfile)
```

- `InputSource` (abstract, `src/ai/input`) has implementations `PlayerInputSource` (devices → command) and `BotInputSource`. The same class can drive a **client-side** headless bot, which is how load and soak tests connect 9 fake players to a dedicated server in M2.
- Decisions run at `BotProfile.decision_hz` (default 5 Hz, staggered). Aim and movement are emitted every tick. Bots buy, spend skill points (via `BotRoleDef.build_order`) and issue all 4 squad commands (`SquadUsageRule` resources: e.g. GO_CAPTURE when the lane front is uncontested, ATTACK_TARGET on the bot's current fight target) through the same `Command` messages as players.
- Behaviour is authored per **role** first (`BotRoleDef`: Soldier, Healer, Tank, Commander…). Per-hero skill-usage rules are `BotSkillRule` resources (condition → slot).
- Debug: `ai_debug_draw.gd` draws path, goal, perception cone and utility scores. Every goal transition is logged on `Log.ai` (rate-limited).

---

## 10. Wardling AI

### 10.1 Brain (`WardlingBrain`, explicit transition table)

| State | Enter when | Exit to |
|---|---|---|
| `FOLLOW` | default; `SquadCommand.FOLLOW` | ENGAGE (enemy within aggro radius or owner damaged), HOLD, DISSOLVING |
| `HOLD` | `SquadCommand.HOLD(pos)` | ENGAGE (leash-limited), FOLLOW, DISSOLVING |
| `ENGAGE` | target acquired (priority: whoever damaged owner < 3 s → whoever damaged me → nearest threat in aggro) | RETURN (target lost/dead or leash exceeded), DISSOLVING |
| `RETURN` | leash exceeded | FOLLOW/HOLD on arrival |
| `ATTACK_TARGET` | `SquadCommand.ATTACK_TARGET(net_id)` | FOLLOW when the target dies, leaves `command_range_m` × 1.5 or after `focus_timeout_s`; DISSOLVING |
| `CAPTURE` | `SquadCommand.GO_CAPTURE(hp)`: path to the hardpoint, then work its task (presence for Hold, escort/defend for Plant, attack the Ward Generator for Breach) | ENGAGE (threat within zone), FOLLOW on a new command, DISSOLVING |
| `GARRISONED` | spawned by `Garrison` | ENGAGE within zone radius only |
| `MARCH` | Vanguard spawn; `LaneFrontResolver` target changed | ENGAGE (enemy within aggro), CAPTURE on arrival at the front hardpoint |
| `DISSOLVING` | owner died (10 s hold, C15) | despawn |

Squad Wardlings use FOLLOW/HOLD/ATTACK_TARGET/CAPTURE/ENGAGE/RETURN/DISSOLVING. Garrisons use GARRISONED/ENGAGE/RETURN. Vanguard members use MARCH/CAPTURE/ENGAGE/RETURN, which is selected by allegiance through a per-allegiance `WardlingAiDef.allowed_states`. Retaliation against whoever damaged the owner (C15) overrides FOLLOW/HOLD/CAPTURE but **not** ATTACK_TARGET.

**Wave-level thinking.** A `WaveBrain` per `VanguardWave` makes the expensive decisions once per wave: the front target, the path (one `NavigationServer3D.query_path` shared by the 4 members, each offset by a formation slot from `VanguardDef.formation`) and the threat list. Members then only pick a target from the wave's threat list. This makes 24 Vanguard cost about as much as 6 thinkers plus 24 cheap target picks.

`WardlingBrain` is a `RefCounted` struct-of-state per Wardling. It never touches the node except through intents. Transitions are table-driven (`const TRANSITIONS`) and logged.

### 10.2 Scheduling and LOD (`AiLodScheduler`)

| LOD | Condition | Decision interval | Repath | Avoidance |
|---|---|---|---|---|
| 0 | ≤ 40 m of any hero **or** damaged in last 3 s | every 3 ticks (10 Hz) | ≤ 2 Hz | on |
| 1 | 40–100 m | every 6 ticks (5 Hz) | 1 Hz | on |
| 2 | > 100 m (idle garrisons, Vanguard marching through empty lanes) | every 30 ticks (1 Hz) | on demand (wave path shared) | off (`avoidance_enabled=false`) |

- Staggering is by `net_id % interval`. A **deterministic cap** (`AiLodConfig.max_decisions_per_tick`, default 32 for ≤110 agents) defers the overflow to the next tick. The cap is count-based, never wall-clock-based, so sims stay reproducible.
- Movement integrates every tick for all LODs (`move_and_slide`, cheap); only *thinking* is LOD'd.
- Perception uses `SpatialHash` queries. LOS rays are pooled under a per-tick ray budget (`max_los_rays_per_tick`, default 40). Steady state at ≤110 agents is ≈ 110/3 ≈ 37 LOD0 worst case, but typically about 40% are LOD1/2. That gives ≈ 20–30 decisions per tick, which fits under the cap.

### 10.3 Navigation

- Each Wardling has a `NavigationAgent3D` with `avoidance_enabled`, `radius`, `max_speed` and `neighbor_distance` from `WardlingDef`. The movement code follows the reference pattern: set `nav_agent.velocity`, consume `velocity_computed(safe_velocity)` and store the result. The **next** tick's `move_and_slide` uses it (the one-tick latency is acceptable).
- Separate navigation layers: 1 = ground (heroes' bots + Wardlings). Barricades are carved per team with `NavigationObstacle3D` (owner team passes; affect_navigation_mesh vs avoidance-only to be verified on 4.7).
- The server world has its own `World3D` and therefore its own navigation map. Clients do no navigation (except the client-bot test harness).
- If profiling shows `NavigationAgent3D` node overhead above budget, the fallback is driving agents through `NavigationServer3D.agent_*` RIDs directly from `WardlingDirector` (no API change for brains).

---

## 11. UI and Presentation Boundary

- UI reads **view models** only (`MatchViewModel`, `HeroViewModel`), which `ClientWorld` updates from snapshots and events. Signals: `lumen_changed`, `cooldown_changed(slot, end_tick)`, `objective_changed(hardpoint_index)`, `kill_feed_added(entry)`.
- UI writes nothing except `UiCommand`s → `ClientSession.send_command()` (shop, skill point, spawn choice). A purchase becomes visible only after the server accepts it (`SHOP_RESULT` event).
- All strings go through `tr()` keys, and the `display_name_key` fields in Defs are translation keys.

---

## 12. Performance Budgets

| Target | Budget |
|---|---|
| Client, recommended spec | **144 fps** (6.94 ms) at 1080p: render ≤ 4.5 ms CPU-side, scripts ≤ 1.5 ms, prediction/reconcile ≤ 0.5 ms average, UI ≤ 0.4 ms |
| Client, minimum spec | **60 fps** (16.6 ms) at 1080p with medium preset |
| Client AI cost | 0 ms (AI is server-only), except debug client bots |
| Server tick (dedicated) | **≤ 10 ms per 33.3 ms tick** (30%, one core) with 10 heroes + 108 Wardlings (54 squad + 30 garrison + 24 Vanguard; Canon C1 budget ≤110) + 9 clients |
| ↳ breakdown | input/motor/abilities 1.0 · Wardling + wave decisions 1.6 · Wardling movement + nav/avoidance 2.6 · bots 0.4 · projectiles/effects/objectives 0.9 · hitbox history + lag comp 0.6 · snapshots (9 clients) 1.7 · slack 1.2 |
| Listen host | server ≤ 10 ms/tick amortised = ≤ 5 ms per rendered frame at 60 fps; host hardware must hold 60 fps (recommended spec only) |
| AI rule mapping | `.claude/rules/ai-code.md` "2 ms per frame": interpreted as **≤ 2 ms per server tick** for decisions (Wardlings and waves 1.6 + bots 0.4). Movement is costed separately. |
| Wardling count | Canon C1 budget **≤110**: squads ≤ 54 (8 × 5 + 2 Vespers × 7), Garrisons ≤ 30, Vanguard ≤ 24 → design max **108**; engineering headroom **120** (perf scenario spawns 120). M1 slice (1 lane, Vesper + Brannoc with duplicates, no Garrisons): squads typically 30–40, worst case 70 (10 Vespers at squad 7) + ≤ 8 Vanguard = **≤ 78**, plus the 120-agent stress scenario. |
| Bandwidth | ≤ 256 kbps down / ≤ 48 kbps up per client typical; ≤ 512 kbps down peak |
| Memory | client ≤ 3 GB RAM / 3 GB VRAM; dedicated server ≤ 1 GB RAM per match |
| Load | match load ≤ 15 s on SSD (Shader Baker pre-compiled pipelines) |

`TickProfiler` (server) and `tick_profiler_overlay` (client) record per-stage µs. CI fails the `perf_server_tick` sim test if the p95 tick cost exceeds the budget × 1.5 on the CI runner (CI hardware is slower, so the threshold is relative and recalibrated per runner image).

---

## 13. Testing Strategy (ADR-0006)

| Layer | Tool | What | Location |
|---|---|---|---|
| Unit | gdUnit4 | StatBlock order of ops; Modifier add/remove; skill tree gating (fork exclusivity, Mastery L9, ult 6/10/14); cooldown ticks; RespawnSystem formula; Incursion scoring; BitWriter/Reader round-trip; quantisation bounds; delta encode/decode against baseline; InterestManager priority; LagCompensator capsule rewind math; WardlingBrain transition table; AmmoFeeds | `tests/unit/[system]/[system]_[feature]_test.gd` |
| Integration | gdUnit4 + `ServerWorld` + `LoopbackTransport` | client connects, handshake rejects a bad content hash; input → movement → snapshot → reconciliation stays < ε at 0 ms; under `net_sim` 100 ms/2% loss the error stays bounded; buy flow; capture flips ownership; Uplink exposure | `tests/integration/[system]/` |
| Headless match sim | `MatchSimHarness` (`--sim-test`) | full matches bot-vs-bot at uncapped tick speed (`ServerWorld.step()` in a loop, no rendering). Asserts invariants: match ends ≤ `time_cap`, no NaN, ownership only changes via the C3 adjacency rule, Lumen never negative, tick p95 within budget. Emits a JSON report (length, captures, kills) for the match-length telemetry risk. | `tests/sim/scenarios/*.tres`, `tools/ci/run_sim_suite.sh` |
| Determinism | harness `--seed` + `StateHasher` | same seed + same binary + same platform ⇒ identical per-tick state hash. Used as a regression tripwire on CI Linux only; Jolt is not claimed to be cross-platform deterministic. | `tests/sim/` |
| Visual ("launch and look") | Movie Maker | `godot --path . --windowed --resolution 1280x720 --write-movie production/qa/evidence/<story>/shot.png --quit-after 90 res://src/ui/debug/scenes/<scene>.tscn`. Debug scenes boot straight into an offline match state from a `ScenarioDef`, which makes every feature reachable from a launch argument. | `production/qa/evidence/` |

Rules: no sim code reads wall-clock time; every RNG is a `SimRng` seeded from `match_seed` + a system salt; tests inject `ContentDB` fixtures; `auto_free()` for all nodes (orphans make gdUnit4 exit 101).

## 14. CI (GitHub Actions)

`.github/workflows/ci.yml` (to be written in M1 sprint 1):

1. `ubuntu-24.04` runner; cache the Godot binary keyed on `GODOT_VERSION=4.7-stable`. Download the official Linux x86_64 editor build plus export templates. *(Exact release asset names for 4.7 to be confirmed.)*
2. `godot --headless --path . --import` (a fresh clone has no `.godot/` class cache).
3. Parse check: `godot --headless --path . -s res://.claude/scripts/godot-parse-check.gd -- <changed .gd>`.
4. `tools/ci/check_deps.sh` (layer direction), then `validate_content.gd` (data integrity).
5. Unit and integration: `godot --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`. Exit codes 0 pass, 100/101/105 fail. JUnit report uploaded.
6. Sim suite (`run_sim_suite.sh`): 6 seeded bot matches of the slice ruleset plus the perf scenario; JSON uploaded as an artifact.
7. On `main`: Linux release export (`commands.build`) uploaded as an artifact; nightly: 50-match soak and a Windows export.
8. Advisory job: screenshot capture under `xvfb-run` with Mesa lavapipe (software Vulkan). Images are uploaded but do not gate, because Forward+ software rendering in CI is slow and unverified.

---

## 15. Verification List (APIs to confirm on 4.7 before ADRs move to Accepted)

1. `ENetMultiplayerPeer` used directly as a `PacketPeer` (`transfer_channel`, `transfer_mode`, `get_packet_peer`) without assigning it to `multiplayer.multiplayer_peer`.
2. `SubViewport.own_world_3d = true` gives a separate Jolt physics space **and** a separate navigation map, and a non-rendering SubViewport (`render_target_update_mode = UPDATE_DISABLED`) still steps physics for its world.
3. `move_and_slide()` called several times within one `_physics_process` (reconciliation replay) behaves identically to one call per tick under Jolt, including floor snapping and `is_on_floor()` state.
4. The `NavigationAgent3D.velocity_computed` dispatch timing relative to `_physics_process` in 4.7. The design tolerates one tick of latency.
5. SceneTree 3D physics interpolation (4.5 rework) with a 30 Hz tick and `reset_physics_interpolation()` on teleports/respawns.
6. `NavigationObstacle3D` carving a per-team barricade at runtime.
7. The gdUnit4 release that supports 4.7 and the CLI flags in `project.yaml`.
8. A dedicated-server export preset and `--headless` both strip rendering in 4.7 without breaking `Resource` loads of visual scenes referenced by Defs. Server code must load only `sim_scene`.

---

## 16. Risk Register

| # | Risk | P | I | Mitigation | Owner | Trigger to act |
|---|---|---|---|---|---|---|
| R1 | **GDScript server tick cost** for 10 heroes + ≤110 Wardlings (squads, Garrisons, Vanguard) + 9 snapshot builds exceeds 10 ms | M | H | Count-based AI LOD, SpatialHash, packed arrays, no per-tick allocation; M1 perf sim scenario; GDExtension candidates pre-identified (snapshot encoder, hitbox rewind, spatial hash) per ADR-0001 | technical-director | p95 > 10 ms in the 120-agent perf scenario |
| R2 | **Prediction/reconciliation jitter** with Jolt `CharacterBody3D` replay (verification item 3) | M | H | `HeroMotor` isolated as a pure step; reconciliation integration test under `net_sim`; fallback: custom kinematic motor on `PhysicsServer3D.body_test_motion` | network-programmer | reconcile corrections > 1 per second at 0% loss |
| R3 | **30 Hz tick feels unresponsive** for a competitive FPS (hit reg, peeker's advantage) | M | M | Mouse look per render frame; lag comp; rate is data (`NetConfig`); benchmark 60 Hz after M1 | network-programmer | playtest complaints or server headroom > 50% |
| R4 | **Bandwidth spikes in big fights** (60+ Wardlings in view once Vanguard waves collide with squads at a contested hardpoint) | M | M | Priority accumulator under a hard byte budget; Wardling records ≤ 6 B; LOD rates; Vanguard far-field sent as `WaveSummary` | network-programmer | budget overflow > 10% of ticks |
| R5 | **Two worlds in one process** (listen/offline) misbehave: physics or nav separation, double cost | M | H | Verification items 2 and 4 in sprint 1; fallback: offline mode spawns a headless server **child process** (`OS.create_process`) over ENet localhost | technical-director | separation test fails |
| R6 | **Bot quality** (bots fill PvP and future co-op) | H | M | Role-first utility AI, humanizer from data, sim harness metrics (captures/min, K/D spread) | ai-programmer | bot-vs-bot matches outside 20–45 min |
| R7 | **Godot 4.7 deltas unknown** (reference verified for 4.6) | M | M | §15 list; ADRs stay Proposed until verified; pin the exact editor build in CI | technical-director | any verification failure |
| R8 | **Lag-comp exploits / cheating** (`view_tick` abuse, speed hacks, wallhacks) | M | H | `view_tick` clamped to 200 ms; input count cap; server-only perception and reveal-gated replication | network-programmer | M2 external playtest |
| R9 | **Determinism drift** breaks sim regression tests | M | L | Hashes are a same-platform tripwire only; gating invariants are not hash-based | lead-programmer | flaky hash on the same runner |
| R10 | **Data sprawl** (28 skills, 56 forks, mods) without validation | H | M | `ContentValidator` in CI; skill nodes restricted to Modifiers and `added_effects` | lead-programmer | validator false negatives in review |
| R11 | **CI cannot render Forward+** for screenshot evidence | H | L | Screenshots taken locally per run-and-observe; CI capture advisory under lavapipe | qa | — |
| R12 | **Listen-host advantage** (0 ms host) in LAN | H | L | Accepted for M1 LAN; competitive play uses a dedicated server (M2) | technical-director | — |
| R13 | **AI population growth** (C15 revision added Vanguard; further canon creep pushes past 120 agents, plus navigation/avoidance congestion at chokepoints and Barricades) | M | H | Canon cap expressed as `VanguardDef`/`SquadDef`/`GarrisonDef` data, checked by `ContentValidator` against `AiLodConfig.max_agents`; wave-level brains; avoidance off at LOD2; `NavigationServer3D` RID fallback | technical-director | live agent count > 110 in sim telemetry, or avoidance cost > 1 ms/tick |
| R14 | **Squad commands as an exploit surface** (ATTACK_TARGET on unseen targets = wallhack-by-proxy; GO_CAPTURE spam) | M | M | Server LOS/range validation at the rewound issuing tick; per-player command rate limit in `NetConfig` | network-programmer | M1 playtest |

---

## 17. Milestone Mapping

| Milestone | Architecture delivered |
|---|---|
| **M1 — offline slice** (1 lane "Shardline Causeway", Vesper Loom + Brannoc with duplicates, bots) | All of §2–§13 in `OFFLINE` and `SIM_TEST` modes; `LoopbackTransport` (with `--net-sim`); prediction/reconciliation; lag comp; interest management active even locally; Hold task first, then Plant and Breach behind `task_kind` within M1; squad with all 4 commands; Vanguard waves on the slice lane; levels and the reduced skill tree (UNLOCK/BOOST/ULT_RANK nodes); minimal mount shop; Uplink exposure; CI with unit, integration and sim suite. Garrisons, Barricades and Supply Caches are M3 |
| **M2 — online PvP** | `ENetTransport`, `LISTEN_HOST` and `CLIENT` modes, `DEDICATED` export and headless server, auth token in `Hello`, reconnect, soak/load tests with client-side bots over ENet, bandwidth telemetry, NAT/hosting decision (new ADR) |
