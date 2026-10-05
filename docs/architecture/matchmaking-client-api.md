# Matchmaking client API (protocol 17)

Story: W17B-SRV. The UI (game menu or launcher) talks to matchmaking only
through `MatchmakingClient` (`src/networking/client/matchmaking_client.gd`,
synced to `launcher/src/shared/`). The wire format is `MatchmakingCodec`
(`MM_REQ` = 32 C->S, `MM_EVENT` = 33 S->C). The server decides everything;
the client only displays it.

## Where the instance lives

| Connection | Instance | Used for |
|---|---|---|
| Front (UDP 7777, after login) | `LobbyClient.matchmaking` | queues, ready check, picks, match assignment, ratings, lockouts, reports, honour, custom games, rejoin |
| Match process (join ticket) | `ClientSession.matchmaking` (`client.session.matchmaking`) | remake vote (`remake_vote`, `remake_prompt`) |

`LobbyClient.step()` and `ClientSession.poll()` already feed every `MM_EVENT`
packet to `handle()`. Create `LobbyClient.new(transport, host)` with the front's
address so a match ticket without a host resolves to it.

## Requests

| Method | Notes |
|---|---|
| `queue_join(queue, lanes)` | Party leader only. `queue`: `&"normal_5v5"`, `&"ranked_5v5"`, `&"all_random_3v3"` (or the index). `lanes`: `[primary, secondary]` of `&"north" &"center" &"south" &"flex"`, or `[&"fill"]`. Ranked needs an account (guests get `E_GUEST`). |
| `queue_leave()` | The whole party leaves. |
| `ready_accept()` / `ready_decline()` | Within the ready-check window (10 s). |
| `draft_pick(hero)` | 5v5 draft, ContentDB HERO index. Only on your turn; team-unique. |
| `aram_reroll()`, `aram_take_bench(hero)`, `aram_swap_request(seat)`, `aram_swap_accept(seat)` | 3v3 All Random. `seat` = index in the state's `seats`. |
| `remake_vote(yes)` | In match. The first yes starts the vote; needs an absent teammate and the first ~3 min. |
| `report(target_id, category, match_id = "")`, `honour(target_id, match_id = "")` | After a match; `match_id` defaults to the last `match_result`. `category` = index into `report_categories` (cheating, griefing, abusive_chat, afk, offensive_name). |
| `request_ranked_info()` | Answered with `rating_update` (also pushed after login and every result). |
| `rejoin()` | Reconnect after a crash or disconnect: a fresh ticket to the running match (`match_assigned`), or `request_failed(OP_REJOIN, E_NOT_FOUND)`. |
| `custom_create(map, mode, bots, team_size)` | `map` index into `MatchmakingCodec.CUSTOM_MAPS` (`shardline_front`, `slice`); `mode` `PM_CUSTOM` (free pick) or `PM_ALL_RANDOM`. |
| `custom_invite(friend_id = "")` | "" invites the whole party. Invitees see `custom_state` and join with `custom_join(host_id)`. |
| `custom_join(host_id)`, `custom_leave()`, `custom_team(team)`, `custom_pick(hero)`, `custom_start()` | `custom_start` is host only. |

## Signals

| Signal | Payload |
|---|---|
| `queue_status(est_s, in_queue)` | Short form. `queue_detail(status)` has everything: `{state (QS_*), queue, waited, estimate, players, locked, code}`. |
| `ready_check(deadline)` | Local seconds (`clock()`); details in `last_ready`: `{match, queue, humans, accepted, you_accepted}`. Re-sent as others accept. |
| `ready_result(result)` | `{outcome: RR_GO / RR_REQUEUED / RR_REMOVED / RR_LOCKED / RR_VOIDED, locked}`. |
| `draft_state(state)` / `aram_state(state)` | `{mode, turn, turn_team, seconds, deadline, you, seats, rerolls, bench, swap_from}`. Seat: `{id, team, lane (byte, see LANES), hero, flags (SEAT_BOT/AUTO/PICKING/YOU/PICKED), name}`. Enemy seats have no id and no name. |
| `match_assigned(host, port, ticket)` | Start the game client: `--connect host:port --ticket <ticket>` (or set `ClientSession.ticket` before `connect_to_server()`). `last_assigned` also has `match`, `team`, `hero`. |
| `rating_update(info)` | `{tracks: [{track, track_id, rating (-1 = calibrating), games_left, band (medal index, 255 none), division}]}`. Medal names: `MatchmakingRulesDef.medal_bands`, Iron to Master. |
| `lockout(info)` | `{seconds, until, ranked, reason (LK_DECLINE / LK_LEAVE)}`. |
| `remake_prompt(info)` | `{state (RV_*), yes, needed, seconds, deadline, team}`. |
| `match_result(result)` | `{match, queue, won, voided, duration, rated, delta (rating points), players: [{id, team, hero, flags, kills, deaths, assists, name}]}`. Bots have flag `MEM_BOT` and a zero id. |
| `custom_state(state)` | `{host, phase (CP_*), map, mode, bots, team_size, members}`. |
| `request_failed(op, code)` | `code` = `MatchmakingCodec.E_*`; show a localised message per code. |

## Mood seed

`ClientSession.mood_seed` (u32, from Welcome) is the same for every client in a
match. The ambience views read it after `welcomed`.
