#!/usr/bin/env bash
# Matchmaking end-to-end (W17B-OPS): the exported server in front mode, two
# scripted headless clients, queue -> ready -> draft -> join match process ->
# result -> rating change; then a crash-void case (kill only the match PID this
# script saw spawned, no rating change).
#   GAME=build/linux/Cybergram.x86_64 tools/ci/matchmaking_e2e.sh
#
# Contract (W17B-SRV): front flags --front --mm-team-size 1 --mm-pick-s 3
# --mm-match-s 20, scripted client --mm-script-client <win|crash> --connect
# host:port --user name (exit 0 on the expected result). Front log lines:
# match_started id= pid=, match_result ... changes=, match_voided, drained.
# Runs the exported binary (GAME=...) or, without it, the project from source
# (GODOT=godot). Only PIDs started here are ever signalled; no pkill.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
GAME="${GAME:-$root/build/linux/Cybergram.x86_64}"
if [[ -x "$GAME" ]]; then game() { "$GAME" --headless -- "$@"; }
else game() { "${GODOT:-godot}" --headless --path "$root" -- "$@"; }; fi
grep -q -- '"--front"' "$root/src/core/app/launch_config.gd" || { echo "FAIL: no --front in launch_config.gd"; exit 1; }

work="$(mktemp -d)"; pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT
mkdir -p "$work/data/accounts" "$work/data/ratings" "$work/data/reports"
port=17777; mport=17800
export CYBERGRAM_DATA_DIR="$work/data/accounts" CYBERGRAM_RATINGS_DIR="$work/data/ratings" \
  CYBERGRAM_REPORTS_DIR="$work/data/reports" CYBERGRAM_MATCH_PORTS="$mport-$((mport+1))" CYBERGRAM_WARM_POOL=1 \
  CYBERGRAM_MAX_MATCHES=1 CYBERGRAM_HEALTH_FILE="$work/health.json" CYBERGRAM_DRAIN_FILE="$work/drain" \
  CYBERGRAM_RATE_GUESTS=1 CYBERGRAM_MM_DIR="$work/data/mm" CYBERGRAM_TICKET_KEYS="k1:$(openssl rand -hex 32)" CYBERGRAM_STATUS_FILE="$work/status.json"
fails=0
expect() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1 (no '$2' in $3)"; fails=$((fails+1)); tail -15 "$3"; fi; }
wait_for() { for _ in $(seq 1 "$3"); do grep -q -- "$2" "$1" 2>/dev/null && return 0; sleep 1; done; return 1; }

start_front() {
  game --server --front --port "$port" --max-clients 8 --mm-team-size 1 --mm-pick-s 3 --mm-match-s 20 > "$work/front.log" 2>&1 &
  front=$!; pids+=("$front")
  wait_for "$work/front.log" "\[front\] listening on UDP $port" 60 || { echo "FAIL front did not start"; tail -20 "$work/front.log"; exit 1; }
}
run_clients() {  # $1 = scenario
  cl=()
  for n in 1 2; do
    game --mm-script-client "$1" --connect "127.0.0.1:$port" --user "e2e$n" > "$work/client$n.log" 2>&1 &
    cl+=("$!"); pids+=("$!")
  done
}

# Case 1: full flow, rating changes.
start_front
expect "warm pool process ready" "\[hosting\]" "$work/front.log"
run_clients win
wait_for "$work/front.log" "match_result" 180
for p in "${cl[@]}"; do wait "$p"; rc=$?; [[ $rc -eq 0 ]] && echo "ok   client exit 0" || { echo "FAIL client exit $rc"; fails=$((fails+1)); }; done
expect "front saw a rated match result" "match_result .*voided=false rated=true" "$work/front.log"
expect "result carries rating changes" "match_result .*changes=[1-9]" "$work/front.log"
ls "$work/data/ratings"/* > /dev/null 2>&1; r=$?
[[ $r -eq 0 ]] && echo "ok   rating files written" || { echo "FAIL no rating files"; fails=$((fails+1)); }
snap="$(cat "$work/data/ratings"/* 2>/dev/null | sha256sum)"

# Case 2: crash void. Kill only the match process the front spawned.
run_clients crash
for _ in $(seq 1 120); do [[ "$(grep -c "match_started id=" "$work/front.log")" -ge 2 ]] && break; sleep 1; done
mpid="$(sed -n 's/.*match_started .*pid=\([0-9]\+\).*/\1/p' "$work/front.log" | tail -1)"
if [[ -n "$mpid" ]] && kill -0 "$mpid" 2>/dev/null; then
  kill -9 "$mpid"
  wait_for "$work/front.log" "match_voided id=" 30
  for p in "${cl[@]}"; do wait "$p" 2>/dev/null; rc=$?; [[ $rc -eq 0 ]] && echo "ok   crash client exit 0" || echo "note crash client exit $rc"; done
  expect "crash voided" "match_voided" "$work/front.log"
  [[ "$(cat "$work/data/ratings"/* | sha256sum)" == "$snap" ]] && echo "ok   no rating change on void" || { echo "FAIL rating changed on void"; fails=$((fails+1)); }
else
  echo "FAIL could not find the match pid in the front log"; fails=$((fails+1))
fi
touch "$work/drain"; wait_for "$work/front.log" "drained: exiting" 30 || true
exit $((fails > 0))
