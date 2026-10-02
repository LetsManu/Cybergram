class_name Scoreboard
extends HudWidget
## Minimal scoreboard (design/ux/hud.md §8, slice §19: no build icons). Hold
## Tab (gamepad: hold View). Own team on top, enemy below, centre overlay on an
## 85% dark backdrop; the gameplay HUD hides except HP and the crosshair
## (HudRoot). Columns: hero (ally chevron / enemy diamond, YOU, BOT tag), level,
## K / D, Lumen (own team only; enemy Lumen is hidden), status.

const W: float = 860.0
const ROW_H: float = 30.0
const HEAD_H: float = 40.0


func _draw() -> void:
	var client := ctx.client
	if client == null:
		return
	# Dim the whole screen, not only the safe area (draw in viewport space).
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	draw_rect(get_viewport_rect(), Color(0.02, 0.03, 0.06, 0.6))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var team := ctx.own_team()
	var teams := ScoreboardModel.build(ctx.roster.rows(), team)
	var own: Array = teams[0]
	var enemy: Array = teams[1]
	var h := 2.0 * (HEAD_H + 12.0) + (own.size() + enemy.size()) * ROW_H + 72.0
	var r := Rect2(Vector2((size.x - W) * 0.5, maxf(0.0, (size.y - h) * 0.5)), Vector2(W, h))
	draw_rect(r, Color(0.02, 0.03, 0.06, 0.85))
	draw_rect(r, HudPalette.KEYLINE, false, 1.0)
	var x := r.position.x + 20.0
	var y := r.position.y + 30.0
	text(tr("HUD_SCOREBOARD"), Vector2(x, y), 20, HudPalette.TEXT, ctx.font_display)
	if client.match_state != null:
		var m := client.match_state
		var phase: String = tr(MatchHeader.PHASE_KEYS[m.phase]) if m.phase < MatchHeader.PHASE_KEYS.size() else ""
		text("%s   %s" % [HudFormat.clock(m.time_s), phase], Vector2(r.position.x, y), 18, HudPalette.TEXT_DIM,
			ctx.font_numbers, HORIZONTAL_ALIGNMENT_RIGHT, W - 20.0)
	y += 18.0
	y = _team_block(own, team, x, y, true)
	y += 8.0
	_team_block(enemy, 1 - team, x, y, false)


func _team_block(rows: Array, team: int, x: float, y: float, own: bool) -> float:
	var col := ctx.team_color(team)
	var hr := Rect2(Vector2(x - 8.0, y), Vector2(W - 24.0, 30.0))
	draw_rect(hr, Color(col, 0.22))
	draw_rect(Rect2(hr.position, Vector2(4.0, hr.size.y)), col)
	var tot := ScoreboardModel.totals(rows)
	var title := tr(MatchHeader.TEAM_KEYS[team])
	var u := ctx.client.uplink_state(team)
	if u != null:
		title += "    " + tr("HUD_UPLINK_PCT") % HudFormat.percent(u.integrity / maxf(u.max_integrity, 1.0))
		if u.exposed:
			title += "  " + tr("HUD_EXPOSED")
	text(title, Vector2(x + 6.0, y + 21.0), 17, HudPalette.TEXT, ctx.font_display)
	text(HudFormat.kd(tot.x, tot.y), Vector2(x + 420.0, y + 21.0), 15, HudPalette.TEXT_DIM, ctx.font_numbers)
	y += HEAD_H + 6.0
	_cols(x, y)
	y += 6.0
	for row: ScoreboardModel.Row in rows:
		var rr := Rect2(Vector2(x - 8.0, y), Vector2(W - 24.0, ROW_H - 3.0))
		if row.is_self:
			draw_rect(rr, Color(1, 1, 1, 0.1))
			draw_rect(rr, Color(1, 1, 1, 0.6), false, 1.0)
		var mid := y + ROW_H * 0.5 + 6.0
		if own:
			chevron(Vector2(x + 8.0, mid - 6.0), 7.0, col)
		else:
			diamond(Vector2(x + 8.0, mid - 6.0), 6.0, col)
		var name := row.name if row.name != "" else tr("HUD_HERO_N") % row.net_id
		text(name, Vector2(x + 26.0, mid), 16, HudPalette.TEXT if row.alive else HudPalette.TEXT_OFF)
		var tag := tr("HUD_YOU") if row.is_self else (tr("HUD_BOT") if row.is_bot else "")
		if tag != "":
			text(tag, Vector2(x + 34.0 + text_width(name, 16), mid), 12, HudPalette.TEXT_DIM, ctx.font_display)
		text(str(row.level) if row.level > 0 else "-", Vector2(x + 300.0, mid), 16, HudPalette.RESONANCE, ctx.font_numbers)
		text(HudFormat.kd(row.kills, row.deaths), Vector2(x + 420.0, mid), 16, HudPalette.TEXT, ctx.font_numbers)
		var lumen := HudFormat.thousands(row.lumen) if own and row.lumen >= 0 else "-"
		text(lumen, Vector2(x + 540.0, mid), 16, HudPalette.LUMEN if own else HudPalette.TEXT_OFF, ctx.font_numbers)
		text(tr("HUD_ALIVE") if row.alive else tr("HUD_DEAD"), Vector2(x + 680.0, mid), 14,
			HudPalette.TEXT_DIM if row.alive else HudPalette.DANGER.lightened(0.2), ctx.font_display)
		y += ROW_H
	return y


func _cols(x: float, y: float) -> void:
	var c := HudPalette.TEXT_DIM
	text(tr("HUD_COL_HERO"), Vector2(x + 26.0, y), 12, c, ctx.font_display)
	text(tr("HUD_COL_LEVEL"), Vector2(x + 300.0, y), 12, c, ctx.font_display)
	text(tr("HUD_COL_KD"), Vector2(x + 420.0, y), 12, c, ctx.font_display)
	text(tr("HUD_COL_LUMEN"), Vector2(x + 540.0, y), 12, c, ctx.font_display)
	text(tr("HUD_COL_STATUS"), Vector2(x + 680.0, y), 12, c, ctx.font_display)
