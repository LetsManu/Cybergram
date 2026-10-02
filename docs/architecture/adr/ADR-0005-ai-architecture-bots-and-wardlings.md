# ADR-0005: AI Architecture — Bots as Input Sources, Wardlings as LOD-Scheduled Server Brains

## Status

Proposed

> Only the user, or technical-director on the user's explicit confirmation, may set this to `Accepted`.

## Date

2026-10-02

## Last Verified

2026-10-02

## Decision Makers

technical-director (author), lead-programmer, network-programmer; ai-programmer to own implementation. Written autonomously.

## Summary

Cybergram needs bots that fill any of 10 hero slots, and about 100 Wardlings (squads ≤ 50, Garrisons ≤ 30, Vanguard waves ≤ 24, per the 2026-10-02 C15 revision), within ≤ 2 ms of AI decision time per server tick. **Bots produce the same `InputCommand`s as humans** through an `InputSource` interface, so the hero sim cannot tell them apart. **Wardlings are server-only bodies with table-driven brains** scheduled by a deterministic LOD scheduler. Vanguard waves think once per wave, navigation uses `NavigationServer3D` with RVO avoidance, and perception is LOS-gated with no omniscience.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.7 |
| **Domain** | Navigation / Scripting |
| **Layer** | Feature |
| **Knowledge Risk** | MEDIUM |
| **References Consulted** | `modules/navigation.md`, `modules/physics.md` |
| **Post-Cutoff APIs Used** | None known; `NavigationAgent3D` avoidance API as in 4.3–4.6 |
| **Verification Required** | `velocity_computed` dispatch timing vs `_physics_process` on 4.7; avoidance cost for 120 agents; runtime `NavigationObstacle3D` for team Barricades; per-`World3D` navigation map inside a `SubViewport` |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (input path, server-only AI), ADR-0003 (AI Defs), ADR-0004 (bots use skills via inputs) |
| **Enables** | Bot epic, Wardling/Squad/Vanguard epic, sim-harness tests (ADR-0006) |
| **Blocks** | M1 bot opponents; M1 Wardlings |
| **Ordering Note** | `InputSource` abstraction lands with the first networking story. |

## Context

### Problem Statement
Bots must fill PvP and later power co-op. Cheating bots (wall vision, perfect aim) would undermine Pillar 2. ~100 Wardlings at 30 Hz in GDScript would exceed budget if every agent thought every tick. Canon C15 now gives squads 4 commands (Follow, Hold Here, Attack Target, Go Capture) and adds ownerless Vanguard waves that march to a computed lane front.

### Constraints
- `.claude/rules/ai-code.md`: ≤ 2 ms AI per frame (mapped to ≤ 2 ms decisions per server tick); data-tunable; debug visualisation; logged transitions; utility or behaviour-tree style over if/else chains.
- Deterministic under a fixed seed for sim tests.

## Decision

### Bots
1. `@abstract InputSource.produce(tick: int, out_cmd: InputCommand)`, implemented by `PlayerInputSource` and `BotInputSource`. Bots run in `BotDirector` on the server (tick-order stage 2). The same class can run in a headless **client** for load tests.
2. `BotBrain` = `BotSensor` (LOS/FOV-gated; hearing via `SimEventQueue` sound events) + `Blackboard` + **utility `GoalSelector`** (PushHardpoint, DefendHardpoint, Fight, Retreat, ReturnToHQ, Shop, EscortSquad) + `Navigator` + `AimHumanizer` (reaction ms, tracking error, overshoot from `BotProfile`).
3. Decisions run at `BotProfile.decision_hz` (5 Hz, staggered); aim/move are emitted every tick. Bots buy, level skills and issue all 4 squad commands through standard `Command`s, driven by `BotRoleDef` build orders and `SquadUsageRule`s.
4. Bots fire with `view_tick = current tick` (no rewind advantage).

### Wardlings
5. **Body vs brain:** `WardlingSim` (gameplay) exposes intents only (`set_move_target`, `set_attack_target`, `stop`). `WardlingBrain` (ai, `RefCounted`) holds state and a `const TRANSITIONS` table. States: FOLLOW, HOLD, ATTACK_TARGET, CAPTURE, ENGAGE, RETURN, GARRISONED, MARCH, DISSOLVING. The allowed subset is chosen per allegiance (SQUAD / GARRISON / VANGUARD) by `WardlingAiDef.allowed_states`.
6. **Squad commands** arrive as `SquadCommand` from `Squad` (server-validated: ATTACK_TARGET needs owner LOS at the rewound issuing tick and range ≤ `SquadDef.command_range_m`). Retaliation against whoever damaged the owner overrides FOLLOW/HOLD/CAPTURE, not ATTACK_TARGET.
7. **Vanguard:** `VanguardSpawner` (gameplay) enforces 4 per lane per team every 60 s, with at most one live wave per lane per team (≤ 24). A `WaveBrain` per wave computes the front via `LaneFrontResolver` (C15 rule), one shared path and a threat list. Members follow formation offsets and pick targets from the wave list.
8. **LOD scheduling** (`AiLodScheduler`): LOD0 ≤ 40 m of a hero or recently damaged → 10 Hz; LOD1 40–100 m → 5 Hz; LOD2 > 100 m → 1 Hz with avoidance off. Staggered by `net_id`. A **count-based** cap `max_decisions_per_tick` (32) defers overflow, never wall-clock based. Movement integrates every tick for all agents.
9. **Navigation:** `NavigationAgent3D` per Wardling with avoidance from `WardlingDef`. Safe velocity from `velocity_computed` is applied on the next tick. Paths come from `NavigationServer3D.query_path` (shared per wave). Fallback, if node overhead is too high: drive `NavigationServer3D.agent_*` RIDs directly from `WardlingDirector`.
10. **Perception:** `SpatialHash` neighbour queries; LOS rays limited to `max_los_rays_per_tick` (40).
11. **Debug:** `ai_debug_draw.gd` shows path, state, target, utility scores and perception; transitions are logged on `Log.ai` (rate-limited).

### Key Interfaces
```gdscript
@abstract class_name InputSource extends RefCounted
@abstract func produce(tick: int, out_cmd: InputCommand) -> void

class_name WardlingDirector extends RefCounted
func think(tick: int) -> void                       # waves first, then LOD buckets
signal brain_state_changed(net_id: int, from: int, to: int)

class_name LaneFrontResolver extends RefCounted
func front_for(team: int, lane: int) -> int          # hardpoint index (C15 rule)
```

## Alternatives Considered

### Alternative 1: Behaviour trees (addon such as Beehave/LimboAI) for everything
- **Pros**: visual editing; familiar.
- **Cons**: per-agent tree ticking is costly at ~100 agents in GDScript; Wardling logic is small and fits an FSM; an addon dependency must track 4.7.
- **Rejection Reason**: FSM tables for Wardlings and utility for bots are cheaper and sufficient. A BT addon may be reconsidered for bots only.

### Alternative 2: Bots that manipulate `HeroSim` directly
- **Rejection Reason**: Creates a second control path that bypasses validation and netcode, and cannot be reused client-side for load tests.

### Alternative 3: Per-agent thinking every tick
- **Rejection Reason**: ~100 × 30 Hz decisions blow the 2 ms budget.

## Consequences

### Positive
- Bots exercise exactly the code humans do, so every bot match is a netcode and gameplay test.
- Deterministic, bounded AI cost regardless of agent count.

### Negative
- Up to 100 ms decision latency at LOD1 is visible in edge cases (mitigated: damage bumps an agent to LOD0).
- Humanised bots need tuning time per role.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Avoidance congestion at Barricades/hardpoints with waves + squads | M | M | Formation offsets; avoidance priority by allegiance; obstacle carving |
| Bots feel dumb or unfair | H | M | Role-first utility, `BotProfile` difficulty tiers, sim telemetry |
| Agent count creep beyond 120 | M | H | Validator check against `AiLodConfig.max_agents` |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Wardling + wave decisions | n/a | ~1.2–1.6 ms/tick | 1.6 ms |
| Wardling movement + avoidance (≤120) | n/a | ~2.0–2.6 ms/tick | 2.6 ms |
| Bots (≤10) | n/a | ~0.3 ms/tick | 0.4 ms |

## Validation Criteria

- [ ] The 120-agent perf scenario keeps AI decisions ≤ 2 ms p95 per tick.
- [ ] Unit tests cover every row of the Wardling transition table and the `LaneFrontResolver` cases (contested, attackable, fallback).
- [ ] Vanguard never exceeds 1 live wave per lane per team over 50 simulated matches.
- [ ] Bot-vs-bot slice matches end within the time cap with ≥ 1 capture per 3 min.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/game-concept.md` | C1 | Bots fill empty or disconnected slots | `BotInputSource` into the slot's `InputBuffer` |
| `design/gdd/game-concept.md` | C15 | Squad 4 commands; retaliation; Vanguard 4/lane/60 s, 1 live wave | Brain states, `Squad`, `VanguardSpawner`, `WaveBrain` |
| `design/gdd/game-concept.md` | C4, C5 | Wardlings count 0.5 for Hold; Garrisons | CAPTURE state; GARRISONED state |
| `design/gdd/game-concept.md` | Pillar 3 | One-key commands, no RTS micro | Commands are intents; no unit selection |

## Related

- `docs/architecture/architecture.md` §9, §10
- ADR-0002, ADR-0006
