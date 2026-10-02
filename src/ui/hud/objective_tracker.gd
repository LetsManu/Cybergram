class_name ObjectiveTracker
extends HudWidget
## Objective tracker, right side (design/ux/hud.md §4.9): the task the player
## stands in, else the nearest within `tuning.tracker_range_m`. Task icon +
## verb (HOLD / PLANT / BREACH), hardpoint name, progress bar + %, state text
## (CAPTURING / ENEMY CAPTURING / CONTESTED / OVERTIME / LOCKED / HELD) and the
## distance when outside. Presence counts are not replicated yet (deviation).

const VERB_KEYS: Array[String] = ["HUD_TASK_HOLD", "HUD_TASK_PLANT", "HUD_TASK_BREACH"]
const W: float = 316.0
const H: float = 92.0


func _draw() -> void:
	var c := ctx.client
	if c == null or c.hardpoints.is_empty() or c.body == null:
		return
	var defs := c.hardpoint_defs()
	var idx := c.own_hardpoint_index()
	var dist := 0.0
	if idx < 0:
		var best := ctx.tuning.tracker_range_m
		var p := c.body.state.position
		for i in defs.size():
			var d := Vector2(p.x - defs[i].position.x, p.z - defs[i].position.z).length() - defs[i].zone_radius
			if d < best:
				best = d
				idx = i
		dist = best
	if idx < 0 or idx >= c.hardpoints.size():
		return
	var st := c.hardpoints[idx]
	var def := defs[idx]
	var team := ctx.own_team()
	var x := size.x - W
	panel(Rect2(x, 0.0, W, H))
	var icon_c := Vector2(x + 24.0, 24.0)
	var col := ctx.team_color(st.owner)
	match def.task:
		HardpointDef.TaskKind.PLANT:
			draw_rect(Rect2(icon_c - Vector2(9, 9), Vector2(18, 18)), col)
		HardpointDef.TaskKind.BREACH:
			draw_colored_polygon(PackedVector2Array([icon_c + Vector2(0, -10), icon_c + Vector2(10, 8), icon_c + Vector2(-10, 8)]), col)
		_:
			draw_circle(icon_c, 10.0, col)
	draw_arc(icon_c, 12.0, 0.0, TAU, 24, Color(1, 1, 1, 0.7), 1.5, true)
	text(tr(VERB_KEYS[clampi(def.task, 0, 2)]), Vector2(x + 44.0, 30.0), 18, HudPalette.TEXT, ctx.font_display)
	var verb_w := text_width(tr(VERB_KEYS[clampi(def.task, 0, 2)]), 18, ctx.font_display)
	text(def.display_name, Vector2(x + 54.0 + verb_w, 30.0), 16, HudPalette.TEXT_DIM, ctx.font_body, HORIZONTAL_ALIGNMENT_LEFT,
		W - 64.0 - verb_w)
	var br := Rect2(x + 14.0, 44.0, W - 80.0, 10.0)
	bar(br, st.progress, ctx.team_color(st.capturing_team))
	text("%d%%" % floori(st.progress * 100.0), Vector2(br.end.x + 8.0, 55.0), 16, HudPalette.TEXT, ctx.font_numbers)
	var state := ""
	var scol := HudPalette.TEXT
	if st.locked[team]:
		state = tr("HUD_STATE_LOCKED")
		scol = HudPalette.TEXT_OFF
	elif st.contested:
		state = tr("HUD_STATE_CONTESTED")
		scol = HudPalette.WARN
	elif st.overtime:
		state = tr("HUD_STATE_OVERTIME")
		scol = HudPalette.WARN
	elif st.progress > 0.0:
		state = tr("HUD_STATE_CAPTURING") if st.capturing_team == team else tr("HUD_STATE_ENEMY_CAPTURING")
		scol = ctx.team_color(st.capturing_team).lightened(0.3)
	elif st.owner == team:
		state = tr("HUD_STATE_HELD")
	text(state, Vector2(x + 14.0, 80.0), 15, scol, ctx.font_display)
	if dist > 0.0:
		text(tr("HUD_DISTANCE_M") % ceili(dist), Vector2(x, 80.0), 14, HudPalette.TEXT_DIM, ctx.font_body,
			HORIZONTAL_ALIGNMENT_RIGHT, W - 14.0)
