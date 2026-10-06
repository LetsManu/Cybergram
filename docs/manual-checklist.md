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

## P3: hero select
Evidence (virtual display): `production/qa/evidence/p3-select/`.
- [ ] Ranked draft: clicking a hero shows "Wants <hero>" to teammates, not to enemies (two machines).
- [ ] A teammate's hovered hero is greyed for you; locking it is refused.
- [ ] Normal blind pick: enemy cards stay empty until everyone has locked, then all heroes appear.
- [ ] Trade window: "Trade with …" buttons, the offer shows as "Accept: … offers …" for the teammate, accepting swaps the heroes; buttons disappear in the last 5 s.
- [ ] Ranked: let the timer run out without clicking any hero: lobby cancels, you get the dodge lockout in the status bar, others go back to the queue.
- [ ] Ready check popup counts 12 s.
