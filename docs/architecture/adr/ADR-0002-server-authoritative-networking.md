# ADR-0002: Server-Authoritative Networking with a Local Server for Offline Play

## Status

Proposed

> Only the user, or technical-director on the user's explicit confirmation, may set this to `Accepted`.

## Date

2026-10-02

## Last Verified

2026-10-02

## Decision Makers

network-programmer (author), technical-director, lead-programmer. Written autonomously.

## Summary

A 5v5 FPS-MOBA with ~100 AI agents needs cheat-resistant, lag-compensated netcode. The owner requires that it is never retrofitted, even though M1 is offline/LAN only. **Every mode runs the same `ServerWorld` at a fixed 30 Hz tick.** Clients talk to it only through versioned binary messages over a `Transport`: in-memory `LoopbackTransport` offline, `ENetMultiplayerPeer` used as a raw packet peer on LAN/online. The design uses client-side prediction for movement, snapshot interpolation, delta-compressed per-client snapshots with interest management, and lag-compensated hitscan.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.7 |
| **Domain** | Networking / Physics |
| **Layer** | Foundation |
| **Knowledge Risk** | HIGH (4.6-verified reference; 4.7 unverified) |
| **References Consulted** | `modules/networking.md`, `modules/physics.md`, `breaking-changes.md` |
| **Post-Cutoff APIs Used** | Jolt `CharacterBody3D` behaviour under replay; SceneTree physics interpolation (4.5) |
| **Verification Required** | (1) `ENetMultiplayerPeer` packet API (`put_packet`, `get_packet`, `transfer_channel`, `transfer_mode`, `get_packet_peer`) used without `SceneMultiplayer`; (2) `SubViewport.own_world_3d` isolates the physics space and navigation map; (3) multiple `move_and_slide()` calls in one physics frame for replay; (4) 3D physics interpolation at 30 Hz |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 |
| **Enables** | ADR-0004 (prediction flags on skills), ADR-0005 (bots as input sources), ADR-0006 (loopback sim tests) |
| **Blocks** | Hero movement, weapons, Wardlings, objectives, and all UI epics in M1 |
| **Ordering Note** | Transport + `ServerWorld`/`ClientWorld` split is the first code written in M1. |

## Context

### Problem Statement
If M1 is built as a single-player game with "local" state, M2 online play would require rewriting every system's authority and replication. The concept's top technical risk is netcode for 10 heroes plus ~100 Wardlings (squads ≤ 50, Garrisons ≤ 30, Vanguard ≤ 24).

### Constraints
- First-person aiming needs < 1 frame of perceived input latency for movement and look, and fair hit registration up to ~150 ms RTT.
- GDScript server cost ≤ 10 ms/tick (ADR-0001).
- Bandwidth ≤ 256 kbps down per client typical.
- No host migration requirement in M1/M2 (a listen host leaving ends the match).

## Decision

1. **Authority:** the server owns all gameplay state. Clients send `InputBatch` (unreliable, last 3 commands, every tick) and `Command` (reliable: buy, skill point, squad command, spawn choice). The server validates ranges, sizes, rates and `view_tick` bounds.
2. **Tick:** 30 Hz fixed (`NetConfig.tick_rate_hz`; `Engine.physics_ticks_per_second` set from it). One `TickRunner` runs systems in the fixed order of architecture §8.3. Mouse look is applied per rendered frame. 60 Hz is reconsidered with M1 perf data.
3. **Modes:** `OFFLINE` and `LISTEN_HOST` host `ServerWorld` inside a `SubViewport` with `own_world_3d = true` in the same process; the local client connects through `LoopbackTransport`. `DEDICATED` runs `ServerWorld` headless. `CLIENT` runs `ClientWorld` only. **There is no code path where the client simulates authoritative state.**
4. **Transport layer:** a custom `Transport` interface over `ENetMultiplayerPeer` packets with 4 channels (0 reliable control, 1 reliable events/commands, 2 unreliable snapshots, 3 unreliable inputs). `@rpc`, `MultiplayerSynchronizer` and `MultiplayerSpawner` are **forbidden for gameplay**, because they cannot provide per-client baselines, priority-under-budget or relevancy at our entity count. `SceneMultiplayer` may be used later for lobby/auth only.
5. **Prediction:** own hero movement through the shared `HeroMotor.step()`; skills flagged `predicted_motion`; weapon cosmetics; cooldown start. Reconciliation compares predicted vs authoritative state at `last_processed_input_seq`, resets and replays (max 16 ticks) when the error exceeds `reconcile_epsilon_m`, and smooths the visual error over 100 ms.
6. **Remote entities:** snapshot interpolation with a 3-tick (100 ms) delay and at most 1 tick of extrapolation.
7. **Snapshots:** per client, delta against the newest acked baseline (32-entry `BaselineStore`), changed-field masks, quantised fields (position 1/32 m i16, Wardling yaw u8, HP u8%). The budget is 1100 B per tick per client, filled by a **priority accumulator**.
8. **Interest management:** `SpatialHash` (16 m cells). Heroes within 80 m or LOS-revealed; enemy heroes never sent unless revealed. Wardlings full rate ≤ 60 m, 6 Hz to 120 m, then dropped. Vanguard waves additionally replicated as 2 Hz `WaveSummary` aggregates. Objectives always.
9. **Lag compensation:** `HitboxHistory` ring of capsule poses per hurtable entity (and dynamic blockers). Hitscan rewinds to the client's `view_tick + view_alpha`, capped at 200 ms. Static occlusion uses a live physics ray; target hit testing uses `Geometry3D` segment-vs-capsule math (no moving physics bodies). Projectiles are server-simulated and not rewound.
10. **Versioning:** `Hello{protocol_version, content_hash}`. A mismatch gives `Reject` with a reason code. Message codecs carry their own version byte when their layout changes.

### Key Interfaces
```gdscript
class_name InputCommand extends RefCounted   # pooled
var seq: int; var move: Vector2; var yaw: float; var pitch: float
var buttons: int; var view_tick: int; var view_alpha: float

class_name ServerWorld extends Node3D
func _init(content: ContentDB, rules: MatchRulesDef, net: NetConfig, seed: int) -> void
func step() -> void                             # one tick; callable directly by the sim harness
signal match_ended(winner_team: int, reason: int)

class_name LagCompensator extends RefCounted
func trace(shooter_net_id: int, origin: Vector3, dir: Vector3, range_m: float,
		view_tick: int, view_alpha: float, out_hit: HitResult) -> bool
```

## Alternatives Considered

### Alternative 1: Godot high-level multiplayer (`@rpc` + `MultiplayerSynchronizer`/`Spawner`)
- **Pros**: least code; editor-configured replication; visibility filters exist.
- **Cons**: no per-client delta baselines or byte budgets; synchronizer per node does not scale to ~120 entities × 9 clients; prediction and rewind still hand-written.
- **Rejection Reason**: Bandwidth and control at our entity count.

### Alternative 2: Deterministic lockstep / rollback of the whole sim
- **Pros**: tiny bandwidth (inputs only).
- **Cons**: Jolt and GDScript floats are not guaranteed cross-machine deterministic; 100 AI agents make full rollback expensive; late-join and reconnect are hard.
- **Rejection Reason**: Determinism cannot be guaranteed on this stack.

### Alternative 3: Build M1 single-player and add networking in M2
- **Rejection Reason**: Explicitly ruled out by the owner. It would mean a retrofit of every system.

### Alternative 4: Offline mode spawns a headless server child process (ENet over localhost)
- **Pros**: perfect world isolation; identical to dedicated.
- **Cons**: two processes to manage; slower startup; harder debugging.
- **Rejection Reason**: Kept as the **fallback** if verification item (2) fails.

## Consequences

### Positive
- M2 online is a deployment problem, not a rewrite. Bots, tests and humans use one path.
- The sim harness can step `ServerWorld` without rendering at uncapped speed.

### Negative
- A listen/offline host pays for two physics worlds.
- More upfront code in M1: codecs, baselines, prediction.
- The 30 Hz tick limits hit-registration granularity (mitigated by rewind interpolation).

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Jolt replay mismatch causes constant corrections | M | H | Reconcile integration test under `net_sim`; fallback motor on `body_test_motion` |
| World isolation in a SubViewport fails | M | H | Fallback: child-process server (Alternative 4) |
| `view_tick` abuse | M | H | 200 ms clamp; monotonic seq; input count cap |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Server snapshot build (9 clients) | n/a | ~1.5 ms/tick | 1.7 ms |
| Client predict + reconcile | n/a | ≤ 0.5 ms avg | 0.5 ms |
| Network down / up per client | n/a | ~120–200 / ~35 kbps | 256 / 48 kbps |

## Validation Criteria

- [ ] Offline match runs entirely through `LoopbackTransport`; a grep finds no `@rpc` in `src/gameplay`.
- [ ] Under `net_sim` 100 ms RTT ±10 ms, 2% loss: < 1 visible correction per 10 s of movement.
- [ ] Rewound hitscan hits a target strafing at max speed when the client aimed on it, at 150 ms RTT (integration test).
- [ ] Snapshot ≤ 1100 B for 99% of ticks in the 120-agent scenario.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/game-concept.md` | C1 | 5v5; bots replace disconnected players | Slot-based `InputBuffer`; a bot takes the slot on disconnect |
| `design/gdd/game-concept.md` | C15, Top Risks | ~10 heroes + ~100 AI replicated | Interest management, priority budget, `WaveSummary` |
| `design/gdd/game-concept.md` | Pillar 2 | Shooter hands: aim decides fights | Prediction + lag-compensated hitscan |
| `design/gdd/game-concept.md` | Scope Tiers | Offline/LAN M1, online M2 | One server path in all modes |

## Related

- `docs/architecture/architecture.md` §2, §8
- ADR-0005 (bots as input sources), ADR-0006 (loopback tests)
