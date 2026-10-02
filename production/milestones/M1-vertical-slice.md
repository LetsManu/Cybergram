# Milestone: M1 Offline Vertical Slice

## Overview

- **Target Date**: 2026-12-14 (start 2026-10-19, after M0 exit)
- **Type**: Vertical Slice
- **Duration**: 8 weeks
- **Number of Sprints**: 4 (2 weeks each)

## Milestone Goal

Answer the concept's Tier 0 question offline: *is the gun + squad + front loop fun?* A human plays
Ryker Vance or Liora Vale in a bot-filled 5v5 on one lane of 5 hardpoints (A-Inner, A-Outer, Mid,
B-Outer, B-Inner). They pick up a Wardling squad at the Foundry and push the front until an Uplink
is Exposed and destroyed. Everything runs on a **local authoritative server**: an in-process
simulation behind a transport interface. The client renders snapshots only, so M2 replaces the
transport and does not rewrite the game.

**Slice overrides of Canon** (slice-only flags that do not change Canon):
- Duplicate heroes are allowed per team (`slice.allow_duplicate_heroes`), because there are only 2
  heroes for 10 slots. This also lets us test 10 heroes + 30 Wardlings.
- All 5 hardpoints use the **Hold** task (C4). Plant and Breach come in M3.
- The match cap is 30:00. Time-out uses 1-lane Incursion (0–3, C9), and a tie is a draw (no Sudden Death).
- No levels or skill trees: each hero has all 4 skills at rank 1 with fixed cooldowns.

Design sources (written in parallel, so paths are provisional): `design/gdd/match-flow-and-map.md`,
`design/gdd/heroes.md`, `design/gdd/weapons-and-mods.md`, `design/gdd/wardlings-and-economy.md`,
`design/ux/hud.md`, `design/art/art-bible.md`, `docs/architecture/architecture.md`,
`docs/architecture/adr-*.md`.

## Success Criteria

- [ ] **Launch and look:** `godot --path . res://scenes/slice/slice_match.tscn` starts a 5v5 bot match
      with the player as Ryker. Captures are saved to `production/qa/evidence/m1/`:
      `01-spawn-sanctum.png`, `02-squad-following.png`, `03-hold-contested.png`,
      `04-uplink-exposed.png` and `05-victory-screen.png`. Repeat with `--hero=liora` for
      `06-heal-beam.png` and `07-mana-meter.png`.
- [ ] A human can win or lose by Uplink destruction (C7). Integrity damage is permanent, and the
      Uplink is invulnerable unless an enemy holds that team's Inner (automated scenario test).
- [ ] 20 consecutive headless bot-vs-bot matches (`--headless --slice-autoplay`) finish with 0 crashes.
      Each logs its winner, length and captures to `production/qa/telemetry/m1/`. ≥15 of them end by
      Uplink kill before 30:00.
- [ ] Client/server separation: no client script references the server sim (CI static check). With
      the simulated latency transport at 150 ms RTT and 2% loss, the match still plays to completion.
- [ ] Respawn follows C11 (`min(30, 6 + 0.4 × minutes)`), and HQ vs. Mid-Beacon spawn choice works (unit + scenario tests).
- [ ] Wardlings follow, return fire, Hold Here, count 0.5 toward Hold presence, and dissolve 10 s after their owner dies (C15).
- [ ] `/playtest-report` from ≥3 owner sessions records a **go / pivot** verdict on fun and on Wardling readability.
- [ ] All S1 and S2 bugs resolved
- [ ] Performance within budget on target hardware (see Quality Gates)
- [ ] Build stable for 5 consecutive days (CI green on `main`, nightly soak passes)

## Feature List

### Must Ship (Milestone Fails Without These)

| Feature | Design Doc | Owner | Sprint Target | Status |
|---------|-----------|-------|--------------|--------|
| E1 Project scaffold, CI, test and evidence harness | docs/architecture/architecture.md | devops-engineer + godot-gdscript-specialist | S1 | Not started |
| E2 FPS controller | design/gdd/heroes.md | gameplay-programmer | S1 | Not started |
| E3 Local authoritative server tick loop | docs/architecture/adr-* (tick, transport) | engine-programmer + network-programmer | S1 | Not started |
| E4 Combat core | design/gdd/weapons-and-mods.md | gameplay-programmer | S1–S2 | Not started |
| E5 Ammo models (Mana / Mechanical) | design/gdd/weapons-and-mods.md | gameplay-programmer | S2 | Not started |
| E6 Slice map greybox | design/gdd/match-flow-and-map.md | level-designer | S2 | Not started |
| E7 Hardpoints and front | design/gdd/match-flow-and-map.md | gameplay-programmer | S2 | Not started |
| E8 Wardlings | design/gdd/wardlings-and-economy.md | ai-programmer | S2–S3 | Not started |
| E9 Uplink and match flow | design/gdd/match-flow-and-map.md | gameplay-programmer | S3 | Not started |
| E10 Hero kits: Ryker and Liora | design/gdd/heroes.md | gameplay-programmer (`/team-combat`) | S3 | Not started |
| E11 Hero bots | design/gdd/heroes.md | ai-programmer | S3–S4 | Not started |
| E12 Core HUD | design/ux/hud.md | ui-programmer (`/team-ui`) | S1–S4 | Not started |
| E14 Integration, soak and playtest | this doc | qa-lead | S4 | Not started |

### Should Ship (Planned but Cuttable)

| Feature | Design Doc | Owner | Sprint Target | Cut Impact | Status |
|---------|-----------|-------|--------------|-----------|--------|
| E13 Spawn choice and Lumen-lite (Wardling drops, 2 Armory items) | design/gdd/wardlings-and-economy.md | gameplay-programmer | S4 | Loses the HQ-vs-Beacon test; push it to M3 | Not started |
| Team-colour cel shader on placeholder meshes | design/art/art-bible.md | technical-artist | S3 | Readability read is weaker | Not started |

### Stretch Goals (Only if Ahead of Schedule)

Placeholder SFX (sound-designer); kill-cam / death recap (ui-programmer, `design/ux/hud.md`).

## Epics and Stories

The 14 epics, their story titles, build order and sprint split are listed in
`production/milestones/roadmap.md` under M1. `/create-stories <epic-slug>` turns each into
`production/epics/<epic-slug>/story-NN-*.md`.

## Quality Gates

| Gate | Threshold | Measurement Method |
|------|-----------|-------------------|
| Crash rate | 0 in 20-match headless soak; 0 in 3 h of owner play | `/soak-test`, Godot logs |
| Frame rate | ≥ 60 FPS at 1080p, 10 heroes + 30 Wardlings | `/perf-profile` on reference PC (owner's machine, specs recorded in report) |
| Server tick | sim step ≤ 25% of tick budget, headless | tick timer in telemetry |
| Load time | < 10 s to in-match from launch | automated timing in soak |
| Critical bugs | 0 open S1 | `production/qa/bugs/` (`/bug-triage`) |
| High-severity bugs | 0 open S2 | `/bug-triage` |
| Test coverage | every Logic story has a gdUnit4 test; all visual stories have screenshots | `/test-evidence-review` |

## Risk Register

| Risk | Probability | Impact | Mitigation | Owner | Status |
|------|------------|--------|-----------|-------|--------|
| Split architecture slows feature work | Med | High | Transport + snapshot done first (E3) with one template entity; later epics copy the pattern | lead-programmer | Open |
| Godot 4.7 API gaps vs. training data | Med | Med | Consult `docs/engine-reference/godot/`; godot-specialist reviews E1–E3 | godot-specialist | Open |
| Wardlings unreadable / cluttered | Med | High | Team-colour shader early (S3), squad cap 3, readability screenshots at 30 m reviewed | art-director | Open |
| Bots too weak to test the loop | High | Med | Bots use player input path; difficulty knob; owner can play 1v1 + bots on own team | ai-programmer | Open |
| Navmesh / 40 agents cost | Med | Med | E8.6 budget test before E11; avoidance tuned, path requests throttled | ai-programmer | Open |
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
