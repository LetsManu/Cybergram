class_name DeathScreen
extends HudWidget
## Death & respawn screen (design/ux/hud.md §9, slice subset): KILLED BY
## [glyph] killer (team colour + shape), large RESPAWN IN timer (C11 timing is
## server-side; this shows the replicated respawn tick), spawn selection
## Sanctum [1] (always: squad + Armory) / Mid Beacon [2] (only when held and
## not under attack; greyed with the reason), the selected option marked, and
## the skill-point hint (points can be spent while dead, C12). Gamepad: D-pad
## Left / Right select. Shown only while the own hero is dead.
## Sends spawn choice through PlayerInputSource.request_action only.
## v0.12 (hud-v0.12.md §2): centred, no box, over the greyscale backdrop
## (HudScrims): KILLED BY, the killer's face (84 px, team ring), glyph + name in
## caps 36 and the hero name; RESPAWN IN with 126 brass-hi numerals; spawn
## options as cut-corner cells (selected = brass rim, unavailable = 45% with the
## reason in warn); the +SP hint with its key chip.

const W: float = 760.0

var _keys: Dictionary = {}


## Spawn-choice keys (edge-triggered); called by HudRoot each frame.
func poll() -> void:
	var client := ctx.client
	if client == null or not client.is_dead() or client.player_input == null:
		return
	if _edge(KEY_1, false) or _edge(JOY_BUTTON_DPAD_LEFT, true):
		client.player_input.request_action(InputCommand.ACTION_SPAWN_CHOICE, HeroProgress.SPAWN_SANCTUM)
	if _edge(KEY_2, false) or _edge(JOY_BUTTON_DPAD_RIGHT, true):
		client.player_input.request_action(InputCommand.ACTION_SPAWN_CHOICE, HeroProgress.SPAWN_BEACON)


func _edge(code: int, joy: bool) -> bool:
	var down := Input.is_joy_button_pressed(0, code) if joy else Input.is_physical_key_pressed(code)
	var id := code + (1000 if joy else 0)
	var was: bool = _keys.get(id, false)
	_keys[id] = down
	return down and not was


func _draw() -> void:
	var client := ctx.client
	if client == null or not client.is_dead():
		return
	var cx := size.x * 0.5
	var y := 24.0
	var killer_id := ctx.roster.last_killer_id
	if killer_id != 0:
		caps_c(tr("HUD_KILLED_BY"), Vector2(cx, y), 16, HudPalette.MUTED, 0.3)
		var team := ctx.roster.team_of(killer_id)
		var h := ctx.roster.hero(killer_id)
		var name := ctx.roster.name_of(killer_id)
		if name == "":
			name = tr("HUD_HERO_N") % killer_id
		var hero := hero_name(h.hero_id) if h != null else ""
		var nw := caps_width(name, 36, 0.1)
		var sub := hero
		var sw := text_width(sub, 18)
		var block := 84.0 + 21.0 + 27.0 + maxf(nw, sw)
		var x0 := cx - block * 0.5
		var fc := Vector2(x0 + 42.0, y + 75.0)
		face_circle(fc, 42.0, h.hero_id if h != null else &"")
		draw_arc(fc, 43.5, 0.0, TAU, 40, ctx.team_color(team), 3.0, true)
		var tx := x0 + 84.0 + 21.0
		team_glyph(Vector2(tx + 9.0, y + 64.0), 9.0, team)
		caps(name, Vector2(tx + 27.0, y + 77.0), 36, HudPalette.IVORY, 0.1)
		if sub != "":
			text(sub, Vector2(tx + 27.0, y + 104.0), 18, HudPalette.MUTED)
		y += 150.0
	else:
		caps_c(tr("HUD_ELIMINATED"), Vector2(cx, y + 40.0), 24, HudPalette.MUTED, 0.3)
		y += 90.0
	caps_c(tr("HUD_RESPAWN_IN_CAPS"), Vector2(cx, y + 18.0), 16, HudPalette.MUTED, 0.22)
	var secs := str(HudFormat.seconds_up(client.respawn_seconds_left()))
	text(secs, Vector2(0.0, y + 130.0), 126, HudPalette.BRASS_HI, ctx.font_numbers, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	y += 180.0
	var p := client.progress
	if p == null:
		return
	var beacon := (p.flags & SnapshotData.ProgressState.FLAG_SPAWN_BEACON) != 0
	var ready := (p.flags & SnapshotData.ProgressState.FLAG_BEACON_READY) != 0
	var ow := 354.0
	_option(Rect2(cx - ow - 12.0, y, ow, 90.0), "1", tr("HUD_SPAWN_SANCTUM"), tr("HUD_SPAWN_SANCTUM_DESC"), not beacon, true)
	var desc := tr("HUD_SPAWN_BEACON_DESC") if ready else tr("HUD_SPAWN_BEACON_UNAVAILABLE")
	_option(Rect2(cx + 12.0, y, ow, 90.0), "2", tr("HUD_SPAWN_BEACON"), desc, beacon, ready)
	y += 123.0
	if p.skill_points > 0:
		var hint := tr("HUD_SP_DEAD_HINT")
		var cw := text_width(tr("HUD_SP_BADGE") % p.skill_points, 16, ctx.font_numbers) + 30.0
		var hw := text_width(hint, 19)
		var kl := ctx.key_label(&"quick_spend", "Alt")
		var total := cw + 15.0 + hw + 15.0 + 40.0
		var hx := cx - total * 0.5
		var bw := brass_chip(Vector2(hx, y), tr("HUD_SP_BADGE") % p.skill_points, 16)
		text(hint, Vector2(hx + bw + 15.0, y + ts(19) * 0.36), 19, HudPalette.MUTED)
		key_chip(Vector2(hx + bw + 15.0 + hw + 15.0 + 20.0, y), kl, 30.0)


## Spawn option: cut-corner cell, key chip, caps title, description; selected =
## brass rim; unavailable = 45% with the reason in warn.
func _option(r: Rect2, key: String, title: String, desc: String, chosen: bool, enabled: bool) -> void:
	var a := 1.0 if enabled else 0.45
	cut_fill(r, 12.0, Color(HudPalette.INK_DEEP, 0.55))
	cut_line(r, 12.0, HudPalette.BRASS if chosen else HudPalette.HAIR_STRONG, 3.0 if chosen else 1.5)
	key_chip(Vector2(r.position.x + 39.0, r.position.y + 33.0), key, 30.0, a)
	caps(title, Vector2(r.position.x + 69.0, r.position.y + 39.0), 19, Color(HudPalette.IVORY, a), 0.2)
	text(desc, Vector2(r.position.x + 69.0, r.position.y + 67.0), 18, HudPalette.MUTED if enabled else HudPalette.WARN_UI)
