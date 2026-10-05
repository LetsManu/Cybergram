class_name EndBanner
extends HudWidget
## End-of-match banner (design/ux/hud.md §12 End; v0.12 look, design/ux/
## hud-v0.12.md §2): VICTORY / DEFEAT / DRAW in 108 numerals with .34em
## tracking between brass hairline wings (brass-hi; DEFEAT in ivory, never a
## team colour), the reason in 24 body and "FINAL STATS IN n S" caps until
## MatchEndScreen opens. Visible only in the End phase; the backdrop is
## blurred and dimmed by HudScrims.

var _end_t: float = 0.0


func _process(delta: float) -> void:
	var c := ctx.client
	if c != null and c.match_state != null and c.match_state.phase == MatchRules.Phase.END:
		_end_t += delta
	else:
		_end_t = 0.0
	super(delta)


func _draw() -> void:
	var c := ctx.client
	if c == null or c.match_state == null or c.match_state.phase != MatchRules.Phase.END:
		return
	var m := c.match_state
	var team := ctx.own_team()
	var title := tr("HUD_DRAW")
	var col := HudPalette.BRASS_HI
	if m.winner == team:
		title = tr("HUD_VICTORY")
	elif m.winner == 1 - team:
		title = tr("HUD_DEFEAT")
		col = HudPalette.IVORY
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
	var cx := size.x * 0.5
	var y := 100.0
	var tw := caps_width(title, 108, 0.34)
	# Tracking adds trailing space after the last glyph: nudge right by half of it.
	var shift := UiKit.track(ts(108), 0.34) * 0.5
	caps(title, Vector2(cx - tw * 0.5 + shift, y), 108, col, 0.34)
	var wy := y - ts(108) * 0.36
	var wl := 330.0
	var gap := tw * 0.5 + 39.0
	_wing(Vector2(cx - gap - wl, wy), wl, false)
	_wing(Vector2(cx + gap, wy), wl, true)
	text(reason, Vector2(0.0, y + 72.0), 24, HudPalette.IVORY, ctx.font_body, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var left := ceili(MatchEndScreen.SHOW_DELAY_S - _end_t)
	if left > 0:
		caps_c(tr("HUD_FINAL_STATS_IN") % left, Vector2(cx, y + 108.0), 15, HudPalette.MUTED, 0.22)


## Brass hairline wing fading to transparent at its outer end.
func _wing(at: Vector2, w: float, right: bool) -> void:
	var inner := Color(HudPalette.BRASS, 1.0)
	var outer := Color(HudPalette.BRASS, 0.0)
	var r := Rect2(at, Vector2(w, 1.5))
	var l := outer if not right else inner
	var rr := inner if not right else outer
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([l, rr, rr, l]))
