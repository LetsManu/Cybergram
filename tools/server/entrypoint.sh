#!/bin/sh
# Starts the static update host (TCP 8080, serves /opt/cybergram-updates:
# version.json + the client zips) next to the game server. Extra container
# arguments are passed on to the game server (later flags win). 32 ENet slots:
# logged-in players idling in the main menu each hold one.
#
# CYBERGRAM_MODE (W17, see docs/HOSTING.md):
#   single  (default) one process: lobby + one match on UDP 7777, as before.
#   front   control plane on UDP 7777 that spawns one headless process per
#           match on CYBERGRAM_MATCH_PORTS. Needs a build with the phase-B
#           wiring (--front); SIGTERM becomes a graceful drain.
if [ -f /opt/cybergram-updates/version.json ]; then
  busybox httpd -f -p 8080 -h /opt/cybergram-updates &
  echo "[update-host] serving client builds on TCP 8080"
else
  echo "[update-host] no version.json baked in; update host disabled"
fi

BIN=/opt/cybergram/Cybergram.x86_64
case "${CYBERGRAM_MODE:-single}" in
  single)
    exec "$BIN" --headless -- --server --port 7777 --max-clients 32 "$@"
    ;;
  front)
    export CYBERGRAM_DRAIN_FILE="${CYBERGRAM_DRAIN_FILE:-/tmp/cybergram-drain}"
    export CYBERGRAM_HEALTH_FILE="${CYBERGRAM_HEALTH_FILE:-/tmp/cybergram-health.json}"
    rm -f "$CYBERGRAM_DRAIN_FILE"
    echo "[entrypoint] front mode: match ports ${CYBERGRAM_MATCH_PORTS:-7800-7809}," \
      "max matches ${CYBERGRAM_MAX_MATCHES:-auto}, public host ${CYBERGRAM_PUBLIC_HOST:-<client's address>}"
    "$BIN" --headless -- --server --front --port 7777 --max-clients 32 "$@" &
    child=$!
    # Godot exits at once on SIGTERM, so the shell catches it and asks the
    # front to drain instead: no new matches, running matches finish
    # (at most CYBERGRAM_DRAIN_MAX_S), then the front exits by itself.
    trap 'echo "[entrypoint] SIGTERM: draining"; touch "$CYBERGRAM_DRAIN_FILE"' TERM INT
    status=0
    while :; do
      wait "$child"
      status=$?
      kill -0 "$child" 2>/dev/null || break
    done
    exit "$status"
    ;;
  *)
    echo "[entrypoint] unknown CYBERGRAM_MODE '${CYBERGRAM_MODE}' (use single or front)" >&2
    exit 64
    ;;
esac
