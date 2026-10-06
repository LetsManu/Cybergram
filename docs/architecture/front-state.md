# Front state machines (P1, protocol 20)

The matchmaking front owns every pre-match state on the server. Three explicit
machines (`src/networking/front/phase_machine.gd`) describe it; `PhaseRegistry`
holds the current state per key, rejects transitions outside the tables and
reports them (log line `illegal_transition`, metric
`cybergram_illegal_transitions_total`). `FrontPhases` derives players and
parties from the authoritative structures (queues, matches, custom lobbies,
parties, connections) after every request and every frame; lobbies move on
explicit calls from `MatchmakingFront`.

## Player

Happy path (matchmade):

```
Offline -> Idle -> (InParty) -> Queued -> ReadyCheck -> ChampSelect -> Loading -> InGame -> PostGame -> Idle | InParty
```

Side transitions:

| From | To | When |
|---|---|---|
| Idle, InParty, PostGame | ChampSelect | joins or opens a custom lobby |
| Queued | Idle, InParty | leaves the queue, or the party changed |
| ReadyCheck | Queued | someone else declined: re-queued with priority |
| ReadyCheck | Idle, InParty | you or a party member declined / timed out (lockout) |
| ChampSelect | Queued | someone else dodged: re-queued |
| ChampSelect | Idle, InParty | you dodged (lockout), or the custom lobby closed |
| Loading, InGame | Queued, Idle, InParty | match voided (no server, crash): re-queued when online |
| PostGame | Queued | queues again within the post-game window |
| Queued, ReadyCheck, ChampSelect, Loading | Reconnecting | menu connection lost while a ticket or seat is held |
| Reconnecting | the state it left, Idle, InParty, Offline | back in time, or the grace ran out |
| any online state | Offline | disconnect without a held ticket or seat |

Exact legal pairs: `PhaseMachine.PLAYER_LEGAL`. Every pair is covered by
`tests/unit/matchmaking/phase_machine_test.gd`.

InGame is derived from the match state: a running match has its own
connection (match process), so a closed menu connection during a match does
not mean Reconnecting.

## Party and lobby

```
Party:  None ─► Idle ◄─► Queued ─► InMatch ─► Idle | Queued      (any ─► None when dissolved)
Lobby:  ReadyCheck ─► ChampSelect ─► Loading ─► Running ─► Ended
             └────────────┴────────────┴──────────┴──► Cancelled   (decline, dodge, void)
```

A custom game's lobby enters at ChampSelect (the custom lobby is its pick phase).

## Versioned state events

`MM_EVENT` op `EV_PHASE` (12) carries the player's state: `epoch` (front start
time), `seq` (grows on every change of that player), `phase`, `prev`, `snap`,
queue, party size and leadership, seconds queued, estimated wait, lockout
seconds left, match id and party id. The client keeps the last event and drops
one with the same epoch and a lower or equal `seq` unless `snap` = 1. After a
reconnect the client sends `OP_STATE_SYNC` (21) and gets a snapshot (`snap` =
1). The first event after coming online is a snapshot too.
