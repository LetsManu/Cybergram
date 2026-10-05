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
# Path-preserving UI kit files (+ sibling .import/.uid companions).
tree="$root/launcher/tools/shared_tree_files.txt"
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  for rel in "$line" "$line.import" "$line.uid"; do
    src="$root/$rel"
    [[ -f "$src" ]] || { [[ "$rel" == "$line" ]] && { echo "missing source: $line" >&2; exit 2; }; continue; }
    dst="$root/launcher/$rel"
    if [[ $check == 1 ]]; then
      cmp -s "$src" "$dst" || { echo "DRIFT: $rel" >&2; drift=1; }
    else
      mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"
    fi
  done
done < "$tree"
[[ $check == 1 ]] && exit "$drift"
echo "synced $(grep -vc '^#\|^$' "$list") flat files into launcher/src/shared/ and $(grep -vc '^#\|^$' "$tree") UI kit files (same paths) under launcher/"
