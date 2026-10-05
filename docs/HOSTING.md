# Hosting Cybergram: NAS today, VPS later

How to run the server container on a home NAS, on a plain VPS, or on a home NAS
behind a VPS relay. Setup basics (image, accounts, TLS, update host) are in
[SERVER.md](SERVER.md). The architecture is in `design/gdd/matchmaking.md`
("Server architecture", "Hosting").

## Modes

| `CYBERGRAM_MODE` | What runs | Ports |
|---|---|---|
| `single` (default) | One process: the lobby and one match on UDP 7777, as before. | 7777/udp, 8080/tcp |
| `front` (phase B) | The front (accounts, parties, queues) on UDP 7777, plus one headless process per match on the match port range. | 7777/udp, 7800-7809/udp, 8080/tcp |

Stay on `single` until a release notes that front mode is wired (phase B). In
front mode a match crash ends only that match: it is voided (no rating change)
and its players are re-queued.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `CYBERGRAM_MODE` | `single` | `single` or `front`. |
| `CYBERGRAM_PUBLIC_HOST` | empty | The address **clients** are told to connect to: a domain or the public IP of the VPS or relay. Empty means the address the client already used. It is separate from the bind address, so NAT, relays and tunnels work. |
| `CYBERGRAM_BIND_HOST` | `*` | The address match processes bind. |
| `CYBERGRAM_MATCH_PORTS` | `7800-7809` | The UDP port range, one port per concurrent match. It must match the compose port mapping and the firewall. |
| `CYBERGRAM_MAX_MATCHES` | `0` | Concurrent matches. `0` means 2 per CPU core. It is never more than the size of the port range. |
| `CYBERGRAM_MATCHES_PER_CORE` | `2` | Used when `MAX_MATCHES` is 0. A 5v5 takes about 22 % of a core. |
| `CYBERGRAM_WARM_POOL` | `1` | Idle match processes kept Ready (0 to 2). |
| `CYBERGRAM_BUILD_VERSION` | `dev` | The build tag of the match processes. |
| `CYBERGRAM_DRAIN_MAX_S` | `3600` (compose: `2340`) | The longest graceful drain. Keep it below `stop_grace_period`. |
| `CYBERGRAM_TICKET_KEYS` / `CYBERGRAM_TICKET_KEYS_FILE` | random | Join ticket keys as `kid:hex` (32+ bytes); the first is active. Without them a random key is used, which is fine on one host. Never logged. |
| `CYBERGRAM_TLS_DIR` | `./tls` | (compose only) The host folder with `fullchain.pem` and `privkey.pem`. |

No variable or path is NAS-specific. The same compose file runs on a VPS.

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
- **TCP 8080**: launcher updates and the status file.
- On a VPS, open the ports in **both** the OS firewall (`ufw allow 7777/udp`,
  `ufw allow 7800:7809/udp`, `ufw allow 8080/tcp`) and the provider's panel.

## Setup 1: home NAS (today)

1. Use `tools/server/docker-compose.yml`. Put `CYBERGRAM_TLS_DIR=/srv/cybergram/tls`
   (your folder) in a `.env` file next to it.
2. On the router, forward UDP 7777, UDP 7800-7809 and TCP 8080 to the NAS.
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
       iifname "eth0" tcp dport 8080 dnat to 10.8.0.2 }
     chain postrouting { type nat hook postrouting priority 100;
       oifname "wg0" masquerade }
   }
   ```
   Also enable `net.ipv4.ip_forward=1`.
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
