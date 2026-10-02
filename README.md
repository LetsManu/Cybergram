# Cybergram

**A 5v5 first-person PvP MOBA shooter.** Heroes with MOBA-style skills fight
over a war-like front line, each player leading their own squad of minions
("Wardlings"). The goal is to push into the enemy base and destroy their
**Mana Uplink**. Anime/cartoon look, futuristic-fantasy world.

> Status: **pre-alpha, playable.** The offline vertical slice (M1) is
> playable: a 3v3 match against bots on a 1-lane map. Its balance target
> (most matches ending by Uplink kill) is not met yet; see
> `production/qa/m1-soak-report.md`.

## The game in short

- **5v5, first person.** Bots fill empty slots.
- **One map, 3 lanes, 15 hardpoints.** Each hardpoint is a task (Hold, Plant
  or Breach). You can only attack the next one along your lane, so the
  front moves step by step.
- **Wardlings:** a free squad of 3 that follows you, with 4 commands
  (Follow, Hold Here, Attack Target, Go Capture). Small Vanguard waves also
  march to the front every 60 s.
- **Two hero types:** Mana guns (recharging pool) and Mechanical guns
  (magazines). Gun upgrades (Crystals and Chips) are visibly mounted on the
  gun.
- **7 heroes:** Vesper Loom (Minionmancer), Sable (Infiltrator), Juniper
  Quill (Trapper), Ryker Vance (Soldier), Brannoc (Tank), Liora Vale
  (Healer), Hex (Hacker).
- **Win:** destroy the enemy Uplink. At 60:00 the deeper push wins, and a
  tie goes to Sudden Death.

The owner's idea list is in [`ideas`](ideas). The full design is in
[`design/`](design/).

## What works today (M1 so far)

| Epic | Feature |
|---|---|
| E1 | Godot project, test framework (gdUnit4), CI on GitHub Actions |
| E2 | First-person controller: walk, sprint, jump, crouch |
| E3 | Local authoritative game server (30 Hz) with client prediction; the same message path will carry online play |
| E4 | Combat: hitscan, falloff, headshots, armor, death and respawn |
| E5 | Mana guns (pool + Burnout) and Mechanical guns (magazine + reload) |
| E6 | Slice map "Shardline Causeway" (1 lane, 5 hardpoints, both HQs) |
| E7 | Hardpoint capture (Hold), lane front, objective strip |
| E8 | Wardling squads with 4 commands, Vanguard waves |

Still to come in M1:
- Uplink and match flow
- Hero skills
- Hero bots
- Full HUD
- Shop and spawn choice
- Levels and skill trees
- Integration and soak testing

The roadmap is in [`production/milestones/roadmap.md`](production/milestones/roadmap.md).

## Playing it

**Download:** open the latest successful **Build** run under the repo's
*Actions* tab and download **Cybergram-Windows** (or **Cybergram-Linux**).
Unzip it and run `Cybergram.exe`. No install is needed.

The game starts straight into a **3v3 match on the slice map** with you as
Vesper Loom and bots filling the other slots. Destroy the enemy Mana Uplink
to win. It only takes damage once your team holds the enemy's Inner
hardpoint.

From source (Godot 4.7): `godot --path .`. Options:

```bash
godot --path . -- --hero brannoc        # play Brannoc instead of Vesper
godot --path . -- --map test_course     # movement test course
godot --headless --path . -- --server --bots-only --seed 3   # all-bot match, prints a summary
```

| Action | Key |
|---|---|
| Move / jump / sprint / crouch | WASD / Space / Shift / Ctrl |
| Fire / reload | Left mouse (click once to capture the mouse) / R |
| Skills / ultimate | Q, E, C / G (ultimate unlocks at level 6) |
| Learn a skill (spend a skill point) | hold Alt + Q/E/C/G |
| Interact (pick up Mana Cell) / open Armory on your HQ pad | F |
| Use Med-Pack | 4 |
| Squad: smart command / wheel / follow | tap Z / hold Z / X |
| Scoreboard | Tab |
| Net graph / colour-blind / UI scale / damage numbers | F3 / F6 / F7-F8 / F9 |

Tests: `GODOT=/path/to/godot tools/ci/run_tests.sh` (gdUnit4) and
`tools/ci/check_deps.sh`.

## Project layout

| Path | What |
|---|---|
| `design/gdd/` | Game design docs: concept + Canon, match flow & map, heroes, weapons & mods, Wardlings & economy |
| `design/art-bible.md`, `design/ux/hud.md` | Visual direction, HUD spec |
| `design/open-questions.md` | Decisions still open for the owner |
| `docs/architecture/` | Technical architecture, ADRs, Godot 4.7 verification notes |
| `src/` | Game code: `core`, `networking`, `gameplay`, `ai`, `ui` |
| `assets/data/` | All gameplay numbers as Godot Resources (`.tres`) |
| `assets/maps/` | Maps (greybox) |
| `tests/` | Unit and integration tests |
| `production/` | Milestones and QA screenshot evidence |
| `.claude/` | [Claude Code Game Studios](https://github.com/donchitos/claude-code-game-studios) agent framework |

## How it's built

Development is driven by Claude Code using the Claude Code Game Studios
framework. Specialist agents (designers, programmers, QA) work through the
milestone epics. Every visual change is launched and screenshotted before
it counts as done. Work is reviewed through pull requests.
