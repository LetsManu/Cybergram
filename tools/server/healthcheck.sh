#!/bin/sh
# Docker HEALTHCHECK probe (W17). Healthy when:
# - the game server holds its UDP 7777 socket (both modes), and
# - front mode: the warm match port is bound (see below), and the supervisor rewrote CYBERGRAM_HEALTH_FILE within 30 s
#   (it does every 2 s from its main loop, so a hung front turns unhealthy).
# Reads only local files; prints nothing secret.
grep -qi ':1E61 ' /proc/net/udp /proc/net/udp6 2>/dev/null || { echo "UDP 7777 not bound"; exit 1; }
if [ "${CYBERGRAM_MODE:-front}" = "front" ]; then
  f="${CYBERGRAM_HEALTH_FILE:-/tmp/cybergram-health.json}"
  [ -f "$f" ] || { echo "no health file"; exit 1; }
  age=$(( $(date +%s) - $(stat -c %Y "$f") ))
  [ "$age" -le 30 ] || { echo "health file is ${age}s old"; exit 1; }
fi
# Front mode: when a warm pool is configured, its first match port must be
# bound too, once the front has been up for a while (the pool starts at boot).
# A port that stays unbound means the supervisor cannot spawn matches.
if [ "${CYBERGRAM_MODE:-front}" = "front" ] && [ "${CYBERGRAM_WARM_POOL:-1}" != "0" ]; then
  first="${CYBERGRAM_MATCH_PORTS:-7800-7809}"; first="${first%%-*}"
  hex=$(printf '%04X' "$first" 2>/dev/null) || exit 0
  grep -qi ":$hex " /proc/net/udp /proc/net/udp6 2>/dev/null || { echo "warm match port $first not bound"; exit 1; }
fi
exit 0
