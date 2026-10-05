# Hosting Cybergram: NAS today, VPS later

How to run the server container on a home NAS, on a plain VPS, or on a home NAS
behind a VPS relay. Setup basics (image, accounts, TLS, update host) are in
[SERVER.md](SERVER.md). The architecture is in `design/gdd/matchmaking.md`
("Server architecture", "Hosting").

## Modes

| `CYBERGRAM_MODE` | What runs | Ports |
|---|---|---|
| `single` | One process: the lobby and one match on UDP 7777, as before. | 7777/udp, 8081/tcp (HTTP) |
| `front` (default since v0.13) | The front (accounts, parties, queues) on UDP 7777, plus one headless process per match on the match port range. | 7777/udp, 7800-7809/udp, 8081/tcp (HTTP) |

Host ports are the compose defaults. Inside the container the HTTP side
(launcher update feed, `status.json`, `snapshot.json`) always listens on 8080;
compose publishes it on host **8081** (`CYBERGRAM_API_PORT`) since W20-WEB,
and the optional website takes host **8080** (see *Website*).

Front mode is the default from v0.13 (queues, draft, ratings). `single` stays
selectable as the rollback. In front mode a match crash ends only that match: it is voided (no rating change)
and its players are re-queued.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `CYBERGRAM_MODE` | `front` | `front` or `single`. |
| `CYBERGRAM_PUBLIC_HOST` | empty | The address **clients** are told to connect to: a domain or the public IP of the VPS or relay. Empty means the address the client already used. It is separate from the bind address, so NAT, relays and tunnels work. |
| `CYBERGRAM_BIND_HOST` | `*` | The address match processes bind. |
| `CYBERGRAM_MATCH_PORTS` | `7800-7809` | The UDP port range, one port per concurrent match. It must match the compose port mapping and the firewall. |
| `CYBERGRAM_MAX_MATCHES` | `0` | Concurrent matches. `0` means 2 per CPU core. It is never more than the size of the port range. |
| `CYBERGRAM_MATCHES_PER_CORE` | `2` | Used when `MAX_MATCHES` is 0. A 5v5 takes about 22 % of a core. |
| `CYBERGRAM_WARM_POOL` | `1` | Idle match processes kept Ready (0 to 2). |
| `CYBERGRAM_BUILD_VERSION` | `dev` | The build tag of the match processes. |
| `CYBERGRAM_DRAIN_MAX_S` | `3600` (compose: `2340`) | The longest graceful drain. Keep it below `stop_grace_period`. |
| `CYBERGRAM_TICKET_KEYS` / `CYBERGRAM_TICKET_KEYS_FILE` | random | Join ticket keys as `kid:hex` (32+ bytes); the first is active. Without them a random key is used, which is fine on one host. Never logged. |
| `CYBERGRAM_IMAGE_TAG` | `latest` | (compose and `auto_update.sh`) The image tag. Pin e.g. `v0.13.0` to stop following `latest`. |
| `CYBERGRAM_MOTD_FILE` | `/data/motd.txt` | Path inside the container of the launcher message of the day. |
| `CYBERGRAM_TLS_DIR` | `./tls` | (compose only) The host folder with `fullchain.pem` and `privkey.pem`. |
| `CYBERGRAM_PUBLIC_DIR` | `/public` | Folder where the front writes `snapshot.json` for the website every 5 s (see *Website*). Empty switches it off. |
| `CYBERGRAM_API_PORT` | `8081` | (compose) Host TCP port of the game server's HTTP side (update feed, `status.json`, `snapshot.json`). Behind the proxy as `https://cyber-api.djboeck.at`. |
| `CYBERGRAM_WEB_PORT` | `8080` | (compose, `web` profile) Host TCP port of the website. Behind the proxy as `https://cyber.djboeck.at`. |
| `CYBERGRAM_API_URL` | `https://cyber-api.djboeck.at` | (website) Public URL of the HTTP side. Old launchers' feed requests to the website get a 301 there. |
| `CYBERGRAM_RELEASE_FETCH` | `1` | (website) `0` stops the website container from reading the latest release from the GitHub API. |

No variable or path is NAS-specific. The same compose file runs on a VPS.

## Upgrading to v0.13

The owner's checklist, the same on the NAS today and on a VPS later. Your
accounts stay in the `/data` volume; nothing is migrated.

1. **Pull.** In the folder with `docker-compose.yml`: `docker compose pull`.
2. **Add `.env`.** `cp .env.example .env` and set at least
   `CYBERGRAM_PUBLIC_HOST` (DynDNS name or VPS domain) and, on the NAS,
   `CYBERGRAM_TLS_DIR=/srv/cybergram/tls`.
3. **Forward UDP 7800-7809** (router to NAS, or `ufw allow 7800:7809/udp` and the
   provider panel on a VPS), next to the existing 7777/udp and the HTTP ports
   (see *Which ports to open*).
4. **Generate the ticket key** and put it in `.env`:
   `echo "k1:$(openssl rand -hex 32)"` gives the line to paste after
   `CYBERGRAM_TICKET_KEYS=`. Without it a random key is made at each start,
   which works on one host. Keep `.env` private (it is git-ignored).
5. **Start.** `docker compose up -d`, then `docker ps` shows `healthy` after
   about a minute. In front mode the logs show `[hosting]` lines.
6. **Review reports** (owner tool): `docker exec cybergram /opt/review_reports.sh list`.

**Roll back to single mode** (the pre-v0.13 server): set `CYBERGRAM_MODE=single`
in `.env` and run `docker compose up -d`. Ratings and history stay on disk and
are used again when you return to `front`. To go back to the old build too, pin
`CYBERGRAM_IMAGE_TAG=v0.12.0` (see below).

## Automatic updates

`tools/server/auto_update.sh` pulls the image every 12 minutes, compares it with
the running container and, if it is new, waits until no match is running (the
front's health file), at most `CYBERGRAM_UPDATE_MAX_WAIT_S` (default 1800 s).
Then it runs `docker compose up -d`: the old container gets SIGTERM and drains
(see "Draining for a patch"). Each update adds one line (time, old -> new image
id) to `/var/log/cybergram-update.log` (or `~/.cybergram-update.log`), trimmed
to `CYBERGRAM_UPDATE_LOG_MAX_BYTES` (64 KiB). Nothing about players is logged.

Setup with systemd (VPS, or a NAS that has it):

```
sudo mkdir -p /opt/cybergram-server && sudo cp tools/server/{auto_update.sh,docker-compose.yml,.env} /opt/cybergram-server/
sudo cp tools/server/cybergram-update.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now cybergram-update.timer
```

Edit `ExecStart` in the service if you used another folder. Without systemd
(e.g. a Synology Task Scheduler or cron), run
`*/12 * * * * /opt/cybergram-server/auto_update.sh` as a user that may run
docker. Set `CYBERGRAM_COMPOSE_CMD=docker-compose` if you only have the old
command.

**Pinning and rollback.** Set `CYBERGRAM_IMAGE_TAG=v0.13.0` in `.env`: the script
then follows only that tag and ignores newer `latest` images. To roll back, pin
the older tag; the next run (or `docker compose up -d`) switches to it, again
waiting for running matches. Remove the pin (`latest`) to follow releases.
Note: auto-update is not a substitute for reading the release notes. If you
want to approve each release, pin and change the tag by hand.

Test: `tools/ci/auto_update_test.sh` (fake docker CLI).

## Capacity and memory (measured 2026-10-05)

Measured on 4 cores with Godot 4.7: three real headless dedicated servers, each
playing a bots-only 5v5, ran side by side
(`production/qa/evidence/w17-sup/memory_rss.txt`):

- **About 188 MiB RSS per match process**, flat over 60 s.
- Server tick average 4.9-5.6 ms against a 33 ms budget. With 10 bots this is
  about 15-17 % of a core, which matches the 2 matches per core budget.
- The empty agent-only process (the warm pool floor) is about 100 MiB.

Sizing rule: **RAM = about 250 MiB (front) + 190 MiB x max matches + 190 MiB x
warm pool.**

| Host | Suggested `CYBERGRAM_MAX_MATCHES` | compose `cpus` / `mem_limit` |
|---|---|---|
| 2 vCPU / 2 GB VPS | 4 | `2.0` / `1536m` |
| 4 vCPU / 4 GB VPS | 8 | `4.0` / `2560m` |
| NAS (shared with other services) | 2-4 | as spare |

Widen `CYBERGRAM_MATCH_PORTS` if `MAX_MATCHES` is larger than 10.

## Which ports to open

- **UDP 7777**: the lobby and the front.
- **UDP 7800-7809** (or your `CYBERGRAM_MATCH_PORTS`): the matches. Front mode only, but open it now so the switch needs no firewall change.
- **TCP 80 and 443**: the TLS reverse proxy (Caddy, Traefik, nginx) that
  serves `https://cyber.djboeck.at` (the website, host 8080) and
  `https://cyber-api.djboeck.at` (the game server's HTTP side: launcher
  updates, `status.json`, `snapshot.json`; host 8081).
- **TCP 8080** (plain HTTP, the website): keep it open while launchers 1.4.0
  and older are around. They ask `http://cyber.djboeck.at:8080/version.json`;
  the website answers their feed paths with a 301 to `cyber-api`.
- **Without the website** nothing listens on host 8080 any more, so old
  launchers would lose their feed: set `CYBERGRAM_API_PORT=8080` in `.env` to
  keep the HTTP side on its old port.
- **TCP 8081** does not need to be public when the proxy runs on the same
  host (it reaches it locally). Without a proxy, open it instead of 80/443.
- On a VPS, open the ports in **both** the OS firewall (`ufw allow 7777/udp`,
  `ufw allow 7800:7809/udp`, `ufw allow 80/tcp`, `ufw allow 443/tcp`,
  `ufw allow 8080/tcp`) and the provider's panel.

## Setup 1: home NAS (today)

1. Use `tools/server/docker-compose.yml`. Put `CYBERGRAM_TLS_DIR=/srv/cybergram/tls`
   (your folder) in a `.env` file next to it.
2. On the router, forward UDP 7777, UDP 7800-7809, TCP 80, TCP 443 (the
   reverse proxy) and TCP 8080 (old launchers, see above) to the NAS.
3. Set `CYBERGRAM_PUBLIC_HOST` to your DynDNS name.

The drawback: players learn your home IP address (see DDoS below).

## Setup 2: plain VPS (later, for public play)

1. Install Docker, copy the compose file, then run `docker compose up -d`.
2. Open the ports listed above.
3. Set `CYBERGRAM_PUBLIC_HOST` to the VPS's domain.
4. Uncomment and size `cpus` / `mem_limit` (see the capacity table).

## Setup 3: VPS relay in front of the NAS (WireGuard)

Players connect to the VPS. The VPS forwards the game ports through a WireGuard
tunnel to the NAS, so only the VPS address is public.

1. Create a WireGuard tunnel: the VPS is `10.8.0.1` and the NAS is `10.8.0.2`.
   The NAS dials out, so no router port forward is needed at home.
2. On the VPS, forward the game ports into the tunnel, for example with nftables:
   ```
   table ip nat {
     chain prerouting { type nat hook prerouting priority -100;
       iifname "eth0" udp dport { 7777, 7800-7809 } dnat to 10.8.0.2
       iifname "eth0" tcp dport { 80, 443, 8080 } dnat to 10.8.0.2 }
     chain postrouting { type nat hook postrouting priority 100;
       oifname "wg0" masquerade }
   }
   ```
   Also enable `net.ipv4.ip_forward=1`. The reverse proxy (80/443) runs on
   the NAS next to the containers. Or run it on the VPS instead and forward
   only 8080 (the website) and 8081 (the HTTP side) to the proxy's upstreams
   through the tunnel.
3. On the NAS, set `CYBERGRAM_PUBLIC_HOST` to the **VPS** domain. The container
   still binds all addresses. This is why the advertised address and the bind
   address are separate.
4. Masquerading hides player IPs from the server. That is fine: it never needs
   them beyond the connection. The login rate limiter then sees one address.
   Raise its limits, or later use a source-preserving setup (policy routing).

Each match packet takes one extra hop through the tunnel. Pick a VPS close to
home and the players.

## Draining for a patch

Front mode only. In single mode a stop ends the running match immediately.

- `docker compose stop` sends SIGTERM. The entrypoint turns it into a **drain**:
  - no new matches start;
  - idle processes stop;
  - running matches finish, up to `CYBERGRAM_DRAIN_MAX_S`.
  - Then the container exits. `stop_grace_period: 40m` gives it time.
  - To stop sooner, run `docker compose stop -t 30`. Matches still running at
    that point are voided (no rating change).
- **Zero-downtime patch (phase B):** the supervisor tags every process with its
  build. After a deploy:
  - new matches go only to the new build;
  - running matches finish on the old one;
  - the front refuses clients on the old build.
- **Rotating the ticket key:** put the new key first in `CYBERGRAM_TICKET_KEYS`
  and keep the old one until every match started under it has ended.

## Resetting a player's password

Accounts have no e-mail. A player who forgot the password uses the recovery
code shown at sign-up ("Forgot password?" in the game or the launcher). If
they lost that code too, the host issues a new one from the server console,
**while the server runs**:

```sh
docker exec cybergram /opt/cybergram/Cybergram.x86_64 --headless \
  --script res://src/networking/auth/account_admin_cli.gd -- --admin-reset-password <username>
```

- The tool prints a **new recovery code once**. Give it to the player (in
  person or a private message). The player then chooses "Forgot password?"
  and enters the username, the code and a new password.
- The old password stops working at once, and every session of that account
  ends. Nothing else about the account changes.
- The running server applies the reset itself (within a few seconds): the
  tool leaves a request in `/data/admin`, it never edits account files.
  If the server is not running, the request waits and is applied at the next
  start (the tool says so). Only the code's hash is written to disk.
- The tool prints only the account's 4-character tag, never password hashes
  or other account data. Exit codes: 0 done (or queued), 2 no such username,
  3 refused by the server, 1 usage or write error.
- Check who is asking: whoever gets the code owns the account.

## Health

The Docker `HEALTHCHECK` (`tools/server/healthcheck.sh`) checks that UDP 7777 is
bound. In front mode it also checks that the supervisor rewrote its health file
in the last 30 s, so a hung front shows as unhealthy. `docker ps` shows the
state. Docker does not restart unhealthy containers by itself: use a watchdog
(e.g. autoheal) if you want that.

## DDoS, and why a VPS hides your home IP

A game server's address is public by nature: every client sends packets to it.
On a home NAS that address is your **home connection**. An angry player can
flood it with traffic. That takes down the game and your whole household's
internet, and your ISP cannot filter it for you.

- With a VPS, or a VPS relay (setup 3), the public address belongs to the
  provider. Most VPS providers include basic volumetric DDoS filtering. If an
  attack still gets through, only the VPS is hit: you can move to another IP,
  and your home stays online.
- Valve's Steam Datagram Relay works the same way at a larger scale.
- What we do in the game itself: match ports are only useful with a one-time
  join ticket, and a match process ignores clients that have no valid ticket.
  This does not stop floods. It does stop strangers from occupying match slots.

## Website

A small public website (`web/`, image `ghcr.io/letsmanu/cybergram-web`, one
per release) runs next to the game server: home page with downloads, heroes,
patch notes, live server status, the ranked leaderboard, Impressum and
privacy. It is static nginx on host port 8080, behind the TLS proxy as
`https://cyber.djboeck.at`. The live parts come from two local JSON files:

- `/data/snapshot.json`: the front writes it every 5 s into
  `CYBERGRAM_PUBLIC_DIR` (`/public`), a volume shared read-only with the web
  container. Contents: up / draining, players online, running and starting
  matches, queue sizes and estimated waits, and the top 100 of the ranked
  leaderboard (display name, medal, rating) of players who switched on
  *Show me on the public leaderboard* in the game (Ranks panel; off by
  default, PRIVACY.md). No ids, usernames or IP addresses. If the file is
  older than 60 s the site shows the server as offline.
- `/data/release.json`: the web container reads the newest GitHub release
  at start and every 6 h, so visitors never contact GitHub just by viewing
  the site. Without it the download button links to the releases page.

**Setup** (same host as the game server):

1. Add `COMPOSE_PROFILES=web` to the `.env` file next to
   `tools/server/docker-compose.yml` (or pass `--profile web`).
2. `docker compose -f tools/server/docker-compose.yml up -d`. The site is on
   `http://<host>:8080` (`CYBERGRAM_WEB_PORT`), the game server's HTTP side
   on `http://<host>:8081` (`CYBERGRAM_API_PORT`).
3. TLS reverse proxy (Caddy, Traefik or nginx with Let's Encrypt) on 80/443:
   `cyber.djboeck.at` -> `127.0.0.1:8080`, `cyber-api.djboeck.at` ->
   `127.0.0.1:8081`. Set HSTS there. A Caddyfile example:
   ```
   cyber.djboeck.at {
     reverse_proxy 127.0.0.1:8080
   }
   cyber-api.djboeck.at {
     reverse_proxy 127.0.0.1:8081
   }
   ```

**Old launchers.** Launchers 1.4.0 and older ask
`http://cyber.djboeck.at:8080/version.json` and the files next to it, which is
now the website. The website answers every update feed path (`/version.json`,
`/version.json.sig`, `/status.json`, `/blobs/`, `/files/`, `/game/`,
`/launcher/`, `Cybergram*.zip` / `.tar.gz` / `.AppImage`, `*.zsync`) with a
**301** to the same path on `CYBERGRAM_API_URL` (default
`https://cyber-api.djboeck.at`; set at container start, URL-safe characters
only). The launcher follows redirects (manifest, signature, status and the
resumable downloader; tested in `launcher/tests/e2e_upd.sh` step 11). New
launchers use `https://cyber-api.djboeck.at/version.json` and rewrite the
old default in `launcher.cfg` on start; a custom `version_url` is kept.
Keep TCP 8080 reachable over plain HTTP until the old launchers have
updated themselves.

The game server's HTTP side also serves `/snapshot.json` read-only (the same
anonymous file the website reads), so `https://cyber-api.djboeck.at/snapshot.json`
works for other tools.

The container runs as an unprivileged user with a read-only root, no Linux
capabilities, a strict Content Security Policy, `Referrer-Policy:
no-referrer` and `nosniff`. Its access log (`docker logs cybergram-web`) has
time, path, status, size and duration only: **no IP address, user agent,
referrer or query string**; the error log records critical faults only.
Logs are rotated at 3 x 10 MB. If your reverse proxy logs IP addresses,
keep them at most 7 days and name it on the privacy page.

Build it yourself from the repo root:
`docker build -f web/Dockerfile -t cybergram-web .` and check it with
`web/smoke.sh cybergram-web`. To preview without Docker:
`python3 web/build.py` writes `web/dist/` (copy `web/sample/snapshot.json`
to `web/dist/data/` and serve the folder; the sample timestamps are old, so
it shows "offline").

**Owner to-dos before the site goes public:**

- **Impressum** (`web/pages/impressum.html`): fill every
  `[TO BE FILLED]` field (name or company, address, e-mail; register
  number, VAT number and chamber only if they apply) and delete the rest.
- **Privacy** (`web/pages/privacy.html`): fill the operator contact, the
  reverse proxy / hosting paragraph (or delete it) and whether HTTPS is used.
- Have both pages and `PRIVACY.md` checked legally (lawyer or WKO).
- Point the DNS names `cyber.djboeck.at` and `cyber-api.djboeck.at` at the
  host and set up the TLS proxy.
- Rebuild the image after editing (or edit and build in CI with the next
  release).

