# Cybergram — Work Breakdown for Sub-Agents

How a large batch of work is split across several agents at once without them
touching each other's files. Adapted from the owner's Aetherspire breakdown
(2026-09) to this Godot 4.7 project. Acceptance criteria live in the GDDs,
UX specs and ADRs; this file only says *who does what, in what order, on which
files*. It extends `coordination-rules.md` (Parallel Task Protocol) and
`model-tiers.md` (tier aliases).

## 1. Roles and model tiers

Tiers are written as the `model:` alias the Agent tool takes (`opus`, `sonnet`,
`haiku`). The alias resolves to the current model of that family.

| Role | Tier | Does | Never does |
|---|---|---|---|
| **Lead** | the session (Opus) | Plans waves, writes each chunk's brief, owns the shared files (§3), merges, resolves spec conflicts, runs the full suite once per merge batch, releases, reports to the owner | Implements chunks itself while agents are idle |
| **Integrator** | `opus` | Cross-cutting or risky chunks: networking/protocol, `ServerWorld` / `ClientWorld` / `GameSession`, abilities core, lobby↔match handover, anything that can break online play | Mechanical data or doc work |
| **Builder** | `sonnet` | Well-bounded features with a clear interface and their tests: one hero kit, one UI screen, one VFX set | Shared files, protocol changes, anything marked `opus` |
| **Scribe** | `haiku` | Mechanical, fully specified work: `.tres` data from GDD tables, localization rows, doc tables, tests for pure functions whose spec is given | Design decisions, anything without an exact spec |
| **Reviewer** | `opus`, fresh context, one per chunk | Reads the brief + diff, reports findings; at most one focused test command | The full suite; fixes |
| **Verifier** | `sonnet` | Confirms a fix against the reviewer's findings | The full suite; design decisions |

Rule of thumb: if the brief can be written as "produce exactly this", `haiku`.
If it needs judgement inside one system, `sonnet`. If it crosses layers
(core/networking/gameplay/ui/ai) or can break the online client, `opus`.
The lead never has more chunks in flight than it can merge and review in the
same session. **Six in flight is the realistic cap**, and fewer when the CI box
is the bottleneck (see §2, CPU).

## 2. How a chunk runs

1. **Brief.** The lead writes it (template in §6): spec sections, owned files,
   forbidden files, exact "done" criteria, the test command, and what to return
   (diff summary, test output, snippets for shared files).
2. **Work.** The agent works only inside its owned files, in its own git
   worktree on branch `claude/<wave>-<chunk-id>`. It commits there and does
   **not** push or open PRs. It runs the tests before returning.
3. **Review.** A fresh `opus` reviewer reads the brief + diff and reports
   findings. It does not run the full suite.
4. **Fix.** The lead fixes or bounces; a `sonnet` verifier confirms the fix.
5. **Merge.** The lead wires the shared-file snippets, merges the batch into
   the integration branch, runs the full suite once, opens the PR, drives CI
   green and merges to `main`.
6. **Release.** The lead updates the release notes (`production/releases/`)
   and runs the release workflow, which also publishes the Docker server image.

**Two agents never own the same file.** If two chunks need the same file, they
are one chunk or they are sequential.

**Godot-specific operating rules (every brief repeats them):**

- **CPU:** one Godot process at a time per agent. The box has 4 cores. Never
  leave background Godot processes running, and never `pkill -f` a pattern that
  can match your own shell.
- **Logs:** always cap them (`| tail -c …` or `grep`). A runaway SCRIPT ERROR
  loop once wrote 17 GB. Abort a run that spams errors.
- **Ports:** each chunk gets its own UDP range (§4), so parallel server tests
  don't collide.
- **Imports:** run `$GODOT --headless --path . --import` after adding a
  `class_name`, before any test or match run.
- **Evidence:** player-visible changes need a screenshot via
  `tools/ci/capture_scene.sh` in `production/qa/evidence/`. Look at it before
  calling the work done (coding-standards: "a parse check is not a run").
- **Regression tests:** watch each one fail against the unfixed code before
  trusting it (`.claude/rules/test-standards.md`).

## 3. Shared files — lead only

Agents return snippets for these; they never edit them:

- `project.godot`, `export_presets.cfg` (version, input map, autoloads)
- `assets/data/app/app_config.tres` (session / overlay / plugin wiring, online server)
- `src/core/app/app_root.gd`, `src/core/app/launch_config.gd` (boot and flags)
- `src/networking/protocol/msg_type.gd` (message ids, `PROTOCOL_VERSION`)
- `src/gameplay/world/game_session.gd`, `server_world.gd`, `client_world.gd`
  (session graph). A chunk that must change them is an `opus` Integrator
  chunk and owns them alone for its wave.
- `assets/localization/hud.csv` (agents return rows; the lead appends them in
  one place, so the merges stay clean)
- `.github/workflows/*`, `tools/server/*` (CI, release, Docker)
- `README.md`, `docs/SERVER.md`, `production/releases/*`, this file

## 4. Chunk ids and ports

Ids: **H** heroes, **S** settings/input, **P** shop (purchase), **G** graphics/VFX,
**L** lobby/social, **N** networking, **U** launcher/updates, **B** bots/AI,
**Q** QA/review, **D** docs/deploy. Each chunk gets a UDP port block:
`7800 + 10 × (its slot in the wave)`.

## 5. Waves

Waves 0-8 are the history up to v0.4.1 (M0 design, M1 epics E1-E15, release
pipeline, menu, tracers, online server, lobby, lag compensation, Docker image).
Only the tables below are live work.

### Wave 9 — "polished game" (owner request 2026-10-04)

Research input for P, L and U: how League of Legends, Dota 2, Apex Legends and
Valorant handle each area. Every chunk does its own short research (training
knowledge; web where the agent has it) and writes its decisions into its
report.

| Id | Chunk | Tier | Owns | Done when |
|---|---|---|---|---|
| H1 | Heroes: Ryker Vance, Liora Vale, Sable (heroes.md §4.2/4.4/4.6) | `sonnet` | `assets/data/heroes/hero_{ryker_vance,liora_vale,sable}*`, their weapon/skill/tree `.tres`, **new** effect files in `src/gameplay/abilities/effects/`, their model blueprints; returns snippets for `ability_world.gd` and the bot roster | Each hero launches with `--hero <id>`, every skill works in the skill demo (screenshot), bots play them without SCRIPT ERROR, unit + integration tests per kit |
| H2 | Heroes: Juniper Quill, Hex (heroes.md §4.3/4.7, §3.7 gadget rule) | `sonnet` | same pattern, their own files | same |
| S1 | Settings + key rebinding: tabs Video (window mode, render scale, VSync, FPS cap, quality preset 0-3 as `GameSettings.graphics_quality`), Audio (buses), Controls (every action rebindable, conflict swap, reset; InputMap applied at boot), Gameplay (crosshair, damage numbers, colour-blind, UI scale) | `sonnet` | `src/ui/menu/settings_panel.gd` (+ new tab files), `src/core/app/game_settings.gd`, new `src/core/input/*`, `src/gameplay/input/player_input_source.gd` | Every action rebinds and survives restart, tests for save/load/conflict/reset, screenshot per tab |
| P1 | LoL-style shop: tabs, search, item cards, detail pane, recommended build per hero, buy / sell-or-undo per the economy GDD, `open_shop` key (B) on the pad | `sonnet` | `src/ui/hud/armory_panel.gd` (+ new shop files), `assets/data/economy/*` | Shop logic tests (filter, affordability, recommended next, buy/undo via the server path), screenshot via `--debug-armory` |
| G1 | Graphics: WorldEnvironment (sky, glow, tonemap, SSAO, void fog), material library, map dressing (no collision, navmesh unchanged), muzzle flash / impact / hit / death / respawn / capture-ring VFX, quality scaling from `GameSettings.graphics_quality` | `sonnet` | `tools/maps/build_shardline_causeway.gd` (visual parts), `assets/maps/slice/*`, `src/gameplay/views/*` (presentation only), new `src/gameplay/views/fx/*` | Map, navmesh and edge-blocker tests green; before/after screenshots; frame time reported; nothing created on the headless server |
| L1 | Player profile (name, colour/emblem, saved locally) + full lobby (names, hero portraits from ContentDB, chat, ready states) + friends list with online status on the server | `opus` | `src/networking/lobby/*`, `src/ui/menu/lobby_screen.gd`, `main_menu.gd`, new `src/ui/menu/profile_*`, `friends_*`; **this wave's Integrator** for `msg_type.gd` | Lobby flow + profile + presence tests over loopback, end-to-end over UDP, protocol version bumped, screenshots |
| U1 | Launcher: a separate small Godot app (`launcher/`): news + patch notes, update check against a `version.json`, download + unzip + start the game; the server container also serves the client builds over HTTP (TCP 8080) | `sonnet` | `launcher/*`, `tools/server/*` additions returned as snippets | Launcher updates an old install to the latest build in a local end-to-end test; screenshot |
| Q1 | Reviewer pass per merged chunk | `opus` | none | Findings list per chunk |

Order: H1, H2, S1, P1, G1, L1 and U1 run at once (six or seven in flight is
the cap). The lead merges as they land; Q1 reviews each, then the lead
releases **v0.5.0**.

## 6. Brief template

```
CHUNK <id> — <name>                      Tier: <opus|sonnet|haiku>
Spec: <file §sections>
Owns (create/edit): <paths>
Forbidden: everything else, especially the shared files in work-breakdown.md §3
Depends on (already merged): <ids>
Done when: <acceptance lines, copied verbatim>
Test: GODOT=~/godot/Godot_v4.7-stable_linux.x86_64 tools/ci/run_tests.sh
      + tools/ci/check_deps.sh + the chunk's screenshot / end-to-end command
Ports: UDP <block>
Strings: every player-facing string through tr() with a HUD_ key; return the
         hud.csv rows to the lead, don't edit hud.csv
Rules: GDScript static typing, doc comments on public APIs, gameplay values in
       .tres data, server decides / client displays, layers per check_deps,
       one Godot process at a time, logs capped
Git: own worktree, branch claude/<wave>-<id>, Conventional Commits with the
     Co-Authored-By + Claude-Session lines, no push
Return: branch, diff summary, test output, snippets for shared files (marked),
        open questions / decisions taken
```
