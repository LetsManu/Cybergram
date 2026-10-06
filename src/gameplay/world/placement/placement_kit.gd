class_name PlacementKit
extends RefCounted
## Shared placement helper (owner plan 2026-10-06, docs/placement.md): every
## world placement (props, decals, objective dressing) snaps, aligns and checks
## through these functions, and PlacementValidator re-checks the result with
## the same ones. Static and pure apart from the physics queries on `space`.
##
## Conventions: an object is a local AABB `box` (its mesh bounds, Y up, base at
## box.position.y) placed by `xf` (basis may be scaled).
##
## Example:
##   var g := PlacementKit.ground(space, p)          # {pos, normal} or {}
##   var xf := PlacementKit.snap(space, xf0, box, 1.0)
##   if PlacementKit.overlaps(space, xf, box, 0.05): ...

## Collision layer of the static world (HeroBody.LAYER_WORLD).
const WORLD_MASK: int = 1


## First surface hit by a ray `from` -> `to` ({position, normal, ...} or {}).
static func ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	q.collide_with_areas = false
	return space.intersect_ray(q)


## The surface below `p` (searching `up` m above to `down` m below):
## {pos, normal} or {} when there is none.
static func ground(space: PhysicsDirectSpaceState3D, p: Vector3, up: float = 0.5, down: float = 1.5) -> Dictionary:
	var h := ray(space, p + Vector3.UP * up, p - Vector3.UP * down)
	if h.is_empty():
		return {}
	return {"pos": h.position, "normal": h.normal}


## The 4 base corners + base centre of `box` under `xf`, in world space.
static func footprint(xf: Transform3D, box: AABB) -> PackedVector3Array:
	var y := box.position.y
	var a := box.position
	var b := box.end
	var out := PackedVector3Array()
	for c: Vector2 in [Vector2(a.x, a.z), Vector2(b.x, a.z), Vector2(b.x, b.z), Vector2(a.x, b.z),
			Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)]:
		out.append(xf * Vector3(c.x, y, c.y))
	return out


## `xf` moved down / up so the base sits on the highest surface under its
## footprint (within `search` m). Unchanged when nothing is found.
static func snap(space: PhysicsDirectSpaceState3D, xf: Transform3D, box: AABB, search: float = 1.0) -> Transform3D:
	var top := -INF
	for c in footprint(xf, box):
		var g := ground(space, c, search, search)
		if not g.is_empty():
			top = maxf(top, (g.pos as Vector3).y)
	if top == -INF:
		return xf
	var base_y: float = footprint(xf, box)[4].y
	return Transform3D(xf.basis, xf.origin + Vector3(0, top - base_y, 0))


## `basis` turned so its Y axis is `normal`, keeping its heading (scale kept).
static func align_up(basis: Basis, normal: Vector3) -> Basis:
	var s := basis.get_scale()
	var y := normal.normalized()
	var z := basis.z.normalized()
	z = (z - y * z.dot(y))
	if z.length() < 0.01:
		z = Vector3.BACK - y * Vector3.BACK.dot(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z).scaled_local(s)


## Fraction (0..1) of the footprint probes with a surface within `tol` of the base.
static func support(space: PhysicsDirectSpaceState3D, xf: Transform3D, box: AABB, tol: float) -> float:
	return support_at(space, footprint(xf, box), tol)


## Fraction (0..1) of the base points `pts` with a surface within `tol`.
static func support_at(space: PhysicsDirectSpaceState3D, pts: PackedVector3Array, tol: float) -> float:
	var ok := 0
	for c in pts:
		var g := ground(space, c, tol + 0.3, tol + 0.3)
		if not g.is_empty() and absf((g.pos as Vector3).y - c.y) <= tol:
			ok += 1
	return float(ok) / float(pts.size())


## True when `box` under `xf`, shrunk `shrink` m a side and lifted `lift` m off
## its base, overlaps static collision.
static func overlaps(space: PhysicsDirectSpaceState3D, xf: Transform3D, box: AABB, shrink: float,
		lift: float = 0.0) -> bool:
	var s := xf.basis.get_scale()
	var size := (box.size - Vector3(2.0 * shrink, 2.0 * shrink + lift, 2.0 * shrink) / s).max(Vector3(0.02, 0.02, 0.02))
	var shape := BoxShape3D.new()
	shape.size = size * s
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = WORLD_MASK
	q.collide_with_areas = false
	var c := box.get_center()
	c.y = box.position.y + (shrink + lift) / s.y + size.y * 0.5
	q.transform = Transform3D(xf.basis.orthonormalized(), xf * c)
	return not space.intersect_shape(q, 1).is_empty()


## Distance from the box face on local +Z (the back) to the first surface
## behind it, measured at `height_frac` of the box height (INF = none in `reach`).
static func back_gap(space: PhysicsDirectSpaceState3D, xf: Transform3D, box: AABB, height_frac: float,
		reach: float = 1.0) -> float:
	var dir := xf.basis.z.normalized()
	var p := xf * Vector3(box.get_center().x, box.position.y + box.size.y * height_frac, box.end.z)
	var h := ray(space, p - dir * 0.05, p + dir * reach)
	if h.is_empty():
		return INF
	return maxf(0.0, ((h.position as Vector3) - p).dot(dir))


## Oriented box of `box` under `xf`: [centre, axis x, axis y, axis z, half extents].
static func obb(xf: Transform3D, box: AABB, shrink: float = 0.0) -> Array:
	var s := xf.basis.get_scale()
	var half := (box.size * s * 0.5 - Vector3.ONE * shrink).max(Vector3(0.001, 0.001, 0.001))
	return [xf * box.get_center(), xf.basis.x.normalized(), xf.basis.y.normalized(), xf.basis.z.normalized(), half]


## True when two oriented boxes (obb()) overlap (separating axis test).
static func obb_overlap(a: Array, b: Array) -> bool:
	var axes: Array[Vector3] = [a[1], a[2], a[3], b[1], b[2], b[3]]
	for i in 3:
		for j in 3:
			var c := (a[1 + i] as Vector3).cross(b[1 + j])
			if c.length_squared() > 1e-6:
				axes.append(c.normalized())
	var d: Vector3 = b[0] - a[0]
	for ax in axes:
		if absf(d.dot(ax)) > _radius(a, ax) + _radius(b, ax):
			return false
	return true


static func _radius(o: Array, ax: Vector3) -> float:
	var h: Vector3 = o[4]
	return h.x * absf((o[1] as Vector3).dot(ax)) + h.y * absf((o[2] as Vector3).dot(ax)) \
			+ h.z * absf((o[3] as Vector3).dot(ax))
