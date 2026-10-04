# Running a Cybergram dedicated server

The server is the normal game binary started headless with `--server --port`.
It runs the 3v3 slice match. Bots fill every slot no player has taken, and
players connect from the main menu (**Join**) or with `--connect`.

> **Status: online test build (v0.4.0).** Lag compensation is in (shots are
> judged at what you saw, up to 200 ms back). No anti-cheat yet: good for
> testing with friends, not for public servers.

### How a session works (lobby → match → lobby)

1. **Lobby.** Players press **PLAY ONLINE** in the main menu. The server puts them on
   Concord / Syndicate by join order (one each side, then the next pair).
   Everyone picks a hero and presses **READY**.
2. **Countdown.** When every player in the lobby is ready, a 5 s countdown
   runs. Un-readying stops it.
3. **Match.** The server builds the 3v3 match. Players get their team and
   hero, and **bots fill every other slot**.
4. **After the match.** The result shows for 15 s. Then the server opens a
   fresh lobby, and the players' games return to it automatically.

Late joiners during a match skip the lobby and take over a bot on the team
with fewer humans. A player who leaves is replaced by a bot. The server log
narrates all of it (`[lobby] ...`, `[bots] ...`, `[server] player joined ...`).
Use `--no-lobby` for the old behaviour (match starts at once, players drop in).

Players reach it with **PLAY ONLINE** (see *Connecting*).

## Requirements

- **x86_64 Linux** (VPS, or a NAS that runs x86_64 Docker containers). ARM
  NAS models (most cheap Synology/QNAP units) cannot run it yet.
- **UDP port 7777** reachable from the players (open it in the firewall, and
  forward it on the router for a home NAS).
- About **1 CPU core and 300 MB RAM** for a 3v3 match with bots.

## Option A: VPS with systemd

```bash
# 1. Download the Linux package from the GitHub release and unpack it
sudo useradd --system --create-home cybergram
sudo mkdir -p /opt/cybergram
sudo tar -xzf Cybergram-v0.2.0-linux-x86_64.tar.gz -C /opt/cybergram

# 2. Try it in the foreground first (Ctrl+C to stop)
/opt/cybergram/Cybergram.x86_64 --headless -- --server --port 7777
#   -> "[server] online: listening on UDP 7777 (max 8 clients)"

# 3. Run it as a service (restarts on failure and at boot)
sudo cp tools/server/cybergram-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cybergram-server
journalctl -u cybergram-server -f          # live log

# 4. Open the port (ufw example)
sudo ufw allow 7777/udp
```

## Option B: NAS or any host with Docker (easiest)

Every release publishes a ready server image. No download or unpacking needed:

```bash
docker run -d --name cybergram --restart unless-stopped \
  -p 7777:7777/udp ghcr.io/letsmanu/cybergram-server:latest
docker logs -f cybergram          # "[lobby] open on UDP 7777 ..."
```

Or with compose: `docker compose -f tools/server/docker-compose.yml up -d`.

**Synology:**
1. Open **Container Manager → Registry → Add**, and add
   `ghcr.io/letsmanu/cybergram-server`.
2. Download the `latest` tag.
3. Create a container from it. Map **UDP 7777 → 7777** and enable
   auto-restart.
4. Forward **UDP 7777** on your router to the NAS.

**Updating:** pull `latest` again and recreate the container. Players need
the same game version as the server.

**Note:** if pulling says *denied* / *unauthorized*, the package is still
private. On GitHub, open the repo's **Packages → cybergram-server → Package
settings** and set the visibility to **Public**. Alternatively, run
`docker login ghcr.io` on the NAS with a personal access token that has
`read:packages`.

Requires an **x86_64** NAS (Intel/AMD CPU). ARM models cannot run it.

## Connecting

Players just press **PLAY ONLINE** in the main menu. The game knows the
official server, **`cyber.djboeck.at:7777`**, which is set in
`assets/data/app/app_config.tres` (`online_server`).

For that to work:
1. **DNS:** an `A` record `cyber.djboeck.at` → the server's public IPv4.
2. **Server:** runs v0.4.0 on UDP 7777 (see above), with the port open in the
   firewall / forwarded on the router.

For testing another server without a rebuild:
`Cybergram.exe -- --open-lobby 203.0.113.5:7777` (or `--connect host:port`
to skip the lobby).

## Server options

| Flag | Meaning |
|---|---|
| `--port 7777` | UDP port to listen on |
| `--max-clients 8` | most players at once (1-32) |
| `--bot-difficulty easy\|normal\|hard` | bot skill |
| `--hero brannoc` | hero for players whose client sends no pick |
| `--match-clock 2` | run the match clock 2× faster (shorter test matches) |

## Logs

- **Server:** everything goes to the container log (Portainer: *Containers →
  cybergram → Logs*, or `docker logs -t cybergram`). The lobby narrates
  joins, hero picks, Ready, countdown and match start; the match logs
  players joining and leaving, and a status line every 5 s. A crash prints
  Godot's crash message and backtrace there too.
- **Game (Windows):** `%APPDATA%\Godot\app_userdata\Cybergram\logs\godot.log`
  (Linux: `~/.local/share/godot/app_userdata/Cybergram/logs/godot.log`).
  The last 5 sessions are kept. Send both logs when something fails.

## Troubleshooting

| Symptom | Check |
|---|---|
| "no answer from …" | The server is running (`journalctl` / `docker logs`). UDP 7777 is open in the VPS firewall *and* the provider's panel. For a home NAS, the router forwards UDP 7777. |
| "server rejected the connection (version mismatch?)" | Client and server must be the same release. |
| "cannot listen on UDP port 7777" | Another process uses the port, or pick another with `--port`. |
| Game is choppy online | Expected on long distances for now. There is no lag compensation yet. |
