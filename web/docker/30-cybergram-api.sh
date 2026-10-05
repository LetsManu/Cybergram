#!/bin/sh
# Cybergram website (W20-WEB): renders the redirects for old launchers.
# Launchers 1.4.0 and older ask http://cyber.djboeck.at:8080/ (now this site)
# for the update feed; every feed path answers 301 to the same path on
# CYBERGRAM_API_URL (default https://cyber-api.djboeck.at), the game server's
# HTTP side. Written to /tmp (the root file system is read-only) and included
# by nginx.conf. Feed paths (launcher/tools/make_update_feed.sh,
# src/networking/lobby/status_writer.gd): version.json(.sig), status.json,
# blobs/, Cybergram*.zip / .tar.gz / .AppImage, *.zsync, and files/, game/,
# launcher/ for safety.
set -eu
api="${CYBERGRAM_API_URL:-https://cyber-api.djboeck.at}"
api="${api%/}"
case "$api" in
  http://*|https://*) ;;
  *) echo "[web] CYBERGRAM_API_URL must start with http:// or https:// (got '$api')" >&2; exit 1 ;;
esac
# Only URL-safe characters: nothing that could break out of the nginx config.
if printf '%s' "$api" | grep -q '[^A-Za-z0-9.:/_-]'; then
  echo "[web] CYBERGRAM_API_URL has characters that are not allowed: '$api'" >&2
  exit 1
fi
mkdir -p /tmp/nginx
cat > /tmp/nginx/api-redirects.conf <<EOF
# Generated at container start by 30-cybergram-api.sh (CYBERGRAM_API_URL).
location = /version.json { return 301 ${api}\$request_uri; }
location = /version.json.sig { return 301 ${api}\$request_uri; }
location = /status.json { return 301 ${api}\$request_uri; }
location ^~ /blobs/ { return 301 ${api}\$request_uri; }
location ^~ /files/ { return 301 ${api}\$request_uri; }
location ^~ /game/ { return 301 ${api}\$request_uri; }
location ^~ /launcher/ { return 301 ${api}\$request_uri; }
location ~ ^/Cybergram[^/]*\.(zip|tar\.gz|AppImage|zsync)$ { return 301 ${api}\$request_uri; }
location ~ \.zsync$ { return 301 ${api}\$request_uri; }
EOF
echo "[web] old launcher feed paths redirect to $api"
