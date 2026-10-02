class_name FrontStrip
extends HudWidget
## Front-Line bar, one lane (design/ux/hud.md §4.7, slice §19), under the match
## header. Chips in lane order with the own HQ on the left; chip shape = task
## (circle Hold, square Plant, triangle Breach, art bible §6.3); ownership =
## own solid + ring glyph, enemy diagonal hatch + tooth glyph, neutral hollow
## (readable in greyscale). The front marker is a bright vertical tick after
## the own team's front chip. Contested: white outline + progress ring in the
## capturing team's colour; Overtime: "OT"; Locked: padlock.

const CHIP: float = 26.0
const GAP: float = 22.0
const HEIGHT: float = 52.0


func _draw() -> void:
	var c := ctx.client
	if c == null or c.hardpoints.is_empty():
		return
	var defs := c.hardpoint_defs()
	var states := c.hardpoints
	var team := ctx.own_team()
	var n := states.size()
	var total := n * CHIP + (n - 1) * GAP
	var x0 := (size.x - total) * 0.5
	panel(Rect2(x0 - 18.0, 0.0, total + 36.0, HEIGHT))
	var front := c.fronts[team] if c.fronts.size() > team else -1
	for k in n:
		var i := k if team == MapDef.TEAM_CONCORD else n - 1 - k
		var st := states[i]
		var center := Vector2(x0 + k * (CHIP + GAP) + CHIP * 0.5, 18.0)
		var task: int = defs[i].task if i < defs.size() else HardpointDef.TaskKind.HOLD
		_chip(center, task, st, team)
		var tag := String(defs[i].id).trim_prefix("s_").to_upper() if i < defs.size() else str(i)
		text_c(tag, center + Vector2(0.0, 25.0), 11, HudPalette.TEXT_DIM, ctx.font_display)
		if i == front:
			var fx := center.x + CHIP * 0.5 + GAP * 0.5
			draw_line(Vector2(fx, 2.0), Vector2(fx, 34.0), Color.WHITE, 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(fx - 5.0, 38.0), Vector2(fx + 5.0, 38.0), Vector2(fx, 33.0)]),
				Color.WHITE)


func _chip(c: Vector2, task: int, st: SnapshotData.HardpointState, team: int) -> void:
	var r := CHIP * 0.5
	var pts := _shape(c, r, task)
	var owner := st.owner
	var col := ctx.team_color(owner)
	if owner == team:
		draw_colored_polygon(pts, col)
		draw_arc(c, r * 0.32, 0.0, TAU, 16, Color.WHITE, 2.0, true)  # ring glyph
	elif owner >= 0:
		draw_colored_polygon(pts, Color(col, 0.35))
		var box := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		_hatch_shape(box, col, task)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -3), c + Vector2(4, -3), c + Vector2(0, 5)]), Color.WHITE)  # tooth
	else:
		draw_colored_polygon(pts, Color(0, 0, 0, 0.35))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color.WHITE if st.contested else Color(1, 1, 1, 0.55), 2.5 if st.contested else 1.5, true)
	if st.progress > 0.0 and st.capturing_team >= 0:
		draw_arc(c, r + 5.0, -PI / 2.0, -PI / 2.0 + TAU * st.progress, 32, ctx.team_color(st.capturing_team), 3.0, true)
	if st.overtime:
		text_c("OT", c + Vector2(0.0, -r - 8.0), 10, HudPalette.WARN, ctx.font_display)
	if st.locked[team]:
		var lc := c + Vector2(r * 0.7, -r * 0.7)
		draw_rect(Rect2(lc + Vector2(-4, -1), Vector2(8, 6)), HudPalette.TEXT_DIM)
		draw_arc(lc + Vector2(0, -1), 3.0, PI, TAU, 8, HudPalette.TEXT_DIM, 1.5)


func _shape(c: Vector2, r: float, task: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match task:
		HardpointDef.TaskKind.PLANT:
			pts = PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])
		HardpointDef.TaskKind.BREACH:
			pts = PackedVector2Array([c + Vector2(0, -r * 1.1), c + Vector2(r * 1.1, r * 0.85), c + Vector2(-r * 1.1, r * 0.85)])
		_:
			for k in 20:
				var a := TAU * k / 20.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Hatch lines clipped roughly to the chip (box for square, inset for others).
func _hatch_shape(box: Rect2, col: Color, task: int) -> void:
	var inset := 0.0 if task == HardpointDef.TaskKind.PLANT else box.size.x * 0.16
	hatch(box.grow(-inset), col, 5.0, 2.0)
