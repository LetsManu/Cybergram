class_name PlacementValidator
extends RefCounted
## Physical-plausibility check for placed world objects (owner plan
## 2026-10-06, docs/placement.md). Each rule below is checked per Item with
## PlacementKit against the static collision in `space`; a violation names the
## rule, the item and what was measured. An item with a `waiver` reason keeps
## its violations in the report but they do not fail (CI fails on unwaived ones).
##
## Rules (PlacementRulesDef holds the numbers):
##   grounded     base within ground_tol_m of the surface under its centre
##   supported    >= support_min of the footprint probes find that surface
##                (mounted items: the wall behind instead, see mounted)
##   mounted      wall-mounted items: wall within mount_gap_m behind the back at
##                1/4 and 3/4 of the height
##   upright      tilt from vertical <= upright_max_deg (floor / wall / roof)
##   no_overlap   box (shrunk overlap_shrink_m) clear of static collision, and of
##                every other item's box
##   scale        height within [min, max] hero heights
##   faces_floor  items flagged `faces_walkable`: floor within front_floor_m in
##                front of their face (local -Z)
##   keep_out     the `keep_out` callable (route / spawn / objective clearance)
##                names no rule for the footprint centre
##   decal_surface  decals: a floor-like surface under the centre
##   decal_clear    decals: the projection box meets no wall or step above the
##                  floor (it would paint up a wall) and no prop
##
## Example:
##   var v := PlacementValidator.new(rules)
##   var report := v.validate(space, items)
##   if PlacementValidator.unwaived(report) > 0: ...

## One placed object.
class Item:
	var id: String
	## &"floor", &"wall" (stands against a wall), &"mounted" (hangs on a wall),
	## &"roof", &"flat" (a sheet lying on the floor: no scale / overlap test),
	## &"cover" (dresses a cover box: it stands inside that box's own
	## collision, so only grounded / supported / upright apply) or &"decal".
	var kind: StringName = &"floor"
	var xform: Transform3D
	## Local bounds (mesh AABB; decals: the projection box, centred).
	var box: AABB
	var faces_walkable := false
	## Real ground contact (4 world corners) when it is smaller than the box
	## (a lamp's base under its arm); empty = the box's base.
	var foot: PackedVector3Array = PackedVector3Array()
	## Decals: Decal.normal_fade (how much it fades on steep surfaces).
	var normal_fade: float = 0.0
	## Reason this item may break the rules ("" = none).
	var waiver: String = ""

	func _init(id_: String, kind_: StringName, xform_: Transform3D, box_: AABB) -> void:
		id = id_
		kind = kind_
		xform = xform_
		box = box_


## One broken rule.
class Violation:
	var rule: StringName
	var item: String
	var detail: String
	var waived: bool = false
	var reason: String = ""

	func text() -> String:
		var w := " (waived: %s)" % reason if waived else ""
		return "%s  %s  %s%s" % [rule, item, detail, w]


var rules: PlacementRulesDef
## Callable(p: Vector3, radius: float) -> String rule name ("" = clear).
var keep_out: Callable = Callable()


func _init(rules_: PlacementRulesDef = null) -> void:
	rules = rules_ if rules_ != null else PlacementRulesDef.new()


## Every violation of `items` (waived ones included, flagged).
func validate(space: PhysicsDirectSpaceState3D, items: Array) -> Array[Violation]:
	var out: Array[Violation] = []
	var solids: Array = []
	for it: Item in items:
		if it.kind != &"decal" and it.kind != &"cover":
			solids.append([it, PlacementKit.obb(it.xform, _solid_box(it), rules.overlap_shrink_m)])
	for it: Item in items:
		var found: Array[Violation] = []
		if it.kind == &"decal":
			_check_decal(space, it, solids, found)
		else:
			_check_solid(space, it, found)
		for v in found:
			v.item = it.id
			v.waived = it.waiver != ""
			v.reason = it.waiver
			out.append(v)
	# item against item (each pair once)
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			if PlacementKit.obb_overlap(solids[i][1], solids[j][1]):
				var a: Item = solids[i][0]
				var b: Item = solids[j][0]
				var v := _v(&"no_overlap", "overlaps %s" % b.id)
				v.item = a.id
				v.waived = a.waiver != "" or b.waiver != ""
				v.reason = a.waiver if a.waiver != "" else b.waiver
				out.append(v)
	return out


## The violations of one item against the level alone (no item pairs, no
## keep-out): what a placer checks before it accepts a spot.
func check_item(space: PhysicsDirectSpaceState3D, it: Item) -> Array[Violation]:
	var found: Array[Violation] = []
	var saved := keep_out
	keep_out = Callable()
	if it.kind == &"decal":
		_check_decal(space, it, [], found)
	else:
		_check_solid(space, it, found)
	keep_out = saved
	return found


## Oriented box an item occupies for the item-pair test (null for decals).
func solid_obb(it: Item) -> Array:
	return [] if it.kind == &"decal" else PlacementKit.obb(it.xform, _solid_box(it), rules.overlap_shrink_m)


## Oriented box of a decal's projection above its floor (what a prop must not
## stand in), or [] for a non-decal.
func decal_obb(space: PhysicsDirectSpaceState3D, it: Item) -> Array:
	if it.kind != &"decal":
		return []
	var g := PlacementKit.ground(space, it.xform.origin, 0.3, 0.3)
	var y: float = it.xform.origin.y if g.is_empty() else (g.pos as Vector3).y
	var top_half := AABB(Vector3(it.box.position.x, 0.0, it.box.position.z),
		Vector3(it.box.size.x, it.box.end.y, it.box.size.z))
	return PlacementKit.obb(Transform3D(it.xform.basis, Vector3(it.xform.origin.x, y, it.xform.origin.z)), top_half)


## Number of violations without a waiver.
static func unwaived(report: Array) -> int:
	return report.filter(func(v: Violation) -> bool: return not v.waived).size()


## Plain-text report: counts per rule, then each violation.
static func format(report: Array, checked: int) -> String:
	var per := {}
	for v: Violation in report:
		per[v.rule] = int(per.get(v.rule, 0)) + 1
	var lines := PackedStringArray(["placement: %d items, %d violations, %d unwaived" % [checked, report.size(), unwaived(report)]])
	var keys := per.keys()
	keys.sort()
	for k in keys:
		lines.append("  %s: %d" % [k, per[k]])
	for v: Violation in report:
		lines.append("  - " + v.text())
	return "\n".join(lines)


func _check_solid(space: PhysicsDirectSpaceState3D, it: Item, out: Array[Violation]) -> void:
	var xf := it.xform
	var up := xf.basis.y.normalized()
	var tilt := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
	if tilt > rules.upright_max_deg:
		out.append(_v(&"upright", "tilted %.1f deg" % tilt))
	var pts := _contact(it)
	var centre: Vector3 = pts[4]
	if it.kind != &"mounted":
		var g := PlacementKit.ground(space, centre, 0.5, 2.0)
		var gap := INF if g.is_empty() else centre.y - (g.pos as Vector3).y
		if absf(gap) > rules.ground_tol_m:
			out.append(_v(&"grounded", "no surface under the base" if g.is_empty() else "base %+.2f m off the surface" % gap))
		var sup := PlacementKit.support_at(space, pts, rules.ground_tol_m)
		if sup < rules.support_min:
			out.append(_v(&"supported", "%.0f%% of the footprint on a surface" % (sup * 100.0)))
	else:
		for f: float in [0.25, 0.75]:
			var bg := PlacementKit.back_gap(space, xf, it.box, f, 1.0)
			if bg > rules.mount_gap_m:
				out.append(_v(&"mounted", "no wall within %.2f m behind (at %d%% height)" % [rules.mount_gap_m, int(f * 100)]))
				break
	if it.kind == &"cover":
		return
	if it.kind == &"flat":
		_keep_out(it, pts, out)
		return
	if PlacementKit.overlaps(space, xf, _solid_box(it), rules.overlap_shrink_m):
		out.append(_v(&"no_overlap", "box intersects the level geometry"))
	var h := it.box.size.y * xf.basis.get_scale().y
	var ratio := h / rules.hero_height_m
	if ratio > rules.max_height_ratio or ratio < rules.min_height_ratio:
		out.append(_v(&"scale", "%.2f m = %.2f hero heights" % [h, ratio]))
	if it.faces_walkable:
		var front := xf * Vector3(it.box.get_center().x, it.box.position.y, it.box.position.z)
		var ahead := front - xf.basis.z.normalized() * rules.front_floor_m
		var g2 := PlacementKit.ground(space, ahead, 0.5, 0.5)
		if g2.is_empty() or (g2.normal as Vector3).y < 0.9 or PlacementKit.ray(space, front + Vector3.UP * 0.8, ahead + Vector3.UP * 0.8).size() > 0:
			out.append(_v(&"faces_floor", "no open floor %.1f m in front" % rules.front_floor_m))
	_keep_out(it, pts, out)


func _keep_out(it: Item, pts: PackedVector3Array, out: Array[Violation]) -> void:
	var centre: Vector3 = pts[4]
	if keep_out.is_valid():
		var r := 0.0
		for i in 4:
			r = maxf(r, Vector2(pts[i].x - centre.x, pts[i].z - centre.z).length())
		var why: String = keep_out.call(centre, r)
		if why != "":
			out.append(_v(&"keep_out", "footprint in %s" % why))


func _check_decal(space: PhysicsDirectSpaceState3D, it: Item, solids: Array, out: Array[Violation]) -> void:
	var xf := it.xform
	var c := xf.origin
	var half := it.box.size.y * 0.5 * xf.basis.get_scale().y
	if half > rules.decal_max_half_height_m:
		out.append(_v(&"decal_clear", "projection %.2f m deep (max %.2f)" % [half, rules.decal_max_half_height_m]))
	var g := PlacementKit.ground(space, c, 0.3, 0.3)
	if g.is_empty() or (g.normal as Vector3).y < rules.decal_floor_normal_y:
		out.append(_v(&"decal_surface", "no floor under the decal"))
		return
	# The upper half of the projection box (above the floor + 4 cm): a ledge,
	# step or prop top in it gets painted; a wall gets painted too unless the
	# decal fades on steep surfaces (normal_fade).
	var floor_y: float = (g.pos as Vector3).y
	var top_half := AABB(Vector3(it.box.position.x, 0.0, it.box.position.z),
		Vector3(it.box.size.x, it.box.end.y, it.box.size.z))
	var on_floor := Transform3D(xf.basis, Vector3(c.x, floor_y, c.z))
	var top := top_half.end.y * xf.basis.get_scale().y
	var bad := ""
	for i in 3:
		for j in 3:
			if bad != "":
				break
			var lp := Vector3(lerpf(top_half.position.x, top_half.end.x, (i + 0.5) / 3.0), 0.0,
				lerpf(top_half.position.z, top_half.end.z, (j + 0.5) / 3.0))
			var wp := on_floor * lp
			# going down through the box, the first surface must be the decal's own
			# floor (within ground_tol_m of its plane); higher = a ledge gets
			# painted, nothing = the decal hangs over a drop
			var h := PlacementKit.ray(space, wp + Vector3.UP * top, wp - Vector3.UP * top)
			if h.is_empty():
				bad = "hangs over a drop"
			else:
				var dy: float = (h.position as Vector3).y - wp.y
				if dy > rules.ground_tol_m and (h.normal as Vector3).y > 0.5:
					bad = "paints onto a ledge %.2f m above its floor" % dy
				elif dy < -rules.ground_tol_m:
					bad = "floor drops %.2f m under the decal" % -dy
	if bad != "":
		out.append(_v(&"decal_clear", bad))
	if it.normal_fade < rules.decal_min_normal_fade and top_half.size.y > 0.07 \
			and PlacementKit.overlaps(space, on_floor, top_half, 0.0, 0.04):
		out.append(_v(&"decal_clear", "projection box meets a wall and normal_fade %.2f < %.2f" % [it.normal_fade, rules.decal_min_normal_fade]))
	var me := PlacementKit.obb(on_floor, top_half)
	for s in solids:
		if PlacementKit.obb_overlap(me, s[1]):
			out.append(_v(&"decal_clear", "projects onto %s" % (s[0] as Item).id))
			break


## The 4 base corners + centre of the item's ground contact (foot or box base).
static func _contact(it: Item) -> PackedVector3Array:
	if it.foot.size() == 4:
		var c := (it.foot[0] + it.foot[1] + it.foot[2] + it.foot[3]) * 0.25
		var pts := it.foot.duplicate()
		pts.append(c)
		return pts
	return PlacementKit.footprint(it.xform, it.box)


## The box tested against the level: with a foot, only the column over the foot
## (a lamp's arm may reach over a rail).
static func _solid_box(it: Item) -> AABB:
	if it.foot.size() != 4:
		return it.box
	var inv := it.xform.affine_inverse()
	var lo := Vector3(INF, it.box.position.y, INF)
	var hi := Vector3(-INF, it.box.end.y, -INF)
	for p in it.foot:
		var l := inv * p
		lo = Vector3(minf(lo.x, l.x), lo.y, minf(lo.z, l.z))
		hi = Vector3(maxf(hi.x, l.x), hi.y, maxf(hi.z, l.z))
	return AABB(lo, hi - lo)


static func _v(rule: StringName, detail: String) -> Violation:
	var v := Violation.new()
	v.rule = rule
	v.detail = detail
	return v
