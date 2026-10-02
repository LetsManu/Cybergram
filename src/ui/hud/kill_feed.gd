class_name KillFeed
extends HudWidget
## Kill feed, top right (design/ux/hud.md §4.10): newest on top, max rows and
## lifetime from HudTuningDef. Row: [glyph] killer  >>  [glyph] victim, glyph =
## ally chevron / enemy diamond in team colour (colour-free cue: the shape).
## Rows that involve the local player get a light frame.

const ROW_H: float = 28.0
const ROW_GAP: float = 4.0

var model: KillFeedModel


func bind(c: HudContext) -> void:
	super(c)
	model = KillFeedModel.new(c.tuning.kill_feed_rows, c.tuning.kill_feed_seconds)


## Adds a hero kill (names already resolved by the caller).
func add(killer: String, killer_team: int, victim: String, victim_team: int, own: bool) -> void:
	var n := ctx.tuning.kill_feed_name_chars
	model.push(KillFeedModel.Entry.make(HudFormat.truncate(killer, n), killer_team, HudFormat.truncate(victim, n),
		victim_team, own))


func _process(delta: float) -> void:
	model.advance(delta)
	super(delta)


func _draw() -> void:
	var y := 0.0
	for e in model.entries:
		var a := model.alpha(e)
		var size_k := 16
		var max_name := (size.x - 90.0) * 0.5
		var killer := _fit(e.killer_name, size_k, max_name)
		var victim := _fit(e.victim_name, size_k, max_name)
		var vw := text_width(victim, size_k)
		var kw := text_width(killer, size_k)
		var arrow := " >> "
		var aw := text_width(arrow, size_k, ctx.font_display)
		var w := 16.0 + 18.0 + kw + aw + 18.0 + vw + 12.0
		var r := Rect2(size.x - w, y, w, ROW_H)
		var style := ctx.panel_own if e.own_involved else ctx.panel
		_row(r, e, killer, victim, style, a, kw, aw, size_k)
		y += ROW_H + ROW_GAP


func _row(r: Rect2, e: KillFeedModel.Entry, killer: String, victim: String, style: StyleBox, a: float, kw: float, aw: float, fs: int) -> void:
	if a >= 0.99:
		draw_style_box(style, r)
	else:
		_faded_panel(r, style, a)
	var x := r.position.x + 12.0
	var mid := r.position.y + ROW_H * 0.5
	_glyph(Vector2(x + 6.0, mid), e.killer_team, a)
	x += 18.0
	text(killer, Vector2(x, mid + 6.0), fs, Color(_name_col(e.killer_team), a))
	x += kw
	text(" >> ", Vector2(x, mid + 6.0), fs, Color(HudPalette.TEXT_DIM, a), ctx.font_display)
	x += aw
	_glyph(Vector2(x + 6.0, mid), e.victim_team, a)
	x += 18.0
	text(victim, Vector2(x, mid + 6.0), fs, Color(_name_col(e.victim_team), a))


func _faded_panel(r: Rect2, style: StyleBox, a: float) -> void:
	draw_rect(r, Color(HudPalette.PANEL, HudPalette.PANEL.a * a))
	if style == ctx.panel_own:
		draw_rect(r, Color(1, 1, 1, 0.8 * a), false, 1.0)


func _glyph(c: Vector2, team: int, a: float) -> void:
	if team < 0:
		return
	var col := Color(ctx.team_color(team), a)
	if team == ctx.own_team():
		chevron(c, 6.0, col)
	else:
		diamond(c, 5.5, col)


func _name_col(team: int) -> Color:
	return ctx.team_color(team).lightened(0.45) if team >= 0 else HudPalette.TEXT


## Shortens `t` until it fits `max_w` (names truncate, glyphs never).
func _fit(t: String, fs: int, max_w: float) -> String:
	var out := t
	while out.length() > 2 and text_width(out, fs) > max_w:
		out = HudFormat.truncate(out, out.length() - 1)
	return out
