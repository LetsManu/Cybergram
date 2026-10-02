# ADR-0003: Data-Driven Custom Resources (.tres) for All Tunables

## Status

Proposed

> Only the user, or technical-director on the user's explicit confirmation, may set this to `Accepted`.

## Date

2026-10-02

## Last Verified

2026-10-02

## Decision Makers

lead-programmer (author), technical-director. Written autonomously.

## Summary

Seven heroes × 4 skills × 4-node trees, plus mods, ammo, Wardling variants, Vanguard/Garrison rules, economy and match rules, give hundreds of tunables. The rules forbid hardcoded gameplay values. **All tunables are typed Godot custom `Resource`s saved as `.tres` under `assets/data/`.** They are indexed by an immutable `ContentDB`, validated in CI, and identified on the wire by a stable uint16 index with a content hash in the handshake.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.7 |
| **Domain** | Core / Scripting |
| **Layer** | Foundation |
| **Knowledge Risk** | MEDIUM |
| **References Consulted** | `current-best-practices.md` (Resources 4.5+), `breaking-changes.md` |
| **Post-Cutoff APIs Used** | `Resource.duplicate_deep()` (4.5); typed `Dictionary[K, V]` exports (4.4+) |
| **Verification Required** | Typed dictionary `@export` round-trips in `.tres` on 4.7; `ResourceLoader` loads of Defs in a headless dedicated export do not pull in visual scenes |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 |
| **Enables** | ADR-0004, ADR-0005 |
| **Blocks** | Any epic that introduces a gameplay number |
| **Ordering Note** | `StatCatalog`, `NetConfig`, `MatchRulesDef` first. |

## Context

### Problem Statement
Designers must tune values without code changes. Clients and servers must agree on content, and the network needs compact ids. `.claude/rules/data-files.md` is written for JSON. We need a decision on the format and on the guarantees.

### Constraints
- Editor-friendly authoring (inspector, curves, sub-resources).
- Static typing for code that reads values.
- Deterministic, version-checked content identity between client and server.

## Decision

1. **Format:** `.tres` text resources, one top-level Def per file, file stem = `id` (snake_case, `[kind]_[name].tres`, e.g. `hero_ryker_vance.tres`, `skill_liora_mend_beam.tres`). Text format keeps diffs reviewable. JSON is used only for generated artifacts (sim reports, telemetry), which keep following the JSON data-file rule.
2. **Class catalogue** (in `src/gameplay/data/`; `StatCatalog` in `src/core/stats/`): `HeroDef`, `SkillDef`, `SkillNodeDef`, `EffectDef` (abstract) + subclasses, `ModifierDef`, `StatusDef`, `WeaponDef`, `ProjectileDef`, `AmmoTypeDef`, `ModDef`, `WardlingDef`, `WardlingTierDef`, `SquadDef`, `GarrisonDef`, `VanguardDef`, `EconomyRewards`, `LevelCurve`, `ShopCatalog`, `MatchRulesDef`, `MapDef`, `HardpointDef`, `UplinkDef`, `NetConfig`, `BotProfile`, `BotRoleDef`, `WardlingAiDef`, `AiLodConfig`, `ScenarioDef` (tests).
3. **Immutability:** Defs are never mutated at runtime. Runtime state lives in runtime objects (`StatBlock`, `SkillInstance`, `Squad`, `VanguardWave`). Code that needs a per-instance variant creates a runtime object; `duplicate_deep()` is a last resort and requires review.
4. **Formulas in code, coefficients in data.** Each formula function names its design source in a doc comment (`## Canon C11`) and reads every coefficient from a Def.
5. **ContentDB:** at boot it scans `assets/data/**` (via a generated `content_manifest.tres` in exports, since directory listing in exported PCKs is unreliable). It builds per-type sorted id arrays → `index_of(id)` uint16, and computes `content_hash` over ids plus the file bytes. It is injected into `ServerWorld`/`ClientWorld`; tests build fixture DBs.
6. **Validation:** `tools/ci/validate_content.gd` runs headless in CI and fails on: missing/out-of-range fields; skill trees not shaped UNLOCK→BOOST→FORK_A|FORK_B→MASTERY (Mastery `required_level ≥ 9`); ultimate ranks not at levels 6/10/14; damage effects on soft-targeted skills (Pillar 2); squad/garrison/Vanguard caps whose total exceeds `AiLodConfig.max_agents`; orphan Defs not referenced by any other Def or the manifest.
7. **Localisation:** Defs hold `*_key` translation keys, never display strings.

### Key Interfaces
```gdscript
class_name ContentDB extends RefCounted
func get_def(id: StringName) -> Resource
func index_of(id: StringName) -> int          # stable u16 per type, net-safe
func def_at(type: StringName, index: int) -> Resource
func content_hash() -> int

class_name VanguardDef extends Resource
@export var interval_s: float = 60.0           ## Canon C15. Default mirrors canon; the .tres is authoritative.
@export var wave_size: int = 4
@export var respawn_threshold_alive: int = 1
@export var formation: PackedVector3Array
```

## Alternatives Considered

### Alternative 1: JSON files + loader
- **Pros**: tool-agnostic, matches the existing data-file rule.
- **Cons**: no inspector, no typed sub-resources/curves, hand-written parsing and schema, references by string only.
- **Rejection Reason**: Worse authoring and typing for no gain in a Godot-only project.

### Alternative 2: Constants in scripts (`const` tables)
- **Rejection Reason**: Violates the gameplay rule (no hardcoded values); requires code review to tune.

### Alternative 3: Binary `.res`
- **Rejection Reason**: Not diffable. Export can still convert to binary at build time.

## Consequences

### Positive
- Designers tune in the inspector; diffs are reviewable; the CI validator protects canon invariants.
- Stable net indices keep packets small.

### Negative
- `.tres` merges can conflict on sub-resource ids. Keep one Def per file and avoid giant files.
- A content-hash mismatch blocks mixed-version play (intended).

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Data sprawl / inconsistency | H | M | Validator + canon invariant checks |
| Def mutation bugs (shared resource edited at runtime) | M | M | Lint: no assignment to Def fields outside `src/gameplay/data`; read-only access by convention plus review |
| Exported builds cannot list directories | M | M | Generated manifest |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Content load at boot | n/a | < 1 s | 2 s |
| Runtime reads | n/a | cached in `StatBlock` arrays; no Dictionary lookup per tick | — |

## Validation Criteria

- [ ] A grep finds no numeric gameplay literals in `src/gameplay` and `src/ai` except 0/1/-1 and indices (lint script).
- [ ] The validator rejects a deliberately broken fixture for each rule.
- [ ] A client with one changed `.tres` is rejected with `CONTENT_MISMATCH`.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/game-concept.md` | Canon table | "(tunable)" values tuned without concept change | All coefficients live in Defs |
| `design/gdd/game-concept.md` | C12 | 4-node trees, Mastery L9, ult at 6/10/14 | Encoded in `SkillNodeDef`, enforced by the validator |
| `design/gdd/game-concept.md` | C15 | Squad, Garrison, Vanguard sizes and timers | `SquadDef`/`GarrisonDef`/`VanguardDef` |

## Related

- `docs/architecture/architecture.md` §6
- ADR-0004 (Modifiers consume these Defs)
