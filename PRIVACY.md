# Cybergram: Privacy Notice

> **Draft. Needs a legal check before public release.** Written in plain
> words for players. Version 3 (game v0.11.0, protocol v15).

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
| Display name, emblem, accent colour, favourite hero | so other players see you in the lobby, the scoreboard and the kill feed |
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

## Legal basis

Art. 6(1)(b) GDPR: we need this data to provide the online game you sign up
for (the contract). Crash reports and Discord Rich Presence are based on your
consent (Art. 6(1)(a) GDPR), see their sections above. You must be **at least 14** to create an account
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

## Server logs

Logs contain no chat text, no usernames, no display names and no passwords.
They contain a short 4-character id tag (for example `account #1A2B`),
connection numbers and game events (joined, ready, match started). The
operator rotates logs, so old log lines are removed after a while.

## Your rights

You have the right to access, correct, delete and take your data with you
(data portability), to restrict or object to processing, and to complain to
a supervisory authority (in Austria: the Datenschutzbehörde, dsb.gv.at).

In the game, under **PROFILE**:

- **Export my data**: the server sends everything it stores about your
  account (without the password hash), and the game saves it as a readable
  JSON file where you choose.
- **Delete account**: needs your password. The account is deleted at once.
  You are also removed from every other player's friends, requests and
  blocks.
- Changing your display name, emblem, colour or favourite hero corrects your
  data. You can change your password there too.

**There is no password recovery.** There is no e-mail, so if you forget your
password, the account cannot be recovered. You can create a new one.

For anything else, contact the operator above.

## Security

Login and all online traffic use encryption (DTLS) when the server has a
certificate. Without a certificate, the server switches accounts off and
only allows guests. A password is never sent unencrypted.
