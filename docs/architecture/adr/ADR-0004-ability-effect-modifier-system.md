# ADR-0004: Ability System — Skill → Effect → Modifier Pipeline on a Shared StatBlock

## Status

Proposed

> Only the user, or technical-director on the user's explicit confirmation, may set this to `Accepted`.

## Date

2026-10-02

## Last Verified

2026-10-02

## Decision Makers

lead-programmer (author), technical-director, network-programmer. Written autonomously.

## Summary

Cybergram has 28 skills with 4-node trees (56 forks), levels, Crystals/Chips, ammo types, statuses and Surge tiers, all of which change numbers. We adopt **one stat pipeline (`StatBlock` + `Modifier`)** that every growth source writes into, and **one data-defined skill pipeline**: `SkillDef` → `TargetingDef` → `EffectDef[]` → (`DamageInfo` | `StatusDef` → `Modifier`). Skill-tree nodes are Modifiers or appended Effects, never new code paths. The server executes everything; the owning client predicts only motion effects and cooldown start.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.7 |
| **Domain** | Core / Scripting |
| **Layer** | Core |
| **Knowledge Risk** | LOW (plain GDScript; `@abstract` is 4.5+) |
| **References Consulted** | `current-best-practices.md` (`@abstract`) |
| **Post-Cutoff APIs Used** | `@abstract` for `EffectDef`, `TargetingDef` |
| **Verification Required** | `@abstract` on a `Resource` subclass loads correctly from `.tres` that reference concrete subclasses |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (Defs), ADR-0002 (authority and prediction rules) |
| **Enables** | Hero, weapon, shop, Wardling-tier and status epics |
| **Blocks** | Ryker and Liora skill implementation (M1) |
| **Ordering Note** | `StatBlock` (core) before `AbilityRunner` (gameplay). |

## Context

### Problem Statement
Without one shared model, each hero's skills, each mod and each level-up would mutate fields ad hoc. Balance would become untestable, and replication would have to know every special case. The concept explicitly mitigates scope with "Forks are modifiers, not new skills".

### Requirements
- C12: 4 skills (3 basic + ult); tree Unlock → Boost → Fork A|B → Mastery (L9+); ult ranks at 6/10/14.
- C16: skills are cooldown-only for all heroes.
- Pillar 2: damage must be aimed or placed; support may soft-target.
- Pillar 4: upgrades have visible tells (Mod visual scenes, level glyphs).
- Zero allocation per tick; deterministic evaluation order.

## Decision

1. **`StatBlock` (src/core/stats)** holds dense per-stat arrays indexed by `StatCatalog`. Evaluation is `clamp(OVERRIDE ?? (base + ΣADD) × (1 + ΣPCT) × ΠMUL, min, max)`; the latest OVERRIDE wins. Values are cached with a dirty flag. Modifiers are pooled `{stat_index, op, value, source_id, expires_tick}`. Parent chaining: a skill's block reads hero-wide stats from its parent.
2. **Sources** are levels, skill nodes, mods/ammo, statuses and Surge tiers. Each source tags its modifiers with a `source_id` so it can remove them all at once (`remove_by_source`).
3. **`AbilityRunner`** (one per hero) owns 4 `SkillInstance`s. `try_activate(slot, cmd, tick)` gates on: node UNLOCK owned, `tick ≥ cooldown_end_tick`, no `silence`/`stun` tag, not already casting. It then runs cast → `TargetingDef.resolve()` → `EffectExecutor.apply()` → sets `cooldown_end_tick = tick + ceil(cooldown × (1 − cdr) × tick_rate)`.
4. **Effects** are stateless `EffectDef` resources with an `apply(ctx: EffectContext, target: TargetRef) -> void` executed by `EffectExecutor`: `DamageEffectDef`, `HealEffectDef`, `ApplyStatusEffectDef`, `ImpulseEffectDef`, `MotionEffectDef`, `SpawnEntityEffectDef`, `AreaEffectDef` (child effects), and `SquadCommandEffectDef` (Vesper's control of Wardlings/Vanguard). Effect magnitudes are read from the **skill's** `StatBlock` by stat id, so a Boost node that adds `+20% skill_damage` needs no effect changes.
5. **Statuses** (`StatusComponent`) apply modifiers and periodic tick effects, with REFRESH/STACK/IGNORE stacking and tags (`stun`, `silence`, `reveal`, `hacked`, `heal_immune`). Expiry is by tick.
6. **Skill-tree nodes** are `SkillNodeDef {kind, required_level, modifiers[], added_effects[], excludes}`. Spending a point is a server-validated `Command(LEVEL_SKILL)`. Fork exclusivity and level gates are enforced in `SkillTree.can_learn()`.
7. **Damage** flows only through `HealthComponent.apply_damage(info: DamageInfo)`. That method applies resist stats, team rules, Uplink exposure and `wardling_damage_scale`, assist tracking, and emits `damaged`/`died` → `SimEventQueue`.
8. **Prediction contract:** `SkillDef.predicted_motion = true` makes the owning client run the `MotionEffectDef` inside `HeroMotor`. All other effects are server-only, with client cosmetics triggered from snapshots/events. A rejected activation gives a `SKILL_REJECTED` event and the client rolls back its cooldown start.
9. **Replication:** own hero block carries `cooldown_end_tick[4]`, learned node bitmask (u16), level and active-status ids. Others see status ids plus remaining ticks (for VFX tells) only when relevant.

### Key Interfaces
```gdscript
class_name AbilityRunner extends Node
signal skill_activated(slot: int, tick: int)
signal cooldown_started(slot: int, end_tick: int)
signal skill_rejected(slot: int, reason: int)
func try_activate(slot: int, cmd: InputCommand, tick: int) -> bool
func learn_node(node_index: int) -> bool

@abstract class_name EffectDef extends Resource
@abstract func apply(ctx: EffectContext, target: TargetRef) -> void

class_name EffectContext extends RefCounted   # pooled
var source: Node3D; var instigator_net_id: int; var team: int
var skill_stats: StatBlock; var rank: int; var tick: int
var aim_origin: Vector3; var aim_dir: Vector3
```

## Alternatives Considered

### Alternative 1: Per-skill scripts (one GDScript class per skill)
- **Pros**: maximum freedom; simple to start.
- **Cons**: 28 scripts × fork variants; balance hidden in code; violates data-driven rules.
- **Rejection Reason**: Scope risk explicitly called out in the concept.

### Alternative 2: Full GAS-style tag/attribute system with gameplay cues and prediction keys for all effects
- **Pros**: industry-proven and very flexible.
- **Cons**: heavy for GDScript; predicting every effect is unnecessary at our tick and RTT targets.
- **Rejection Reason**: We keep the parts we need: tags on statuses, predicted motion only.

## Consequences

### Positive
- One code path to test (unit tests on `StatBlock` order of ops and on each `EffectDef`).
- New forks and mods are content-only changes most of the time.

### Negative
- Truly novel mechanics need a new `EffectDef` subclass and a design review.
- Stat-id namespacing must be disciplined (`StatCatalog` is the single list).

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Order-of-ops surprises in balance | M | M | Documented formula; unit tests with boundary cases; balance sheet export |
| Stat explosion (too many skill-scoped stats) | M | L | Generic skill params (`skill_damage`, `skill_radius`, `skill_duration`, …) reused across skills |
| Cooldown mispredict flicker | L | L | Rollback on `SKILL_REJECTED`; predict only on local gating success |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Stat reads | n/a | O(1) cached array read | — |
| Abilities + statuses per tick (10 heroes, ~100 agents) | n/a | ~0.4 ms | part of 1.0 + 0.9 ms (§12) |

## Validation Criteria

- [ ] Unit tests: StatBlock order of ops, remove_by_source, expiry by tick, fork exclusivity, Mastery L9, ult 6/10/14.
- [ ] Ryker and Liora skills in M1 are implemented with zero hero-specific scripts beyond `EffectDef` subclasses.
- [ ] No per-tick allocations in `AbilityRunner`/`StatusComponent` (profiler check).

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/game-concept.md` | C12 | Skill trees and level gates | `SkillNodeDef` + `SkillTree.can_learn()` |
| `design/gdd/game-concept.md` | C16 | Cooldown-only skills; Crystals/Chips | Tick cooldowns; `ModDef` modifiers on the weapon scope |
| `design/gdd/game-concept.md` | Pillar 2 | Aimed damage only | Targeting kinds + validator rule |
| `design/gdd/game-concept.md` | Phases / C15 | Surge tiers for Wardlings | SURGE-sourced modifiers |

## Related

- `docs/architecture/architecture.md` §7
- ADR-0003, ADR-0002
