class_name EmblemIcon
extends Control
## A player emblem (design/ux/lobby-and-social.md §2.1): one of
## PlayerProfile.EMBLEM_COUNT code-drawn glyphs in the player's accent colour
## on a dark tile with an accent keyline. Shape + colour, so the colour is
## never the only cue.
##
## Example:
##   var e := EmblemIcon.make(3, 1, 40.0)
##   add_child(e)

var emblem: int = 0:
	set(v):
		emblem = v
		queue_redraw()
var accent: int = 0:
	set(v):
		accent = v
		queue_redraw()
## Draw a dimmed tile (e.g. a disconnected player).
var dim: bool = false:
	set(v):
		dim = v
		queue_redraw()


static func make(emblem_: int, accent_: int, size_px: float) -> EmblemIcon:
	var e := EmblemIcon.new()
	e.emblem = emblem_
	e.accent = accent_
	e.custom_minimum_size = Vector2(size_px, size_px)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return e


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(size.x, size.y) * 0.5
	var col := PlayerProfile.accent_of(accent)
	if dim:
		col = col.darkened(0.55)
	var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
	draw_rect(r, Color(0.06, 0.07, 0.12, 0.95))
	draw_rect(r, col.darkened(0.2), false, maxf(1.0, s * 0.04))
	draw_glyph(self, emblem, c, s * 0.34, col)


## Draws glyph `index` centred at `c` with half-size `h` on `ci`.
static func draw_glyph(ci: CanvasItem, index: int, c: Vector2, h: float, col: Color) -> void:
	var w := maxf(1.5, h * 0.22)
	match posmod(index, PlayerProfile.EMBLEM_COUNT):
		0:  # chevron
			ci.draw_polyline(_pts(c, h, [[-0.9, 0.5], [0.0, -0.4], [0.9, 0.5]]), col, w * 1.3)
			ci.draw_polyline(_pts(c, h, [[-0.6, 0.95], [0.0, 0.35], [0.6, 0.95]]), col, w)
		1:  # diamond
			ci.draw_colored_polygon(_pts(c, h, [[0, -1], [0.75, 0], [0, 1], [-0.75, 0]]), col)
		2:  # star
			var star := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + i * PI / 5.0
				star.append(c + Vector2(cos(a), sin(a)) * h * (1.0 if i % 2 == 0 else 0.42))
			ci.draw_colored_polygon(star, col)
		3:  # bolt
			ci.draw_colored_polygon(_pts(c, h, [[0.2, -1], [-0.6, 0.15], [-0.05, 0.15], [-0.25, 1],
				[0.6, -0.2], [0.05, -0.2]]), col)
		4:  # ring
			ci.draw_arc(c, h * 0.8, 0.0, TAU, 32, col, w * 1.2, true)
			ci.draw_circle(c, h * 0.25, col)
		5:  # cross
			ci.draw_rect(Rect2(c - Vector2(h * 0.22, h * 0.95), Vector2(h * 0.44, h * 1.9)), col)
			ci.draw_rect(Rect2(c - Vector2(h * 0.95, h * 0.22), Vector2(h * 1.9, h * 0.44)), col)
		6:  # triangle
			ci.draw_colored_polygon(_pts(c, h, [[0, -0.95], [0.95, 0.75], [-0.95, 0.75]]), col)
			ci.draw_colored_polygon(_pts(c, h, [[0, -0.2], [0.35, 0.45], [-0.35, 0.45]]), Color(0.06, 0.07, 0.12))
		7:  # hexagon
			var hex := PackedVector2Array()
			for i in 6:
				var a := PI / 6.0 + i * TAU / 6.0
				hex.append(c + Vector2(cos(a), sin(a)) * h)
			hex.append(hex[0])
			ci.draw_polyline(hex, col, w * 1.2)
			ci.draw_circle(c, h * 0.3, col)
		8:  # crescent
			ci.draw_circle(c, h * 0.9, col)
			ci.draw_circle(c + Vector2(h * 0.4, -h * 0.25), h * 0.72, Color(0.06, 0.07, 0.12))
		9:  # eye
			ci.draw_arc(c + Vector2(0, h * 0.75), h * 1.2, -PI * 0.8, -PI * 0.2, 16, col, w)
			ci.draw_arc(c - Vector2(0, h * 0.75), h * 1.2, PI * 0.2, PI * 0.8, 16, col, w)
			ci.draw_circle(c, h * 0.3, col)
		10:  # shield
			ci.draw_colored_polygon(_pts(c, h, [[-0.8, -0.85], [0.8, -0.85], [0.8, 0.1], [0, 1], [-0.8, 0.1]]), col)
			ci.draw_line(c + Vector2(0, -h * 0.6), c + Vector2(0, h * 0.6), Color(0.06, 0.07, 0.12), w)
		11:  # crown
			ci.draw_colored_polygon(_pts(c, h, [[-0.9, 0.6], [-0.9, -0.5], [-0.45, 0.05], [0, -0.85],
				[0.45, 0.05], [0.9, -0.5], [0.9, 0.6]]), col)


static func _pts(c: Vector2, h: float, xy: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in xy:
		out.append(c + Vector2(float(p[0]), float(p[1])) * h)
	return out
