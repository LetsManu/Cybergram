#!/usr/bin/env bash
# Tests tools/server/auto_update.sh against a fake docker CLI on PATH (W17B-OPS).
# Cases: no update, update while idle, update waiting for a match, max-wait
# drain, pinned tag (rollback). No real docker needed.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
# Fake docker. State files in $FAKE: running_id, tag_id.<tag>, matches (a count
# that drops by one per `exec` when countdown is set), calls (log of calls).
cat > "$tmp/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$1" in
  pull) exit 0 ;;
  image) tag="${*: -1}"; tag="${tag##*:}"; cat "$FAKE/tag_id.$tag" ;;
  inspect) if [[ "$*" == *State.Running* ]]; then echo true; else cat "$FAKE/running_id"; fi ;;
  exec)
    n="$(cat "$FAKE/matches")"
    echo "{\"processes\":{\"starting\":0,\"ready\":1,\"allocated\":$n,\"draining\":0,\"shutdown\":0},\"draining\":false,\"capacity\":4}"
    if [[ -f "$FAKE/countdown" && "$n" -gt 0 ]]; then echo $((n-1)) > "$FAKE/matches"; fi ;;
  compose) echo "tag=$CYBERGRAM_IMAGE_TAG" >> "$FAKE/calls"; cat "$FAKE/tag_id.$CYBERGRAM_IMAGE_TAG" > "$FAKE/running_id" ;;
esac
STUB
chmod +x "$tmp/bin/docker"
fails=0
check() { if [[ "$2" == "0" ]]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
# run <name> <running id> <latest id> <matches> [countdown] [extra env...]
run() {
  export FAKE="$tmp/f"; rm -rf "$FAKE"; mkdir -p "$FAKE"
  echo "$2" > "$FAKE/running_id"; echo "$3" > "$FAKE/tag_id.latest"; echo "sha256:old" > "$FAKE/tag_id.v0.12.0"
  echo "$4" > "$FAKE/matches"; [[ "$5" == "countdown" ]] && : > "$FAKE/countdown"
  shift 5
  out="$(env PATH="$tmp/bin:$PATH" CYBERGRAM_UPDATE_LOG="$tmp/f/log" CYBERGRAM_UPDATE_LOCK="$tmp/f/lock" \
    CYBERGRAM_COMPOSE_FILE="$tmp/f/docker-compose.yml" CYBERGRAM_UPDATE_POLL_S=0.1 CYBERGRAM_UPDATE_MAX_WAIT_S=1 \
    "$@" "$root/tools/server/auto_update.sh" 2>&1)"; rc=$?
}
restarted() { grep -q '^compose' "$FAKE/calls"; }

run t1 sha256:aaa sha256:aaa 0 none
check "no update: exit 0" "$rc"; ! restarted; check "no update: no restart" "$?"

run t2 sha256:aaa sha256:bbb 0 none
check "idle update: exit 0" "$rc"; restarted; check "idle update: restarted" "$?"
grep -q 'aaa -> bbb (idle)' "$FAKE/log"; check "idle update: logged old -> new" "$?"

run t3 sha256:aaa sha256:bbb 2 countdown CYBERGRAM_UPDATE_MAX_WAIT_S=20
restarted; check "waits for match: restarted once empty" "$?"
grep -q '(idle)' "$FAKE/log"; check "waits for match: reason idle" "$?"
[[ "$(cat "$FAKE/matches")" == "0" ]]; check "waits for match: matches drained first" "$?"

run t4 sha256:aaa sha256:bbb 3 none CYBERGRAM_UPDATE_MAX_WAIT_S=1
restarted; check "max wait: drains and restarts anyway" "$?"
grep -q 'max wait 1s reached (3 running)' "$FAKE/log"; check "max wait: logged" "$?"

run t5 sha256:aaa sha256:bbb 0 none CYBERGRAM_IMAGE_TAG=v0.12.0
restarted; check "pinned tag: rollback applied" "$?"
grep -q 'tag=v0.12.0' "$FAKE/calls"; check "pinned tag: compose gets the pinned tag" "$?"
! grep -q 'latest' "$FAKE/calls"; check "pinned tag: :latest never touched" "$?"

run t6 sha256:old sha256:bbb 0 none CYBERGRAM_IMAGE_TAG=v0.12.0
! restarted; check "pinned and current: no restart even though latest moved" "$?"

# log cap
run t7 sha256:aaa sha256:bbb 0 none CYBERGRAM_UPDATE_LOG_MAX_BYTES=200
for _ in 1 2 3 4 5 6; do echo "sha256:aaa" > "$FAKE/running_id"
  env PATH="$tmp/bin:$PATH" CYBERGRAM_UPDATE_LOG="$FAKE/log" CYBERGRAM_UPDATE_LOCK="$FAKE/lock" CYBERGRAM_COMPOSE_FILE="$FAKE/docker-compose.yml" \
    CYBERGRAM_UPDATE_LOG_MAX_BYTES=200 "$root/tools/server/auto_update.sh" > /dev/null 2>&1; done
(( $(wc -c < "$FAKE/log") <= 200 )); check "log stays capped" "$?"
exit $((fails > 0))
