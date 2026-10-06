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
- **Champ select formats** (game-design agent, 2026-10-06): Normal blind pick,
  Ranked draft; a hovered-but-unlocked hero auto-locks even in Ranked (only
  "nothing hovered" cancels). Owner confirmed 2026-10-06: "it should lock the hero".
- **Social (P2)**: party chat and DMs are online-only and never stored or
  logged; DMs only between friends; blocks hide chat, invites, join requests;
  "join a friend" = a join request to that party's leader (who then invites);
  ready flags are informational (they do not gate the queue).

## Done
- P1a State machines (player, party, lobby) with legal tables, rejection +
  reporting of illegal transitions. `phase_machine_test.gd` (every pair).
- P1b Protocol 20: `EV_PHASE` (epoch + seq, snapshot flag), `OP_STATE_SYNC`
  resync; `FrontPhases` derives and pushes; `MatchmakingClient.phase_changed`.
  `front_phases_test.gd`: full flow order, decline, resync, reconnect grace.
- P1c `OpsLog` (JSON lines, player tags), `OpsMetrics` (Prometheus),
  `OpsHttpServer` (`/health`, `/health/live`, `/metrics`, `/admin`,
  `/admin.json`), `docs/monitoring.md` (Icinga), compose + Dockerfile, PRIVACY v7.

- P1d Client: `MmStatusBar` (bottom strip of the matchmaking flow:
  connection + ping, server phase, queue timer + estimate, lockout countdown,
  plain-language hints when a wait runs long), `MmStatusModel` (view-model),
  `ClientEventLog` + Diagnostics panel with Copy (never tickets / passwords),
  resync when no state arrives within 10 s. Screenshots:
  `production/qa/evidence/p1-status/`. CLAUDE.md: commands + architecture.
  Found: the real client adapter never emitted `connection_lost`; the bar now
  reads the transport state itself.

- P3 Champ select (formats from the game-design agent, PROGRESS decisions
  below): hover / declare intent (allies only), hovered hero auto-locks,
  Ranked timeout with nothing hovered = dodge (own ladder 360/1800/7200/14400 s,
  rating 5 then 10), Normal = blind pick 45 s (enemy picks hidden until all
  locked), 20 s finalize window with pick trades, ban phase built in (0 per
  team, capped by roster - 8), ready check 12 s, decline ladder
  60/300/900/1800/3600 s with 24 h tier decay. Protocol 20: OP_HOVER, PICK_STATE
  stage / bans / trade_s, PM_BLIND, SEAT_HOVER / SEAT_BANNING. Draft screen:
  hovers, bans, blind, trade offers (screenshots `production/qa/evidence/p3-select/`).
  Headless simulation `tests/integration/net/matchmaking_sim_test.gd`: 23
  clients, parties, a decline, a ranked dodge, two matches start, 0 illegal
  transitions, ~1.5 s. Bugs found by it and fixed: login + queue in one frame
  left the player stuck as Offline (now via Reconnecting); a draft order
  shorter than the teams left seats without heroes (now auto-filled).

- P2a Server social: protocol 20 ops PARTY_PROMOTE / KICK / READY / CHAT,
  PARTY_JOIN_REQUEST, DM, SET_AWAY and the OP_NOTIFY push (party invite,
  friend request, join request, chat, DM, party changed, kicked); presence
  with 7 states + queue mode from FrontPhases; per-account rate limits
  (chat 5 burst / 1 s, invites 5 / 10 s); stale-invite bug fixed (an invite
  from someone who left stayed valid). `tests/integration/auth/social_flow_test.gd`
  covers leader disconnect, crash + rejoin, stale / duplicate / expired
  invites, simultaneous kick + leave, inviter leaves before accept, blocked
  users, chat sanitising + rate limit, DMs online-only. PRIVACY.md updated.

- P2b Client: `SocialModel` (view-model: DM threads + unread, party chat,
  party invites, join requests, toasts), friends panel with 7 presence states
  (own shape each) + mode, Message / Invite / Ask to join, party-invite and
  join-request groups; `SocialDmWindow`; play screen party with Ready / Leave /
  Lead / Kick and party chat; auto-away after 5 min idle. Found and fixed: the
  play screen never showed the real party online (only the fake's); a party
  was forgotten 60 s into a match because the menu disconnects (sessions of
  players in a match are now kept, max 4 h). Screenshots
  `production/qa/evidence/p2-social/`.

## In progress
- nothing (waiting for the owner).

## Next (prioritised)
1. Phase 3 leftovers: bot difficulty and bot slots in custom lobbies;
   per-player loading progress (needs a match-process report); ability
   preview / team chat in hero select (team chat exists in the old lobby only).
2. Phase 2 leftovers: the separate launcher app's social view still shows
   the W15 states (the game menu has the full set); invite-expiry countdown
   is not shown (invites expire after 120 s server-side).
3. Phase 4: launcher polish (needs human visual checks).

## Manual checks needed (no display in the cloud session)
See `docs/manual-checklist.md` (created with P1d).
