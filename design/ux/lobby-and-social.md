# Lobby and Social — UX decisions (Wave 9, chunk L1)

Status: implemented in v0.5.0 (protocol v11). Owner: L1 (lobby/social).
Scope: player profile, the full pre-match lobby, lobby chat, friends and
presence. One dedicated server and no accounts, so everything that a live
service keeps in a backend lives either in the client's `user://` files or in
the server's memory.

## 1. Reference: how the big four do it

| Area | League of Legends | Dota 2 | Apex Legends | Valorant | What we take |
|---|---|---|---|---|---|
| Identity | Riot ID `Name#TAG`; summoner icon + border | Steam name + avatar | EA/platform name, banner | Riot ID `Name#TAG`, player card | **Riot-ID style**: free name + a 4-char tag derived from a stable id, an emblem and an accent colour |
| Client home | Big PLAY button, social panel docked on the right at all times | Dashboard, friends column on the right | Lobby with your squad visible | Home with party panel on the left | A **compact friends panel docked right** on the main menu and in the lobby |
| Pre-game | Champ select: two team columns, portraits, lock-in, a short final countdown | All Pick: hero grid, timers | Legend select in turn order | Agent select: two columns, Lock In, countdown | **Two team columns**, hero badges per slot, Ready = **Lock In** (pick frozen), countdown, final 2 s fully locked |
| Custom games | Free team switch when the other side has room | Lobby slots, drag to a team | — | Custom: team switch | **Player-chosen team switch** when the other side has a free slot (waiting phase only) |
| Chat | Lobby chat with system lines (joined / left / locked in) | Lobby chat | Squad text + pings | Team/party chat | One lobby chat, server-sanitised, rate-limited, with **localised system lines** |
| Friends | Add by Riot ID; online / in champ select / in game / away; "Join" / "Invite" | Steam friends, "Join game" | Platform friends, "Join party" | Add by Riot ID, party join | Add by name (or `Name#TAG`); statuses **online / in lobby / in match / offline**; **Join** |
| Parties | Party queues together, same team | Party | Squad | Party | **Party-lite**: "Join" asks the server to seat you on your friend's team when it has room |

## 2. Decisions

### 2.1 Profile (`src/core/profile/player_profile.gd`, `user://profile.cfg`)

- **Name**: 3-16 characters from `A-Z a-z 0-9 _ - .` and single inner spaces;
  no leading/trailing space. ASCII only: every glyph is in the UI font, the
  wire size is bounded (≤ 16 bytes) and there are no look-alike names. The
  server re-validates every name it receives (never trusts the client).
- **Id**: 16 random bytes generated once (hex string, "UUID-ish").
  **Tag** = first 4 hex digits, upper case, shown as `Name#1A2B` (Riot ID).
  Two players may share a name; the tag tells them apart.
- **Key**: a second 16 random bytes that never leave the client except to the
  server. While an id is connected (or its lobby seat is in the reconnect
  grace), the server refuses a join that claims it with another key — nobody
  can steal a seat by copying a friend's (public) id. The claim is forgotten
  on disconnect (§4).
- **Emblem**: one of 12 code-drawn emblems; **accent colour**: one of 10
  presets (indices on the wire, validated on the server). Presets rather than
  a free colour picker keep every combination readable on the dark panels.
- **First launch** shows the profile screen before anything else (LoL/Valorant
  make you pick a name before the client opens). A test run with
  `--auto-ready` gets a generated valid profile so automation never blocks.
- Editable any time from **PROFILE** on the main menu.

### 2.2 Lobby (`LobbyServer`, `LobbyScreen`)

- **Seating**: a joiner goes to the smaller team (ties: Concord), or to their
  friend's team when they came through **Join friend** and it has room.
- **Team switch**: SWITCH TEAM button under each column header while the
  phase is *waiting* and the other side has fewer than `team_size` players.
  Switching un-readies you (LoL custom games behave the same).
- **Hero picker**: built from ContentDB (every `assets/data/heroes/hero_*.tres`),
  sorted by display name; label = `tr("HUD_HERO_NAME_<STEM>")` when the key
  exists, else `HeroDef.display_name`. New heroes appear with no code change.
  Each slot shows a code-drawn **hero badge** (hex in the hero's signature
  colour with initials).
- **Ready = Lock In**: while ready the hero cannot change (the server ignores
  hero changes from a ready player; the picker greys out).
- **Countdown**: 5 s once everyone is ready. Un-readying cancels it, except in
  the **final 2 s (LOCKED)**, where nobody can un-ready and the line turns
  gold — the Valorant/LoL "picks are final" beat. A leaver during LOCKED does
  not cancel the start.
- **Reconnect-safe**: a player who drops keeps their slot (team + hero) for
  15 s, shown as *reconnecting*; rejoining with the same id + key restores it
  (the client retries on its own). A disconnected slot does not block the
  countdown. A second connection with the same id + key replaces the first.
- **Leave**: LEAVE LOBBY closes the connection; the seat is held for the
  reconnect grace, but a disconnected seat never blocks the countdown and is
  dropped when the match starts.
- **Handover**: unchanged slot-token flow; the token now also maps to the
  player's name on the match server (§2.5).

### 2.3 Chat

- Max 120 characters (and 240 UTF-8 bytes); the server strips control
  characters, bidi overrides and zero-width characters, collapses whitespace
  and drops empty results. Shown in a plain `Label`/`RichTextLabel` with
  BBCode **off**, so no markup injection.
- **Rate limit**: token bucket, 4 messages burst, 1 new message every 1.5 s;
  an over-limit message is dropped and only the sender gets a "slow down"
  system line.
- The server keeps the last 20 lines **in memory** and sends them to a joiner
  (reconnects keep context); the buffer is cleared when the match starts.
- **System lines** (joined, left, reconnecting, switched team, locked in) are
  sent as codes + a name and composed client-side with `tr()`, so they are
  localisable.

### 2.4 Friends and presence

- Friends are stored locally (`user://friends.cfg`): name, and the id once
  seen. Add by `Name` or `Name#TAG`; it resolves when the server (or the
  lobby roster) has seen exactly one matching player, or the tag matches.
- The server keeps a presence table **in memory, for connected players
  only** (§4): id, key, name, status. **Online** = the client's main menu
  checked in within the last 25 s; **In lobby** / **In match** are set by the
  lobby and the match server; anything else (including unknown) is
  **Offline**. An entry is forgotten on disconnect.
- The main menu polls every 10 s with a short-lived connection
  (connect → PRESENCE_QUERY → PRESENCE → close) so it never holds one of the
  server's client slots. In the lobby the query rides the lobby connection.
- **Join friend** (friend in lobby or match) opens the server's lobby with a
  party request: you are seated on the friend's team if it has room; during a
  match you join the match (bot takeover, as any late joiner).
- Panel: a compact column docked right (LoL client), status dot + text,
  sorted online-first, with Join and Remove per row and an add field on top.
  In the lobby, every other player's row has a **+** to add them as a friend.

### 2.5 Match

- The lobby sends each player's validated name with its slot token to the
  match server (`ServerSession.token_names`). When the player's Hello is
  accepted, the server broadcasts a PLAYER_NAMES table (net id → name);
  clients feed it to the HUD roster, so the **scoreboard and kill feed show
  player names** online. Late joiners get a token too, so they are named.
- Names above heroes are left to the views owner (G1 wave owns
  `src/gameplay/views/*`); the data is on `ClientSession.player_names`.

## 4. Privacy / GDPR (owner requirement, 2026-10-04)

The owner is in Austria (EU); the full notice is `PRIVACY.md` (repo root).

1. **Data minimisation.** No e-mail, password, real name, IP display,
   analytics or tracking. The profile is name + emblem + colour + random id
   (+ a private key that only goes to the server, to protect a seat), stored
   only in `user://profile.cfg`. No server accounts.
2. **Notice + acknowledgement.** The profile screen shows a short notice (what
   is sent: name, emblem, colour, player id, chat; why; how long) and an
   acknowledgement checkbox, versioned (`PlayerProfile.PRIVACY_VERSION`, saved
   in `profile.cfg`). PLAY ONLINE, Join friend and the menu's presence
   check-ins need it; otherwise the profile screen opens first with the
   notice highlighted. Offline play needs nothing. Unticking withdraws it.
   Automated `--auto-ready` runs create a generated profile with the notice
   acknowledged (the tester is the user).
3. **Server retention.** `PresenceRegistry` and the lobby seats live in memory
   only and are connection-scoped: forgotten on disconnect (lobby seat after the
   15 s reconnect grace, menu check-ins after 25 s, match players on leave and
   at match end). Chat is relayed; the 20-line replay buffer is per lobby and
   cleared at match start. **Logs** contain no chat text and no display names,
   only `player #TAG` (the 4-hex id tag), peer numbers and game events. Log
   rotation is still recommended (`docs/SERVER.md`, compose `logging:`).
4. **Friends list** is local only (names + ids on the player's machine). The
   server answers presence only for the ids/names the client asks about, from
   what it holds for currently connected players.
5. **Rights.** Profile screen: **Export my data** (`LocalData.export_json` →
   `user://my_cybergram_data.json`, readable JSON, path shown) and
   **Delete my profile & data** (two presses; removes profile, friends,
   moderation, menu prefs and an earlier export; back to first launch).
   Server-side data vanishes on disconnect, so there is nothing to delete
   there.
6. **Chat safety.** 120 chars / 240 bytes, 4-burst + 1 per 1.5 s rate limit,
   control / bidi / zero-width characters stripped on the server; per-player
   **Mute** (by id, local) and a **Report** stub that only records locally
   (`user://moderation.cfg`). Offensive / impersonating names are refused by
   a data list (`assets/data/social/name_filter.tres`, `NameFilterDef`) on
   the client (hint) and the server (authoritative).

## 5. Not doing (yet)

Invites/notifications, blocking/muting, persistent server-side accounts,
whispers, party chat, a hero grid with portraits (badges until hero art
exists), drag-and-drop seating.
