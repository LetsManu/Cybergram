# Cybergram

**A 5v5 first-person PvP MOBA shooter.** Heroes with MOBA-style skills fight
over a war-like front line, each player leading their own squad of minions
("Wardlings"). The goal is to push into the enemy base and destroy their
**Mana Uplink**. Anime/cartoon look, futuristic-fantasy world.

> Status: **pre-alpha, playable online.** Latest release:
> [**v0.19.0**](https://github.com/LetsManu/Cybergram/releases/tag/v0.19.0)
> for Windows and Linux, installed and kept up to date by the launcher.
> There is an official server (`cyber.djboeck.at`) with accounts, friends,
> parties, Normal and Ranked queues and custom games. Offline play against
> bots needs no account. Patch notes: [`production/releases/`](production/releases/).

## The game in short

- **5v5, first person.** Bots fill empty slots.
- **One map, "Shardline Front":** 3 lanes and 15 hardpoints. Each hardpoint is
  a task (Hold, Plant or Breach). You can only attack the next one along
  your lane, so the front moves step by step. A smaller 1-lane map,
  "Shardline Causeway", hosts the 3v3 modes.
- **Wardlings:** a free squad that follows you, with 4 commands
  (Follow, Hold Here, Attack Target, Go Capture). Vanguard waves march to
  the front on a timer.
- **Hardpoints:**
  - Every held hardpoint is guarded by two **Garrison Sentinels** and has a
    **Supply Cache** (ammo for Mechanical guns, faster mana for Mana guns).
  - A held Mid gives a **Forward Beacon** you can spawn at.
- **Two gun types:** Mana guns (recharging pool) and Mechanical guns
  (magazines). Gun upgrades (Crystals and Chips) bought at the **Armory** are
  mounted visibly on the gun.
- **7 heroes:** Vesper Loom (Minionmancer), Sable (Infiltrator), Juniper
  Quill (Trapper), Ryker Vance (Soldier), Brannoc (Tank), Liora Vale
  (Healer), Hex (Hacker). Each has 4 skills, and you choose which to level
  up as your hero gains levels.
- **Win:** destroy the enemy Uplink. At 60:00 the deeper push wins, and a
  tie goes to Sudden Death.

The owner's idea list is in [`ideas`](ideas). The full design is in
[`design/`](design/).

## What works today

**Playing**
- Full 5v5 matches on the 3-lane map: hardpoint tasks, Surges, the Uplink
  siege and Sudden Death.
- Hero bots for every empty slot.
- Lag-compensated shooting on an authoritative server (30 Hz) with client
  prediction.
- **Main menu modes:**
  - Online.
  - Vs Bots: 5v5 offline.
  - Quick Match: 3v3 offline, on the 1-lane map.
  - Practice Range.
  - Tutorial.
  - Movement Course.

**Online, like a real client**
- Accounts with a recovery code; guests are allowed.
- **Queues:** Normal 5v5 (blind pick), Ranked 5v5 (draft with hover and trades
  in the last seconds), 3v3 All Random, and custom games with bot slots.
- Ready check, dodge and decline penalties.
- Friends with 7 presence states, direct messages, and party chat, invites
  and join requests.
- Ranks, and an opt-in public leaderboard.
- A status bar and a Diagnostics panel for connection problems.

**Look and sound**
- Heroes, Wardlings, objectives, floors and props are hand-built models in
  one cel-shaded style.
- Full sound design: weapons, all skills, footsteps, objectives and menus.
  Music grows with the match, and there are announcer cues and ambience.

**Settings**
- Key rebinding, crosshair editor, video and audio settings.
- Comfort and accessibility options (colour-blind modes, UI scale, reduce
  motion), and localisation-ready UI text.

**Around the game**
- The **launcher** installs, updates and starts the game, shows patch notes
  and has a connection test.
- A small **website** shows downloads, heroes, patch notes, server status and
  the leaderboard.
- **Server ops:** `/health`, `/metrics` (Prometheus) and a token-protected
  `/admin` page. See [`docs/monitoring.md`](docs/monitoring.md).

**Not done yet** (see [`docs/polish-backlog.md`](docs/polish-backlog.md)):
- Barricade gameplay.
- Sanctum and Foundry art.
- Bots do not use Supply Caches.
- More balance passes.

The roadmap is in [`production/milestones/roadmap.md`](production/milestones/roadmap.md);
current work and decisions are in [`PROGRESS.md`](PROGRESS.md).

## Playing it

**Download:** get the latest build from
[**Releases**](https://github.com/LetsManu/Cybergram/releases).

**Recommended: the installer.** It includes the launcher, which keeps the
game up to date. Details, uninstalling and the unsigned-installer warning
are in [`docs/INSTALL.md`](docs/INSTALL.md).

| Platform | File | How to start |
|---|---|---|
| Windows 10/11 (x86_64) | `CybergramSetup-<version>.exe` | Run it (per-user, no admin) |
| Linux (x86_64) | `Cybergram-<version>-x86_64.AppImage` | `chmod +x`, run it |
| Linux (x86_64) | `CybergramInstaller-<version>-linux-x86_64.tar.gz` | Extract, run `./install.sh` |

**Portable builds** (advanced users, no install, no auto-update):

| Platform | File | How to start |
|---|---|---|
| Windows 10/11 (x86_64) | `Cybergram-<version>-windows-x86_64.zip` | Unzip, run `Cybergram.exe` |
| Linux (x86_64) | `Cybergram-<version>-linux-x86_64.tar.gz` | Extract, run `./Cybergram.x86_64` |

You need a Vulkan-capable GPU. The Windows builds aren't code-signed, so
SmartScreen may warn: choose *More info → Run anyway*. If you can't
connect, see [`docs/connecting.md`](docs/connecting.md).

### The launcher

The launcher works like the League client or Battle.net:
- It logs you in, installs the game into a `game/` folder next to itself
  and checks every download's sha256.
- It shows the patch notes and updates itself and the game.
- **PLAY** starts the game, or **UPDATE** when a new version is out.
- Offline you can still start the installed version.

Settings are in the launcher, plus `launcher.cfg` next to it. Source and
tests: [`launcher/`](launcher/).

### Controls (defaults, rebindable in Settings)

| Action | Key |
|---|---|
| Move / jump / sprint / crouch | WASD / Space / Shift / Ctrl |
| Fire / reload | Left mouse / R |
| Skills / ultimate | Q, E, C / G (ultimate unlocks at level 6) |
| Learn a skill (spend a skill point) | hold Alt + Q/E/C/G |
| Interact / open the Armory | F |
| Use Med-Pack | 4 |
| Squad: smart command / wheel / follow | tap Z / hold Z / X |
| Scoreboard | Tab |
| Pause menu / settings | Esc |
| Net graph / colour-blind / UI scale / damage numbers | F3 / F6 / F7-F8 / F9 |

### From source (Godot 4.7)

```bash
godot --path .                                       # main menu
godot --path . -- --hero brannoc                     # skip the menu: 5v5 vs bots on Shardline Front
godot --path . -- --map slice --bots --hero sable    # 3v3 vs bots on the 1-lane map
godot --path . -- --map test_course                  # movement test course
godot --headless --path . -- --server --bots-only --seed 3   # all-bot match, prints a summary
```

All command-line options are documented at the top of
`src/core/app/launch_config.gd`.

Tests: `GODOT=/path/to/godot tools/ci/run_tests.sh` (gdUnit4, about 1500
tests) and `tools/ci/check_deps.sh` (layer check).

## Hosting a server

The server runs in Docker (`ghcr.io/letsmanu/cybergram-server`).
- **Processes:** a front process handles accounts, friends, parties and
  matchmaking on UDP 7777, and each match runs in its own process.
- **Launcher updates:** the same container serves them.
- **Data:** accounts live in the `/data` volume. Keep it when updating;
  removing it deletes every account.

Guides:
- [`docs/SERVER.md`](docs/SERVER.md): setup.
- [`docs/HOSTING.md`](docs/HOSTING.md): NAS, VPS, ports and automatic updates.
- [`docs/monitoring.md`](docs/monitoring.md): health checks and the admin page.
- `tools/server/docker-compose.yml`: the compose file.

The website is a separate image (`ghcr.io/letsmanu/cybergram-web`, source
in [`web/`](web/)).

## Making a release

1. Set the version in `project.godot` (`config/version`) and in
   `export_presets.cfg` (`file_version` / `product_version`). Bump
   `launcher/project.godot` only when the launcher changed.
2. Write the player-facing notes in `production/releases/vX.Y.Z.md` and copy
   them to `launcher/assets/notes/`.
3. Merge to `main`, then push a tag `vX.Y.Z` or run the **Build** workflow
   manually with `release_version` set.

The workflow does the rest:
- Exports both platforms, builds the installers and runs the smoke and e2e
  tests.
- Publishes the GitHub release with `SHA256SUMS.txt`.
- Pushes the server image with the baked update feed, so launchers pick up
  the new version once the server is updated.

A tag with a `-` (e.g. `v0.2.0-beta`) is marked as a pre-release.

## Project layout

| Path | What |
|---|---|
| `design/gdd/` | Game design docs: concept + Canon, match flow & map, heroes, weapons & mods, Wardlings & economy |
| `design/art-bible.md`, `design/ux/` | Visual direction, HUD and menu specs |
| `docs/architecture/` | Architecture, ADRs, online state machines (`front-state.md`) |
| `docs/assets/` | One page per world asset: look, states, sounds |
| `src/` | Game code: `core`, `networking`, `gameplay`, `ai`, `ui` |
| `assets/data/` | All gameplay numbers as Godot Resources (`.tres`) |
| `assets/maps/` | Shardline Front, Shardline Causeway (slice), test course |
| `tools/` | CI, server, Blender asset scripts (`tools/art/`), audio pipeline (`tools/audio/`) |
| `launcher/` | The launcher app |
| `web/` | The website |
| `tests/` | Unit and integration tests |
| `production/` | Milestones, release notes and QA screenshot evidence |
| `.claude/` | [Claude Code Game Studios](https://github.com/donchitos/claude-code-game-studios) agent framework |

## How it's built

Claude Code drives development, using the Claude Code Game Studios
framework.
- Specialist agents (designers, programmers, QA) work through the plan.
- Every visual change is launched and screenshotted before it counts as
  done.
- Every change goes through a pull request with CI: tests, export, a
  dedicated-server smoke test and matchmaking e2e tests.
