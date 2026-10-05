#!/usr/bin/env bash
# Authenticode-signs Windows executables with osslsigncode (apt install osslsigncode).
# Usage: installer/sign_windows.sh <file.exe>...
#
# Reads the certificate from the environment (GitHub Actions secrets):
#   WINDOWS_SIGN_PFX_B64   base64 of the .pfx / .p12 file (code signing cert + private key)
#   WINDOWS_SIGN_PASSWORD  the .pfx password
# When WINDOWS_SIGN_PFX_B64 is empty, it prints a notice and exits 0, so unsigned
# builds keep working until the owner adds the secrets. See docs/INSTALL.md.
set -euo pipefail
[[ $# -ge 1 ]] || { echo "usage: $0 <file.exe>..." >&2; exit 2; }
if [[ -z "${WINDOWS_SIGN_PFX_B64:-}" ]]; then
  echo "sign_windows: no WINDOWS_SIGN_PFX_B64 secret, leaving files unsigned"
  exit 0
fi
command -v osslsigncode >/dev/null || { echo "sign_windows: osslsigncode not installed" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pfx="$tmp/cert.pfx"
printf '%s' "$WINDOWS_SIGN_PFX_B64" | base64 -d > "$pfx"
# Timestamping keeps the signature valid after the cert expires; try a second server if one is down.
read -r -a ts_urls <<< "${WINDOWS_SIGN_TIMESTAMP_URL:-http://timestamp.digicert.com http://timestamp.sectigo.com}"
for f in "$@"; do
  ok=0
  for ts in "${ts_urls[@]}"; do
    rm -f "$tmp/signed.exe"
    if osslsigncode sign -pkcs12 "$pfx" -pass "${WINDOWS_SIGN_PASSWORD:-}" -h sha256 \
        -n "Cybergram" -i "https://github.com/LetsManu/Cybergram" -t "$ts" \
        -in "$f" -out "$tmp/signed.exe" >/dev/null && [[ -s "$tmp/signed.exe" ]]; then ok=1; break; fi
    echo "sign_windows: timestamp server $ts failed, trying the next one" >&2
  done
  [[ $ok -eq 1 ]] || { echo "sign_windows: could not sign $f" >&2; exit 1; }
  mv "$tmp/signed.exe" "$f"
  # A cert the runner doesn't trust (e.g. self-signed test cert) fails verify; warn, don't fail.
  osslsigncode verify -in "$f" >/dev/null 2>&1 || echo "sign_windows: warning: verify failed for $f (untrusted chain?)"
  echo "sign_windows: signed $f"
done
