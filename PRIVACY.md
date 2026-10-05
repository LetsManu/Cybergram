# Cybergram: Privacy Notice

> **Draft. Needs a legal check before public release.** Written in plain
> words for players. Version 2 (game v0.5.0, protocol v12).

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

## Legal basis

Art. 6(1)(b) GDPR: we need this data to provide the online game you sign up
for (the contract). You must be **at least 14** to create an account
(Austria, Art. 8 GDPR and § 4 DSG). You confirm both when you register.

## How long

- Your account is kept until you delete it.
- **Accounts that have not logged in for 365 days are deleted
  automatically.** The server checks this when it starts and once a day.
- Session data, presence and chat: only while you are connected, as
  described above.

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
