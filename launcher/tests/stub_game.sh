#!/usr/bin/env bash
# Stand-in for the game in login_e2e.gd: records what it inherited.
out="$1"
printf '%s' "${CYBERGRAM_SESSION_TOKEN:-}" > "$out/env_token.txt"
printf '%s' "${CYBERGRAM_SESSION_SERVER:-}" > "$out/env_server.txt"
tr '\0' ' ' < /proc/$$/cmdline > "$out/cmdline.txt"
