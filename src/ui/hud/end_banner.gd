class_name EndBanner
extends HudWidget
## End-of-match banner (design/ux/hud.md §12 End): VICTORY / DEFEAT / DRAW
## and the reason, across the upper third. Visible only in the End phase.


func _draw() -> void:
	var c := ctx.client
	if c == null or c.match_state == null or c.match_state.phase != MatchRules.Phase.END:
		return
	var m := c.match_state
	var team := ctx.own_team()
	var title := tr("HUD_DRAW")
	var col := HudPalette.TEXT
	if m.winner == team:
		title = tr("HUD_VICTORY")
		col = ctx.team_color(team).lightened(0.3)
	elif m.winner == 1 - team:
		title = tr("HUD_DEFEAT")
		col = ctx.team_color(1 - team).lightened(0.2)
	var winner_name := tr(MatchHeader.TEAM_KEYS[m.winner]) if m.winner >= 0 and m.winner <= 1 else ""
	var loser_name := tr(MatchHeader.TEAM_KEYS[1 - m.winner]) if m.winner >= 0 and m.winner <= 1 else ""
	var reason := ""
	match m.end_reason:
		MatchRules.EndReason.UPLINK_DESTROYED:
			reason = tr("HUD_END_UPLINK_DESTROYED") % loser_name
		MatchRules.EndReason.INCURSION:
			reason = tr("HUD_END_INCURSION") % winner_name
		MatchRules.EndReason.UPLINK_DAMAGE:
			reason = tr("HUD_END_UPLINK_DAMAGE") % winner_name
		MatchRules.EndReason.DRAW:
			reason = tr("HUD_END_DRAW")
		MatchRules.EndReason.SUDDEN_DEATH:
			reason = tr("HUD_END_SUDDEN_DEATH") % winner_name
	var r := Rect2(Vector2(0.0, 0.0), Vector2(size.x, 132.0))
	panel(r, ctx.panel_strong)
	text(title, Vector2(0.0, 78.0), 68, col, ctx.font_numbers, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	text(reason, Vector2(0.0, 116.0), 22, HudPalette.TEXT, ctx.font_body, HORIZONTAL_ALIGNMENT_CENTER, size.x)
