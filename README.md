# Cybergram

**A 5v5 first-person PvP MOBA shooter.** Heroes with MOBA-style skills fight
over a war-like front line, each player leading their own squad of minions
("Wardlings"). The goal is to push into the enemy base and destroy their
**Mana Uplink**. Anime/cartoon look, futuristic-fantasy world.

> Status: **pre-alpha, playable.** Latest release:
> [**v0.4.0**](https://github.com/LetsManu/Cybergram/releases/tag/v0.4.0) for
> Windows and Linux: main menu, pause menu with settings, placeholder sound,
> and a dedicated server with a matchmaking lobby and lag compensation ([`docs/SERVER.md`](docs/SERVER.md)). The offline vertical slice (M1) is a 3v3 match against
> bots on a 1-lane map. Its balance target (most matches ending by Uplink
> kill) is not met yet; see `production/qa/m1-soak-report.md`.

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

## What works today (M1 vertical slice)

All 15 M1 epics are built:

| Epic | Feature |
|---|---|
| E1 | Godot project, test framework (gdUnit4), CI and release builds on GitHub Actions |
| E2 | First-person controller: walk, sprint, jump, crouch |
| E3 | Local authoritative game server (30 Hz) with client prediction; the same message path will carry online play |
| E4 | Combat: hitscan, falloff, headshots, armor, death and respawn |
| E5 | Mana guns (pool + Burnout) and Mechanical guns (magazine + reload) |
| E6 | Slice map "Shardline Causeway" (1 lane, 5 hardpoints, both HQs) |
| E7 | Hardpoint tasks (Hold, Plant, Breach), lane front, objective strip |
| E8 | Wardling squads with 4 commands, Vanguard waves |
| E9 | Mana Uplink and match flow (phases, Sudden Death, time-out) |
| E10 | Hero kits: Vesper Loom and Brannoc |
| E11 | Hero bots for every empty slot |
| E12 | Full HUD with accessibility toggles |
| E13 | Spawn choice and Armory (Lumen, squad upgrades, Med-Pack, gun mounts) |
| E14 | Integration, soak and playtest (balance target still open) |
| E15 | Levels and a reduced skill tree |

Since v0.1.0: main menu, Esc pause menu with saved settings (sensitivity,
FOV, volume, fullscreen), bullet tracers, placeholder combat sounds,
invisible edge walls so heroes can't fall off the lane, and an online
dedicated server (UDP / ENet) with a LoL-style lobby (teams, hero pick, Ready,
countdown, back to the lobby after each match) and lag-compensated shooting.

Next up:
- Balance pass so most matches end by Uplink kill
- Bot AI: siege the exposed Uplink and contest defuses (see `design/balance/slice-tuning.md`)
- Real art and audio

The roadmap is in [`production/milestones/roadmap.md`](production/milestones/roadmap.md).

## Playing it

**Download:** get the latest build from
[**Releases**](https://github.com/LetsManu/Cybergram/releases):

| Platform | File | How to start |
|---|---|---|
| Windows 10/11 (x86_64) | `Cybergram-<version>-windows-x86_64.zip` | Unzip, run `Cybergram.exe` |
| Linux (x86_64) | `Cybergram-<version>-linux-x86_64.tar.gz` | Extract, run `./Cybergram.x86_64` |

No install is needed, but a Vulkan-capable GPU is. The Windows build isn't
code-signed, so SmartScreen may warn: choose *More info → Run anyway*.
Builds for every commit are also attached to each **Build** run under the
*Actions* tab.

The game opens on the **main menu**: pick a hero, then **Play vs Bots** (a
**3v3 match on the slice map**, bots fill the other slots) or **Play Online**
on the official server (`cyber.djboeck.at`). To host one, see [`docs/SERVER.md`](docs/SERVER.md). Destroy the enemy Mana Uplink
to win. It only takes damage once your team holds the enemy's Inner
hardpoint.

From source (Godot 4.7): `godot --path .`. Options:

```bash
godot --path . -- --hero brannoc        # skip the menu: play Brannoc vs bots
godot --headless --path . -- --server --port 7777   # online dedicated server
godot --path . -- --connect 127.0.0.1:7777          # join it
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
| Pause menu / settings | Esc |
| Net graph / colour-blind / UI scale / damage numbers | F3 / F6 / F7-F8 / F9 |

Tests: `GODOT=/path/to/godot tools/ci/run_tests.sh` (gdUnit4) and
`tools/ci/check_deps.sh`.

## Making a release

1. Set the version in `project.godot` (`config/version`) and in
   `export_presets.cfg` (`file_version` / `product_version`).
2. Write the player-facing notes in `production/releases/vX.Y.Z.md`.
3. Push a tag `vX.Y.Z` to `main`, or run the **Build** workflow manually
   with `release_version` set.

The workflow exports both platforms, packages them with `SHA256SUMS.txt`
and publishes the GitHub release. A tag with a `-` (e.g. `v0.2.0-beta`) is
marked as a pre-release.

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
| `production/` | Milestones, release notes and QA screenshot evidence |
| `.claude/` | [Claude Code Game Studios](https://github.com/donchitos/claude-code-game-studios) agent framework |

## How it's built

Development is driven by Claude Code using the Claude Code Game Studios
framework. Specialist agents (designers, programmers, QA) work through the
milestone epics. Every visual change is launched and screenshotted before
it counts as done. Work is reviewed through pull requests.
