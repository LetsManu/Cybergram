#!/usr/bin/env bash
# Copies the Let's Encrypt certificate that Nginx Proxy Manager (NPM) keeps for
# the game's hostname into the folder the Cybergram server reads
# (CYBERGRAM_TLS_DIR -> /data/tls), readable by the container user. When the
# certificate changed (NPM renews about every 60 days), the server is
# restarted so it loads the new one. Running matches drain first.
#
# Why a copy: NPM stores privkey.pem as root, mode 0600, behind symlinks into
# ../../archive/. A plain bind mount would be unreadable for the unprivileged
# game server, and the symlinks would not resolve inside the container.
#
# Usage (as root, e.g. daily from cron or a systemd timer):
#   NPM_LE_DIR=/volume1/docker/npm/letsencrypt NPM_CERT_ID=5 \
#   TLS_DIR=/srv/cybergram/tls COMPOSE_DIR=/srv/cybergram \
#   tools/server/sync_npm_cert.sh
#
#   NPM_LE_DIR   host folder mapped to /etc/letsencrypt in the NPM container
#   NPM_CERT_ID  the number of the certificate in NPM (SSL Certificates; the
#                folder is live/npm-<ID>); `ls $NPM_LE_DIR/live` lists them
#   TLS_DIR      the host folder in CYBERGRAM_TLS_DIR (.env)
#   COMPOSE_DIR  folder with docker-compose.yml (for the restart)
#   CONTAINER    container name (default: cybergram)
set -euo pipefail

: "${NPM_LE_DIR:?set NPM_LE_DIR (the NPM letsencrypt folder on the host)}"
: "${NPM_CERT_ID:?set NPM_CERT_ID (the N in live/npm-N)}"
: "${TLS_DIR:?set TLS_DIR (CYBERGRAM_TLS_DIR from .env)}"
COMPOSE_DIR="${COMPOSE_DIR:-$(pwd)}"
CONTAINER="${CONTAINER:-cybergram}"

src="$NPM_LE_DIR/live/npm-$NPM_CERT_ID"
[[ -r "$src/fullchain.pem" && -r "$src/privkey.pem" ]] || { echo "no certificate in $src" >&2; exit 1; }

# uid and gid of the container user (fallback: the usual system uid).
uid="$(docker exec "$CONTAINER" id -u 2>/dev/null || echo 999)"
gid="$(docker exec "$CONTAINER" id -g 2>/dev/null || echo 999)"

mkdir -p "$TLS_DIR"
changed=0
for f in fullchain.pem privkey.pem; do
  # readlink -f follows NPM's live/ -> archive/ symlinks.
  if ! cmp -s "$(readlink -f "$src/$f")" "$TLS_DIR/$f" 2>/dev/null; then
    install -m 0640 -o "$uid" -g "$gid" "$(readlink -f "$src/$f")" "$TLS_DIR/$f.new"
    mv -f "$TLS_DIR/$f.new" "$TLS_DIR/$f"
    changed=1
  fi
done

if [[ "$changed" == 1 ]]; then
  echo "$(date -Is) certificate updated from npm-$NPM_CERT_ID; restarting $CONTAINER"
  # SIGTERM drains: running matches finish first (stop_grace_period).
  (cd "$COMPOSE_DIR" && docker compose restart "$CONTAINER")
else
  echo "$(date -Is) certificate unchanged"
fi
