# Matchmaking phase B: integration notes (W17-MM)

Status: **phase A done** (pure logic, unit tested, not wired). Phase B wires it
into the front, the protocol and the match supervisor once the netcode chunk
(protocol 16) has landed. Design: `design/gdd/matchmaking.md`.

## 1. What phase A delivered (`src/networking/matchmaking/`)

| Class | Role | Owner of state |
|---|---|---|
| `MatchmakingRulesDef` / `MatchQueueDef` | every knob; data `assets/data/net/matchmaking_rules.tres` | data |
| `Matchmaker` | queues, match forming, bot fill, wait estimate, ready-check outcome | front, memory |
| `ReadyCheck` | one accept window | front, per proposal |
| `LockoutTracker` | decline / leaver strikes, escalation, decay | front, memory (`to_dict()` for restarts) |
| `LaneAssigner` | lane preferences to starting lanes | stateless |
| `DraftSession` / `AllRandomSession` | 5v5 draft, 3v3 deal / reroll / bench / swap | front, per match |
| `HeroPool` | hero ids from `ContentDB` | stateless |
| `Glicko2`, `RatingService` | rating math, team results, leaver, void, dodge, medals | stateless + store |
| `RatingStore` / `MemoryRatingStore` / `FileRatingStore` | ratings per account per track | disk |
| `RemakeVote` | early remake vote per team | **match process** |
| `ReportStore`, `ReportReview` | reports, honour, retention, owner CLI | front, disk |

Everything takes time as an argument (`now`: float seconds for queue/pick
logic, `now_unix`: int for persisted data). Phase B passes
`Time.get_unix_time_from_system()` for both.

## 2. Messages (new, protocol 17 or later)

Proposed as a new `MatchmakingCodec` (op byte + fields) under one new pair of
message ids, the same way `ACCOUNT_REQ` / `ACCOUNT_RESULT` work. This avoids
claiming many top-level ids. Phase B picks the ids (next free after 31) and bumps
`PROTOCOL_VERSION`.

| Op | Dir | Fields | Front calls |
|---|---|---|---|
| `QUEUE_JOIN` | C->S | queue id (u8 index into `rules.queues`), lanes (u8 primary, u8 secondary; 0xFF = fill) | leader only; builds the members from `PartyService` and `RatingService.entry()`, then `Matchmaker.enqueue()` |
| `QUEUE_LEAVE` | C->S | — | `Matchmaker.leave(account)` (the whole party leaves) |
| `QUEUE_STATUS` | S->C | u8 state, u16 waited s, u16 estimate s, u16 players in queue, f32 locked_until (0 = none), u8 err | every ~2 s while queued; from `queue_info()` / `estimated_wait_s()`; `err` = `Matchmaker.Err` |
| `MATCH_FOUND` | S->C | match id, u8 deadline s, u8 humans, u8 accepted | on `tick()` proposals, and again on every accept |
| `READY_REPLY` | C->S | match id, u8 accept | `ReadyCheck.accept/decline` |
| `READY_RESULT` | S->C | u8 outcome (go / requeued / removed / locked), f32 locked_until | from `resolve_ready_check()` or `confirm()` |
| `PICK_STATE` | S->C | mode, u8 turn, u8 team, f32 deadline, seats (id, team, lane, hero u16, flags: bot, auto, my turn), 3v3: rerolls left, bench heroes | after every pick-phase change |
| `PICK` | C->S | u16 hero index | `DraftSession.pick()` |
| `ARAM_ACTION` | C->S | u8 action (reroll / take bench / request swap / accept swap), u16 hero or seat index | `AllRandomSession.*` |
| `RANKED_INFO` | S->C | per track: visible rating (i16, -1 = calibrating), games left, medal label key | `RatingService.ranked_display()` on login and after each result |
| `POST_MATCH_REPORT` | C->S | match id, target id, u8 category index | `ReportStore.report()` with the match's participant list |
| `POST_MATCH_HONOUR` | C->S | match id, target id | `ReportStore.honour()` |

The match process gets two in-match messages: `REMAKE_START` and `REMAKE_VOTE`
(C->S), and `REMAKE_STATE` (S->C: yes, needed, deadline, outcome). This can be a
`GameEvent` kind instead of new ids, if the netcode chunk prefers.

## 3. Where the front calls the matchmaker

The front process (today `LobbyServer` + `AccountService`) gains one owner object,
`MatchmakingFront` (phase B, new file). It holds a `Matchmaker`, the open
`ReadyCheck`s and pick sessions per match id, `RatingService(FileRatingStore)`
and `ReportStore`. Its `step(delta)` is called from the same place as
`LobbyServer.step`:

1. Run `matchmaker.tick(now)`. For each proposal, create a
   `ReadyCheck(Matchmaker.human_ids(p), now, rules.ready_check_s)` and send
   `MATCH_FOUND`.
2. Run `ReadyCheck.tick(now)` for each open check:
   - `ACCEPTED`: call `matchmaker.confirm(p)`. Create `DraftSession` (DRAFT), using
     `p.match_id` as the seed and `HeroPool.from_content_db()`, or create
     `AllRandomSession` (ALL_RANDOM).
   - `FAILED`: call `matchmaker.resolve_ready_check(p, rc.failed_ids(), now)` and
     send `READY_RESULT`.
3. Run `tick(now)` on each pick session:
   - `DONE` or `LOCKED`: build the match setup (section 4) and hand it to the
     supervisor.
   - `ABORTED` (dodge = disconnect or leave during picks): call
     `resolve_ready_check(p, [dodger], now)`. In ranked, also call
     `RatingService.apply_dodge_penalty()`.
4. Once a day, together with the crash-report sweep: call
   `ReportStore.purge(now)` and `LockoutTracker.sweep(now)`.

Other hooks:

- **Account deletion cascade** (`AccountStore.delete_cascade` caller): add
  `rating_store.erase_account(id)` and `report_store.erase_account(id)`.
- **Party rules:** `OnlineRulesDef.party_max` is **3** today and must become
  **5**. Only the party leader may queue. A member who joins or leaves calls
  `Matchmaker.leave(leader)` (the design's §5 "friend is in-game" case: refuse
  `QUEUE_JOIN` while any member is in a match).
- **Disconnect while queued:** `Matchmaker.leave(account)` after the existing
  grace period. A disconnect during a ready check is a timeout (no special path).
- **Front restart:** queues and checks are lost. Clients re-queue. Persist
  `LockoutTracker.to_dict()` (optional, needs a PRIVACY.md line) or accept that
  lockouts reset.

## 4. Match setup and results (supervisor channel)

**Setup** (the "Megapacket", front to match process):
`{match_id, queue, map_id, rated, teams: [[{id, lane, hero, bot}]], rules
snapshot (remake_window_s, remake_vote_s, remake_vote_fraction), build}`.
Bots carry `MatchmakingRulesDef.BOT_PREFIX` ids and must be shown labelled.
Each human gets a one-time HMAC join ticket bound to `(account, match_id)`.

**The match process owns** one `RemakeVote` per team, created with
`match_start` = the time the first player spawns. It calls `mark_absent()` for
a seat that has not connected by the start, or that leaves, and
`mark_present()` on reconnect.

**Result** (match process to front, local channel):
`{match_id, winner (0/1), voided, leavers: [ids], duration_s, stats}`.

The front then does:

- `RatingService.apply_result(track, team_a, team_b, winner, now, leavers, voided)`.
  The track is `rules.queue(q).rating_track`. Pass `voided=true` for a remake or
  a match-process crash. Unrated bot matches return `{}` by themselves.
- For each leaver (not on a void): `LockoutTracker.record(id, LEAVE, now)`.
  Decision for the owner: should a leaver who caused a remake also get a strike?
  My recommendation is yes.
- Push `RANKED_INFO` to the ranked players, and open post-match reports and
  honour for this `match_id`. Keep the participant list for as long as reports
  are accepted (suggestion: 10 min).

## 5. Data and privacy (PRIVACY.md entries to add in phase B, when the data is live)

- **Ratings:** for each queue type, a rating number, its uncertainty, the number
  of games and the date of the last change. These are used to find fair games
  and to show your rank. They are kept until the account is deleted. No match
  list and no address is stored.
- **Reports:** who reported whom, in which match, the category and the time. No
  free text and no chat. They are kept for 30 days, then deleted automatically,
  whether reviewed or not.
- **Honour:** a count per account (kept with the account). Who honoured whom in a
  match is kept for 30 days to prevent double honour.
- **Queue lockouts:** strike counts and lockout end times. These are kept in
  memory and reset by a server restart (unless persisted, see section 3).

## 6. Deployment notes

- `tools/server/review_reports.sh` runs from a source checkout (`GODOT` = the
  binary). To use it inside the container, the export must include
  `tools/server/review_reports.gd`, or the tool must become a `--review-reports`
  flag of the server binary (phase B, devops). Reports folder:
  `CYBERGRAM_REPORTS_DIR`, otherwise `reports` next to `CYBERGRAM_DATA_DIR`
  (`/data/reports`). Ratings folder suggestion: `CYBERGRAM_RATINGS_DIR` /
  `/data/ratings`.
- `match_port_first/last` and `max_concurrent_matches` are in the rules def as
  defaults. `CYBERGRAM_MATCH_PORTS` overrides them (supervisor, phase B).

## 7. Open owner decisions

1. Medal names (placeholders: Static, Copper Trace, Circuit, Relay, Overclock,
   Shardbreaker, Prime Signal).
2. 5v5 lane slots: currently North, Center, South, Flex, Flex. This is an
   assumption, because the map design does not fix lanes per player.
3. Leaver rule: the leaver loses the game plus 15 points, and losing teammates
   lose 50 %. Bot matches are unrated (`rate_bot_matches = false`).
4. Remake threshold: 0.8 of the connected teammates, rounded up (in practice
   all of them).
