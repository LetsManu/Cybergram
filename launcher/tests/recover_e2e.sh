#!/usr/bin/env bash
# W21-N1 local end-to-end run: a headless game server with DTLS (throw-away
# self-signed certificate), the launcher's "Forgot password?" flow, then the
# host tool (--admin-reset-password) against the RUNNING server and a
# recovery with the code it printed. Also checks that neither codes nor
# passwords reach the server log. Exit 0 = everything held.
#   launcher/tests/recover_e2e.sh      (needs godot (GODOT) and openssl; UDP E2E_PORT, default 7810)
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$here/.." && pwd)"
godot="${GODOT:-godot}"
port="${E2E_PORT:-7810}"
tmp="$(mktemp -d)"
fails=0
ok() { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
mkdir -p "$tmp/tls" "$tmp/accounts"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/tls/key.pem" -out "$tmp/tls/cert.pem" -subj "/CN=localhost" -days 1 > /dev/null 2>&1
"$godot" --headless --path "$root" -- --server --port "$port" --max-clients 4 --data-dir "$tmp/accounts" \
  --tls-cert "$tmp/tls/cert.pem" --tls-key "$tmp/tls/key.pem" > "$tmp/server.log" 2>&1 &
srv=$!
for _ in $(seq 1 120); do grep -q "open on UDP $port" "$tmp/server.log" && break; sleep 0.5; done
run() { timeout 120 "$godot" --headless --path "$here" -s tests/recover_e2e.gd -- "$@" --dtls-insecure 2>&1 | grep -a "RECOVER-E2E"; }
res="$(run recover "127.0.0.1:$port")"; echo "$res"
echo "$res" | grep -q "RECOVER-E2E: PASS" && ok "forgot password in the launcher" || bad "forgot password in the launcher"
# The host tool, while the server runs (one Godot at a time besides the server).
out="$(timeout 120 "$godot" --headless --path "$root" --script res://src/networking/auth/account_admin_cli.gd -- \
  --admin-reset-password recuser --data-dir "$tmp/accounts" 2>&1)"
echo "$out" | grep -av "^Godot Engine\|^$" | sed 's/^/    /' | sed -E 's/[0-9A-Z]{5}-[0-9A-Z]{5}-[0-9A-Z]{5}-[0-9A-Z]{5}/<code hidden in this log>/'
code="$(echo "$out" | grep -aoE '[0-9A-Z]{5}-[0-9A-Z]{5}-[0-9A-Z]{5}-[0-9A-Z]{5}' | head -n 1)"
echo "$out" | grep -q "Done: the old password" && ok "running server applied the host reset" || bad "host reset not applied"
[[ -n "$code" ]] && ok "host tool printed a code" || bad "no code printed"
res="$(run admin "127.0.0.1:$port" "$code")"; echo "$res"
echo "$res" | grep -q "RECOVER-E2E: PASS" && ok "recovery with the host's code" || bad "recovery with the host's code"
nope="$(timeout 60 "$godot" --headless --path "$root" --script res://src/networking/auth/account_admin_cli.gd -- \
  --admin-reset-password nobody --data-dir "$tmp/accounts" 2>&1; echo "exit=$?")"
echo "$nope" | grep -q "exit=2" && ok "unknown username: exit 2, no code" || bad "unknown username handling"
if [[ -n "$code" ]] && grep -aq "$code" "$tmp/server.log"; then bad "code in the server log"; else ok "code never logged"; fi
if grep -aqE "first-password|second-password|third-password|recuser" "$tmp/server.log"; then bad "password or username in the server log"; else ok "no password or username in the server log"; fi
grep -a "\[accounts\]" "$tmp/server.log" | tail -c 2000
kill "$srv" 2>/dev/null
wait "$srv" 2>/dev/null
rm -rf "$tmp"
echo
[[ "$fails" == 0 ]] && echo "RECOVER E2E PASS" || echo "RECOVER E2E FAILED ($fails)"
exit "$fails"
