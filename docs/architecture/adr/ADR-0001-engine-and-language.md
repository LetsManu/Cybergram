# ADR-0001: Engine and Language — Godot 4.7 + GDScript, GDExtension by Exception

## Status

Proposed

> Only the user, or technical-director on the user's explicit confirmation, may set this to `Accepted`.

## Date

2026-10-02

## Last Verified

2026-10-02

## Decision Makers

technical-director (author), lead-programmer, network-programmer. Written autonomously (`modes.automation: autonomous`).

## Summary

Cybergram needs one engine and language for client, listen server, dedicated server and headless test runs. We use **Godot 4.7 stable with GDScript** (statically typed) throughout, Forward+ rendering and Jolt 3D physics. **GDExtension (C++)** is allowed only for a measured hot path that misses its budget after algorithmic fixes.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.7 stable |
| **Domain** | Core / Scripting |
| **Layer** | Foundation |
| **Knowledge Risk** | HIGH: 4.4–4.7 are post-cutoff; the reference is verified for 4.6 only |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `breaking-changes.md`, `current-best-practices.md`, `modules/physics.md` |
| **Post-Cutoff APIs Used** | Jolt default (4.6), `@abstract` (4.5), `Resource.duplicate_deep()` (4.5), SceneTree physics interpolation (4.5) |
| **Verification Required** | Exact 4.7 editor build pinned in CI; gdUnit4 release compatible with 4.7; headless run of `--sim-test` on Linux; dedicated-server export preset on 4.7 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0002, ADR-0003, ADR-0004, ADR-0005, ADR-0006 |
| **Blocks** | Every M1 epic |
| **Ordering Note** | Must be Accepted first. |

## Context

### Problem Statement
The owner fixed the stack (Godot 4.7, GDScript, Forward+, Jolt). This ADR records **where the boundaries of that choice are**: typed GDScript conventions, when native code is justified, and how we keep a team without C++ specialists productive while a ~100-agent server sim runs at 30 Hz.

### Constraints
- PC first; Linux CI runners; no paid engine.
- A small team. GDScript iteration speed matters more than raw throughput until profiling says otherwise.
- The server sim (10 heroes, ≤ 120 Wardlings, 9 snapshot builds) must stay ≤ 10 ms per 33.3 ms tick (architecture §12).
- The reference docs lag the pinned version, so any 4.7 API must be verified before an ADR depending on it is Accepted.

## Decision

1. **GDScript, statically typed everywhere.** Every variable, parameter and return is typed; `class_name` on every reusable class; `@abstract` for interfaces (`Transport`, `InputSource`, `AmmoFeed`, `EffectDef`). Untyped `Variant` is allowed only at serialization boundaries.
2. **Hot-path discipline in GDScript** (from `.claude/rules/engine-code.md`): no allocation per tick; `PackedFloat32Array`/`PackedInt32Array` storage for stats, hitbox history and snapshots; object pools; built-in C++ helpers preferred (`Geometry3D`, `PackedByteArray.encode_*`, `NavigationServer3D`).
3. **GDExtension gate.** A system may move to C++ (godot-cpp, `godot-gdextension-specialist`) only when **all** of these hold:
   - a `TickProfiler` measurement shows the stage exceeds its §12 budget at the 120-agent perf scenario;
   - an algorithmic fix (LOD, caching, fewer calls) was tried and measured;
   - the GDScript version stays as the reference implementation and the gdUnit4 tests run against both.

   Pre-identified candidates are `SnapshotEncoder` (bit packing/delta), `HitboxHistory` + capsule rewind, and `SpatialHash`. Gameplay rules (abilities, objectives, economy) never move to C++.
4. **Physics:** Jolt (project default). Hit detection does not depend on Jolt determinism (ADR-0002).
5. **Rendering:** Forward+, cel shading; Shader Baker for pipeline pre-compilation.
6. **Version pin:** `project.yaml engine.version: "4.7"` plus an exact build id in CI (`GODOT_VERSION`). Upgrading the engine requires re-running the architecture §15 verification list.

### Key Interfaces
```gdscript
@abstract class_name Transport extends RefCounted
@abstract func poll() -> void
@abstract func send(peer_id: int, channel: int, bytes: PackedByteArray, reliable: bool) -> void
@abstract func drain(out_packets: Array[NetPacket]) -> void
```

## Alternatives Considered

### Alternative 1: C# (.NET) for gameplay
- **Pros**: faster CPU-bound code; strong tooling.
- **Cons**: owner chose GDScript; .NET export maturity and team skill; two languages in one codebase.
- **Rejection Reason**: Not needed before measurement. GDExtension covers the narrow hot paths.

### Alternative 2: Server core entirely in C++ GDExtension from day 1
- **Pros**: maximum headroom for ~100 agents.
- **Cons**: slow iteration on rules that the design will churn; specialist bottleneck; harder testing.
- **Rejection Reason**: Premature. The ≤ 10 ms tick budget looks achievable in GDScript with LOD (to be proven in the M1 perf scenario).

## Consequences

### Positive
- One language and fast iteration; tests in gdUnit4 only.
- An explicit, measurable gate keeps native code from spreading.

### Negative
- GDScript call overhead caps how many per-entity calls a tick can afford. The architecture compensates with batching and LOD.
- Post-cutoff APIs require verification work in sprint 1.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Server tick > 10 ms in GDScript | M | H | Perf scenario in CI; GDExtension candidates pre-identified |
| 4.7 behaviour differs from the 4.6 reference | M | M | Verification list in architecture §15; ADRs stay Proposed until checked |
| gdUnit4 lags behind 4.7 | L | M | Pin the gdUnit4 version; fall back to the last compatible release |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Server tick | n/a | 6–9 ms | ≤ 10 ms |
| Client frame | n/a | ≤ 6.9 ms on recommended spec | 144 fps |

## Validation Criteria

- [ ] The 120-agent perf sim scenario p95 ≤ 10 ms/tick on the reference PC, or a GDExtension ADR is opened with measurements.
- [ ] CI runs the pinned 4.7 build headless with gdUnit4 green.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/game-concept.md` | Core Identity | Godot 4.7, GDScript, Forward+, Jolt | Adopted as the stack, with a GDExtension escape hatch |
| `design/gdd/game-concept.md` | Top Risks | Netcode for ~10 heroes + ~100 AI | Performance discipline + measured native fallback |

## Related

- `docs/architecture/architecture.md` §1, §12, §15
- ADR-0002 (networking), ADR-0006 (tests/CI)
