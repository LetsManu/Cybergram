# Matchmaking, queues and ranked (design: owner decisions 2026-10-05)

Status: **Approved direction, not built.** Implementation starts after the
netcode release (protocol 16). Benchmarked against League of Legends and
Dota 2: same pipeline, adapted to a small player base and a 7-hero roster.

## 1. Overview

Players pick a queue, alone or in a party. A central matchmaker groups
players of similar skill. Everyone accepts a ready check, picks heroes, and
is sent with a one-time ticket to a match process from a pool. After the
match, ratings, stats and history update.

## 2. Player fantasy

Press PLAY, find a fair game quickly, climb a visible rank in 5v5, or blow
off steam in chaotic 3v3 all-random games.

## 3. Detailed rules

### Queues

| Queue | Map / size | Picking | Rating | Bots |
|---|---|---|---|---|
| **Normal 5v5** | Shardline Front, 5v5 | Alternating draft, team-unique | Hidden MMR (own track) | Fill empty slots after a wait |
| **Ranked 5v5** | Shardline Front, 5v5 | Alternating draft, team-unique | Visible MMR + medals | Never |
| **3v3 All Random** (fun, "like ARAM") | Slice map, 3v3 | All random, rerolls, team swaps | Hidden MMR (own track), no rank | Fill empty slots after a wait |
| **Custom game** | Any map / size | Host's choice | None | Host's choice |

- **No 3v3 ranked:** 3v3 is the fun mode.
- **Parties:** any size from 1 to 5 in every queue.
  - **Ranked parties:** have a rating-gap limit inside the party.
  - **Balancing:** the matchmaker puts premades of similar size against each other where possible, and balances teams by summed MMR.

### Ready check
- **Accept window:** 12 s (P3, 2026-10-06).
- **Declining or timing out:** a queue lockout of 60 / 300 / 900 / 1800 / 3600 s (one tier drops per 24 h without an offence); everyone else re-queues with priority.
- **Pick-phase dodge:** its own, harsher ladder: 360 / 1800 / 7200 / 14400 s, one tier drops per 24 h. In ranked it also costs 5 rating (10 from the second strike on).

### Lane preference
- **Choice:** each player picks a primary and a secondary lane from North, Center, South and Flex, or picks Fill.
- **Use:** these drive team balance and starting assignments, in the style of LoL's position queue.

### Picking (5v5)
- **Ranked: draft**, alternating 1-2-2-2-2-1, 30 s per turn.
- **Normal: blind pick**, everyone at once in 45 s; enemy picks stay hidden until everyone has locked in.
- **Hover:** selecting a hero declares it to your team; an ally cannot hover or lock a hero a teammate declared. Locking commits.
- **Uniqueness:** heroes are unique within a team; both teams may field the same hero, since the roster is only 7.
- **Timeout:** a hovered hero is locked for you. With nothing hovered: Normal locks a random legal hero; Ranked cancels champ select and counts it as your dodge (others re-queue with priority).
- **Trades:** after the last lock a 20 s window: teammates who both locked may trade heroes (offer + accept within 10 s) during the first 15 s; the last 5 s are the countdown.
- **Bans:** built in, off while the roster is small. Planned 1 per team from 13 heroes, 2 from 18 (total bans never above roster - 8; the server enforces that cap). Both teams ban at once, hidden from the enemy, 25 s; a hovered ban locks at the deadline, no hover = no ban; 4 s reveal.

### 3v3 All Random
- **Heroes:** each player is dealt a random hero (team-unique).
- **Rerolls:** 1–2 per game, with a reroll bench shared by the team.
- **Swaps:** teammates may swap heroes.

### Rating and ranks
- **Ratings:** hidden MMR per queue, with a separate track for normal, ranked and 3v3.
- **Ranked display:** a visible MMR number plus a medal band (Dota style).
- **New players:** calibration games before the number is shown.
- **Rating changes:** on win/loss, scaled by uncertainty, which shrinks with games played.

### Low population
- **Normal and 3v3:** fill empty slots with **labelled bots** after roughly 60–90 s.
- **Ranked:** waits for real players and never uses bots.
- **Search widening:** the allowed skill range widens over time.
- **Queue info:** players see the estimated wait and how many are in queue.

### Fair play
- **Reconnect:** a disconnected player can rejoin their running match.
- **Leaver penalty:** escalating ranked lockouts plus rating loss for repeated abandons.
- **Early remake vote:** if a player never connects or leaves in the first ~3 minutes, the team may end the game with no rating change.
- **Reports and honour after the game:**
  - Reports are stored with a retention limit (GDPR) and reviewed by the owner with a server-side tool.
  - Honour is positive only.

### Server architecture (researched 2026-10-05: LoL and Dota 2)

The model follows League of Legends: a control plane plus disposable match processes.
- **Riot:** the central GSM tells a per-host LSM to spawn one game process per match with a config "Megapacket". Many matches share a host, placed round-robin by CPU.
- **Valve:** the Game Coordinator allocates the server and issues credentials, and Steam Datagram Relay hides server IPs.

What we build:

- **Front process (control plane)** on UDP 7777:
  - holds accounts, friends, parties, queues, the matchmaker, the ready check and the pick phase
  - owns a **match supervisor**
- **One Godot headless process per match:**
  - crash isolation: a script error kills one match, not all of them
  - capacity budget of **2 matches per core** (a 5v5 is about 22 % of a core)
  - a configurable maximum of concurrent matches
  - memory per process to be measured
- **Supervisor lifecycle** (from Agones' ideas, without Kubernetes): `Starting -> Ready -> Allocated -> Draining -> Shutdown`.
  - It keeps a **warm pool of 1-2 Ready processes** and spawns more on demand.
  - Health is checked by heartbeat.
  - A match process crash **voids** the match: no rating change, players are told and re-queued.
- **Match setup:** handed to the process at start (roster, teams, picks, mode, rules), like Riot's Megapacket.
- **Join tickets:** one-time, signed by the front (HMAC), bound to account + match, valid for seconds. This is the Dota GC credential idea and reuses the W15 launch-token pattern. Reconnect issues a fresh ticket to the same running match.
- **Results:** the match reports to the front over a local channel (winner, stats, abandon events), then frees its slot.
- **Patch draining:** every process is tagged with its build version.
  - On deploy, new matches only go to the new build.
  - Running matches finish on the old one.
  - The front refuses clients on old builds.

### Hosting (owner decision)

The owner will move the servers to a **VPS** when public play starts, so the container must be **VPS-ready from day one**:
- **Addresses:** the advertised public address is separate from the bind address (`CYBERGRAM_PUBLIC_HOST`). This works behind NAT, a relay or a WireGuard tunnel, and on a plain VPS.
- **Configuration:** the port range comes from the environment (`CYBERGRAM_MATCH_PORTS=7800-7809`), and everything else is set by env vars or flags. No NAS-specific paths.
- **Operation:** a Docker `HEALTHCHECK`, CPU and memory limits in compose, and graceful SIGTERM (stop allocating, drain running matches).
- **Exposure:** still **one container** that exposes 7777/udp, the match port range/udp and 8080/tcp.
- **Not used:** Agones and Open Match are overkill at this scale. We copy their state model only.

## 4. Formulas

To be fixed in implementation:
- the rating update (Glicko-2-style uncertainty)
- the search-window growth rate
- the party-gap limit
- the lockout escalation steps
- calibration length

All are data-driven in a `MatchmakingRulesDef`.

## 5. Edge cases

To be specified in the implementation brief:
- a party member declines the ready check
- the match process crashes mid-game (no rating change)
- the front restarts
- a player is in a party with a friend who is in-game
- a bot backfills a leaver in normal games

## 6. Dependencies

- Accounts.
- Friends and parties (W15).
- Launch tokens.
- Netcode protocol 16.
- Progression (account level, mastery, match history), which is planned and fed by match results.

## 7. Tuning knobs

All in `MatchmakingRulesDef`:
- timers
- windows
- bot-fill delay
- party-gap limit
- penalties
- calibration games
- port range
- maximum concurrent matches

## 8. Acceptance criteria

To be written with the implementation stories.
