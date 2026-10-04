#!/bin/sh
# Starts the static update host (TCP 8080, serves /opt/cybergram-updates:
# version.json + the client zips) next to the game server. Extra container
# arguments are passed on to the game server (later flags win). 32 ENet slots:
# logged-in players idling in the main menu each hold one.
if [ -f /opt/cybergram-updates/version.json ]; then
  busybox httpd -f -p 8080 -h /opt/cybergram-updates &
  echo "[update-host] serving client builds on TCP 8080"
else
  echo "[update-host] no version.json baked in; update host disabled"
fi
exec /opt/cybergram/Cybergram.x86_64 --headless -- --server --port 7777 --max-clients 32 "$@"
