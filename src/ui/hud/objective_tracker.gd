class_name ObjectiveTracker
extends HudWidget
## Objective tracker, right side (design/ux/hud.md §4.9): the task the player
## stands in, else the nearest within `tuning.tracker_range_m`. Task icon +
## verb (HOLD / PLANT / BREACH), hardpoint name, progress bar + %, state text
## (CAPTURING / ENEMY CAPTURING / CONTESTED / OVERTIME / LOCKED / HELD) and the
## distance when outside. Presence counts are not replicated yet (deviation).
## v0.12 (hud-v0.12.md §2): no box; a 3 px left rule in the owner's colour, the
## task glyph (shape = task, fill = ownership), the verb in caps 22, the
## hardpoint + "in zone" / distance muted, a 4 px progress bar, the state in caps
## (CONTESTED pulses, static with reduce motion / effects 0) and the %. Idle:
## collapses to the glyph, verb and place.

const VERB_KEYS: Array[String] = ["HUD_TASK_HOLD", "HUD_TASK_PLANT", "HUD_TASK_BREACH"]
const W: float = 366.0
const H: float = 86.0

var _t: float = 0.0


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
	var collapsed := ctx.idle_k > 0.5
	var rule_col := ctx.team_color(st.owner) if st.owner >= 0 and st.owner <= 1 else HudPalette.IVORY
	draw_rect(Rect2(x, 0.0, 3.0, 36.0 if collapsed else H), rule_col)
	var gx := x + 30.0
	task_chip(Vector2(gx, 18.0), 21.0, def.task, ownership(st.owner, team), ctx.team_color(st.owner), false)
	var verb := tr(VERB_KEYS[clampi(def.task, 0, 2)])
	caps(verb, Vector2(gx + 24.0, 26.0), 22, HudPalette.IVORY, 0.2)
	var where := def.display_name
	where += " · " + (tr("HUD_IN_ZONE") if dist <= 0.0 else tr("HUD_DISTANCE_M") % ceili(dist))
	var vw := caps_width(verb, 22, 0.2)
	text(where, Vector2(gx + 36.0 + vw, 25.0), 18, HudPalette.MUTED, ctx.font_body, HORIZONTAL_ALIGNMENT_RIGHT,
		size.x - (gx + 36.0 + vw))
	if collapsed:
		return
	var cap_col := ctx.team_color(st.capturing_team) if st.capturing_team >= 0 else HudPalette.IVORY
	bar(Rect2(x + 21.0, 44.0, W - 21.0, 4.0), st.progress, cap_col)
	var state := ""
	var scol := HudPalette.IVORY
	if st.locked[team]:
		state = tr("HUD_STATE_LOCKED")
		scol = HudPalette.DIM
	elif st.contested:
		state = tr("HUD_STATE_CONTESTED")
		scol = Color(HudPalette.IVORY, pulse(_t, 1.2, 0.45))
	elif st.overtime:
		state = tr("HUD_STATE_OVERTIME")
		scol = HudPalette.WARN_UI
	elif st.progress > 0.0:
		state = tr("HUD_STATE_CAPTURING") if st.capturing_team == team else tr("HUD_STATE_ENEMY_CAPTURING")
	elif st.owner == team:
		state = tr("HUD_STATE_HELD")
	var sx := x + 21.0
	if state != "":
		caps(state, Vector2(sx, 76.0), 16, scol, 0.2)
		sx += caps_width(state, 16, 0.2) + 15.0
	if st.progress > 0.0 or state == "":
		text("%d%%" % floori(st.progress * 100.0), Vector2(sx, 76.0), 18, HudPalette.IVORY, ctx.font_numbers)


func _process(delta: float) -> void:
	_t += delta
	super(delta)
