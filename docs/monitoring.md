# Monitoring the Cybergram server

The front process (default `CYBERGRAM_MODE=front`) serves a small operations
endpoint over plain HTTP on TCP **8090** inside the container (P1, protocol 20).

| Setting | Default (compose) | Meaning |
|---|---|---|
| `CYBERGRAM_OPS_PORT` | `8090` | Port inside the container. Empty = endpoint off. |
| `CYBERGRAM_OPS_PUBLISH` | `127.0.0.1:8090` | Host address:port it is published on. Use the LAN IP for a monitoring box. |
| `CYBERGRAM_ADMIN_TOKEN` | empty | Password for `/admin`. Empty = `/admin` answers 404. Use a long random string. |
| `CYBERGRAM_LOG_FORMAT` | `json` | `json` = one JSON object per log line from the matchmaking front; `text` = classic `[front] ...` lines. |
| `CYBERGRAM_LOG_SALT` | empty | Fixed salt so player tags stay the same across restarts. |

**Never forward port 8090 through the public reverse proxy.** `/health` and
`/metrics` hold no personal data, but they are for the operator.

## Endpoints

| Path | Answer |
|---|---|
| `GET /health` | `200 {"status":"ok","version":"v0.17.0","protocol":20,"uptime_s":…,"clients":…,"checks":{…}}` when ready; `503` with `"status":"degraded"` when a check fails (e.g. the server is draining for an update). |
| `GET /health/live` | `200 {"status":"alive"}` while the main loop runs (a hung loop stops answering). |
| `GET /metrics` | Prometheus text format. |
| `GET /admin` | HTML status page (refreshes every 5 s): queues, lobbies and matches, parties, players with their state, the last 200 events. HTTP Basic login: any user name, the token as password. |
| `GET /admin.json` | The same as JSON. `Authorization: Bearer <token>` or Basic. |

Quick checks from the NAS:

```sh
curl -s localhost:8090/health
curl -s localhost:8090/metrics | grep -v '^#'
curl -s -H "Authorization: Bearer $CYBERGRAM_ADMIN_TOKEN" localhost:8090/admin.json | head -c 600
```

## Metrics

| Metric | Type | Labels |
|---|---|---|
| `cybergram_connected_clients` | gauge | |
| `cybergram_queue_players` | gauge | `queue` |
| `cybergram_queue_estimated_wait_seconds` | gauge | `queue` |
| `cybergram_queue_wait_seconds_sum` / `_count` | counter | `queue` (average wait = sum / count) |
| `cybergram_queue_joins_total` | counter | `queue` |
| `cybergram_ready_checks_total` | counter | `outcome` = started, accepted, failed |
| `cybergram_ready_check_declines_total` | counter | |
| `cybergram_dodges_total` | counter | |
| `cybergram_matches_total` | counter | `event` = started, ended, voided |
| `cybergram_lobbies` | gauge | `state` = ReadyCheck, ChampSelect, Loading, Running |
| `cybergram_players` | gauge | `phase` (see the state machine in `docs/architecture/front-state.md`) |
| `cybergram_parties` | gauge | `state` |
| `cybergram_custom_lobbies` | gauge | |
| `cybergram_illegal_transitions_total` | gauge | rejected state changes since start (should stay 0) |
| `cybergram_front_tick_ms`, `cybergram_front_tick_ms_max` | gauge | main-loop time; max resets on every scrape |
| `cybergram_protocol_violations` | gauge | peers that sent malformed packets |
| `cybergram_connections_rejected_total` | counter | `reason` = plain_udp, bad_certificate, handshake_other, version_mismatch, auth (see `docs/connecting.md`) |
| `cybergram_uptime_seconds` | gauge | |
| `cybergram_build_info` | gauge (1) | `version`, `protocol` |

Ready-check accept rate = `accepted / started` over a window, e.g. in PromQL
`increase(cybergram_ready_checks_total{outcome="accepted"}[1h]) / increase(cybergram_ready_checks_total{outcome="started"}[1h])`.

## Icinga 2 examples

Monitoring plugins `check_http` (or `check_curl`) and a small shell check for metrics.
Replace `192.168.1.7` with the address you published the port on.

```
object Service "cybergram-health" {
  host_name = "nas"
  check_command = "http"
  vars.http_address = "192.168.1.7"
  vars.http_port = 8090
  vars.http_uri = "/health"
  vars.http_string = "\"status\":\"ok\""     // 503 / degraded -> CRITICAL
  vars.http_warn_time = 1
  vars.http_critical_time = 3
  check_interval = 1m
}

object Service "cybergram-live" {
  host_name = "nas"
  check_command = "http"
  vars.http_address = "192.168.1.7"
  vars.http_port = 8090
  vars.http_uri = "/health/live"
  check_interval = 30s
}
```

Metric thresholds with a tiny script (`/usr/lib/nagios/plugins/check_cybergram_metric`):

```sh
#!/bin/sh
# usage: check_cybergram_metric URL METRIC_REGEX WARN CRIT   (numbers; higher = worse)
v=$(curl -sf --max-time 3 "$1" | grep -E "^$2 " | awk '{s+=$2} END {print s+0}') || { echo "UNKNOWN: no metrics"; exit 3; }
if [ "$(echo "$v >= $4" | bc)" = 1 ]; then echo "CRITICAL: $2 = $v | v=$v"; exit 2; fi
if [ "$(echo "$v >= $3" | bc)" = 1 ]; then echo "WARNING: $2 = $v | v=$v"; exit 1; fi
echo "OK: $2 = $v | v=$v"; exit 0
```

Suggested thresholds (small community server):

| What | Metric | Warn | Crit |
|---|---|---|---|
| Main loop slow | `cybergram_front_tick_ms_max` | 50 | 200 |
| State machine bug | `cybergram_illegal_transitions_total` | 1 | 20 |
| Matches stuck loading | `cybergram_lobbies\{state="Loading"\}` | 3 | 6 |
| Long waits | `cybergram_queue_estimated_wait_seconds` | 300 | 900 |
| Bare-IP connects | `cybergram_connections_rejected_total\{reason="plain_udp"\}` | 50 | 500 |
| Certificate refused | `cybergram_connections_rejected_total\{reason="bad_certificate"\}` | 10 | 100 |

Rejected connections, their log line and the client-side connection test are
described in `docs/connecting.md`.

Prometheus works the same way: scrape `http://192.168.1.7:8090/metrics`.

## Logs

`docker logs cybergram` shows the front's events as JSON lines (with
`CYBERGRAM_LOG_FORMAT=json`), for example:

```json
{"comp":"front","event":"player_phase","level":"info","match":"9f3c…","msg":"player 4be1c0a2d9: ReadyCheck -> ChampSelect","player":"4be1c0a2d9","ts":"2026-10-06T10:12:03Z"}
```

Correlation fields: `player` (salted tag, never the account id), `party`,
`lobby` / `match` (random ids). Filter one player's journey with
`docker logs cybergram | grep 4be1c0a2d9`. Levels: `info`, `warn` (illegal
transitions, protocol violations), `error`. Other components (accounts,
hosting, match processes) still print text lines; that is a known gap.
Docker rotates logs when the daemon is set to (`log-opts max-size`).

Privacy: see PRIVACY.md "Server logs".
