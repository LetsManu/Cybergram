# Cybergram -- PvP First-Person MOBA Shooter

Built with the Claude Code Game Studios framework (v1.1.2, MIT — see `.claude/CCGS-LICENSE`).

Indie game development managed through 39 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Godot 4.7 (Forward+, Jolt physics)
- **Language**: GDScript (GDExtension only if profiling demands it)
- **Version Control**: Git with trunk-based development
- **Build System**: Godot headless export (`project.yaml` → `commands`)
- **Asset Pipeline**: Godot import pipeline; glTF 2.0 for 3D assets

> **Note**: Only the Godot specialist agents are installed (Unity/Unreal sets removed).

## Commands (headless; cloud sessions have Godot at ~/godot)

- Godot binary: `tools/ci/install_godot.sh` (pinned 4.7-stable, prints the path; cached in `~/godot`).
- Import once after cloning or adding a `class_name`: `$GODOT --headless --path . --import`
- Tests: `tools/ci/run_tests.sh` (all), or one suite:
  `$GODOT --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/matchmaking --ignoreHeadlessMode -c`
  (leave out `-d` locally: with it a script error stops in the debugger and the run hangs).
- Layer check: `tools/ci/check_deps.sh`. Launcher copies of shared scripts: `launcher/tools/sync_shared.sh`.
- Armory (items, build guides, recommendations): `docs/armory.md`. Regenerate the hero guides with
  `python3 tools/armory/build_guides.py`; data checks + advisor tests: `-a res://tests/unit/economy`.
  Catalog order is the wire id: append items only.
- Screenshot under a virtual display: `GODOT=... tools/ci/capture_scene.sh res://src/ui/menu/matchmaking/mm_preview.tscn out.png 90 --mm queued`
- Server (front + match processes): `tools/server/docker-compose.yml`; monitoring: `docs/monitoring.md`.

## Online architecture (short)

Front process (`--front`, UDP 7777, ENet/DTLS): AccountService (accounts,
friends, parties) + MatchmakingFront (queues, ready check, draft + team chat,
custom lobbies with bot slots, loading progress relay) + FrontPhases (player / party / lobby state machines, pushed as
versioned `EV_PHASE`, protocol 21) + OpsHttpServer (`/health`, `/metrics`,
`/admin` on TCP 8090). Matches run in separate processes (MatchSupervisor).
The game's main menu (`src/ui/menu/matchmaking/`) is the queueing client; the
launcher logs in, updates and starts the game. State diagram:
`docs/architecture/front-state.md`. Plan and status: `PROGRESS.md`. Manual
(visual) checks: `docs/manual-checklist.md`. Logs never carry account ids or
names in clear (`OpsLog.tag`).

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

<!-- ENGINE-REFERENCE-IMPORT: the line below is engine-specific. /setup-engine
     rewrites it to @docs/engine-reference/<engine>/VERSION.md for the chosen
     engine, so a Unity or Unreal project stops loading the Godot reference every
     session. It defaults to Godot (the template's example engine); skills that
     need the pinned version read docs/engine-reference/<engine>/VERSION.md on
     demand regardless of this import. -->
@docs/engine-reference/godot/VERSION.md


## Technical Preferences

`project.yaml` at the repo root is the primary config store — engine, specialists,
naming, platform, performance, modes. Skills resolve it via `resolve_config`
(see `.claude/docs/config-resolution.md`).

`.claude/docs/technical-preferences.md` is the **legacy fallback**, read on demand
when a key is absent from `project.yaml`. It is no longer imported here: before
`/setup-engine` runs it is almost entirely `[TO BE CONFIGURED]` placeholders, and
after it runs `project.yaml` holds the real values.

## Usage Rule (owner, 2026-10-06; replaces the $250 cap of 2026-10-02)

Claude work on this project runs on the owner's subscription; there is no
dollar cap any more.

- If a usage limit is hit, commit and push finished work; continue when the
  owner says the limit has reset.
- Prefer one focused agent over many parallel agents unless parallelism is
  clearly worth it.

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

Read `.claude/docs/context-management.md` on demand — it is a reference, not
session context. Two of its conventions are load-bearing and cited by name
elsewhere in the repo, so they are restated here rather than lost:

- **`production/session-state/active.md` is the session checkpoint.** The file is
  the memory, not the conversation. Read it first after any compaction, crash, or
  `/clear`.
- **Helpers in `.claude/scripts/` emit observations, never verdicts.** A script
  that scores or judges will eventually contradict a mode or override it cannot
  see. (Cited by `artifact-check.sh` and `adr-dep-graph.sh`.)
