#!/usr/bin/env bash
# Smoke test of the website image (W20-WEB, used by build.yml):
#   web/smoke.sh [image]   (default cybergram-web:test)
# Runs the container hardened like the compose file (read-only, no
# capabilities) with web/sample/snapshot.json in the public volume, then
# checks: the home page, every generated page, the snapshot JSON, the
# security headers, the 404 page, the 301s that send old launchers' feed
# requests to CYBERGRAM_API_URL, and an access log without IP addresses.
set -euo pipefail
image="${1:-cybergram-web:test}"
root="$(cd "$(dirname "$0")/.." && pwd)"
port="${SMOKE_PORT:-18089}"
name="cybergram-web-smoke-$$"
pub="$(mktemp -d)"
cp "$root/web/sample/snapshot.json" "$pub/snapshot.json"
chmod 755 "$pub"; chmod 644 "$pub/snapshot.json"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$pub"; }
trap cleanup EXIT

api="https://api.example.test"
docker run -d --name "$name" -p "127.0.0.1:$port:8080" -e CYBERGRAM_RELEASE_FETCH=0 -e CYBERGRAM_API_URL="$api/" \
  -v "$pub:/srv/public:ro" --read-only --tmpfs /tmp --tmpfs /var/cache/cybergram-web:uid=101,gid=101 \
  --cap-drop ALL --security-opt no-new-privileges:true "$image" >/dev/null
base="http://127.0.0.1:$port"
for _ in $(seq 1 30); do curl -fsS -o /dev/null "$base/" 2>/dev/null && break; sleep 1; done

fail() { echo "SMOKE FAIL: $*" >&2; docker logs "$name" 2>&1 | tail -20 >&2; exit 1; }
headers="$(curl -fsS -D - -o /tmp/web-smoke-index.html "$base/")" || fail "home page"
grep -q "Hold the lane" /tmp/web-smoke-index.html || fail "home page content"
for h in "Content-Security-Policy: default-src 'none'" "Referrer-Policy: no-referrer" "X-Content-Type-Options: nosniff"; do
  grep -qi "^$h" <<<"$headers" || fail "missing header: $h"
done
for p in heroes.html patch-notes.html status.html leaderboard.html impressum.html privacy.html static/site.css static/site.js; do
  curl -fsS -o /dev/null "$base/$p" || fail "$p"
done
# Fetch first, then search: `curl | grep -q` under pipefail fails at random when
# grep exits on its match while curl is still writing (curl: write error 23).
heroes="$(curl -fsS "$base/heroes.html")" || fail "hero roster fetch"
grep -q 'id="vesper_loom"' <<<"$heroes" || fail "hero roster"
notes="$(curl -fsS "$base/patch-notes.html")" || fail "patch notes fetch"
grep -q 'id="v0-1-0"' <<<"$notes" || fail "patch notes"
snap="$(curl -fsS "$base/data/snapshot.json")" || fail "snapshot JSON"
grep -q '"leaderboard"' <<<"$snap" || fail "snapshot content"
code="$(curl -s -o /dev/null -w '%{http_code}' "$base/no-such-page")"
[[ "$code" == 404 ]] || fail "404 page answered $code"
# Old launchers' feed paths answer 301 to the API host, same path and query.
for p in version.json version.json.sig status.json "blobs/$(printf 'a%.0s' {1..64})" files/x game/x launcher/x \
    Cybergram-v0.13.1-windows-x86_64.zip CybergramLauncher-v0.13.1-linux-x86_64.zip \
    Cybergram-0.13.1-x86_64.AppImage Cybergram-0.13.1-x86_64.AppImage.zsync "version.json?t=1"; do
  got="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$base/$p")"
  [[ "$got" == "301 $api/$p" ]] || fail "redirect of /$p: $got"
done
# The site's own files are not redirected.
code="$(curl -s -o /dev/null -w '%{http_code}' "$base/data/snapshot.json")"
[[ "$code" == 200 ]] || fail "snapshot redirected or missing ($code)"
# The access log holds no client address (the request came from 172.17.0.1 / 127.0.0.1).
logs="$(docker logs "$name" 2>&1)"
grep -q '"GET /data/snapshot.json" 200' <<<"$logs" || fail "access log line missing"
if grep -Eq '(^|[^0-9.])(127\.0\.0\.1|172\.[0-9]+\.[0-9]+\.[0-9]+)([^0-9.]|$)' <<<"$logs"; then fail "IP address in the log"; fi
echo "web smoke OK ($image)"
