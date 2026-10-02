# Milestone: M1 Offline Vertical Slice

## Overview

- **Target Date**: 2026-12-14 (start 2026-10-19, after M0 exit)
- **Type**: Vertical Slice
- **Duration**: 8 weeks
- **Number of Sprints**: 4 (2 weeks each)

## Milestone Goal

Answer the concept's Tier 0 question offline: *is the gun + squad + front loop fun?* A human plays
**Vesper Loom** (Mana, commander) or **Brannoc** (Mechanical, tank) in a bot-filled **3v3** on the 1-lane Slice
Map **"Shardline Causeway"** (`design/gdd/match-flow-and-map.md` §3.7): S-AI Breach, S-AO Plant, S-MID Hold,
S-BO Plant, S-BI Breach. They pick up a Wardling squad at the Foundry, command it with the 4 squad commands,
level up, buy at the Armory, and push the front until an Uplink is Exposed and destroyed. Everything runs on a
**local authoritative server**: an in-process simulation behind a transport interface. The client renders
snapshots only, so M2 replaces the transport and does not rewrite the game.

*Consistency pass 2026-10-02: heroes, map, task layout, progression and shop scope aligned with the GDDs (Canon C1
slice exception; `heroes.md` §11; `weapons-and-mods.md` §3.10; `wardlings-and-economy.md` §26).*

**Slice overrides of Canon** (slice-only flags; the C1 duplicate exception is itself Canon):
- **3v3, not 5v5** (owner decision 2026-10-02, Canon C1 slice exception): `match_rules_slice.tres` sets
  `team_size = 3`, read by `GameSession` and `BotDirector`. Ten heroes in one lane tripled the full game's lane
  density (~3.3 heroes per lane). Each team is a Vesper Loom / Brannoc mix. The full game stays 5v5.
- Duplicate heroes are allowed per team (`slice.allow_duplicate_heroes`, Canon C1 slice exception), because there are
  only 2 heroes for 10 slots.
- **Task staging:** the slice may start with all 5 hardpoints running **Hold** (`slice.tasks = hold_only`, sprint 2);
  Plant (S-AO/S-BO) and Breach (S-AI/S-BI) replace them later in M1 (sprints 3–4). M1 exits on the full
  Breach / Plant / Hold / Plant / Breach layout.
- The match cap is 30:00 (Surge I at 15:00 is in; Surge II, Drought, capture overtime and Sudden Death are M3).
  Time-out uses 1-lane Incursion (0–3, C9), then Uplink %; a remaining tie is a draw.
- **Levels and a reduced skill tree:** levels 1–15 from Resonance with level scaling; each basic skill has
  **Unlock + Boost** only, plus ultimate ranks at 6/10/14 (no Forks, no Mastery; extra points stay banked).
- No Garrisons, Barricades or Supply Caches (M3). Lumen trickle is 60/min to compensate (`wardlings-and-economy.md` §26).
- Armory: squad upgrades (Expansion I/II, Reinforced Cores I/II, Amplifier Emitters), Med-Pack, and the minimal
  mount pipeline (`weapons-and-mods.md` §3.10).

Design sources: `design/gdd/game-concept.md` (Canon), `design/gdd/match-flow-and-map.md`, `design/gdd/heroes.md`,
`design/gdd/weapons-and-mods.md`, `design/gdd/wardlings-and-economy.md`, `design/ux/hud.md`, `design/art-bible.md`,
`docs/architecture/architecture.md`, `docs/architecture/adr/ADR-0001…0006`.

## Success Criteria

- [ ] **Launch and look:** `godot --path .` (no arguments) starts a 3v3 bot match on the slice
      with the player as Vesper Loom. Captures are saved to `production/qa/evidence/m1/`:
      `01-spawn-sanctum.png`, `02-squad-following.png`, `03-hold-contested.png`,
      `04-uplink-exposed.png` and `05-victory-screen.png`. Repeat with `--hero=brannoc` for
      `06-aegis-wall.png`, `07-plant-carrier.png` and `08-breach-generator.png`, and capture
      `09-armory-mounts.png` and `10-skill-tree.png`.
- [ ] A human can win or lose by Uplink destruction (C7: Integrity 33,000). Integrity damage is permanent, and the
      Uplink is invulnerable unless an enemy holds that team's Inner (automated scenario test).
- [ ] 20 consecutive headless bot-vs-bot matches (`--headless --slice-autoplay`) finish with 0 crashes.
      Each logs its winner, length, captures and levels to `production/qa/telemetry/m1/`. ≥15 of them end by
      Uplink kill before 30:00.
- [ ] Client/server separation: no client script references the server sim (CI static check). With
      the simulated latency transport at 150 ms RTT and 2% loss, the match still plays to completion.
- [ ] Respawn follows C11 (`min(30, 6 + 0.4 × minutes)`), and HQ vs. Mid-Beacon spawn choice works (unit + scenario tests).
- [ ] Wardlings follow, return fire, obey all 4 commands (Smart Command `Z`, Follow `X`, radial), count 0.5 toward Hold
      presence (capped at 3.0 per team, C4), and dissolve 10 s after their owner dies (C15). Vanguard waves spawn on the
      60 s tick behind the ≤1-alive gate, and Vesper can conduct them.
- [ ] Hold, Plant and Breach each complete in a scripted scenario on the slice map, within ±1 s of the
      `match-flow-and-map.md` F2–F4 predictions.
- [ ] Levelling and the reduced tree work: Boost is refused before L3, ult ranks before L6/10/14, Forks/Mastery are absent;
      buying, upgrading in place, selling and undoing a mount follow `weapons-and-mods.md` §3.6.4 (unit + scenario tests).
- [ ] `/playtest-report` from ≥3 owner sessions records a **go / pivot** verdict on fun and on Wardling readability.
- [ ] All S1 and S2 bugs resolved
- [ ] Performance within budget on target hardware (see Quality Gates)
- [ ] Build stable for 5 consecutive days (CI green on `main`, nightly soak passes)

## Exit Criteria Status (E14, 2026-10-02)

Evidence: `production/qa/m1-soak-report.md` and `design/balance/slice-tuning.md`. The full gdUnit4 suite passes
(360 tests). `tools/ci/check_deps.sh` is OK.

| Criterion | Status | Evidence / gap |
| ---- | ---- | ---- |
| Launch and look (captures 01–10 in `production/qa/evidence/m1/`) | **Not met** | The m1 capture set does not exist yet. Only the E14 task captures exist (`evidence/e14/plant.png`, `breach.png`). `scenes/slice/slice_match.tscn` was not checked |
| Win or lose by Uplink destruction; Integrity permanent; invulnerable unless an enemy holds an Inner | **Met (scenario tests)**, with deviations | `uplink_siege_test.gd` (staged layout) and `plant_breach_server_test.gd`: the real Breach of S-BI exposes the Uplink. The slice deviates from Canon: Integrity 12,000 (not 33,000), and an Outer also exposes the Uplink from 5:00 (`slice-tuning.md`) |
| 20 headless bot matches, 0 crashes, telemetry to `production/qa/telemetry/m1/` | **Met** | 20/20 reached End with exit 0 and no script errors. Exit-time leak report only, which predates E14 |
| ≥15 of 20 end by Uplink kill before 30:00 | **Not met (1/20)** | 19 time-outs on Incursion. The Mid see-saws, and no Inner Generator fell in 20 matches. See slice-tuning F1–F2 |
| Client/server separation CI check; plays to completion at 150 ms RTT / 2 % loss | **Partly met** | `check_deps.sh` is OK. The latency run was not repeated in E14; the existing net tests pass |
| Respawn follows C11; HQ vs Mid-Beacon spawn choice | **Met, with a slice deviation** | Unit and scenario tests pass. Canon C11 is tested on the class defaults. The slice uses 10 + 1.0·m (cap 30), ×1.5 while Exposed (`slice-tuning.md`) |
| Wardlings: follow, 4 commands, 0.5 presence capped at 3.0, dissolve 10 s, Vanguard cadence | **Met (tests)** | E8 suites green. Waves now skip Plant nodes unless an allied Cell is carried or planted |
| Hold, Plant and Breach complete in scripted scenarios within ±1 s of F2–F4 | **Met** | `plant_breach_test.gd`: Plant 75 ± 1 s (F3), Breach 40 ± 1 s (F4), Hold (E7). `plant_breach_server_test.gd`: carry at 5.4 m/s ±2 %, plant 3 s, flip 75 ± 1 s, and the breach hold 31.25 ± 1 s |
| Levelling and the reduced tree; mount buy / upgrade / sell / undo | **Met (E13/E15 tests)** | Unchanged by E14 |
| `/playtest-report` from ≥3 owner sessions (go / pivot) | **Not met** | Needs the owner |
| All S1 and S2 bugs resolved | **Not assessed** | `production/qa/bugs/` is empty. The soak found no crash |
| Performance within budget | **Partly met** | Server tick p95 4.9 ms against an 8.3 ms budget (pass, headless). Bot cost 0.43 ms against 0.4 ms (narrow miss). FPS on the reference PC was not measured |
| Build stable for 5 consecutive days | **Not assessed** | No nightly CI history |

## Feature List

### Must Ship (Milestone Fails Without These)

| Feature | Design Doc | Owner | Sprint Target | Status |
|---------|-----------|-------|--------------|--------|
| E1 Project scaffold, CI, test and evidence harness | docs/architecture/architecture.md | devops-engineer + godot-gdscript-specialist | S1 | Not started |
| E2 FPS controller | design/gdd/heroes.md | gameplay-programmer | S1 | Not started |
| E3 Local authoritative server tick loop | docs/architecture/adr/ADR-0002-server-authoritative-networking.md | engine-programmer + network-programmer | S1 | Not started |
| E4 Combat core | design/gdd/weapons-and-mods.md | gameplay-programmer | S1–S2 | Not started |
| E5 Ammo models (Mana / Mechanical) | design/gdd/weapons-and-mods.md | gameplay-programmer | S2 | Not started |
| E6 Slice map greybox | design/gdd/match-flow-and-map.md | level-designer | S2 | Not started |
| E7 Hardpoints and front (Hold in S2; Plant S3, Breach S4) | design/gdd/match-flow-and-map.md | gameplay-programmer | S2–S4 | Not started |
| E8 Wardlings (squads, 4 commands, Vanguard waves) | design/gdd/wardlings-and-economy.md | ai-programmer | S2–S3 | Not started |
| E9 Uplink and match flow | design/gdd/match-flow-and-map.md | gameplay-programmer | S3 | Not started |
| E10 Hero kits: Vesper Loom and Brannoc | design/gdd/heroes.md | gameplay-programmer (`/team-combat`) | S3 | Not started |
| E11 Hero bots | design/gdd/heroes.md | ai-programmer | S3–S4 | Not started |
| E12 Core HUD | design/ux/hud.md | ui-programmer (`/team-ui`) | S1–S4 | Not started |
| E13 Spawn choice and Armory (Lumen, squad upgrades, Med-Pack, minimal mount pipeline) | design/gdd/wardlings-and-economy.md, design/gdd/weapons-and-mods.md | gameplay-programmer | S4 | Not started |
| E15 Progression-lite (levels, reduced skill tree) | design/gdd/heroes.md, design/gdd/wardlings-and-economy.md | gameplay-programmer | S3 | Not started |
| E14 Integration, soak and playtest | this doc | qa-lead | S4 | Not started |

### Should Ship (Planned but Cuttable)

| Feature | Design Doc | Owner | Sprint Target | Cut Impact | Status |
|---------|-----------|-------|--------------|-----------|--------|
| Team-colour cel shader on placeholder meshes | design/art-bible.md | technical-artist | S3 | Readability read is weaker | Not started |

### Stretch Goals (Only if Ahead of Schedule)

Placeholder SFX (sound-designer); kill-cam / death recap (ui-programmer, `design/ux/hud.md`).

## Epics and Stories

The 15 epics (E1–E15), their story titles, build order and sprint split are listed in
`production/milestones/roadmap.md` under M1. `/create-stories <epic-slug>` turns each into
`production/epics/<epic-slug>/story-NN-*.md`.

## Quality Gates

| Gate | Threshold | Measurement Method |
|------|-----------|-------------------|
| Crash rate | 0 in 20-match headless soak; 0 in 3 h of owner play | `/soak-test`, Godot logs |
| Frame rate | ≥ 60 FPS at 1080p, 10 heroes + 80 Wardlings (slice worst case: 10 Vespers × 7 squad + 8 Vanguard = 78; full-map design budget is ≤ 110, Canon C1) | `/perf-profile` on reference PC (owner's machine, specs recorded in report) |
| Server tick | sim step ≤ 25% of tick budget, headless, at 80 Wardlings; the 120-agent stress scenario stays ≤ 10 ms p95 (architecture §12) | tick timer in telemetry |
| Load time | < 10 s to in-match from launch | automated timing in soak |
| Critical bugs | 0 open S1 | `production/qa/bugs/` (`/bug-triage`) |
| High-severity bugs | 0 open S2 | `/bug-triage` |
| Test coverage | every Logic story has a gdUnit4 test; all visual stories have screenshots | `/test-evidence-review` |

## Risk Register

| Risk | Probability | Impact | Mitigation | Owner | Status |
|------|------------|--------|-----------|-------|--------|
| Split architecture slows feature work | Med | High | Transport + snapshot done first (E3) with one template entity; later epics copy the pattern | lead-programmer | Open |
| Godot 4.7 API gaps vs. training data | Med | Med | Consult `docs/engine-reference/godot/`; godot-specialist reviews E1–E3 | godot-specialist | Open |
| Wardlings unreadable / cluttered | Med | High | Team-colour shader early (S3), base squad 3 (Vesper 5), Vanguard pennants, readability screenshots at 30 m reviewed | art-director | Open |
| Bots too weak to test the loop | High | Med | Bots use player input path; difficulty knob; owner can play 1v1 + bots on own team | ai-programmer | Open |
| Navmesh / 80 agents cost | Med | Med | E8.8 budget test before E11; avoidance tuned, path requests throttled, wave-level brains | ai-programmer | Open |
| Scope added by the 2026-10-02 consistency pass (Vanguard waves, 4 commands, Plant/Breach, levels, mount shop) | Med | High | Staged order (Hold-only first); producer re-baselines at the end-of-S2 review; if late, cut mount visuals to primitives before cutting tasks | producer | Open |
| Headless Godot can't render captures in CI | Low | Med | M0 engine probe; fall back to Xvfb + `--write-movie` | devops-engineer | Open |
| Loop not fun | Med | High | go/pivot at E14; pivots go to creative-director before M2 starts | producer | Open |

## Dependencies

### Internal Dependencies

| Feature | Depends On | Owner of Dependency | Status |
|---------|-----------|-------------------|--------|
| E2–E14 | E1 scaffold + CI | devops-engineer | Not started |
| E4, E7, E8, E9 | E3 tick loop + snapshots | engine-programmer | Not started |
| E5, E10 | E4 combat core | gameplay-programmer | Not started |
| E7, E8 | E6 map + navmesh | level-designer | Not started |
| E9, E11 | E7 hardpoints | gameplay-programmer | Not started |
| E11 | E8 Wardlings, E10 hero kits | ai-programmer | Not started |
| E14 | all Must Ship epics | qa-lead | Not started |
| All epics | M0 GDDs + ADRs approved | technical-director / game-designer | In progress |

### External Dependencies

| Dependency | Provider | Status | Risk if Delayed |
|-----------|---------|--------|----------------|
| Godot 4.7 stable binary (headless + editor) | Godot Foundation | Available | Blocks E1 |
| gdUnit4 compatible with 4.7 | gdUnit4 maintainers | Verify in E1 | Fall back to custom test runner |
| GitHub Actions runners | GitHub | Available | Local `/smoke-check` only |

## Review Schedule

| Date | Review Type | Attendees |
|------|-----------|-----------|
| 2026-11-02 (end S1) | Early progress check: player moves and shoots through LocalTransport | Owner, producer, technical-director |
| 2026-11-16 (end S2) | Mid-milestone review: lane captures, squads follow | Owner, producer, game-designer |
| 2026-11-30 (end S3) | Pre-milestone review: first full bot match | Owner, producer, directors |
| 2026-12-14 | Milestone review (`/milestone-review`) + go/pivot | Owner, producer, creative-director, technical-director |
