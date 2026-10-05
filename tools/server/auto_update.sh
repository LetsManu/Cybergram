#!/usr/bin/env bash
# Server auto-update (W17B-OPS). Run every 10-15 minutes from a systemd timer
# (cybergram-update.timer) or cron. Works on a NAS and on a VPS.
#
#   1. docker pull <image>:<tag>, then compare the image id of the running
#      container with the one the tag now points to. Same = nothing to do.
#   2. New image: wait until no match is running (front health file) or
#      CYBERGRAM_UPDATE_MAX_WAIT_S (default 1800), whichever comes first.
#   3. `docker compose up -d` recreates the container. Docker sends SIGTERM,
#      the front drains gracefully (see docs/HOSTING.md "Draining").
#   4. One log line per update, in a capped log file.
#
# Pinning: CYBERGRAM_IMAGE_TAG=v0.13.0 (in .env next to the compose file, or
# in the environment) stops following :latest. Changing the pin (e.g. back to
# an older tag) is applied by this same script: that is the rollback.
#
# cron example (every 12 minutes, as the user that runs docker):
#   */12 * * * * /path/to/tools/server/auto_update.sh >> /dev/null 2>&1
#
# Settings (environment, or in .env next to the compose file):
#   CYBERGRAM_IMAGE            ghcr.io/letsmanu/cybergram-server
#   CYBERGRAM_IMAGE_TAG        latest
#   CYBERGRAM_CONTAINER        cybergram
#   CYBERGRAM_COMPOSE_FILE     docker-compose.yml next to this script
#   CYBERGRAM_COMPOSE_CMD      "docker compose" (Synology: "docker-compose")
#   CYBERGRAM_UPDATE_MAX_WAIT_S  1800   longest wait for running matches
#   CYBERGRAM_UPDATE_POLL_S      30     seconds between checks while waiting
#   CYBERGRAM_UPDATE_LOG       /var/log/cybergram-update.log, or
#                              ~/.cybergram-update.log when /var/log is not writable
#   CYBERGRAM_UPDATE_LOG_MAX_BYTES  65536
#   CYBERGRAM_HEALTH_FILE      /tmp/cybergram-health.json (inside the container)
# Exit codes: 0 ok / nothing to do, 1 failure (pull or restart), 75 another run is active.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
compose_file="${CYBERGRAM_COMPOSE_FILE:-$here/docker-compose.yml}"
env_file="$(dirname "$compose_file")/.env"
# Read only the settings this script needs from .env (never source it).
envval() { [[ -f "$env_file" ]] && sed -n "s/^$1=//p" "$env_file" | tail -1 | tr -d '"' || true; }
cfg() { local v="${!1:-}"; [[ -n "$v" ]] || v="$(envval "$1")"; printf '%s' "${v:-$2}"; }

image="$(cfg CYBERGRAM_IMAGE ghcr.io/letsmanu/cybergram-server)"
tag="$(cfg CYBERGRAM_IMAGE_TAG latest)"
container="$(cfg CYBERGRAM_CONTAINER cybergram)"
compose_cmd="$(cfg CYBERGRAM_COMPOSE_CMD 'docker compose')"
max_wait="$(cfg CYBERGRAM_UPDATE_MAX_WAIT_S 1800)"
poll="$(cfg CYBERGRAM_UPDATE_POLL_S 30)"
health_file="$(cfg CYBERGRAM_HEALTH_FILE /tmp/cybergram-health.json)"
log_max="$(cfg CYBERGRAM_UPDATE_LOG_MAX_BYTES 65536)"
log="${CYBERGRAM_UPDATE_LOG:-}"
if [[ -z "$log" ]]; then
  if [[ -w /var/log ]]; then log=/var/log/cybergram-update.log; else log="$HOME/.cybergram-update.log"; fi
fi

say() {  # one log line, trimmed to the newest log_max bytes
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$log" 2>/dev/null || true
  printf '%s\n' "$*"
  if [[ -f "$log" ]] && (( $(wc -c < "$log") > log_max )); then
    tail -c $(( log_max / 2 )) "$log" | tail -n +2 > "$log.tmp" && mv "$log.tmp" "$log"
  fi
}

# One run at a time (a wait can outlast the timer interval).
lock="${CYBERGRAM_UPDATE_LOCK:-${TMPDIR:-/tmp}/cybergram-update.lock}"
if command -v flock > /dev/null; then
  exec 9> "$lock"
  flock -n 9 || { echo "another update run is active"; exit 75; }
fi

ref="$image:$tag"
if ! docker pull -q "$ref" > /dev/null; then
  say "pull of $ref failed; nothing changed"
  exit 1
fi
new_id="$(docker image inspect --format '{{.Id}}' "$ref" 2>/dev/null)"
old_id="$(docker inspect --format '{{.Image}}' "$container" 2>/dev/null || true)"
if [[ -z "$new_id" ]]; then say "cannot read image id of $ref"; exit 1; fi
if [[ "$old_id" == "$new_id" ]]; then
  echo "up to date ($ref)"
  exit 0
fi

# Matches that would be cut off by a restart: allocated + draining processes
# in the front's health file. Prints a number, or "?" when it cannot be read
# (single mode, container stopped).
running_matches() {
  local js a d
  js="$(docker exec "$container" cat "$health_file" 2>/dev/null)" || { echo "?"; return; }
  a="$(printf '%s' "$js" | sed -n 's/.*"allocated": *\([0-9]*\).*/\1/p')"
  d="$(printf '%s' "$js" | sed -n 's/.*"draining": *\([0-9]\+\).*/\1/p')"
  [[ -n "$a" ]] || { echo "?"; return; }
  echo $(( a + ${d:-0} ))
}

short() { local s="${1#sha256:}"; printf '%s' "${s:0:12}"; }
running="$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || echo false)"
start="$(date +%s)"
reason="idle"
if [[ "$running" == "true" ]]; then
  while :; do
    n="$(running_matches)"
    [[ "$n" == "0" ]] && break
    if (( $(date +%s) - start >= max_wait )); then reason="max wait ${max_wait}s reached ($n running)"; break; fi
    sleep "$poll"
  done
else
  reason="container not running"
fi

export CYBERGRAM_IMAGE_TAG="$tag" CYBERGRAM_IMAGE="$image"
# shellcheck disable=SC2086
if $compose_cmd -f "$compose_file" up -d > /dev/null 2>&1; then
  say "updated $ref: $(short "$old_id") -> $(short "$new_id") ($reason)"
else
  say "update to $ref FAILED at restart ($(short "$old_id") -> $(short "$new_id"))"
  exit 1
fi
