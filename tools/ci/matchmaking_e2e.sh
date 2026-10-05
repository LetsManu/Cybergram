#!/usr/bin/env bash
# Matchmaking end-to-end (W17B-OPS): the exported server in front mode, two
# scripted headless clients, queue -> ready -> draft -> join match process ->
# result -> rating change; then a crash-void case (kill only the match PID this
# script saw spawned, no rating change).
#   GAME=build/linux/Cybergram.x86_64 tools/ci/matchmaking_e2e.sh
#
# PENDING GATE: the front (--front, --match-host) and the scripted client come
# from chunk W17B-SRV. Until the flags exist in src/core/app/launch_config.gd
# this script prints "PENDING" and exits 0, so CI stays green. Set
# E2E_REQUIRE=1 to make a missing flag a failure (flip it on once SRV merged).
# Client flag names below are the documented placeholders: adjust CLIENT_FLAG
# and CLIENT_ARGS when SRV's tooling lands.
# Only PIDs started here are ever signalled; no pkill.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
GAME="${GAME:-$root/build/linux/Cybergram.x86_64}"
CLIENT_FLAG="${CLIENT_FLAG:---mm-script-client}"
cfg="$root/src/core/app/launch_config.gd"
missing=()
for f in "--front" "${CLIENT_FLAG}"; do grep -q -- "\"$f\"\|$f" "$cfg" 2>/dev/null || missing+=("$f"); done
if (( ${#missing[@]} )); then
  echo "PENDING: matchmaking e2e needs flags not in launch_config.gd yet: ${missing[*]}"
  [[ "${E2E_REQUIRE:-0}" == "1" ]] && exit 1
  exit 0
fi
[[ -x "$GAME" ]] || { echo "no game binary at $GAME"; exit 1; }

work="$(mktemp -d)"; pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT
mkdir -p "$work/data/accounts" "$work/data/ratings" "$work/data/reports"
port=17777; mport=17800
export CYBERGRAM_DATA_DIR="$work/data/accounts" CYBERGRAM_RATINGS_DIR="$work/data/ratings" \
  CYBERGRAM_REPORTS_DIR="$work/data/reports" CYBERGRAM_MATCH_PORTS="$mport-$((mport+1))" CYBERGRAM_WARM_POOL=1 \
  CYBERGRAM_MAX_MATCHES=1 CYBERGRAM_HEALTH_FILE="$work/health.json" CYBERGRAM_DRAIN_FILE="$work/drain" \
  CYBERGRAM_TICKET_KEYS="k1:$(openssl rand -hex 32)" CYBERGRAM_STATUS_FILE="$work/status.json"
fails=0
expect() { if grep -q -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1 (no '$2' in $3)"; fails=$((fails+1)); tail -15 "$3"; fi; }
wait_for() { for _ in $(seq 1 "$3"); do grep -q -- "$2" "$1" 2>/dev/null && return 0; sleep 1; done; return 1; }

start_front() {
  "$GAME" --headless -- --server --front --port "$port" --max-clients 8 --quit-after-ticks 100000 > "$work/front.log" 2>&1 &
  front=$!; pids+=("$front")
  wait_for "$work/front.log" "listening on UDP $port" 60 || { echo "FAIL front did not start"; tail -20 "$work/front.log"; exit 1; }
}
run_clients() {  # $1 = scenario
  for n in 1 2; do
    "$GAME" --headless -- "$CLIENT_FLAG" "$1" --connect "127.0.0.1:$port" --user "e2e$n" > "$work/client$n.log" 2>&1 &
    pids+=("$!")
  done
}

# Case 1: full flow, rating changes.
start_front
expect "warm pool process ready" "\[hosting\]" "$work/front.log"
run_clients win
wait_for "$work/front.log" "match_result" 180
expect "front saw a match result" "match_result" "$work/front.log"
ls "$work/data/ratings"/* > /dev/null 2>&1; r=$?
[[ $r -eq 0 ]] && echo "ok   rating files written" || { echo "FAIL no rating files"; fails=$((fails+1)); }
snap="$(cat "$work/data/ratings"/* 2>/dev/null | sha256sum)"

# Case 2: crash void. Kill only the match process the front spawned.
run_clients crash
wait_for "$work/front.log" "match_started" 120
mpid="$(sed -n 's/.*match_started.*pid[= ]\([0-9]\+\).*/\1/p' "$work/front.log" | tail -1)"
if [[ -n "$mpid" ]] && kill -0 "$mpid" 2>/dev/null; then
  kill -9 "$mpid"
  wait_for "$work/front.log" "match_voided" 30
  expect "crash voided" "match_voided" "$work/front.log"
  [[ "$(cat "$work/data/ratings"/* | sha256sum)" == "$snap" ]] && echo "ok   no rating change on void" || { echo "FAIL rating changed on void"; fails=$((fails+1)); }
else
  echo "FAIL could not find the match pid in the front log"; fails=$((fails+1))
fi
touch "$work/drain"; wait_for "$work/front.log" "drained" 30 || true
exit $((fails > 0))
