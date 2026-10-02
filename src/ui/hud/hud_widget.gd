class_name HudWidget
extends Control
## Base for HUD widgets: a Control placed by anchors inside a HudRoot zone,
## redrawn every frame while visible, with themed text / panel / glyph helpers.
## Widgets read ctx.client (replicated state) and never write gameplay state.

var ctx: HudContext


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(c: HudContext) -> void:
	ctx = c


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## Text with the HUD outline. `pos` is the baseline-left point; `width` > 0 with
## `align` aligns inside [pos.x, pos.x + width].
func text(t: String, pos: Vector2, size: int, col: Color, font: Font = null,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := font if font != null else ctx.font_body
	draw_string_outline(f, pos, t, align, width, size, 4, Color(HudPalette.OUTLINE, HudPalette.OUTLINE.a * col.a))
	draw_string(f, pos, t, align, width, size, col)


## Text centred on `center` (both axes, approximately).
func text_c(t: String, center: Vector2, size: int, col: Color, font: Font = null) -> void:
	var f := font if font != null else ctx.font_body
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(t, center + Vector2(-w * 0.5, size * 0.36), size, col, f)


func text_width(t: String, size: int, font: Font = null) -> float:
	var f := font if font != null else ctx.font_body
	return f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func panel(r: Rect2, style: StyleBox = null) -> void:
	draw_style_box(style if style != null else ctx.panel, r)


## Ally chevron (pointing up) — art bible §4.4 nameplate glyph.
func chevron(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(0.0, -s * 0.6), c + Vector2(s, s * 0.6),
		c + Vector2(s * 0.55, s * 0.6), c + Vector2(0.0, -s * 0.05), c + Vector2(-s * 0.55, s * 0.6)])
	draw_colored_polygon(pts, col)


## Enemy diamond — art bible §4.4 nameplate glyph.
func diamond(c: Vector2, s: float, col: Color, filled: bool = true) -> void:
	var pts := PackedVector2Array([c + Vector2(0.0, -s), c + Vector2(s, 0.0), c + Vector2(0.0, s), c + Vector2(-s, 0.0)])
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, 1.5, true)


## Ally chevron or enemy diamond for `team` relative to the own team.
func team_glyph(c: Vector2, s: float, team: int) -> void:
	if team < 0:
		return
	if team == ctx.own_team():
		chevron(c, s, ctx.team_color(team))
	else:
		diamond(c, s * 0.8, ctx.team_color(team))


## Horizontal bar with a dark track; `frac` of it filled.
func bar(r: Rect2, frac: float, col: Color, track: Color = Color(0, 0, 0, 0.55)) -> void:
	draw_rect(r, track)
	if frac > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)


## Diagonal hatching inside `r` (enemy ownership pattern, art bible §4.4).
func hatch(r: Rect2, col: Color, step: float = 6.0, width: float = 2.0) -> void:
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(x, r.end.y)
		var b := Vector2(x + r.size.y, r.position.y)
		# clip to r
		if a.x < r.position.x:
			a = Vector2(r.position.x, r.end.y - (r.position.x - a.x))
		if b.x > r.end.x:
			b = Vector2(r.end.x, r.position.y + (b.x - r.end.x))
		if a.x <= b.x:
			draw_line(a, b, col, width)
		x += step
