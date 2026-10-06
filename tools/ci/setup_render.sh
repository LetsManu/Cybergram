#!/usr/bin/env bash
# Render setup for screenshots in a GPU-less VM (docs/visual-verification.md):
# Mesa lavapipe (software Vulkan, so Godot runs Forward+ like the game) + xvfb.
# Idempotent. Prints the ICD path to export as VK_ICD_FILENAMES.
set -euo pipefail
icd=/usr/share/vulkan/icd.d/lvp_icd.json
if [[ ! -f "$icd" ]] || ! command -v xvfb-run >/dev/null; then
  sudo_cmd=""; [[ $(id -u) -ne 0 ]] && sudo_cmd="sudo"
  $sudo_cmd apt-get install -y -q mesa-vulkan-drivers xvfb >/dev/null 2>&1 || {
    $sudo_cmd apt-get update -q >/dev/null && $sudo_cmd apt-get install -y -q mesa-vulkan-drivers xvfb >/dev/null; }
fi
[[ -f "$icd" ]] || { echo "setup_render: lavapipe ICD missing after install" >&2; exit 1; }
echo "$icd"
