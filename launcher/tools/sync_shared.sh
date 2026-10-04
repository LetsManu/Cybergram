#!/usr/bin/env bash
# Copies the game's login/networking scripts (launcher/tools/shared_files.txt)
# into launcher/src/shared/ so the launcher speaks the exact same protocol
# instead of a fork. Run before exporting the launcher (build.yml does) and
# after changing any listed file. `--check` only compares (exit 1 on drift).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
list="$root/launcher/tools/shared_files.txt"
dest="$root/launcher/src/shared"
check=0; [[ "${1:-}" == "--check" ]] && check=1
mkdir -p "$dest"
drift=0
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  src="$root/$line"
  [[ -f "$src" ]] || { echo "missing source: $line" >&2; exit 2; }
  dst="$dest/$(basename "$line")"
  if [[ $check == 1 ]]; then
    cmp -s "$src" "$dst" || { echo "DRIFT: $line" >&2; drift=1; }
  else
    cp "$src" "$dst"
  fi
done < "$list"
[[ $check == 1 ]] && exit "$drift"
echo "synced $(grep -vc '^#\|^$' "$list") files into launcher/src/shared/"
