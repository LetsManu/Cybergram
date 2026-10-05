class_name FrontStrip
extends HudWidget
## Front-Line bar, one row per lane (design/ux/hud.md §4.7, slice §19), under the match
## header. Chips in lane order with the own HQ on the left; chip shape = task
## (circle Hold, square Plant, triangle Breach, art bible §6.3); ownership =
## own solid + ring glyph, enemy diagonal hatch + tooth glyph, neutral hollow
## (readable in greyscale). The front marker is a bright vertical tick after
## the own team's front chip. Contested: white outline + progress ring in the
## capturing team's colour; Overtime: "OT"; Locked: padlock.

const CHIP: float = 26.0
const GAP: float = 22.0
const HEIGHT: float = 52.0
## W14: 3-lane maps draw one compact row per lane (N / C / S), tagged on the left.
const ROW_CHIP: float = 18.0
const ROW_GAP: float = 20.0
const ROW_H: float = 34.0
const LANE_TAGS: Array[String] = ["HUD_LANE_TAG_N", "HUD_LANE_TAG_C", "HUD_LANE_TAG_S"]


## Short chip label for a hardpoint id: the slice drops its "s_" prefix
## (S-AI -> AI); the full map keeps the lane letter (N-AI, C-MID ...).
static func tag_of(id: StringName, lane_count: int) -> String:
	var s := String(id)
	if lane_count <= 1:
		s = s.trim_prefix("s_")
	return s.replace("_", "-").to_upper()


func _draw() -> void:
	var c := ctx.client
	if c == null or c.hardpoints.is_empty():
		return
	var defs := c.hardpoint_defs()
	var states := c.hardpoints
	var team := ctx.own_team()
	var md := c.map_def
	var lanes := md.lanes.size() if md != null else 1
	if lanes <= 1:
		_draw_lane(0, states.size(), 0, defs, states, team, c.fronts[team] if c.fronts.size() > team else -1,
			CHIP, GAP, 0.0, "", 1)
		return
	var per := md.lanes[0].hardpoints.size()
	var total := per * ROW_CHIP + (per - 1) * ROW_GAP
	var x0 := (size.x - total) * 0.5
	panel(Rect2(x0 - 34.0, 0.0, total + 52.0, ROW_H * lanes + 4.0))
	var base := 0
	for li in lanes:
		var n := md.lanes[li].hardpoints.size()
		var fi := li * 2 + team
		var front := c.fronts[fi] if fi < c.fronts.size() else -1
		var tag: String = tr(LANE_TAGS[li]) if li < LANE_TAGS.size() else str(li)
		_draw_lane(base, n, li, defs, states, team, front, ROW_CHIP, ROW_GAP, ROW_H * li, tag, lanes)
		base += n


## One lane row: chips base..base+n-1, own HQ side on the left.
func _draw_lane(base: int, n: int, _li: int, defs: Array[HardpointDef], states: Array[SnapshotData.HardpointState],
		team: int, front: int, chip: float, gap: float, y: float, tag: String, lanes: int) -> void:
	var total := n * chip + (n - 1) * gap
	var x0 := (size.x - total) * 0.5
	if lanes <= 1:
		panel(Rect2(x0 - 18.0, 0.0, total + 36.0, HEIGHT))
	else:
		text_c(tag, Vector2(x0 - 20.0, y + 14.0), 12, HudPalette.TEXT_DIM, ctx.font_display)
	var cy := y + (18.0 if lanes <= 1 else 13.0)
	for k in n:
		var local := k if team == MapDef.TEAM_CONCORD else n - 1 - k
		var i := base + local
		if i >= states.size():
			continue
		var st := states[i]
		var center := Vector2(x0 + k * (chip + gap) + chip * 0.5, cy)
		var task: int = defs[i].task if i < defs.size() else HardpointDef.TaskKind.HOLD
		_chip(center, task, st, team, chip)
		if lanes <= 1:
			var t := tag_of(defs[i].id, lanes) if i < defs.size() else str(i)
			text_c(t, center + Vector2(0.0, 25.0), 11, HudPalette.TEXT_DIM, ctx.font_display)
		if local == front:
			var fx := center.x + chip * 0.5 + gap * 0.5
			var h := 32.0 if lanes <= 1 else 22.0
			draw_line(Vector2(fx, cy - 16.0), Vector2(fx, cy - 16.0 + h), Color.WHITE, 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(fx - 5.0, cy - 12.0 + h), Vector2(fx + 5.0, cy - 12.0 + h),
				Vector2(fx, cy - 17.0 + h)]), Color.WHITE)


func _chip(c: Vector2, task: int, st: SnapshotData.HardpointState, team: int, chip: float = CHIP) -> void:
	var r := chip * 0.5
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
