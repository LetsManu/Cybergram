class_name Scoreboard
extends HudWidget
## Scoreboard (design/ux/hud.md §8, slice §19: no build icons). Hold Tab
## (gamepad: hold View). v0.12 look (design/ux/hud-v0.12.md §2): no box, 1470
## wide over the blurred, dimmed game (HudScrims backdrop + ink): a header with
## each team's kills and Uplink % (ally ▲ left, enemy ◆ right) around the clock
## and phase; own team then enemy team in 45 px rows: face crop (team ring),
## name (brass-hi for you), BOT tag, muted hero name, LV, K / D, Lumen (own team
## brass-hi, enemy "—"), Forks (mono), status (teal ALIVE / warn RESPAWN). Own
## row: brass 10% tint + 3 px brass left rule. Footer: front per lane with the
## hardpoint glyphs and names (front in brass-hi), squad and next wave, the
## objective and team Lumen. The gameplay HUD hides except HP and the
## crosshair (HudRoot).

const W: float = 1470.0
const TOP: float = 52.0
const ROW_H: float = 45.0
const HEAD_H: float = 36.0
## Column anchors (from the left of the board): right edges for numbers.
const C_LV: float = 640.0
const C_KD: float = 880.0
const C_LUMEN: float = 1030.0
const C_FORKS: float = 1065.0
const C_STATUS: float = 1215.0
const NAMES: Array[String] = ["AI", "AO", "MID", "BO", "BI"]


func _draw() -> void:
	var client := ctx.client
	if client == null:
		return
	# Dim the whole screen, not only the safe area (draw in viewport space).
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	draw_rect(get_viewport_rect(), Color(HudPalette.INK_DEEP, 0.35))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var team := ctx.own_team()
	var teams := ScoreboardModel.build(ctx.roster.rows(), team)
	var x := (size.x - W) * 0.5
	var y := TOP
	_header(client, x, y, team, teams)
	y += 78.0
	draw_rect(Rect2(x, y, W, 1.0), HudPalette.HAIR_STRONG)
	y += 9.0
	y = _team_block(teams[0], team, x, y, true)
	y += 18.0
	y = _team_block(teams[1], 1 - team, x, y, false)
	y += 27.0
	draw_rect(Rect2(x, y, W, 1.0), HudPalette.HAIR_STRONG)
	_footer(client, x, y + 21.0, team, teams[0])


func _header(client: ClientWorld, x: float, y: float, team: int, teams: Array) -> void:
	for side in 2:
		var t := team if side == 0 else 1 - team
		var right := side == 1
		var col := ctx.team_color(t)
		var name := tr(MatchHeader.TEAM_KEYS[t])
		var gl := Vector2(x + 7.0 if not right else x + W - 7.0, y + 9.0)
		if side == 0:
			chevron(gl, 7.0, col)
		else:
			diamond(gl, 6.0, col)
		var nw := caps_width(name, 16, 0.22)
		caps(name, Vector2(x + 21.0 if not right else x + W - 21.0 - nw, y + 15.0), 16, col, 0.22)
		var kills := str(ScoreboardModel.totals(teams[side]).x)
		var u := client.uplink_state(t)
		var sub := tr("HUD_SB_KILLS_UPLINK") % (HudFormat.percent(u.integrity / maxf(u.max_integrity, 1.0)) if u != null else 0)
		if u != null and u.exposed:
			sub += " · " + tr("HUD_EXPOSED")
		var kw := text_width(kills, 39, ctx.font_numbers)
		var sw := text_width(sub, 19, ctx.font_numbers)
		if not right:
			text(kills, Vector2(x, y + 63.0), 39, HudPalette.IVORY, ctx.font_numbers)
			text(sub, Vector2(x + kw + 9.0, y + 61.0), 19, HudPalette.MUTED, ctx.font_numbers)
		else:
			text(kills, Vector2(x + W - kw, y + 63.0), 39, HudPalette.IVORY, ctx.font_numbers)
			text(sub, Vector2(x + W - kw - 9.0 - sw, y + 61.0), 19, HudPalette.MUTED, ctx.font_numbers)
	if client.match_state != null:
		var m := client.match_state
		text(HudFormat.clock(m.time_s), Vector2(x, y + 36.0), 33, HudPalette.IVORY, ctx.font_numbers, HORIZONTAL_ALIGNMENT_CENTER, W)
		var phase: String = tr(MatchHeader.PHASE_KEYS[m.phase]) if m.phase < MatchHeader.PHASE_KEYS.size() else ""
		if m.next_phase_s >= 0.0 and m.phase != MatchRules.Phase.END and m.phase != MatchRules.Phase.SUDDEN_DEATH:
			phase += " · " + tr("HUD_NEXT_PHASE") % HudFormat.clock(ceilf(m.next_phase_s - m.time_s))
		caps(phase, Vector2(x, y + 63.0), 16, HudPalette.BRASS_HI, 0.22, HORIZONTAL_ALIGNMENT_CENTER, W)


func _team_block(rows: Array, team: int, x: float, y: float, own: bool) -> float:
	var col := ctx.team_color(team)
	var hy := y + 24.0
	var gl := Vector2(x + 18.0, hy - 6.0)
	if own:
		chevron(gl, 6.0, col)
	else:
		diamond(gl, 5.0, col)
	caps(tr(MatchHeader.TEAM_KEYS[team]), Vector2(x + 30.0, hy), 15, col, 0.22)
	var dim := HudPalette.DIM
	caps(tr("HUD_COL_LEVEL"), Vector2(x, hy), 15, dim, 0.22, HORIZONTAL_ALIGNMENT_RIGHT, C_LV)
	caps(tr("HUD_COL_KD"), Vector2(x, hy), 15, dim, 0.22, HORIZONTAL_ALIGNMENT_RIGHT, C_KD)
	caps(tr("HUD_COL_LUMEN"), Vector2(x, hy), 15, dim, 0.22, HORIZONTAL_ALIGNMENT_RIGHT, C_LUMEN)
	caps(tr("HUD_COL_FORKS"), Vector2(x + C_FORKS, hy), 15, dim, 0.22)
	caps(tr("HUD_COL_STATUS"), Vector2(x + C_STATUS, hy), 15, dim, 0.22)
	y += HEAD_H
	for row: ScoreboardModel.Row in rows:
		var rr := Rect2(Vector2(x, y), Vector2(W, ROW_H))
		if row.is_self:
			draw_rect(rr, Color(HudPalette.BRASS, 0.10))
			draw_rect(Rect2(rr.position, Vector2(3.0, ROW_H)), HudPalette.BRASS)
		draw_rect(Rect2(x, rr.end.y - 1.0, W, 1.0), Color(HudPalette.HAIR, 0.8))
		var mid := y + ROW_H * 0.5
		var base := mid + ts(19) * 0.36
		var fa := 1.0 if row.alive else 0.55
		var fc := Vector2(x + 33.0, mid)
		face_circle(fc, 19.5, row.hero_id, fa)
		draw_arc(fc, 20.5, 0.0, TAU, 32, Color(col, fa), 1.5, true)
		var name := row.name if row.name != "" else tr("HUD_HERO_N") % row.net_id
		var ncol := HudPalette.BRASS_HI if row.is_self else HudPalette.IVORY
		if not row.alive:
			ncol = HudPalette.DIM
		text(name, Vector2(x + 66.0, base), 19, ncol, UiKit.body_font(600))
		var nx := x + 66.0 + text_width(name, 19, UiKit.body_font(600)) + 12.0
		if row.is_bot:
			var bt := tr("HUD_BOT")
			var bw := text_width(bt, 15, ctx.font_mono) + 12.0
			draw_rect(Rect2(nx, mid - 11.0, bw, 22.0), HudPalette.HAIR_STRONG, false, 1.0)
			text(bt, Vector2(nx + 6.0, mid + 5.0), 15, HudPalette.DIM, ctx.font_mono)
			nx += bw + 12.0
		var hn := hero_name(row.hero_id)
		if hn != "":
			text(hn, Vector2(nx, base - 1.0), 18, HudPalette.MUTED)
			nx += text_width(hn, 18) + 16.0
		# Armory v2: every hero's sockets, Chamber and open slots as icons (§3.8 rule 7).
		var bld := ScoreboardModel.build_of(ctx.client, row.net_id)
		if BuildIcons.has_any(bld):
			var bx := maxf(nx, x + 300.0)
			var room := x + C_LV - 64.0 - bx
			var cell := clampf(room / (BuildIcons.strip_width(1.0)), 12.0, 20.0)
			BuildIcons.draw_strip(self, bld, ScoreboardModel.build_catalog(ctx.client), Vector2(bx, mid - cell * 0.5), cell, fa)
		var ncl := HudPalette.IVORY if row.alive else HudPalette.DIM
		text(str(row.level) if row.level > 0 else "–", Vector2(x, base), 21, ncl, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, C_LV)
		text(HudFormat.kd(row.kills, row.deaths), Vector2(x, base), 21, ncl, ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, C_KD)
		var lumen := HudFormat.thousands(row.lumen) if own and row.lumen >= 0 else "—"
		text(lumen, Vector2(x, base), 21, HudPalette.BRASS_HI if own and row.alive else HudPalette.DIM, ctx.font_numbers,
			HORIZONTAL_ALIGNMENT_RIGHT, C_LUMEN)
		_fork_cell(row, x + C_FORKS, base)
		caps(tr("HUD_ALIVE") if row.alive else tr("HUD_SB_RESPAWN"), Vector2(x + C_STATUS, base - 1.0), 16,
			HudPalette.TEAL if row.alive else HudPalette.WARN_UI, 0.2)
		y += ROW_H
	return y


## W11-V1: Fork choices of the 3 basic skills: A / B / – (mono), Mastery *.
func _fork_cell(row: ScoreboardModel.Row, x: float, base: float) -> void:
	var parts := PackedStringArray()
	for slot in 3:
		var f := NamePlateModel.fork_of(row.fork_bits, slot)
		var t := "–" if f == 0 else ("A" if f == 1 else "B")
		if ((row.fork_bits >> (slot * 3 + 2)) & 1) != 0:
			t += "*"
		parts.append(t)
	text(" ".join(parts), Vector2(x, base), 18, HudPalette.MUTED if row.alive else HudPalette.DIM, ctx.font_mono)


func _footer(client: ClientWorld, x: float, y: float, team: int, own_rows: Array) -> void:
	var cw := W / 3.3
	caps(tr("HUD_SCOREBOARD_FRONTS"), Vector2(x, y), 16, HudPalette.MUTED, 0.22)
	_fronts(client, x, y + 33.0, team)
	var x2 := x + cw * 1.3 + 42.0
	caps(tr("HUD_SQUAD"), Vector2(x2, y), 16, HudPalette.MUTED, 0.22)
	var pips: Array = client.wardlings.own_squad if client.wardlings != null else []
	var cmd := ""
	if not pips.is_empty():
		cmd = tr(SquadStrip.COMMAND_KEYS.get((pips[0] as WardlingPresenter.SquadPip).command, "HUD_SQUAD"))
	text(tr("HUD_SB_SQUAD_LINE") % [pips.size(), cmd.capitalize()], Vector2(x2, y + 39.0), 18, HudPalette.MUTED)
	if client.wardlings != null and client.match_state != null:
		var nw := HudFormat.clock(ceilf(LaneMinimap.next_wave_in(client.match_state.time_s, client.wardlings.rules)))
		text(tr("HUD_SB_NEXT_WAVE") % nw, Vector2(x2, y + 69.0), 18, HudPalette.MUTED)
	var x3 := x2 + cw + 42.0
	caps(tr("HUD_SB_OBJECTIVE"), Vector2(x3, y), 16, HudPalette.MUTED, 0.22)
	var obj := _objective_line(client, team)
	if obj != "":
		text(obj, Vector2(x3, y + 39.0), 18, HudPalette.MUTED, ctx.font_body, HORIZONTAL_ALIGNMENT_LEFT, W - (x3 - x))
	var total := 0
	for r: ScoreboardModel.Row in own_rows:
		total += maxi(r.lumen, 0)
	var tl := tr("HUD_SB_TEAM_LUMEN")
	text(tl, Vector2(x3, y + 69.0), 18, HudPalette.MUTED)
	text(HudFormat.thousands(total), Vector2(x3 + text_width(tl, 18) + 9.0, y + 69.0), 18, HudPalette.BRASS_HI, ctx.font_numbers)


## Front per lane: lane letter, the hardpoint glyphs with their short names
## (own HQ side on the left), the front hardpoint's name in brass-hi.
func _fronts(client: ClientWorld, x: float, y: float, team: int) -> void:
	var md := client.map_def
	if md == null or md.lanes.is_empty() or client.hardpoints.is_empty():
		return
	var defs := client.hardpoint_defs()
	var base := 0
	for li in md.lanes.size():
		var n := md.lanes[li].hardpoints.size()
		var fi := li * 2 + team
		var front := client.fronts[fi] if fi < client.fronts.size() else -1
		var ly := y + li * 30.0
		var tag := tr(FrontStrip.LANE_TAGS[li]) if li < FrontStrip.LANE_TAGS.size() else str(li)
		text(tag, Vector2(x, ly + 6.0), 15, HudPalette.DIM, ctx.font_mono)
		for k in n:
			var local := FrontStrip.column_of(k, n, team)
			var i := base + local
			if i >= client.hardpoints.size():
				continue
			var st := client.hardpoints[i]
			var gx := x + 39.0 + k * 75.0
			task_chip(Vector2(gx, ly), 18.0, defs[i].task if i < defs.size() else 0, ownership(st.owner, team),
				ctx.team_color(st.owner), false)
			if st.contested:
				capture_ring(Vector2(gx, ly), 18.0, st.progress, ctx.team_color(st.capturing_team), 1.0)
			var nm: String = NAMES[k] if n == NAMES.size() else FrontStrip.tag_of(defs[i].id, 1)
			text(nm, Vector2(gx + 15.0, ly + 6.0), 15, HudPalette.BRASS_HI if local == front else HudPalette.DIM, ctx.font_mono)
		base += n


func _objective_line(client: ClientWorld, team: int) -> String:
	var idx := client.own_hardpoint_index()
	if idx < 0 or idx >= client.hardpoints.size():
		return ""
	var defs := client.hardpoint_defs()
	var st := client.hardpoints[idx]
	var verb := tr(ObjectiveTracker.VERB_KEYS[clampi(defs[idx].task, 0, 2)])
	var state := tr("HUD_STATE_CONTESTED") if st.contested else (tr("HUD_STATE_HELD") if st.owner == team else "")
	return "%s %s · %s %d%%" % [verb, defs[idx].display_name, state.to_lower(), floori(st.progress * 100.0)]
