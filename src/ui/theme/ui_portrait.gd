class_name UiPortrait
extends Control
## A circular hero-portrait crop (design/ux/mockups/v0.9): the face region
## (`FACE`) of a portrait rendered by tools/art/render_hero_portraits.gd, on
## the well colour, with an optional outside ring (the mockup's
## `box-shadow: 0 0 0 2px`) and an optional status dot at the bottom right.
## No texture = an empty well (an unpicked slot).
##
## Example:
##   var p := UiPortrait.create(UiKit.portrait_texture("sable"), 38.0, UiKit.tokens().accent)
##   p.status_dot = UiKit.tokens().ok

## Default face window of a 720x1000 portrait in UV (the mockup crop); a
## hero's own window comes from UiKit.portrait_face().
const FACE := Rect2(0.3, 0.11, 0.4, 0.288)
## Circle tessellation.
const SEGMENTS := 48

var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
## The UV window shown in the circle (UiKit.portrait_face(stem)).
var face := FACE:
	set(v):
		face = v
		queue_redraw()
## Outside ring colour (alpha 0 = none) and width in px.
var ring := Color(0, 0, 0, 0):
	set(v):
		ring = v
		queue_redraw()
var ring_width: float = 2.0:
	set(v):
		ring_width = v
		queue_redraw()
## Well colour behind the portrait.
var well := Color("#111A20"):
	set(v):
		well = v
		queue_redraw()
## Status dot colour (alpha 0 = none); `dot_cut` = the gap ring colour
## (the surface the portrait sits on).
var status_dot := Color(0, 0, 0, 0):
	set(v):
		status_dot = v
		queue_redraw()
var dot_cut := Color("#0D1318"):
	set(v):
		dot_cut = v
		queue_redraw()
## Draw darker / desaturated (e.g. a disconnected player).
var dim: bool = false:
	set(v):
		dim = v
		queue_redraw()


## A portrait `side` px across showing `tex` with an outside `ring_`.
static func create(tex: Texture2D, side: float, ring_ := Color(0, 0, 0, 0), face_ := FACE) -> UiPortrait:
	var p := UiPortrait.new()
	p.texture = tex
	p.face = face_
	p.ring = ring_
	p.custom_minimum_size = Vector2(side, side)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## The circle outline (`n` points) of radius `r` around `c`.
static func circle(c: Vector2, r: float, n: int = SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := i * TAU / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5
	var pts := circle(c, r)
	draw_colored_polygon(pts, well.darkened(0.3) if dim else well)
	if texture != null:
		var uvs := PackedVector2Array()
		for p in pts:
			var n := (p - c) / (2.0 * r) + Vector2(0.5, 0.5)
			uvs.append(face.position + n * face.size)
		var tint := Color(0.45, 0.45, 0.45, 0.8) if dim else Color.WHITE
		draw_polygon(pts, PackedColorArray([tint]), uvs, texture)
	if ring.a > 0.0 and ring_width > 0.0:
		draw_arc(c, r + ring_width * 0.5, 0.0, TAU, SEGMENTS, ring, ring_width, true)
	else:
		draw_arc(c, r, 0.0, TAU, SEGMENTS, Color(well.lightened(0.1), 0.6), 1.0, true)
	if status_dot.a > 0.0:
		var dr := maxf(3.0, s * 0.15)
		var dc := c + Vector2(r, r) * 0.7071 + Vector2(dr, dr) * 0.15
		draw_circle(dc, dr + 2.0, dot_cut)
		draw_circle(dc, dr, status_dot)
