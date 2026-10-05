class_name FrontStrip
extends HudWidget
## Front line under the match header (design/ux/hud.md §4.7; v0.12 variant D,
## design/ux/hud-v0.12.md §2a): all lanes on ONE line, `N ▸ 5 chips · C ▸ … ·
## S ▸ …`, each group running from the own HQ side (left) to the enemy side
## (right) with the hardpoints at fixed columns. Track: ally colour up to the
## front, dimmer enemy colour beyond it; the front is a brass-hi needle. Chip
## shape = task (circle Hold, square Plant, triangle Breach) on an ink halo;
## ownership = own solid + ink inner mark, enemy outline + hatch, neutral
## hollow (readable in greyscale). Contested / capturing: an ivory ring pulsing
## at 1.6 s plus a progress arc in the capturing team's colour. Capture
## Overtime: in-progress chips pulse at 0.9 s with a warn arc, the others drop
## to 32% with a padlock. Sudden Death replaces the line with alive pips
## (chevrons / diamonds, hollow when dead, plus counts) and the ring timer.
## Idle: the line fades to 42%.

const HEIGHT: float = 30.0
const CHIP: float = 12.0
const COL_STEP: float = 36.75
const GROUP_W: float = 177.0
const GROUP_GAP: float = 30.0
const KEY_W: float = 24.0
const LANE_TAGS: Array[String] = ["HUD_LANE_TAG_N", "HUD_LANE_TAG_C", "HUD_LANE_TAG_S"]

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	super(delta)


## Short chip label for a hardpoint id: the slice drops its "s_" prefix
## (S-AI -> AI); the full map keeps the lane letter (N-AI, C-MID ...).
static func tag_of(id: StringName, lane_count: int) -> String:
	var s := String(id)
	if lane_count <= 1:
		s = s.trim_prefix("s_")
	return s.replace("_", "-").to_upper()


## Display column (0 = own HQ side) of lane-local hardpoint `local` for `team`.
static func column_of(local: int, n: int, team: int) -> int:
	return local if team == MapDef.TEAM_CONCORD else n - 1 - local


func _draw() -> void:
	var c := ctx.client
	if c == null:
		return
	var a := idle_a(0.42)
	if c.sudden_death != null and c.sudden_death.active:
		_sudden_death(c, a)
		return
	if c.hardpoints.is_empty():
		return
	var defs := c.hardpoint_defs()
	var team := ctx.own_team()
	var md := c.map_def
	var lanes := md.lanes.size() if md != null and not md.lanes.is_empty() else 1
	var ot := MatchHeader.phase_of(c.match_state, c.hardpoints) == MatchHeader.Phase.OVERTIME
	var total := lanes * (KEY_W + GROUP_W) + (lanes - 1) * GROUP_GAP
	var x := (size.x - total) * 0.5
	var base := 0
	for li in lanes:
		var n := md.lanes[li].hardpoints.size() if md != null and not md.lanes.is_empty() else c.hardpoints.size()
		var fi := li * 2 + team
		var front := c.fronts[fi] if fi < c.fronts.size() else -1
		if lanes > 1:
			var tag: String = tr(LANE_TAGS[li]) if li < LANE_TAGS.size() else str(li)
			text(tag, Vector2(x, HEIGHT * 0.5 + 5.0), 15, Color(HudPalette.DIM, a), ctx.font_mono)
		_group(x + KEY_W, base, n, defs, c.hardpoints, team, front, ot, a)
		base += n
		x += KEY_W + GROUP_W + GROUP_GAP


## One lane group: track, chips, front needle.
func _group(x0: float, base: int, n: int, defs: Array[HardpointDef], states: Array[SnapshotData.HardpointState],
		team: int, front: int, ot: bool, a: float) -> void:
	var y := HEIGHT * 0.5
	var step := COL_STEP if n <= 5 else (GROUP_W - 30.0) / maxf(n - 1, 1)
	var cx0 := x0 + 15.0
	# Front needle x: between the own front chip and the next one (column order).
	var fcol := -1
	if front >= 0 and front < n:
		fcol = column_of(front, n, team)
	var fx := cx0 + (fcol + 0.5) * step if fcol >= 0 else cx0 - step * 0.5
	var own_col := ctx.team_color(team)
	var en_col := ctx.team_color(1 - team)
	draw_line(Vector2(x0 + 3.0, y), Vector2(fx, y), Color(own_col, 0.7 * a), 2.25)
	draw_line(Vector2(fx, y), Vector2(x0 + GROUP_W - 3.0, y), Color(en_col, 0.45 * a), 2.25)
	for k in n:
		var local := column_of(k, n, team)  # symmetric: column k shows lane-local `local`
		var i := base + local
		if i >= states.size():
			continue
		var st := states[i]
		var center := Vector2(cx0 + k * step, y)
		var task: int = defs[i].task if i < defs.size() else HardpointDef.TaskKind.HOLD
		var dim := ot and not st.overtime
		var ca := a * (0.32 if dim else 1.0)
		task_chip(center, CHIP, task, ownership(st.owner, team), ctx.team_color(st.owner), true, ca)
		if st.overtime:
			capture_ring(center, CHIP, st.progress, HudPalette.WARN_UI, pulse(_t, 0.9, 0.4) * a)
		elif st.contested or (st.progress > 0.0 and st.capturing_team >= 0):
			capture_ring(center, CHIP, st.progress, ctx.team_color(st.capturing_team), pulse(_t, 1.6, 0.4) * a)
		if dim or st.locked[team]:
			padlock(center + Vector2(CHIP * 0.5 + 1.0, -CHIP * 0.5 - 2.0), 7.0, Color(HudPalette.IVORY, a))
	draw_rect(Rect2(fx - 1.0, 0.0, 2.0, HEIGHT), Color(HudPalette.BRASS_HI, a))
	draw_colored_polygon(PackedVector2Array([Vector2(fx - 5.0, 0.0), Vector2(fx + 5.0, 0.0), Vector2(fx, 5.0)]),
		Color(HudPalette.BRASS_HI, a))
	draw_colored_polygon(PackedVector2Array([Vector2(fx - 5.0, HEIGHT), Vector2(fx + 5.0, HEIGHT), Vector2(fx, HEIGHT - 5.0)]),
		Color(HudPalette.BRASS_HI, a))


## Sudden Death: CONCORD ▲▲▲▲△ 4 · RING 0:41 → 4 m · 2 ◆◆◇◇◇ SYNDICATE.
func _sudden_death(c: ClientWorld, a: float) -> void:
	var team := ctx.own_team()
	var alive := [0, 0]
	var total := [0, 0]
	for r: ScoreboardModel.Row in ctx.roster.rows():
		if r.team >= 0 and r.team <= 1:
			total[r.team] += 1
			alive[r.team] += int(r.alive)
	var sd := c.sudden_death
	var left := maxf(sd.rules.sudden_death_shrink_s - sd.elapsed_s, 0.0)
	var ring := tr("HUD_SD_RING") % HudFormat.clock(ceilf(left))
	var dest := tr("HUD_SD_RING_TO") % roundi(sd.rules.sudden_death_ring_end_m)
	var y := HEIGHT * 0.5
	var rw := caps_width(ring, 19, 0.06)
	var dw := text_width(dest, 15, ctx.font_mono)
	var mid_w := rw + 8.0 + dw
	var cx := size.x * 0.5
	caps(ring, Vector2(cx - mid_w * 0.5, y + 7.0), 19, Color(HudPalette.IVORY, a), 0.06)
	text(dest, Vector2(cx - mid_w * 0.5 + rw + 8.0, y + 6.0), 15, Color(HudPalette.MUTED, a), ctx.font_mono)
	_pips(cx - mid_w * 0.5 - 24.0, y, team, alive[team], maxi(total[team], 5), false, a)
	_pips(cx + mid_w * 0.5 + 24.0, y, 1 - team, alive[1 - team], maxi(total[1 - team], 5), true, a)


## Alive pips for `team` growing away from `x` (rightwards when `right`):
## count, glyphs (hollow = dead), team name.
func _pips(x: float, y: float, team: int, alive: int, n: int, right: bool, a: float) -> void:
	var col := ctx.team_color(team)
	var own := team == ctx.own_team()
	var dir := 1.0 if right else -1.0
	var cnt := str(alive)
	var cw := text_width(cnt, 19, ctx.font_numbers)
	text(cnt, Vector2(x if right else x - cw, y + 7.0), 19, Color(HudPalette.IVORY, a), ctx.font_numbers)
	var gx := x + dir * (cw + 20.0)
	for k in n:
		var gc := Vector2(gx + dir * k * 21.0, y)
		var on := (k < alive) if right else (k >= n - alive)
		if own:
			if on:
				chevron(gc, 7.5, Color(col, a))
			else:
				chevron_line(gc, 7.5, Color(col, 0.55 * a))
		elif on:
			diamond(gc, 7.0, Color(col, a))
		else:
			var p := PackedVector2Array([gc + Vector2(0, -7), gc + Vector2(7, 0), gc + Vector2(0, 7), gc + Vector2(-7, 0), gc + Vector2(0, -7)])
			draw_polyline(p, Color(col, 0.55 * a), 1.0, true)
	var nm := tr(MatchHeader.TEAM_KEYS[team])
	var end_x := gx + dir * ((n - 1) * 21.0 + 20.0)
	var nw := caps_width(nm, 15, 0.22)
	caps(nm, Vector2(end_x if right else end_x - nw, y + 5.0), 15, Color(col, a), 0.22)
