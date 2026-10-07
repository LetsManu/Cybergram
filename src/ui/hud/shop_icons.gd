class_name ShopIcons
extends RefCounted
## Code-drawn item glyphs for the Armory shop (art bible §4 shape-first rule:
## no textures, each family has its own silhouette so colour is never the only
## cue; v0.12: brass line art). Crystal = faceted gem, Chip = square with pins, Frame = bracket,
## Barrel = lens rings / shroud, defensive Frame = shield, Ammo = round, Squad = three chevrons
## (Tether + link, Quick Mint = bolt, Bulwark = shield), Med-Pack = cross.
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
			match it.id:
				&"harmonic_tether":
					_chevrons(ci, c + Vector2(0.0, s * 0.12), s * 0.5, lc, w)
					_link(ci, c + Vector2(0.0, -s * 0.62), s * 0.3, lc, w)
				&"quick_mint":
					_bolt(ci, c, s * 0.66, lc, w)
				&"bulwark_protocol":
					_shield(ci, c, s * 0.66, lc, w)
					_chevrons(ci, c + Vector2(0.0, s * 0.1), s * 0.28, lc, w)
				_:
					_chevrons(ci, c, s * 0.62, lc, w)
		ArmoryItemDef.Kind.AMMO:
			_bullet(ci, c, s * 0.62, lc, w)
		_:
			if it.category == &"defense":  # defensive Frame lines (fit every gun)
				_shield(ci, c, s * 0.66, lc, w)
				if it.counter_tags.has("skill_dps"):
					ci.draw_arc(c + Vector2(0.0, -s * 0.05), s * 0.22, 0.0, TAU, 16, lc, w, true)
				else:
					ci.draw_line(c + Vector2(-s * 0.3, -s * 0.05), c + Vector2(s * 0.3, -s * 0.05), lc, w, true)
			elif it.socket == ArmoryItemDef.Socket.BARREL:
				_lens(ci, c, s * 0.62, lc, w, it.family == ArmoryItemDef.Family.CHIP)
			elif it.socket == ArmoryItemDef.Socket.FRAME:
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


## Barrel: lens rings (Crystal) or a ribbed shroud (Chip), seen from the side.
static func _lens(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float, chip: bool) -> void:
	ci.draw_line(c + Vector2(-s, 0.0), c + Vector2(s, 0.0), col, w, true)
	for i in 3:
		var x := -s * 0.5 + s * 0.5 * i
		if chip:
			ci.draw_rect(Rect2(c + Vector2(x - s * 0.12, -s * 0.5), Vector2(s * 0.24, s)), col, false, w)
		else:
			ci.draw_arc(c + Vector2(x, 0.0), s * (0.35 + 0.12 * i), PI * 0.5, PI * 1.5, 12, col, w, true)


## Defensive shield outline.
static func _shield(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.75, -s * 0.8), c + Vector2(s * 0.75, -s * 0.8),
		c + Vector2(s * 0.75, -s * 0.05), c + Vector2(0.0, s), c + Vector2(-s * 0.75, -s * 0.05),
		c + Vector2(-s * 0.75, -s * 0.8)]), col, w, true)


## Lightning bolt (fast minting).
static func _bolt(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(s * 0.2, -s), c + Vector2(-s * 0.45, s * 0.1),
		c + Vector2(s * 0.05, s * 0.1), c + Vector2(-s * 0.2, s), c + Vector2(s * 0.45, -s * 0.15),
		c + Vector2(-s * 0.05, -s * 0.15), c + Vector2(s * 0.2, -s)]), col, w, true)


## Two linked rings (tether).
static func _link(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	ci.draw_arc(c + Vector2(-s * 0.45, 0.0), s * 0.6, 0.0, TAU, 14, col, w, true)
	ci.draw_arc(c + Vector2(s * 0.45, 0.0), s * 0.6, 0.0, TAU, 14, col, w, true)


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


## Armory v2 glyph (design/gdd/items-and-armory.md §3.2, §3.9): the line's
## silhouette from its main stat or socket, plus a colour-free tier mark in the
## top-left corner: 1 / 2 / 3 diamond pips for Component / Assembly /
## Signature, and a crown over Signatures. Ammo = round, Ammo Mod = round in a
## ring, squad and Med-Pack keep their v1 glyphs.
static func draw_v2(ci: CanvasItem, it: ArmoryItemDef, r: Rect2, col: Color) -> void:
	if not it.is_recipe_item() and it.kind != ArmoryItemDef.Kind.AMMO_MOD:
		draw(ci, it, r, col)
		return
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	var lc := Color(HudPalette.BRASS_HI, col.a)
	var w := clampf(s * 0.08, 1.2, 2.4)
	if it.kind == ArmoryItemDef.Kind.AMMO_MOD:
		_bullet(ci, c, s * 0.5, lc, w)
		ci.draw_arc(c, s * 0.9, 0.0, TAU, 20, lc, w * 0.8, true)
		return
	var gs := s * (0.55 if it.tier == ArmoryItemDef.Tier.COMPONENT else 0.66)
	var gc := c + Vector2(0.0, s * 0.08)
	var main := String(it.stat_ids[0]) if not it.stat_ids.is_empty() else ""
	if it.socket == ArmoryItemDef.Socket.BARREL:
		_lens(ci, gc, gs, lc, w, false)
	elif it.socket == ArmoryItemDef.Socket.FRAME:
		_bracket(ci, gc, gs, lc, w, false)
	else:
		match main:
			"fire_rate_bonus":
				_bolt(ci, gc, gs, lc, w)
			"falloff_range":
				_lens(ci, gc, gs, lc, w, false)
			"spread_mult", "recoil_mult":
				ci.draw_arc(gc, gs * 0.7, 0.0, TAU, 18, lc, w, true)
				ci.draw_line(gc + Vector2(-gs, 0.0), gc + Vector2(gs, 0.0), lc, w, true)
				ci.draw_line(gc + Vector2(0.0, -gs), gc + Vector2(0.0, gs), lc, w, true)
			"mana_regen", "capacity_mult", "reload_time":
				_bracket(ci, gc, gs, lc, w, true)
			"item_max_hp":
				_cross(ci, gc, gs * 0.85, lc, w)
			"gear_armor":
				_shield(ci, gc, gs, lc, w)
				ci.draw_line(gc + Vector2(-gs * 0.4, -gs * 0.1), gc + Vector2(gs * 0.4, -gs * 0.1), lc, w, true)
			"gear_resist":
				_shield(ci, gc, gs, lc, w)
				ci.draw_arc(gc + Vector2(0.0, -gs * 0.1), gs * 0.25, 0.0, TAU, 14, lc, w, true)
			"cooldown_reduction":
				ci.draw_arc(gc, gs * 0.8, -PI * 0.5, PI * 1.2, 18, lc, w, true)
				ci.draw_line(gc, gc + Vector2(0.0, -gs * 0.5), lc, w, true)
				ci.draw_line(gc, gc + Vector2(gs * 0.35, 0.0), lc, w, true)
			"item_move_speed":
				ci.draw_polyline(PackedVector2Array([gc + Vector2(-gs * 0.6, -gs * 0.7), gc + Vector2(gs * 0.1, 0.0),
					gc + Vector2(-gs * 0.6, gs * 0.7)]), lc, w, true)
				ci.draw_polyline(PackedVector2Array([gc + Vector2(0.0, -gs * 0.7), gc + Vector2(gs * 0.7, 0.0),
					gc + Vector2(0.0, gs * 0.7)]), lc, w, true)
			_:
				_gem(ci, gc, gs, lc, w)
	# Tier mark (shape, never colour alone).
	var pips := int(it.tier)
	var ps := maxf(1.6, s * 0.11)
	for i in pips:
		var pc := r.position + Vector2(ps * 1.6 + i * ps * 2.6, ps * 1.6)
		ci.draw_colored_polygon(PackedVector2Array([pc + Vector2(0, -ps), pc + Vector2(ps, 0), pc + Vector2(0, ps),
			pc + Vector2(-ps, 0)]), lc)
	if it.tier == ArmoryItemDef.Tier.SIGNATURE:
		var top := c + Vector2(0.0, -s * 0.78)
		var cw := s * 0.36
		ci.draw_polyline(PackedVector2Array([top + Vector2(-cw, s * 0.16), top + Vector2(-cw, -s * 0.04),
			top + Vector2(-cw * 0.5, s * 0.06), top + Vector2(0.0, -s * 0.12), top + Vector2(cw * 0.5, s * 0.06),
			top + Vector2(cw, -s * 0.04), top + Vector2(cw, s * 0.16), top + Vector2(-cw, s * 0.16)]), lc, w * 0.8, true)
