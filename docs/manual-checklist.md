# Manual checks (need a human with a real display)

The cloud session renders only under a virtual display (software OpenGL,
fixed 1280x720) and cannot try a real server, a controller or another
resolution. Everything below is unverified by a person until ticked.

## P1: status bar and diagnostics (game menu, Play)
Evidence from the virtual display: `production/qa/evidence/p1-status/`.
- [ ] Bar readable at 1080p and 1440p, and at 1280x720 window (text not clipped).
- [ ] "Online" + ping shows a sensible number against cyber.djboeck.at.
- [ ] Queue on the live server: bar shows "In queue", timer counts, "~estimate" matches the page.
- [ ] Pull the network cable while queued: bar turns red "Connection lost" with the reconnect hint, no endless spinner.
- [ ] Decline a ready check: bar shows "Queue locked: m:ss" counting down and the hint.
- [ ] Diagnostics button: panel opens above the bar, lists events, "Copy" puts text on the clipboard; paste it somewhere and check it has no ticket or password.
- [ ] Keyboard: Tab reaches "Diagnostics"; controller: focus reaches it.
- [ ] The bar does not hide buttons at the bottom of any matchmaking page (play, ready, draft, all random, loading, post-match, custom).

## P1: server operations
- [ ] On the NAS: `curl -s localhost:8090/health` answers `"status":"ok"` after `CYBERGRAM_IMAGE_TAG` with protocol 20 is deployed.
- [ ] `/metrics` scraped by Icinga / Prometheus; thresholds from docs/monitoring.md.
- [ ] `/admin` in a browser asks for a password; with `CYBERGRAM_ADMIN_TOKEN` it shows queues, players (tags only), events.
- [ ] `docker logs cybergram` shows JSON lines with `player` tags, no names.
