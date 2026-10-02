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

const W: float = 600.0
const H: float = 214.0

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
	var r := Rect2(Vector2((size.x - W) * 0.5, 0.0), Vector2(W, H))
	panel(r, ctx.panel_strong)
	var x := r.position.x + 22.0
	var killer_id := ctx.roster.last_killer_id
	if killer_id != 0:
		text(tr("HUD_KILLED_BY"), Vector2(x, r.position.y + 32.0), 15, HudPalette.TEXT_DIM, ctx.font_display)
		var kw := text_width(tr("HUD_KILLED_BY"), 15, ctx.font_display)
		var team := ctx.roster.team_of(killer_id)
		team_glyph(Vector2(x + kw + 16.0, r.position.y + 26.0), 7.0, team)
		var name := ctx.roster.name_of(killer_id)
		if name == "":
			name = tr("HUD_HERO_N") % killer_id
		text(name, Vector2(x + kw + 30.0, r.position.y + 33.0), 20, ctx.team_color(team).lightened(0.4), ctx.font_display)
	else:
		text(tr("HUD_ELIMINATED"), Vector2(x, r.position.y + 32.0), 18, HudPalette.TEXT_DIM, ctx.font_display)
	var secs := HudFormat.seconds_up(client.respawn_seconds_left())
	text(tr("HUD_RESPAWN_IN") % secs, Vector2(x, r.position.y + 80.0), 38, HudPalette.TEXT, ctx.font_numbers)
	var p := client.progress
	if p == null:
		return
	var beacon := (p.flags & SnapshotData.ProgressState.FLAG_SPAWN_BEACON) != 0
	var ready := (p.flags & SnapshotData.ProgressState.FLAG_BEACON_READY) != 0
	_option(Vector2(x, r.position.y + 118.0), "1", tr("HUD_SPAWN_SANCTUM"), tr("HUD_SPAWN_SANCTUM_DESC"), not beacon, true)
	var desc := tr("HUD_SPAWN_BEACON_DESC") if ready else tr("HUD_SPAWN_BEACON_UNAVAILABLE")
	_option(Vector2(x, r.position.y + 162.0), "2", tr("HUD_SPAWN_BEACON"), desc, beacon, ready)
	if p.skill_points > 0:
		text(tr("HUD_SP_HINT") % p.skill_points, Vector2(r.position.x, r.position.y + 32.0), 14, HudPalette.SP,
			ctx.font_display, HORIZONTAL_ALIGNMENT_RIGHT, W - 22.0)


func _option(at: Vector2, key: String, title: String, desc: String, chosen: bool, enabled: bool) -> void:
	var col := HudPalette.TEXT if enabled else HudPalette.TEXT_OFF
	var box := Rect2(at + Vector2(0.0, -16.0), Vector2(W - 44.0, 38.0))
	if chosen:
		draw_rect(box, Color(1, 1, 1, 0.08))
		draw_rect(box, Color(1, 1, 1, 0.7), false, 1.5)
	draw_circle(at + Vector2(14.0, 3.0), 7.0, Color(0, 0, 0, 0.5))
	draw_arc(at + Vector2(14.0, 3.0), 7.0, 0.0, TAU, 20, col, 1.5, true)
	if chosen:
		draw_circle(at + Vector2(14.0, 3.0), 3.5, col)
	text("[%s]  %s" % [key, title], at + Vector2(30.0, 9.0), 18, col, ctx.font_display)
	var tw := text_width("[%s]  %s" % [key, title], 18, ctx.font_display)
	text(desc, at + Vector2(44.0 + tw, 9.0), 14, HudPalette.TEXT_DIM if enabled else HudPalette.TEXT_OFF)
