@tool
class_name UiBevelBox
extends StyleBox
## Kit style box (design/ux/ui-kit.md §4): a rectangle with clipped top-left /
## bottom-right corners (`bevel` = 0 gives a plain rectangle), a 1 px frame
## and an optional soft outer glow. `hover` (0..1) blends fill / frame / glow
## toward their hover values, so UiKit can tween it for a smooth hover.
##
## Example:
##   var sb := UiBevelBox.new()
##   sb.fill = UiKit.tokens().accent
##   button.add_theme_stylebox_override("normal", sb)

@export var fill := Color(0, 0, 0, 0):
	set(v):
		fill = v
		emit_changed()
@export var fill_hover := Color(0, 0, 0, 0):
	set(v):
		fill_hover = v
		emit_changed()
@export var border := Color(0, 0, 0, 0):
	set(v):
		border = v
		emit_changed()
@export var border_hover := Color(0, 0, 0, 0):
	set(v):
		border_hover = v
		emit_changed()
@export var border_width: float = 1.0:
	set(v):
		border_width = v
		emit_changed()
## Clipped corner size in px (0 = square).
@export var bevel: float = 0.0:
	set(v):
		bevel = v
		emit_changed()
## Glow colour at hover = 1 (alpha = strength); `glow_rest` at hover = 0.
@export var glow := Color(0, 0, 0, 0):
	set(v):
		glow = v
		emit_changed()
@export var glow_rest: float = 0.0:
	set(v):
		glow_rest = v
		emit_changed()
@export var glow_size: float = 8.0:
	set(v):
		glow_size = v
		emit_changed()
## 0 = rest look, 1 = hover look (tweened by UiKit).
@export_range(0.0, 1.0) var hover: float = 0.0:
	set(v):
		hover = v
		emit_changed()
## Extra glow multiplier (the PLAY button pulse).
@export var pulse: float = 1.0:
	set(v):
		pulse = v
		emit_changed()

## Glow rings drawn (cheap: a few translucent polygons).
const GLOW_STEPS := 4


func _init() -> void:
	set_content_margin_all(10)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var g := lerpf(glow_rest, 1.0, hover) * pulse * glow.a
	if g > 0.001 and glow_size > 0.0:
		for i in GLOW_STEPS:
			var k := float(GLOW_STEPS - i) / GLOW_STEPS
			var c := Color(glow, g * 0.22 * (1.0 - k * 0.7))
			var pts := outline(rect.grow(glow_size * k), bevel + glow_size * k * 0.4)
			RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([c]))
	var f := fill.lerp(fill_hover, hover) if fill_hover.a > 0.0 or fill.a > 0.0 else fill
	var pts := outline(rect, bevel)
	if f.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([f]))
	var b := border.lerp(border_hover, hover) if border_hover.a > 0.0 else border
	if b.a > 0.0 and border_width > 0.0:
		var inset := outline(rect.grow(-border_width * 0.5), maxf(bevel - border_width * 0.3, 0.0))
		inset.append(inset[0])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, inset, PackedColorArray([b]), border_width, true)


## The clipped-corner outline of `r` (clockwise from the top-left bevel).
static func outline(r: Rect2, cut: float) -> PackedVector2Array:
	var c := clampf(cut, 0.0, minf(r.size.x, r.size.y) * 0.5)
	if c <= 0.0:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y),
		Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y + c)])
