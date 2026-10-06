# Plan: expand the Armory into a deep, recommended build system

## Context
The owner wants Cybergram's existing Armory (Lumen, mounts/sockets, squad upgrades,
Med-Packs, tiers, buy/sell/undo, `RecommendedBuildDef`) to reach the depth and
usability of LoL recommended items / Dota guides / Deadlock default builds, with
original content. No second item, shop or recommendation system: everything extends
the existing files. Owner decisions (2026-10-06): add GDD-cut items **plus** a new
defensive line; bump protocol 20 -> 21; allow same-visit undo for squad upgrades and
Med-Packs; custom builds stored locally on the PC.

## Phase 0 audit (done, read-only)

### Current architecture
```
assets/data/economy/armory_catalog_slice.tres  (12 ArmoryItemDef; ORDER = wire index)
assets/data/economy/recommended_builds_slice.tres (2 RecommendedBuildDef: Vesper, Brannoc)
        |                                   |
 client: ShopModel (pure, reads ProgressState) <- ArmoryPanel (draw/input, polls)
        |  request_action(ACTION_BUY idx|tier<<8 / ACTION_SELL socket)
        v  InputCommand (edge event, redundancy 3)
 server: ServerWorld._step_hero -> ProgressionSystem.handle_action -> Armory.buy/sell
        |  result code DISCARDED (server_world.gd:472)
        v
 HeroProgress (lumen, mounts{socket->Mount(index,tier,paid,paid_visit)}, owned, medpacks)
        -> fill_own -> SnapshotData.ProgressState -> BLOB_PROGRESS (full-state, resync-safe)
```

### Existing behaviour (keep)
| Area | Behaviour |
|---|---|
| Items | Kind CONSUMABLE/SQUAD/MOUNT/AMMO; Socket CORE/FRAME/CHAMBER (BARREL unused); Family CRYSTAL (Mana guns)/CHIP (Mech guns); per-tier prices + 2 stat modifiers; `requires`; `carry_limit` |
| Rules | HQ/Sanctum only, alive; upgrade = list(new)-list(held); swap auto-sells; 100% refund same visit, 60% later (round 5); visit ends on leaving zone or death |
| Effects | One modifier source per catalog index (`Modifier.source(SRC_MOD, idx)`), re-applied on tier change -> no duplicates |
| Results | `HeroProgress.Result` OK, NOT_AT_ARMORY, DEAD, UNKNOWN_ITEM, NO_FUNDS, WRONG_FAMILY, REQUIRES, LIMIT, NOT_OWNED, MAXED, DISABLED … |
| UI | Tabs All/Core/Frame/Chamber/Squad/Consumables, search, States AVAILABLE/CANT_AFFORD/OWNED/MAXED/LOCKED/WRONG_FAMILY/CARRY_FULL with reasons, NEXT/REC tags, build strip, R = jump to recommended (auto on open), keyboard + partial gamepad |
| Tests | armory_test, shop_model_test, economy_math_test, economy_curve_test, progression_test, armory_guidance_test, economy_loop_test, armory_reach_test |

### Missing / broken
| Gap | Notes |
|---|---|
| Result never reaches client | generic "refused" after 1.5 s; lost edge input silently drops a buy |
| Squad/Med-Pack undo | impossible (owner: allow same visit) |
| Builds | only 2/7 heroes; ordered list only; no reasons, branches, alternatives, tags |
| Content | 12 items, no Barrel, no defensive line, GDD squad items (Tether, Quick Mint, Bulwark) cut |
| Bots | never buy (Lumen piles up) |
| Hero roles | UI-only table (`hero_showcase.gd ROLE_KEYS`); no server tags |
| Telemetry for rules | no damage-taken per victim, no damage type in `hero_damaged` |
| Logging | no purchase logs at all |
| Wire safety | catalog order = wire id, no hash check; `owned_bits` only idx < 32; `mount_item` s8 |
| UI | no sort/affordable filter, gamepad lacks search/tier buy/jump, Ctrl+F may close panel (interact=F), panel untested, no screenshot preset, catalog text not localized |
| Custom builds | none |

## Approach (recommended)

### A. Data (extend, append-only)
- `ArmoryItemDef` new optional fields (defaults keep old .tres valid): `category` (StringName),
  `tags: PackedStringArray` (starter/core/defensive/offensive/utility/counter/luxury),
  `counter_tags`, `keywords`, `phase` (early/mid/late), `beginner: bool`, `situational: bool`,
  `unique_group: StringName`, `explain_key`, `upgrades_to: StringName`, `hidden_in_guides: bool`,
  `disabled: bool`, `name_key`/`effect_key` for localization. No six-slot inventory; mounts/squad/consumables stay canonical.
- New items **appended** after index 11 (wire indices unchanged): Barrel line per family,
  squad Tether / Quick Mint / Bulwark (GDD §7), and a new defensive line (designed by
  economy-designer + writer; GDD weapons-and-mods / wardlings-and-economy and
  `design/registry/entities.yaml` updated first, inside existing price bands). Icons via `shop_icons.gd` line-art.
- `HeroDef` gains `roles: PackedStringArray` and `tags` (cc/burst/sustain/…) — server truth; `hero_showcase.gd` reads them instead of its own table.
- `RecommendedBuildDef` keeps `item_ids/targets` (simple mode, unchanged behaviour) and adds
  `nodes: Array[BuildNodeDef]` (new small Resource) + `modes`, `roles`, `beginner`.
  `BuildNodeDef`: `id, item_id, target, section (OPENING/EARLY/SPIKE/CORE/SQUAD/CONSUMABLE/DEFENSIVE/OFFENSIVE/UTILITY/COUNTER/LATE), priority, requires (node ids), alternatives (item ids), conditions (rule ids), reason_key, core, optional, fallback, skippable, min_s/max_s, expected_lumen, expert`.
  `RecommendedBuildsDef.for_hero(hero, mode)` returns all matching builds. Default builds for all 7 heroes.
- `ArmoryValidator` (static, used by a test and at load in debug): unknown ids, tier targets > tiers, requirement cycles, unreachable paths, duplicate unique groups, wrong hero/mode/family, disabled items in builds, squad index >= 32, item index > 127.

### B. Server hardening (protocol 21)
- `ProgressState` gains `last_req_seq` (u8) + `last_result` (u8) + compact advice signals (u8 bitfield) ; client tags each buy/sell with a seq inside `action_arg` high bits only if it fits, else a separate u8 field in InputCommand (decide in code; documented). `MsgType.PROTOCOL_VERSION = 21`; launcher/game version check rejects 20.
- Catalog hash in the match handshake (mismatch = clear error, not silent corruption).
- `Armory`: squad/Med-Pack undo within the visit (track `visit_bought` list on HeroProgress; refund 100%, remove modifiers by source; respect `requires` — cannot undo Expansion I while II owned). New result `INVALID_TIER` only if MAXED/LIMIT don't cover a case; reuse enum otherwise; Med-Pack "already healing" gets its own code instead of LIMIT.
- `price_of` respects ownership/limits. Atomicity already holds (checks before mutation) — tests prove it, incl. repeated/duplicate commands and forged args (bad index/tier/socket).
- OpsLog events `armory.buy|sell|undo|reject` (player via `OpsLog.tag`, item id, tier, Lumen before/after, result) + Lumen spent tracked in `MatchStats`.

### C. Recommendation evaluator
- `BuildAdvisor` (pure RefCounted, `src/gameplay/progression/build_advisor.gd`), shared by client (`ShopModel`) and server bots. Input: `BuildState` (lumen, mounts/tiers, owned, medpacks, weapon family, match time, mode, hero/enemy hero tags, advice signals). Output: ranked `Advice[]` {node, item, target, cost_now, affordable, reason_key, alternatives} + debug trace (rules evaluated/matched, scores, rejected alternatives).
- Simple builds = today's "first unsatisfied step" (exact compatibility test).
- Graph builds: node is open when requires done; score = priority + rule bonuses; skipped/alternative-satisfied nodes count as done; unavailable/wrong-family -> fallback node.
- Rules (`AdviceRuleDef` data, ids referenced by nodes): next core tier ready, affordable component, repeated skill/weapon damage taken, many deaths (stabilize), enemy CC/burst/sustain tags, team behind/ahead (`deficit`), objective soon, missing team function (roles). Server tracks damage taken by type per hero (rolling 60 s) -> packed into advice signals.
- Debug: `--debug-advisor` prints the trace; shop shows it in an expert detail toggle.

### D. Armory UI (ui-programmer; ShopModel first, then panel)
- Recommended tab (new first tab): next purchase + one-line reason (glance); expand = full path by section, alternatives, progress; expert = conditions/tags/stat compare.
- Catalog: sort (cost/name), "affordable now" + role/category filter, blocked reason, affordable-soon (≤ 60 s of trickle), total vs remaining cost on lines, kind badges (tier upgrade / new mount / squad / consumable / maxed), unique/active markers, compare with held mount.
- Exact server reason toasts (from `last_result`), success/fail/sell/undo feedback, reconnect while open re-reads state.
- Gamepad parity: search, tier buy, jump-to-recommended, chip/branch navigation; fix Ctrl+F vs interact=F.
- Recommendations never block buying; full catalog always reachable.

### E. Custom builds (local)
- `user://builds.json`, versioned (`{"version":1,"builds":[…]}`), `CustomBuildStore` (load/save/validate/import/export string). Create/rename/delete/duplicate/reset-to-default, sections, order, alternatives, notes. Invalid refs shown as warnings, never deleted. Selected build per hero used by the Advisor.
- Editor UI: simple list editor in the Armory (Builds sub-view) and/or main menu hero page.

### F. Bots
- `BotBrain`: on the pad with Lumen, ask `BuildAdvisor` for the hero's default build and send `ACTION_BUY` through the same InputCommand path; respects all server checks; buys Med-Packs at low HP; debug log of choices.

### G. Balance (economy-designer agent + balance-check skill)
- Headless script `tools/balance/armory_report.gd`: per build, when each node becomes affordable on the §18 Lumen curve (5v5/3v3), dead zones, unreachable/never-recommended items, recommendation diversity, cost-efficiency outliers. Reports in `docs/balance/armory-*.md`; proposed changes only with rationale; canon value changes go through GDD + registry.

### H. Visual polish + docs
- Screenshot preset for the open panel (`--map slice --debug-armory` + new `tools/shot.gd` armory-panel states), all required states captured at 1920x1080 and 1280x720 into `production/qa/evidence/armory-builds/`, looked at, issues in `docs/item-shop-polish.md`.
- `docs/armory.md`: item data, adding item/tier/recommendation/branch/rule, testing purchases, balance check, debugging the advisor. CLAUDE.md commands, PROGRESS.md per phase.

## Order, commits, PRs
1. Data fields + HeroDef roles + validator + tests (commit)
2. Protocol 21 result feedback + catalog hash + undo scope + logging + hardening tests (commit) — PR 1
3. BuildNodeDef + BuildAdvisor + rules + damage-taken signals + 7 default builds (commit)
4. ShopModel + ArmoryPanel (recommended tab, filters, gamepad) (commits) — PR 2
5. New items (GDD + defensive line), icons, registry (commit)
6. Custom builds (commit); bots (commit)
7. Balance reports; visual polish; docs — PR 3, then release (protocol 21 = server + all players update; launcher fetches game).

## Critical files
`src/gameplay/data/{armory_item_def,armory_catalog_def,recommended_build_def,recommended_builds_def,hero_def}.gd`,
new `build_node_def.gd`, `advice_rule_def.gd`; `src/gameplay/progression/{armory,progression_system,hero_progress,economy_math}.gd`,
new `build_advisor.gd`, `armory_validator.gd`; `src/networking/snapshot/{snapshot_data,snapshot_codec}.gd`, `msg_type.gd`;
`src/ui/hud/{shop_model,armory_panel,shop_icons}.gd`; `src/ai/bot_brain.gd`; `assets/data/economy/*.tres`, `assets/data/heroes/*.tres`;
`assets/localization/hud.csv`; `design/gdd/{wardlings-and-economy,weapons-and-mods}.md`, `design/registry/entities.yaml`.

## Verification
- New suites: `tests/unit/economy/{armory_validator,build_advisor,custom_builds,armory_undo}_test.gd`, extended `armory_test`, `shop_model_test`; integration `tests/integration/economy/{armory_protocol,armory_reconnect,bot_shopping}_test.gd` (5v5 front, 3v3 slice, custom, bots-only: bots finish ≥ first spike by 10 min).
- Forged client args, repeated commands, failed buy leaves Lumen/state unchanged, snapshot resync after reconnect with panel open.
- Full `tools/ci/run_tests.sh`, CI green incl. export e2e; screenshots reviewed; balance report produced.

## Assumptions recorded
- Simple ordered builds keep exactly today's highlight behaviour.
- Item text gets localization keys; English only for now.
- No community sharing; no ML.
- Deadlock/LoL/Dota used only as UX reference, no names/values/art copied.
