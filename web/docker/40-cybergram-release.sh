#!/bin/sh
# Cybergram website (W20-WEB): fetches the latest GitHub release info into a
# local JSON file served as /data/release.json, at start and then every
# CYBERGRAM_RELEASE_REFRESH_S seconds (default 6 h). The visitor's browser
# never calls GitHub for this (privacy page). On any failure the previous
# file stays; without one, the home page shows the static releases link.
#   CYBERGRAM_RELEASE_FETCH=0   switch fetching off (offline hosts, CI)
#   CYBERGRAM_GITHUB_REPO       owner/repo (default LetsManu/Cybergram)
out=/var/cache/cybergram-web/release.json
repo="${CYBERGRAM_GITHUB_REPO:-LetsManu/Cybergram}"
every="${CYBERGRAM_RELEASE_REFRESH_S:-21600}"

[ "${CYBERGRAM_RELEASE_FETCH:-1}" = "0" ] && exit 0

fetch() {
    tmp="$out.tmp"
    # Newest release first, pre-releases included (all early builds are).
    if curl -fsS --max-time 20 --max-filesize 4000000 \
            -H "Accept: application/vnd.github+json" -H "User-Agent: cybergram-web" \
            "https://api.github.com/repos/$repo/releases?per_page=1" -o "$tmp" \
            && grep -q '"tag_name"' "$tmp"; then
        mv "$tmp" "$out"
        echo "[web] release info updated"
    else
        rm -f "$tmp"
        echo "[web] release info not updated (keeping the previous file or the static link)"
    fi
}

fetch
( while sleep "$every"; do fetch; done ) </dev/null >/dev/null 2>&1 &
exit 0
