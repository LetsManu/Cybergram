# Cybergram: Privacy Notice

> **Draft. Needs a legal check before public release.** Written in plain
> words for players. Version 7 (2026-10-06, protocol v20: player tags in server logs, operator status page).

**Offline play (PLAY VS BOTS, the test course) sends nothing anywhere.** This
notice is about **online play**.

## Who is responsible (controller)

The operator of the game server you connect to. For the official server
`cyber.djboeck.at`:

> **[CONTACT TO BE FILLED]**

If you run your own server, you are the controller for that server.

## What is stored, and why

**On the server, for each account:**

| Data | Why |
|---|---|
| Username | to log in |
| Password, stored only as a salted hash (PBKDF2-HMAC-SHA256) | to log in; nobody, not even the operator, can read your password |
| Your recovery code, stored only as a salted hash (PBKDF2-HMAC-SHA256), and when it was made | to set a new password if you forget yours; nobody, not even the operator, can read the code |
| Display name, emblem, accent colour, favourite hero | so other players see you in the lobby, the scoreboard and the kill feed |
| Whether you chose to appear on the public leaderboard (off unless you switch it on) | the website's ranked leaderboard (see *Public leaderboard*) |
| A random player id | to tell accounts apart |
| Friends, friend requests, players you blocked | the friends list and blocking |
| Date of sign-up and of your last login | to delete unused accounts (see *How long*) |

That is all. **No e-mail address, no real name, no IP address, no device or
hardware ids** are stored. There is no tracking and no analytics.

**On your computer:** only your hero pick and, if you tick it, your username
("remember username"). No password and no session token is written to disk.

**While you are connected**, the server also keeps in memory your session
(a random token), which lobby or match you are in (shown to your friends as
online / in lobby / in match), and your network address, which is
technically needed to send you game data. All of this is forgotten when you
disconnect. After a short grace period (about a minute), your session can no
longer be resumed.

**After a failed login** (wrong password), the server keeps in memory the
username that was tried, your network address and the time, to stop password
guessing. This is deleted at the latest about 11 minutes later (a 5-minute
window, a 5-minute lock if there were too many failures, then cleanup
within a minute). It is never written to disk or to the logs.

**Guests**, if the server allows them, have no account. The server keeps
their display name, emblem and colour only while they are connected.

**Chat is never stored.** Lobby messages are passed on to the players in the
same lobby. The lobby keeps the last 20 lines in memory so that a player who
joins can read them. They are cleared when the match starts. Chat is never
logged.

**Party chat and direct messages are never stored either.** The server passes
a party chat line to the members of your party, and a direct message to the
friend you wrote to, only while they are online. If they are offline, the
message is refused, not kept. Nothing is written to disk or to the log. People
who blocked you never receive your messages, invites or join requests.

**Your status for friends.** Friends see whether you are online, away, in a
queue, in hero select or in a match, and which mode. "Away" is something you
set; it lasts while you are connected.

**Hero play history (local only).** The game keeps, on your PC only, how many
matches and minutes you played with each hero and when you last played it
(`hero_play_history.cfg` in the game's user folder). The launcher reads this
file on the same PC to show the patch notes for your most played heroes. It is
never sent to any server. Delete the file to reset it.

**Signing in through the launcher.** When you sign in in the launcher and
press Play, the launcher asks the server for a one-time launch code and hands
it to the game (in the game's environment, never on its command line). The
server keeps only a scrambled form (a SHA-256 hash) of the code, linked to
your account, in memory. The code works once and for 60 seconds at most, then
it is deleted. Your password is never passed to the game.

**Server status and ping.** The launcher shows whether the server is online,
how many players are online (a number only) and your ping. To measure the
ping it sends a tiny request over its connection every second while the
launcher window is visible; nothing about it is stored. The message of the
day is set by the operator and contains no data about you.

**Party (online, memory only).** When you invite a friend to a party, or join
one, the server keeps in memory who is in the party, who leads it and open
invites (your player id and display name, as for the friends list), so that
you start in the same lobby. Only your accepted friends can invite you.
Invites expire after 2 minutes. A party is forgotten when you leave it, or
when you have no connection left after the usual grace period of about a
minute. Nothing about parties is written to disk.

## Ratings, match history, lockouts and reports (online matchmaking)

**Purpose:** fair games, and fair play. **Legal basis:** our legitimate
interest in fair matchmaking and a fair community, Art. 6(1)(f) GDPR
(together with the contract, Art. 6(1)(b)). You can object at any time
(see *Your rights*); then we delete the data below, or you delete your
account. None of it contains your IP address, chat or free text.

- **Ratings (per queue).** For each queue you played (for example ranked 5v5,
  normal), the server stores a rating number, its uncertainty, the number of
  games and the date of the last change, with your player id. It is used to put
  you in an even match and to show your rank. **Kept as long as the account
  exists, and deleted with it.** Matches with bots are not rated. Guests (no account) cannot play ranked and
  no rating is ever stored for them.
- **Match history (minimal).** For each finished match: a match id, the
  heroes played, the result (win, loss, void) and the duration, linked to
  your player id. No chat, no positions, no address.
  It is used for your match list, for the rating and to settle disputes.
  **Kept for 180 days, then deleted automatically** (checked at start and
  daily), or earlier with the account.
- **Lockouts and leaver strikes.** If you decline a found match or leave a
  match early, the server counts a strike and may keep you out of the queue for
  a short time. It stores the strike count, its type and the lockout end. Purpose:
  fair play (a missing player spoils the game for nine others). Strikes
  **decay by themselves** (declines after 6 hours, leaver strikes after 7 days
  without a new one) and are deleted on decay, **at the latest 30 days** after
  the last strike, or with the account.
- **Reports and honour.** After a match you can report a player (a category from
  a fixed list, never free text) or honour a player. The server stores who
  reported or honoured whom, in which match, the category and the time. **Reports
  and the who-honoured-whom records are deleted after 30 days**, reviewed or
  not. The operator reviews reports by hand; there are no automatic bans from
  reports. Your honour **count** (a number on your account) is kept with the
  account. The reported player is not told who reported them.
- **Matches.** While a match runs, its roster (player ids and heroes) is held
  by the match process in memory and passed over a local, authenticated
  channel. A one-time join ticket, bound to your account and that match, lets
  you in; it is valid for seconds. Nothing of this is kept after the match
  except the history above.

**Account deletion removes all of it:** your ratings, match history, strikes
and lockouts, the reports you filed, and your honour count are deleted together
with the account, at once. Reports *about* you and honour records that name you
are deleted at the latest after their 30 days (or earlier on request to the
operator).

## Crash reports (only if you agree)

**Purpose:** find and fix crashes. **Legal basis:** your consent,
Art. 6(1)(a) GDPR.

- When the game crashes, the launcher asks "Send crash report?". Nothing is
  sent unless you click **Send**, or you chose "Send automatically" in the
  launcher's Settings > Privacy (off by default). You can change this at any
  time; withdrawing consent stops future reports.
- **What is sent:** the game's and launcher's log files (the last part) and
  basic system information (operating system and version, processor, number
  of cores, memory, graphics card and driver, language, game and launcher
  version, the exit code). Before sending, the launcher removes passwords,
  session and launch codes, IP addresses, player and account ids, e-mail
  addresses and your home folder path. No user name, computer name or device
  id is included.
- **How:** only over the encrypted (DTLS) connection to the game server.
  Without encryption the launcher does not send it.
- **Stored:** as one file on the server, without your IP address, account or
  player id. To stop abuse the server counts reports per network address
  (3 per hour) and per account (5 per day) **in memory only**; these counts
  are forgotten after one day at the latest.
- **How long:** deleted automatically after **30 days**. The server also
  keeps the folder small (the oldest reports go first).
- **Deletion before that:** because a report carries no name or id, we can
  only find yours if you tell us roughly when it was sent (date and time) and
  your operating system. Contact the operator above and we will delete the
  matching report(s).

**Diagnostics zip (local only).** Settings > Support in the launcher can
create a zip file with the same logs (passwords and codes removed) and system
information in your Downloads folder. It is created only when you click and
is never uploaded; you decide whether to share it.

## Discord Rich Presence (only if you switch it on)

Off by default. If you switch it on in the launcher (Settings > Privacy), the
game tells the Discord app running on your own computer what you are doing,
and Discord shows it on your Discord profile: "In launcher", "In lobby" or
"In match" with the game mode. Your Cybergram name, ids and the server
address are never shared. The game talks only to the local Discord app; what
Discord does with this is covered by Discord's own privacy policy. Switch it
off at any time; the status disappears when the game closes. If Discord is
not running, nothing happens.

## Public leaderboard on the website (only if you switch it on)

Off by default. In the game, under **RANKS** (the matchmaking ranks panel),
you can switch on **Show me on the public leaderboard**. Then the Cybergram
website lists your **display name, your ranked medal (Iron to Master) and
your visible ranked rating** among the best ranked players, once you have
finished your calibration games. Nothing else about you is published: no
username, no player id, no match history, no IP address.

- The setting is stored with your account (one yes/no value) and you can
  switch it off at any time. The website stops showing you within about a
  minute (the leaderboard is rebuilt every 60 seconds).
- Deleting your account deletes the setting with it, and you leave the
  leaderboard at the next rebuild.
- Guests cannot appear on the leaderboard.
- The leaderboard is public: anyone can see it while you are on it.

**Public server status.** The game server also publishes, for the website,
anonymous numbers only: whether the server is up, how many players are
online, how many matches run, how many players wait in each queue and the
estimated wait. These numbers say nothing about any single person. The
same file (with the opt-in leaderboard) is also served read-only next to the
launcher update feed. The website's own privacy page (no cookies, no trackers, its server logs) is
part of the website.

## Legal basis

Art. 6(1)(b) GDPR: we need this data to provide the online game you sign up
for (the contract). Crash reports, Discord Rich Presence and the public
leaderboard are based on your consent (Art. 6(1)(a) GDPR), see their
sections above; you can withdraw it at any time by switching them off. You must be **at least 14** to create an account
(Austria, Art. 8 GDPR and § 4 DSG). You confirm both when you register.

## How long

- Your account is kept until you delete it.
- **Accounts that have not logged in for 365 days are deleted
  automatically.** The server checks this when it starts and once a day.
- Session data, presence and chat: only while you are connected, as
  described above.
- Launch codes: 60 seconds at most, or until used. Parties and invites: while
  you are connected (invites 2 minutes).
- Crash reports: 30 days, then deleted automatically.
- Ratings: while the account exists. Match history: 180 days. Strikes and
  lockouts: until they decay, 30 days at the latest. Reports and honour
  records: 30 days. All of it is deleted with the account.
- Public leaderboard setting: while the account exists, or until you switch
  it off. The published entry disappears within about a minute after that.

## Server logs

Logs contain no chat text, no usernames, no display names and no passwords.
They contain a short 4-character id tag (for example `account #1A2B`) or, on
the matchmaking server, a 10-character player tag that is a salted one-way
hash of your account id (it cannot be turned back into your id), connection
numbers, random party, lobby and match ids, and game events (joined, queued,
ready, match started). The operator rotates logs, so old log lines are removed
after a while.

The server also keeps the last 200 of these events in memory for its
operator's status page (`/admin`, protected by a password). It shows the same
tags, never names, and is lost when the server restarts. The monitoring
numbers (`/metrics`) are counts only (players queued, matches running).

## Your rights

You have the right to access, correct, delete and take your data with you
(data portability), to restrict or object to processing, and to complain to
a supervisory authority (in Austria: the Datenschutzbehörde, dsb.gv.at).

In the game, under **PROFILE**:

- **Export my data**: the server sends everything it stores about your
  account, including ratings and match history (without the password hash
  and without the recovery code hash; it only says whether you have a code
  and since when), and the game saves it as a readable
  JSON file where you choose.
- **Delete account**: needs your password. The account is deleted at once.
  You are also removed from every other player's friends, requests and
  blocks. Your ratings, match history, strikes, filed reports, honour count
  and your public leaderboard setting are deleted too.
- Under **RANKS**, switch **Show me on the public leaderboard** on or off.
- Changing your display name, emblem, colour or favourite hero corrects your
  data. You can change your password there too, and make a **new recovery
  code** (needs your password; the old code stops working).

**Forgotten password: the recovery code.** There is no e-mail. When you create
an account, the game shows you a one-time **recovery code** once; write it
down. With your username and that code, **Forgot password?** (game or
launcher) lets you set a new password. The code then stops working, you get a
new one (again shown once), and every other device you were signed in on is
signed out. Tries are limited like logins. If you lost the code too, ask the
server operator: they can reset your password and give you a fresh code; your
old password then stops working. The operator never sees your password or a
code you made yourself.

For anything else, contact the operator above.

## Security

Login and all online traffic use encryption (DTLS) when the server has a
certificate. Without a certificate, the server switches accounts off and
only allows guests. A password is never sent unencrypted.
