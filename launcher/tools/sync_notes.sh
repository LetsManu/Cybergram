#!/usr/bin/env bash
# Copies production/releases/v*.md into launcher/assets/notes/ (bundled patch
# notes for the launcher's NOTES history; images referenced by notes go there
# too). Run before a launcher build.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
mkdir -p "$here/assets/notes"
cp "$repo"/production/releases/v*.md "$here/assets/notes/"
echo "synced $(ls "$here"/assets/notes/v*.md | wc -l) notes"
