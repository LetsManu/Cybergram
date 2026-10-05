#!/bin/sh
# Docker HEALTHCHECK probe (W17). Healthy when:
# - the game server holds its UDP 7777 socket (both modes), and
# - front mode: the supervisor rewrote CYBERGRAM_HEALTH_FILE within 30 s
#   (it does every 2 s from its main loop, so a hung front turns unhealthy).
# Reads only local files; prints nothing secret.
grep -qi ':1E61 ' /proc/net/udp /proc/net/udp6 2>/dev/null || { echo "UDP 7777 not bound"; exit 1; }
if [ "${CYBERGRAM_MODE:-single}" = "front" ]; then
  f="${CYBERGRAM_HEALTH_FILE:-/tmp/cybergram-health.json}"
  [ -f "$f" ] || { echo "no health file"; exit 1; }
  age=$(( $(date +%s) - $(stat -c %Y "$f") ))
  [ "$age" -le 30 ] || { echo "health file is ${age}s old"; exit 1; }
fi
exit 0
