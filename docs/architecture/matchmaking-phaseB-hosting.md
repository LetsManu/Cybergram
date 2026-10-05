# Phase B hook: match hosting (W17-SUP)

Phase A (W17-SUP) built the self-contained parts: the hosting code is in
`src/networking/hosting/`, and the container work is in `tools/server/`. None of
it is called by the game yet. This page lists what phase B has to wire.

## Pieces

| Class | Role |
|---|---|
| `MatchSupervisor` | Runs in the front. Spawns, watches and drains match processes. Front API: `request_match`, `issue_join_ticket`, `begin_drain`, `set_build`, `is_current_build`, `status`, `tick(now)`, plus signals `match_started`, `match_result`, `match_voided`, `abandon_reported`, `drained`. |
| `MatchHostAgent` | Runs in the match process: the Ready message, the heartbeat, the result report, join ticket checks. |
| `HostingConfig` | The env vars, documented in `docs/HOSTING.md`. |
| `JoinTicket`, `JoinTicketVerifier`, `TicketKeyRing` | One-time HMAC tickets, bound to an account and a match. |
| `MatchSetup` | Validates the match setup dictionary (roster, teams, picks, mode, map, rules). |
| `HostChannelCodec`, `HostChannelUdp` | The authenticated loopback channel. |
| `MatchHostFiles` | Owner-only boot and setup files, deleted on read. |
| `MatchProcessLauncher` | `OS.create_process` and the pid watch. Injectable. |
| `match_host_stub.gd` | An agent-only stand-in process, used for proofs and dry runs. |

## Front side (lobby_server / app_root)

```gdscript
var cfg := HostingConfig.from_env()
var chan := HostChannelUdp.new(); chan.open_server(0)
var files := MatchHostFiles.new(); files.prepare()
var sup := MatchSupervisor.new(cfg, MatchProcessLauncher.new(), chan, files, TicketKeyRing.from_env())
# every frame: sup.tick(Time.get_ticks_msec() / 1000.0)
# pick phase done:   sup.request_match({match_id = JoinTicket.new_match_id(), mode, map, rules, roster})
# match_started(id, ep): per player: sup.issue_join_ticket(id, account, unix_now)
#                        -> send {host or the address the client used, port, ticket}
# reconnect:         issue_join_ticket again (a fresh ticket to the same match)
# match_result:      rating, progression, match history (with a retention period and a PRIVACY.md entry)
# match_voided:      tell the players, re-queue them, no rating change
# abandon_reported:  leaver penalty input
# drained:           get_tree().quit()
```

- `--front` has to be added to `LaunchConfig`. The entrypoint already passes it
  in front mode.
- The default launcher runs this same binary with `--headless`. Supervised
  processes get `--server --port N --host-boot <file>`.
- An empty `endpoint.host` means "use the address the client used to reach the
  front".

## Match side (game_session / server_session)

```gdscript
var agent := MatchHostAgent.from_cmdline(OS.get_cmdline_user_args())
if agent != null:                     # started by a supervisor
    # listen on agent.port(), no pre-match lobby
    agent.allocated.connect(func(setup): start_match(setup))  # roster/teams/picks
    agent.mark_ready()
# every frame: agent.tick(Time.get_ticks_msec() / 1000.0)
# client HELLO carries the ticket: agent.verify_ticket(t, Time.get_unix_time_from_system())
#   -> {result == OK, account}; reject anything else (and unknown accounts)
# leaver: agent.report_abandon(account)
# end:    agent.report_result(winner_team, [{account, team, kills, deaths, assists, ...}], abandons)
#         or agent.report_void("reason")
# agent.drain_requested: optional "server restarts after this match" notice
# exit when agent.should_exit(): agent.close(); get_tree().quit()
```

The join ticket must go into the client hello, which means a protocol bump.
That is owned by the netcode chunk.

## Design notes and deviations

- **Two-step setup.** The design says the match setup is handed over "at
  start". Warm-pool processes start before their match exists, so:
  - a process gets a **boot file** at spawn (port, channel secret, build, ticket key);
  - it gets the **match setup file** when allocated (ALLOCATE names the file).
  - Both files are owner-only (0600 in a 0700 directory) and deleted after
    reading. Secrets never go on a command line.
- **Ticket keys.** The process gets the key of the key id that was active at
  spawn, and the front signs tickets for that match with the same key id. An old
  key can therefore be removed once its processes have ended.
- **SIGTERM.** Godot 4.7 exits at once on SIGTERM. The front-mode entrypoint
  catches the signal and touches `CYBERGRAM_DRAIN_FILE`, which the supervisor
  polls.
- **Data-driven defaults.** The defaults sit in `HostingConfig` (env
  overridable) until `MatchmakingRulesDef` exists. Then they move there.
