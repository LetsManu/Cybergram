# Cybergram: Privacy Notice

Version 1 (protocol v11, game v0.5.0). The game shows a short version of this
notice when you create your profile. You must acknowledge it before you play
online. **Offline play (PLAY VS BOTS, the test course) sends nothing anywhere.**

## Who is responsible (controller)

The **operator of the game server** you connect to is the controller under
the GDPR (Art. 4(7)). For the official server `cyber.djboeck.at`:

> **[OWNER: your name / organisation, postal address, contact e-mail]**

If you run your own server, you are the controller for that server and should
put your own contact details here.

## What is processed, and why

There are **no accounts**: no e-mail address, password or real name. The game
does not track you or use analytics, and it never shows other players' IP
addresses.

| Data | Where it is stored | Sent to the server? | Why |
|---|---|---|---|
| Display name, emblem, accent colour | your computer (`profile.cfg`) | yes, when you play online | so other players can see who is in the lobby or the match and in the kill feed / scoreboard |
| Random player id (+ a private key) | your computer (`profile.cfg`) | yes, when you play online | to tell players with the same name apart, to let friends find you, and to stop someone else from taking your seat (the key) |
| Lobby chat messages | not stored | yes, passed on to the players in the same lobby | lobby chat |
| Friends list (friends' names and ids) | your computer (`friends.cfg`) | only the ids / names you ask about | to show if your friends are online, in a lobby or in a match |
| Mutes, blocks, reports | your computer (`moderation.cfg`) | **no** | to hide a player's chat for you; reports stay on your computer for now |
| Network address (IP) | the server, while connected | technically required | to send game data to you; never shown to players, not logged by the game |

**Legal basis:** Art. 6(1)(b) GDPR (providing the online game you ask for)
and your acknowledgement of this notice; the presence and chat features are
part of that service. You can withdraw by unticking the box in **PROFILE**;
online play is then off, offline play still works.

## How long

- **The server keeps everything in memory only, while you are connected.**
  When you disconnect, it forgets your name, id, status and seat (in the lobby
  your seat is held for 15 seconds so a short drop can reconnect).
- A check-in from the main menu ("online" status for friends) is forgotten
  after 25 seconds.
- **Chat is relayed, not stored.** The lobby keeps the last 20 lines in
  memory so a player who (re)joins sees the context; this buffer is cleared
  when the match starts.
- **Server logs** contain no chat text and no display names, only a short
  4-character id tag (e.g. `player #1A2B`), connection numbers and game
  events. Operators should rotate logs (see `docs/SERVER.md`).
- Data on your computer stays until you delete it.

## Your rights

You have the rights of access, rectification, erasure, restriction, data
portability and objection (Art. 15-21 GDPR), and you may lodge a complaint
with a supervisory authority (in Austria: the Datenschutzbehörde,
www.dsb.gv.at).

In the game, under **PROFILE**:

- **Export my data** writes everything the game stores on your computer to
  `my_cybergram_data.json` in the game's user folder and shows the path.
- **Delete my profile & data** removes your profile, friends list,
  mutes / reports and menu preferences from your computer.
- Changing your name, emblem or colour corrects them.

There is nothing to delete on the server: it forgets you when you disconnect.
For anything else, contact the operator above.

## Where the files are

- Windows: `%APPDATA%\Godot\app_userdata\Cybergram\`
- Linux: `~/.local/share/godot/app_userdata/Cybergram/`
