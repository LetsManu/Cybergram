class_name ShopIcons
extends RefCounted
## Code-drawn item glyphs for the Armory shop (art bible §4 shape-first rule:
## no textures, each family has its own silhouette so colour is never the only
## cue). Crystal = faceted gem, Chip = square with pins, Frame = bracket,
## Ammo = round, Squad = three chevrons, Med-Pack = cross.
##
## Example: ShopIcons.draw(self, item, Rect2(8, 8, 56, 56), item.hue)


## Draws the glyph of `it` fitted inside `r` on `ci` (call from its _draw).
static func draw(ci: CanvasItem, it: ArmoryItemDef, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	var dark := Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, col.a)
	ci.draw_rect(r, Color(0.02, 0.03, 0.06, 0.55 * col.a))
	ci.draw_rect(r, Color(col.r, col.g, col.b, 0.55 * col.a), false, 1.5)
	match it.kind:
		ArmoryItemDef.Kind.CONSUMABLE:
			_cross(ci, c, s * 0.62, col, dark)
		ArmoryItemDef.Kind.SQUAD:
			_chevrons(ci, c, s * 0.62, col, dark)
		ArmoryItemDef.Kind.AMMO:
			_bullet(ci, c, s * 0.62, col, dark)
		_:
			if it.socket == ArmoryItemDef.Socket.FRAME:
				_bracket(ci, c, s * 0.6, col, it.family == ArmoryItemDef.Family.CHIP)
			elif it.family == ArmoryItemDef.Family.CHIP:
				_chip(ci, c, s * 0.6, col, dark)
			else:
				_gem(ci, c, s * 0.66, col, dark)


static func _gem(ci: CanvasItem, c: Vector2, s: float, col: Color, dark: Color) -> void:
	var top := PackedVector2Array([c + Vector2(-s * 0.6, -s * 0.3), c + Vector2(-s * 0.3, -s), c + Vector2(s * 0.3, -s),
		c + Vector2(s * 0.6, -s * 0.3)])
	var body := PackedVector2Array([top[0], top[3], c + Vector2(0.0, s)])
	ci.draw_colored_polygon(body, col)
	ci.draw_colored_polygon(PackedVector2Array([top[0], top[1], top[2], top[3]]), col.lightened(0.25))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -s * 0.3), top[3], c + Vector2(0.0, s)]), dark)
	var outline := PackedVector2Array([top[0], top[1], top[2], top[3], c + Vector2(0.0, s), top[0]])
	ci.draw_polyline(outline, Color(1, 1, 1, 0.8), 1.5, true)


static func _chip(ci: CanvasItem, c: Vector2, s: float, col: Color, dark: Color) -> void:
	var body := Rect2(c - Vector2(s * 0.6, s * 0.6), Vector2(s * 1.2, s * 1.2))
	for i in 3:
		var t := -s * 0.35 + s * 0.35 * i
		ci.draw_line(Vector2(body.position.x - s * 0.3, c.y + t), Vector2(body.position.x, c.y + t), col, 2.0)
		ci.draw_line(Vector2(body.end.x, c.y + t), Vector2(body.end.x + s * 0.3, c.y + t), col, 2.0)
		ci.draw_line(Vector2(c.x + t, body.position.y - s * 0.3), Vector2(c.x + t, body.position.y), col, 2.0)
		ci.draw_line(Vector2(c.x + t, body.end.y), Vector2(c.x + t, body.end.y + s * 0.3), col, 2.0)
	ci.draw_rect(body, dark)
	ci.draw_rect(body, col, false, 2.0)
	ci.draw_rect(Rect2(c - Vector2(s * 0.25, s * 0.25), Vector2(s * 0.5, s * 0.5)), col)


static func _bracket(ci: CanvasItem, c: Vector2, s: float, col: Color, chip: bool) -> void:
	var w := 4.0
	ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.2, -s), c + Vector2(-s, -s), c + Vector2(-s, s),
		c + Vector2(-s * 0.2, s)]), col, w, true)
	ci.draw_polyline(PackedVector2Array([c + Vector2(s * 0.2, -s), c + Vector2(s, -s), c + Vector2(s, s),
		c + Vector2(s * 0.2, s)]), col, w, true)
	if chip:
		ci.draw_rect(Rect2(c - Vector2(s * 0.3, s * 0.3), Vector2(s * 0.6, s * 0.6)), col)
	else:
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -s * 0.4), c + Vector2(s * 0.35, 0.0),
			c + Vector2(0.0, s * 0.4), c + Vector2(-s * 0.35, 0.0)]), col)


static func _bullet(ci: CanvasItem, c: Vector2, s: float, col: Color, dark: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-s * 0.4, s), c + Vector2(-s * 0.4, -s * 0.3), c + Vector2(0.0, -s),
		c + Vector2(s * 0.4, -s * 0.3), c + Vector2(s * 0.4, s)])
	ci.draw_colored_polygon(pts, col)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.45), Vector2(s * 0.8, s * 0.2)), dark)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(1, 1, 1, 0.75), 1.5, true)


static func _chevrons(ci: CanvasItem, c: Vector2, s: float, col: Color, _dark: Color) -> void:
	for i in 3:
		var y := -s * 0.6 + s * 0.6 * i
		ci.draw_polyline(PackedVector2Array([c + Vector2(-s, y + s * 0.5), c + Vector2(0.0, y - s * 0.1),
			c + Vector2(s, y + s * 0.5)]), col.lightened(0.1 * (2 - i)), 4.0, true)


static func _cross(ci: CanvasItem, c: Vector2, s: float, col: Color, dark: Color) -> void:
	var t := s * 0.38
	ci.draw_rect(Rect2(c + Vector2(-s, -t), Vector2(s * 2.0, t * 2.0)), col)
	ci.draw_rect(Rect2(c + Vector2(-t, -s), Vector2(t * 2.0, s * 2.0)), col)
	ci.draw_rect(Rect2(c + Vector2(-s, -t), Vector2(s * 2.0, t * 2.0)), dark, false, 1.5)


## Five-point star (recommended badge), centre `c`, outer radius `s`.
static func star(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * i / 10.0
		var rad := s if i % 2 == 0 else s * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(pts, col)


## Check mark inside a box of half-size `s` at `c`.
static func check(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-s, 0.0), c + Vector2(-s * 0.3, s * 0.7), c + Vector2(s, -s * 0.7)]),
		col, 3.0, true)
