class_name BuildIcons
extends RefCounted
## Armory v2 build icons for the HUD weapon panel, the Tab scoreboard and the
## death card (items-and-armory.md §3.8 rule 7). One cell per build place
## (Core, Barrel, Frame, Ammo Type, Ammo Mod, open slots 0..5). Tier never by
## colour alone (weapons-and-mods.md §3.6.2): the glyph grows with the tier
## and carries 1-3 pips; Signatures add a ring. Ammo = circle, Mod = small
## square, spares = hollow and dim, empty = dim outline.

const GAP_RATIO: float = 0.14
## Gap between the 5 gun places and the 6 open slots, in cells.
const GROUP_GAP: float = 0.45


## True when any place of `build` holds an item.
static func has_any(build: PackedInt32Array) -> bool:
	for v in build:
		if v >= 0:
			return true
	return false


## Width of a strip of `places` cells of size `cell`.
static func strip_width(cell: float, places: int = SnapshotData.EntityState.BUILD_SIZE) -> float:
	var gap := cell * GAP_RATIO
	var w := places * cell + (places - 1) * gap
	if places > SnapshotData.EntityState.B_OPEN0:
		w += cell * GROUP_GAP
	return w


## Draws `places` cells of `build` from `at` (top-left). Returns the width.
static func draw_strip(ci: CanvasItem, build: PackedInt32Array, cat: ArmoryCatalogDef, at: Vector2,
		cell: float, alpha: float = 1.0, places: int = SnapshotData.EntityState.BUILD_SIZE) -> float:
	var gap := cell * GAP_RATIO
	var x := at.x
	for i in places:
		if i == SnapshotData.EntityState.B_OPEN0:
			x += cell * GROUP_GAP
		var r := Rect2(Vector2(x, at.y), Vector2(cell, cell))
		var it := BuildVisuals.item_at(build, i, cat)
		var spare := i >= SnapshotData.EntityState.B_OPEN0 and SnapshotData.spare_at(build, i - SnapshotData.EntityState.B_OPEN0)
		draw_cell(ci, r, it, i, spare, alpha)
		x += cell + gap
	return x - gap - at.x


## One cell: frame + glyph for `item` at build place `place`.
static func draw_cell(ci: CanvasItem, r: Rect2, item: ArmoryItemDef, place: int, spare: bool, alpha: float) -> void:
	var frame := Color(HudPalette.HAIR_STRONG, 0.8 * alpha)
	ci.draw_rect(Rect2(r.position + Vector2.ONE, r.size - Vector2.ONE * 2.0), Color(HudPalette.INK_DEEP, 0.55 * alpha))
	ci.draw_rect(r, frame, false, 1.0)
	if item == null:
		return
	var c := Color(item.hue, alpha * (0.35 if spare else 1.0))
	var ctr := r.get_center() - Vector2(0.0, r.size.y * 0.08)
	var s := r.size.x
	if place == SnapshotData.EntityState.B_AMMO:
		var ac := ArmoryVisualsData.ammo_color(item.ammo_type, item.hue)
		ci.draw_circle(ctr, s * 0.26, Color(ac, alpha))
		ci.draw_arc(ctr, s * 0.26, 0.0, TAU, 16, Color(HudPalette.IVORY, 0.6 * alpha), 1.0, true)
		return
	if place == SnapshotData.EntityState.B_MOD:
		ci.draw_rect(Rect2(ctr - Vector2.ONE * s * 0.16, Vector2.ONE * s * 0.32), c)
		return
	var t := BuildVisuals.visual_tier(item)
	var rad := s * (0.16 + 0.07 * (t - 1))  # size grows with tier
	var pts := PackedVector2Array([ctr + Vector2(0, -rad), ctr + Vector2(rad * 0.8, 0), ctr + Vector2(0, rad), ctr + Vector2(-rad * 0.8, 0)])
	if spare:
		pts.append(pts[0])
		ci.draw_polyline(pts, c, 1.0, true)
	else:
		ci.draw_colored_polygon(pts, c)
	if t >= 3:
		ci.draw_arc(ctr, rad + s * 0.08, 0.0, TAU, 20, Color(HudPalette.IVORY, 0.75 * alpha), 1.0, true)
	# Tier pips along the bottom edge (count = tier).
	var pw := s * 0.1
	var px := r.get_center().x - (t * pw + (t - 1) * pw * 0.6) * 0.5
	for k in t:
		ci.draw_rect(Rect2(Vector2(px + k * pw * 1.6, r.end.y - pw * 1.6), Vector2(pw, pw)), Color(HudPalette.IVORY, 0.85 * alpha))
