# Running a Cybergram dedicated server

The server is the normal game binary started headless with `--server --port`.
It runs the 3v3 slice match. Bots fill every slot no player has taken, and
players connect from the main menu (**Join**) or with `--connect`.

> **Status: first online test (v0.2.0).** It works over the internet, but
> there is no lag compensation or anti-cheat yet. Every player joins the
> Concord team (bots keep one Concord slot free, so a second player makes it
> 4v3), and a player who disconnects leaves an idle hero behind. Good
> for testing with friends, not for public servers.

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

## Option B: NAS or any host with Docker

```bash
# in a checkout of this repo (or copy the tools/server folder)
tar -xzf Cybergram-v0.2.0-linux-x86_64.tar.gz -C tools/server/game
docker compose -f tools/server/docker-compose.yml up -d --build
docker logs -f cybergram
```

On a Synology NAS: install **Container Manager**, copy the `tools/server`
folder (with `game/` filled) to the NAS, and create a *Project* from its
`docker-compose.yml`. Then forward **UDP 7777** on your router to the NAS.

## Connecting

Start the game, enter the server address in the main menu (for example
`203.0.113.5` or `myserver.example.com:7777`), pick a hero and press
**JOIN**. From a terminal:

```bash
./Cybergram.x86_64 -- --connect 203.0.113.5:7777 --hero brannoc
```

If the server does not answer within 8 s, the game goes back to the menu and
names the likely cause.

## Server options

| Flag | Meaning |
|---|---|
| `--port 7777` | UDP port to listen on |
| `--max-clients 8` | most players at once (1-32) |
| `--bot-difficulty easy\|normal\|hard` | bot skill |
| `--hero brannoc` | hero for players whose client sends no pick |
| `--match-clock 2` | run the match clock 2× faster (shorter test matches) |

## Troubleshooting

| Symptom | Check |
|---|---|
| "no answer from …" | The server is running (`journalctl` / `docker logs`). UDP 7777 is open in the VPS firewall *and* the provider's panel. For a home NAS, the router forwards UDP 7777. |
| "server rejected the connection (version mismatch?)" | Client and server must be the same release. |
| "cannot listen on UDP port 7777" | Another process uses the port, or pick another with `--port`. |
| Game is choppy online | Expected on long distances for now. There is no lag compensation yet. |
