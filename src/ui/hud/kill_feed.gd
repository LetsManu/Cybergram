class_name KillFeed
extends HudWidget
## Kill feed, top right (design/ux/hud.md §4.10): newest on top, max rows and
## lifetime from HudTuningDef. Row: [glyph] killer  >>  [glyph] victim, glyph =
## ally chevron / enemy diamond in team colour (colour-free cue: the shape).
## Rows that involve the local player get a light frame.

const ROW_H: float = 33.0
const ROW_GAP: float = 6.0
const ARROW_W: float = 27.0

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
	var n := model.entries.size()
	var idx := 0
	for e in model.entries:
		var a := model.alpha(e) * (0.55 if n >= 3 and idx == n - 1 else 1.0)
		var fs := 19
		var max_name := (size.x - 120.0) * 0.5
		var killer := _fit(e.killer_name, fs, max_name)
		var victim := _fit(e.victim_name, fs, max_name)
		var kw := text_width(killer, fs)
		var vw := text_width(victim, fs)
		var w := 12.0 + 18.0 + kw + 12.0 + ARROW_W + 12.0 + 18.0 + vw + 15.0
		_row(Rect2(size.x - w, y, w, ROW_H), e, killer, victim, a, kw, fs)
		y += ROW_H + ROW_GAP
		idx += 1


func _row(r: Rect2, e: KillFeedModel.Entry, killer: String, victim: String, a: float, kw: float, fs: int) -> void:
	# Right-fading ink gradient instead of a frame: clear on the left, 50% from 30%.
	var k := r.position.x + r.size.x * 0.3
	scrim_h(Rect2(r.position, Vector2(k - r.position.x, r.size.y)), 0.0, 0.5 * a)
	draw_rect(Rect2(Vector2(k, r.position.y), Vector2(r.end.x - k, r.size.y)), Color(HudPalette.INK_DEEP, 0.5 * a))
	if e.own_involved:
		draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), Color(HudPalette.BRASS, a))
	var x := r.position.x + 12.0
	var mid := r.position.y + ROW_H * 0.5
	var base := mid + ts(fs) * 0.36
	_glyph(Vector2(x + 6.0, mid), e.killer_team, a)
	x += 18.0
	text(killer, Vector2(x, base), fs, Color(_name_col(killer), a))
	x += kw + 12.0
	var ac := Color(HudPalette.IVORY, a)
	draw_line(Vector2(x, mid), Vector2(x + ARROW_W - 4.0, mid), ac, 1.5)
	draw_polyline(PackedVector2Array([Vector2(x + ARROW_W - 9.0, mid - 6.0), Vector2(x + ARROW_W - 1.5, mid),
		Vector2(x + ARROW_W - 9.0, mid + 6.0)]), ac, 1.5)
	x += ARROW_W + 12.0
	_glyph(Vector2(x + 6.0, mid), e.victim_team, a)
	x += 18.0
	text(victim, Vector2(x, base), fs, Color(_name_col(victim), a))


func _glyph(c: Vector2, team: int, a: float) -> void:
	if team < 0:
		return
	var col := Color(ctx.team_color(team), a)
	if team == ctx.own_team():
		chevron(c, 7.0, col)
	else:
		diamond(c, 6.5, col)


## "You" in brass-hi, everyone else ivory (the glyph carries the team).
func _name_col(name: String) -> Color:
	return HudPalette.BRASS_HI if name == tr("HUD_YOU") else HudPalette.IVORY


## Shortens `t` until it fits `max_w` (names truncate, glyphs never).
func _fit(t: String, fs: int, max_w: float) -> String:
	var out := t
	while out.length() > 2 and text_width(out, fs) > max_w:
		out = HudFormat.truncate(out, out.length() - 1)
	return out
