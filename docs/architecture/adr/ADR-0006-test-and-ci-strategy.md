# ADR-0006: Test and CI Strategy — gdUnit4, Headless Match Sim, Movie-Maker Screenshots, GitHub Actions

## Status

Proposed

> Only the user, or technical-director on the user's explicit confirmation, may set this to `Accepted`.

## Date

2026-10-02

## Last Verified

2026-10-02

## Decision Makers

lead-programmer (author), technical-director; qa-lead consulted by role definition. Written autonomously.

## Summary

The project needs logic tests, multi-system network tests, whole-match regression and the mandatory "launch and look" evidence, all runnable unattended on a headless Linux runner. We use **gdUnit4** for unit and integration tests, a **headless deterministic match-sim harness** that steps `ServerWorld` with bot clients over `LoopbackTransport`, **Movie Maker (`--write-movie`)** screenshots for visual evidence, and **GitHub Actions** running a pinned headless Godot 4.7.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.7 |
| **Domain** | Core / Tooling |
| **Layer** | Foundation |
| **Knowledge Risk** | MEDIUM |
| **References Consulted** | `current-best-practices.md` (Command Line — Tests and Parse Check), `.claude/docs/run-and-observe.md`, `.claude/docs/coding-standards.md`, `.claude/rules/test-standards.md` |
| **Post-Cutoff APIs Used** | None beyond the CLI flags documented for 4.6 |
| **Verification Required** | gdUnit4 version supporting 4.7 and its exit codes (0/100/101/103/105); `--write-movie` + `--quit-after` on 4.7; Forward+ under Mesa lavapipe on `ubuntu-24.04` |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001, ADR-0002 (stepable `ServerWorld`, loopback) |
| **Enables** | All story Definition-of-Done gates |
| **Blocks** | M1 sprint 1 closes only with CI green |
| **Ordering Note** | `/test-setup` scaffolding is the first sprint-1 task alongside the transport. |

## Context

### Problem Statement
Netcode and AI bugs show up only across many ticks and conditions; logic tests alone miss them. The coding standards require tests for logic and a retained screenshot for anything player-visible. CI has no GPU.

### Constraints
- Deterministic tests: no wall-clock, no unseeded RNG.
- Unit tests have no file or network I/O (fixtures via factories / injected `ContentDB`).
- Headless CI cannot render Forward+ reliably.

## Decision

1. **Unit tests (gdUnit4)** in `tests/unit/[system]/[system]_[feature]_test.gd`, functions named `test_[scenario]_[expected]`, Arrange/Act/Assert, `auto_free()` for nodes. Priority targets: StatBlock, skill tree gating, cooldown ticks, respawn/Incursion formulas, codecs and quantisation, delta baselines, InterestManager priority, LagCompensator rewind, Wardling transition table, `LaneFrontResolver`, `VanguardSpawner` cap.
2. **Integration tests** in `tests/integration/[system]/` instantiate `ServerWorld` + `ClientWorld` with `LoopbackTransport` and `NetSimConditioner` (latency/jitter/loss from the fixture). They cover handshake/version reject, prediction-reconciliation error bounds, buy flow, capture → ownership → Uplink exposure, and bot slot takeover on disconnect.
3. **Match-sim harness** (`MatchSimHarness`, `--sim-test <ScenarioDef.tres>`): headless; calls `ServerWorld.step()` in a tight loop (no real-time wait), with bots in all slots, optionally as headless client bots over loopback to exercise snapshots. It asserts invariants (match ends ≤ cap; no NaN; ownership changes obey C3; Lumen ≥ 0; ≤ 1 live Vanguard wave per lane per team; agent count ≤ `max_agents`; tick p95 within budget) and writes a JSON report (length, captures, kills, bandwidth, per-stage µs).
4. **Determinism tripwire:** every system draws from `SimRng(match_seed, salt)`, and `StateHasher` hashes the authoritative state per N ticks. Same seed + same binary + same platform must reproduce the hash; this is checked on CI Linux only. Gating uses invariants, not hashes, because Jolt is not assumed cross-platform deterministic.
5. **Performance test:** `perf_server_tick` scenario (10 bot heroes, 120 Wardlings, 9 loopback clients). It fails if p95 > budget × `ci_perf_factor` (runner-calibrated, stored in the scenario).
6. **Visual evidence:** `godot --path . --windowed --resolution 1280x720 --write-movie production/qa/evidence/<story>/shot.png --quit-after 90 <debug scene>` locally. Debug scenes under `src/ui/debug/scenes/` boot an offline match from a `ScenarioDef`, so every feature is reachable from a launch argument. The last frame is retained, per run-and-observe.
7. **CI (`.github/workflows/ci.yml`)** on push to `main` and on PRs, on `ubuntu-24.04`:
   - install + cache Godot `4.7-stable` (exact asset name to be confirmed) and export templates;
   - `--headless --import`;
   - parse check;
   - `check_deps.sh` + `validate_content.gd`;
   - gdUnit4 (`godot --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`);
   - sim suite (6 seeds + perf);
   - Linux export on `main`.

   **Blocking:** parse, deps, content, unit, integration, sim invariants. **Advisory:** perf on shared runners, screenshot capture under `xvfb-run` + lavapipe. Nightly: 50-match soak and a Windows export.
8. Never skip or disable failing tests. Every bug fix gets a regression test watched failing first (`.claude/rules/test-standards.md`).

### Key Interfaces
```gdscript
class_name MatchSimHarness extends RefCounted
func run(scenario: ScenarioDef, seed: int) -> SimReport   # no rendering, uncapped speed

class_name ScenarioDef extends Resource
@export var rules: MatchRulesDef
@export var map: MapDef
@export var bot_slots: Array[StringName]   # hero ids
@export var max_ticks: int
@export var net_conditions: NetConfig
@export var ci_perf_factor: float = 1.5
```

## Alternatives Considered

### Alternative 1: GUT (Godot Unit Test) instead of gdUnit4
- **Pros**: simple and popular.
- **Cons**: the project's `commands.test` and rules already standardise on gdUnit4 (CLI, exit codes, orphan detection).
- **Rejection Reason**: Consistency with existing framework tooling.

### Alternative 2: Real-time networked bot matches as the only integration test
- **Rejection Reason**: Slow (minutes per match) and nondeterministic. The stepped harness gives 30–60× speed.

### Alternative 3: Gating CI on GPU screenshots
- **Rejection Reason**: No GPU runner; software Forward+ is unverified. Kept advisory; evidence is local per run-and-observe.

## Consequences

### Positive
- Netcode, AI and rules are regression-tested together every push.
- Match-length telemetry exists from M1 (concept risk "match length drift").

### Negative
- Harness and fixtures are real engineering cost in sprint 1.
- Perf gating on shared runners is noisy, hence advisory there.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| gdUnit4 incompatible with 4.7 at start | L | M | Pin a version; fallback to the latest compatible release |
| Flaky sim tests from hidden nondeterminism | M | M | Lint for `randf()`/`Time.` in `src/gameplay|ai`; `/test-flakiness` |
| CI time grows with the sim suite | M | L | Parallel jobs; full soak nightly only |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CI wall time (PR) | n/a | ~8–12 min | 15 min |
| Sim speed | n/a | ≥ 30× real time for the slice | — |

## Validation Criteria

- [ ] CI green on an empty project skeleton with one test of each kind.
- [ ] A seeded sim reproduces its state hash twice on the same runner.
- [ ] A deliberately injected ownership bug (C3 violation) fails the sim invariant check.
- [ ] Screenshot evidence exists for each player-visible M1 story.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/game-concept.md` | Top Risks | Match length drift; telemetry from playtests with bots | Sim harness JSON reports |
| `design/gdd/game-concept.md` | C3, C7, C15 | Ownership adjacency, Uplink exposure, Vanguard cap | Sim invariants + integration tests |

Foundational: also enables every system's test evidence gate.

## Related

- `docs/architecture/architecture.md` §13, §14
- `.claude/docs/run-and-observe.md`, `.claude/rules/test-standards.md`
