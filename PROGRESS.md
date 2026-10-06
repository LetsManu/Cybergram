# Progress: League-client parity (launcher, lobby, party, matchmaking)

Branch: `claude/happy-bardeen-s25y8x`. Plan agreed 2026-10-06. Order: Phase 1 ->
Phase 3 -> Phase 2 -> Phase 4. Phase 0 (CI) skipped by owner decision: CI stays
as it is, new tests run inside the existing test job.

## Decisions and assumptions
- **CI untouched** (owner). Observation for later: `tools/ci/run_tests.sh` runs
  gdUnit4 with `-d`; a script error then stops in the debugger and waits until
  the job timeout instead of failing fast. Locally the run hung the same way.
- **Bans**: built as a setting, 0 per team while the roster has 7 heroes (each
  team needs 5 distinct heroes). Raise it when the roster grows.
- **Ops endpoint**: internal TCP 8090, `/health` + `/metrics` open, `/admin`
  only with `CYBERGRAM_ADMIN_TOKEN`; published on 127.0.0.1 by default.
- **"Launcher" in the spec** = the game's main menu matchmaking flow
  (`src/ui/menu/matchmaking/`), because queueing happens there; the separate
  launcher app logs in, updates and starts the game.
- **Player tags in logs**: salted hash (OpsLog.tag), never account ids (GDPR).
- **InGame vs Reconnecting**: a running match owns its own connection, so a
  closed menu connection during a match stays InGame.
- **Transport** stays ENet/DTLS (no websockets); protocol bumped to 20.

## Done
- P1a State machines (player, party, lobby) with legal tables, rejection +
  reporting of illegal transitions. `phase_machine_test.gd` (every pair).
- P1b Protocol 20: `EV_PHASE` (epoch + seq, snapshot flag), `OP_STATE_SYNC`
  resync; `FrontPhases` derives and pushes; `MatchmakingClient.phase_changed`.
  `front_phases_test.gd`: full flow order, decline, resync, reconnect grace.
- P1c `OpsLog` (JSON lines, player tags), `OpsMetrics` (Prometheus),
  `OpsHttpServer` (`/health`, `/health/live`, `/metrics`, `/admin`,
  `/admin.json`), `docs/monitoring.md` (Icinga), compose + Dockerfile, PRIVACY v7.

## In progress
- P1d Client: status bar (connection, ping, phase, queue timer + estimate,
  lockout), diagnostics event list with copy, timeouts on every wait.

## Next (prioritised)
1. P1d (above), CLAUDE.md commands / architecture / state diagram.
2. Phase 3: estimated wait in UI, ready check 12 s, draft: hover/intent,
   pick trades, blind pick variant, ban phase (setting, 0 now), lockout timer,
   bot difficulty and slots in custom lobbies, loading progress, return to
   party, headless N-client simulation.
3. Phase 2: party promote / kick / chat / ready flags / invite expiry UI;
   presence with 7 states + Away; join/invite from friends list; direct
   messages (memory only) with unread counts; toasts; rate limits.
4. Phase 4: launcher polish (needs human visual checks).

## Manual checks needed (no display in the cloud session)
See `docs/manual-checklist.md` (created with P1d).
