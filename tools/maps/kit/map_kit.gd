extends RefCounted
## Procedural geometry kit for the map builders (W18-GEO "living map"): rolling
## terrain strips, solid wedges (ramps / stairs), stair step dressing and walls
## with door / window openings. Static helpers that return meshes and shapes;
## the builder owns the scene, materials and the walkable-shape registry.
##
## Motion contract (HeroMotor / HeroBody, assets/data/movement): there is no
## step-up in CharacterBody3D, floor_max_angle is 46 degrees and floor snap is
## 0.3 m. So every stair is a smooth wedge COLLIDER (<= 32 degrees) with the
## steps as non-colliding dressing, and terrain is one smooth trimesh. Server
## and client prediction load the same scene, so both see identical colliders.

## Max visual step rise of stair dressing (m).
const STEP_RISE := 0.25


## Godot front faces are clockwise as seen by the viewer: orders a, b, c so the
## face points along `n`, and adds it with that normal.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	tri(st, a, b, c, n)
	tri(st, a, c, d, n)


static func _face_n(a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> Vector3:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(a - inside) < 0.0:
		n = -n
	return n


## Hexahedron (8 corners: bottom 0..3 then top 4..7, both in the same ring order)
## as a mesh. Used for wedges (sloped top) and any convex block.
static func hexa_mesh(p: PackedVector3Array, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3.ZERO
	for v in p:
		c += v / 8.0
	var faces := [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	for f in faces:
		var a := p[f[0]]
		var b := p[f[1]]
		var cc := p[f[2]]
		var d := p[f[3]]
		var n := _face_n(a, b, cc, c)
		if n.length_squared() < 0.5:
			n = _face_n(a, cc, d, c)
		if n.length_squared() < 0.5:
			continue
		quad(st, a, b, cc, d, n)
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


## Solid wedge in world space over the rect [x0,x1] x [z0,z1]: the top rises
## linearly from y_a on the low-coordinate side to y_b on the high side of
## `axis` (0 = along x, 2 = along z); the bottom is flat at `base`.
## Returns the 8 corners (bottom ring, then top ring).
static func wedge_points(x0: float, x1: float, z0: float, z1: float, axis: int, y_a: float, y_b: float, base: float) -> PackedVector3Array:
	var ring := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
	var out := PackedVector3Array()
	for r in ring:
		out.append(Vector3(r.x, base, r.y))
	for r in ring:
		var t: float = (r.x - x0) / (x1 - x0) if axis == 0 else (r.y - z0) / (z1 - z0)
		out.append(Vector3(r.x, lerpf(y_a, y_b, t), r.y))
	return out


static func convex(points: PackedVector3Array) -> ConvexPolygonShape3D:
	var s := ConvexPolygonShape3D.new()
	s.points = points
	return s


## Stair-step dressing for a wedge (non-colliding): boxes whose front edges sit
## on the wedge's slope, so the visual steps never poke through the collider by
## more than one step rise.
static func steps_mesh(x0: float, x1: float, z0: float, z1: float, axis: int, y_a: float, y_b: float, mat: Material) -> ArrayMesh:
	var n := maxi(2, ceili(absf(y_b - y_a) / STEP_RISE))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := minf(y_a, y_b)
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		# step i spans t0..t1 along the axis, top at the higher end of the slope there
		var top := maxf(lerpf(y_a, y_b, t0), lerpf(y_a, y_b, t1))
		var bx0 := x0
		var bx1 := x1
		var bz0 := z0
		var bz1 := z1
		if axis == 0:
			bx0 = lerpf(x0, x1, t0)
			bx1 = lerpf(x0, x1, t1)
		else:
			bz0 = lerpf(z0, z1, t0)
			bz1 = lerpf(z0, z1, t1)
		var p := wedge_points(bx0, bx1, bz0, bz1, axis, top + 0.02, top + 0.02, lo - 0.05)
		_hexa_into(st, p)
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


static func _hexa_into(st: SurfaceTool, p: PackedVector3Array) -> void:
	var c := Vector3.ZERO
	for v in p:
		c += v / 8.0
	for f in [[4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		var n := _face_n(p[f[0]], p[f[1]], p[f[2]], c)
		quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], n)


## Rolling floor strip: lateral x0..x1 (world x), along world z through the
## samples zs[i] with top heights ys[i]; `thick` m deep. Returns [ArrayMesh,
## ConcavePolygonShape3D] (top + side skirts; the shape is two-sided).
static func terrain_strip(x0: float, x1: float, zs: PackedFloat32Array, ys: PackedFloat32Array, thick: float, mat: Material) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in zs.size() - 1:
		var za := zs[i]
		var zb := zs[i + 1]
		var a0 := Vector3(x0, ys[i], za)
		var a1 := Vector3(x1, ys[i], za)
		var b0 := Vector3(x0, ys[i + 1], zb)
		var b1 := Vector3(x1, ys[i + 1], zb)
		var up := (b0 - a0).cross(a1 - a0).normalized()
		if up.y < 0.0:
			up = -up
		quad(st, a0, a1, b1, b0, up)
		faces.append_array([a0, a1, b1, a0, b1, b0])
		for side in [[a0, b0, Vector3.LEFT], [a1, b1, Vector3.RIGHT]]:
			var p: Vector3 = side[0]
			var q: Vector3 = side[1]
			var d := Vector3(0, -thick, 0)
			quad(st, p, q, q + d, p + d, side[2])
			faces.append_array([p, q, q + d, p, q + d, p + d])
		var dn := Vector3(0, -thick, 0)
		quad(st, a0 + dn, a1 + dn, b1 + dn, b0 + dn, Vector3.DOWN)
	var m := st.commit()
	m.surface_set_material(0, mat)
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	return [m, sh]


## Splits the wall run [a0, a1] (along the wall, metres) of height h into box
## pieces around openings [[from, to, y0, y1], ...] (doors y0 = 0, windows
## y0 > 0). Returns [[along_from, along_to, y_from, y_to], ...].
static func wall_pieces(a0: float, a1: float, h: float, openings: Array) -> Array:
	var ops := openings.duplicate()
	ops.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var out := []
	var cur := a0
	for o in ops:
		if o[0] > cur + 0.01:
			out.append([cur, o[0], 0.0, h])
		if o[2] > 0.01:
			out.append([o[0], o[1], 0.0, o[2]])
		if o[3] < h - 0.01:
			out.append([o[0], o[1], o[3], h])
		cur = o[1]
	if a1 > cur + 0.01:
		out.append([cur, a1, 0.0, h])
	return out
