#!/usr/bin/env bash
# W15-ONLINE local end-to-end run: two headless game servers (DTLS with a
# throw-away self-signed certificate, and plain/guest-only), then the
# launcher's login e2e (login, launch token hand-over, redeem once, reuse
# refused; plain: no password, no token). Exit 0 = everything held.
#   launcher/tests/online_e2e.sh            (needs godot on PATH and openssl)
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$here/.." && pwd)"
godot="${GODOT:-godot}"
tmp="$(mktemp -d)"
fails=0
ok() { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$tmp/tls" "$tmp/acc" "$tmp/acc2" "$tmp/out"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/tls/key.pem" -out "$tmp/tls/cert.pem" -subj "/CN=localhost" -days 1 > /dev/null 2>&1
srv() { # <port> <datadir> [extra...]
  local port="$1" dd="$2"; shift 2
  "$godot" --headless --path "$root" -- --server --port "$port" --max-clients 4 --data-dir "$dd" "$@" > "$tmp/game_$port.log" 2>&1 &
  echo $!
}
s1=$(srv 7793 "$tmp/acc" --tls-cert "$tmp/tls/cert.pem" --tls-key "$tmp/tls/key.pem")
s2=$(srv 7794 "$tmp/acc2")
for _ in $(seq 1 90); do grep -q "open on UDP 7793" "$tmp/game_7793.log" && grep -q "open on UDP 7794" "$tmp/game_7794.log" && break; sleep 0.5; done
login() { timeout 90 "$godot" --headless --path "$here" -s tests/login_e2e.gd -- "$@" 2>&1 | grep -a "LOGIN-E2E"; }
res="$(login secure 127.0.0.1:7793 "$tmp/out" "$here/tests/stub_game.sh" --dtls-insecure)"; echo "$res"
echo "$res" | grep -q "LOGIN-E2E: PASS" && ok "secure login and launch token hand-over" || bad "secure login hand-over"
res="$(login plain 127.0.0.1:7794 "$tmp/out" "$here/tests/stub_game.sh")"; echo "$res"
echo "$res" | grep -q "LOGIN-E2E: PASS" && ok "plain server: no password, no launch token" || bad "plain server behaviour"
if grep -aq "$(cat "$tmp/out/env_token.txt" 2>/dev/null || echo none)" "$tmp/game_7793.log"; then bad "token text in the server log"; else ok "token never logged"; fi
kill "$s1" "$s2" 2>/dev/null
wait 2>/dev/null
echo
[[ "$fails" == 0 ]] && echo "ONLINE E2E PASS" || echo "ONLINE E2E FAILED ($fails)"
exit "$fails"
