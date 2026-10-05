class_name ShopIcons
extends RefCounted
## Code-drawn item glyphs for the Armory shop (art bible §4 shape-first rule:
## no textures, each family has its own silhouette so colour is never the only
## cue; v0.12: brass line art). Crystal = faceted gem, Chip = square with pins, Frame = bracket,
## Ammo = round, Squad = three chevrons, Med-Pack = cross.
##
## Example: ShopIcons.draw(self, item, Rect2(8, 8, 56, 56), item.hue)


## Draws the glyph of `it` fitted inside `r` on `ci` (call from its _draw).
## v0.12 (design/ux/hud-v0.12.md §2 Armory): brass-hi line art, no box; `col`
## only supplies the alpha (the item hue is no longer a cue: the silhouette is).
static func draw(ci: CanvasItem, it: ArmoryItemDef, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	var lc := Color(HudPalette.BRASS_HI, col.a)
	var w := clampf(s * 0.07, 1.4, 2.4)
	match it.kind:
		ArmoryItemDef.Kind.CONSUMABLE:
			_cross(ci, c, s * 0.62, lc, w)
		ArmoryItemDef.Kind.SQUAD:
			_chevrons(ci, c, s * 0.62, lc, w)
		ArmoryItemDef.Kind.AMMO:
			_bullet(ci, c, s * 0.62, lc, w)
		_:
			if it.socket == ArmoryItemDef.Socket.FRAME:
				_bracket(ci, c, s * 0.6, lc, w, it.family == ArmoryItemDef.Family.CHIP)
			elif it.family == ArmoryItemDef.Family.CHIP:
				_chip(ci, c, s * 0.6, lc, w)
			else:
				_gem(ci, c, s * 0.7, lc, w)


static func _gem(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	var a := c + Vector2(0.0, -s)
	var r := c + Vector2(s * 0.62, -s * 0.38)
	var b := c + Vector2(0.0, s)
	var l := c + Vector2(-s * 0.62, -s * 0.38)
	ci.draw_polyline(PackedVector2Array([a, r, b, l, a]), col, w, true)
	ci.draw_line(l, r, col, w, true)


static func _chip(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	var body := Rect2(c - Vector2(s * 0.6, s * 0.6), Vector2(s * 1.2, s * 1.2))
	for i in 3:
		var t := -s * 0.35 + s * 0.35 * i
		ci.draw_line(Vector2(body.position.x - s * 0.3, c.y + t), Vector2(body.position.x, c.y + t), col, w)
		ci.draw_line(Vector2(body.end.x, c.y + t), Vector2(body.end.x + s * 0.3, c.y + t), col, w)
		ci.draw_line(Vector2(c.x + t, body.position.y - s * 0.3), Vector2(c.x + t, body.position.y), col, w)
		ci.draw_line(Vector2(c.x + t, body.end.y), Vector2(c.x + t, body.end.y + s * 0.3), col, w)
	ci.draw_rect(body, col, false, w)
	ci.draw_rect(Rect2(c - Vector2(s * 0.22, s * 0.22), Vector2(s * 0.44, s * 0.44)), col, false, w)


static func _bracket(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float, chip: bool) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.3, -s), c + Vector2(-s, -s), c + Vector2(-s, s),
		c + Vector2(-s * 0.3, s)]), col, w, true)
	ci.draw_polyline(PackedVector2Array([c + Vector2(s * 0.3, -s), c + Vector2(s, -s), c + Vector2(s, s),
		c + Vector2(s * 0.3, s)]), col, w, true)
	if chip:
		ci.draw_rect(Rect2(c - Vector2(s * 0.28, s * 0.28), Vector2(s * 0.56, s * 0.56)), col, false, w)
	else:
		ci.draw_line(c + Vector2(-s * 0.4, 0.0), c + Vector2(s * 0.4, 0.0), col, w, true)


static func _bullet(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-s * 0.4, s), c + Vector2(-s * 0.4, -s * 0.3), c + Vector2(0.0, -s),
		c + Vector2(s * 0.4, -s * 0.3), c + Vector2(s * 0.4, s), c + Vector2(-s * 0.4, s)])
	ci.draw_polyline(pts, col, w, true)
	ci.draw_line(c + Vector2(-s * 0.4, s * 0.55), c + Vector2(s * 0.4, s * 0.55), col, w)


static func _chevrons(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	for i in 3:
		var y := -s * 0.6 + s * 0.6 * i
		ci.draw_polyline(PackedVector2Array([c + Vector2(-s, y + s * 0.5), c + Vector2(0.0, y - s * 0.1),
			c + Vector2(s, y + s * 0.5)]), Color(col, col.a * (1.0 - 0.2 * i)), w, true)


static func _cross(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	var t := s * 0.36
	ci.draw_polyline(PackedVector2Array([c + Vector2(-t, -s), c + Vector2(t, -s), c + Vector2(t, -t), c + Vector2(s, -t),
		c + Vector2(s, t), c + Vector2(t, t), c + Vector2(t, s), c + Vector2(-t, s), c + Vector2(-t, t), c + Vector2(-s, t),
		c + Vector2(-s, -t), c + Vector2(-t, -t), c + Vector2(-t, -s)]), col, w, true)


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
