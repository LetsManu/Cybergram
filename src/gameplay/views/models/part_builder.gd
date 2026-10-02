class_name PartBuilder
extends RefCounted
## Accumulates shaped primitives into ONE ArrayMesh (one draw call per body
## segment). Each vertex carries its material zone for the toon master
## (COLOR = zone albedo, UV = (kind, emission energy)) and a smoothed outline
## direction in TANGENT.xyz, so the inverted-hull outline stays closed on hard
## box corners. Primitive geometry comes from Godot's PrimitiveMesh arrays.

enum Kind { FLAT, TRIM, CHROME, NEON, GLOW, METAL, SIGNAL, SKIN }

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _t := PackedFloat32Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _i := PackedInt32Array()
## Keep the primitive's own UVs (holo panels with a UV pattern) instead of
## encoding the zone kind into UV.
var keep_uv: bool = false

static var _prims: Dictionary = {}


static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled_local(scl)
	return Transform3D(b, pos)


func is_empty() -> bool:
	return _i.is_empty()


func triangle_count() -> int:
	return _i.size() / 3


## Box; `taper` scales the top face (x, z) for V-tapers, flares and wedges.
func box(size: Vector3, t: Transform3D, color: Color, kind: int = Kind.FLAT, energy: float = 0.0,
		taper: Vector2 = Vector2.ONE) -> PartBuilder:
	var a := _arrays("box", func() -> PrimitiveMesh:
		var m := BoxMesh.new()
		return m)
	_append(a, t, size, color, kind, energy, true, taper)
	return self


## Cylinder along local Y (top / bottom radius may differ: cones, tapered limbs).
func cyl(r_top: float, r_bot: float, h: float, t: Transform3D, color: Color, kind: int = Kind.FLAT,
		energy: float = 0.0, segs: int = 10) -> PartBuilder:
	var key := "cyl%d|%.3f" % [segs, r_top / maxf(r_bot, 0.0001)]
	var ratio := r_top / maxf(r_bot, 0.0001)
	var a := _arrays(key, func() -> PrimitiveMesh:
		var m := CylinderMesh.new()
		m.radial_segments = segs
		m.rings = 0
		m.height = 1.0
		m.bottom_radius = 0.5 if ratio <= 1.0 else 0.5 / ratio
		m.top_radius = 0.5 * ratio if ratio <= 1.0 else 0.5
		return m)
	var rb := r_bot if ratio <= 1.0 else r_top
	_append(a, t, Vector3(rb * 2.0, h, rb * 2.0), color, kind, energy, false)
	return self


func sphere(r: float, t: Transform3D, color: Color, kind: int = Kind.FLAT, energy: float = 0.0,
		segs: int = 12) -> PartBuilder:
	var a := _arrays("sph%d" % segs, func() -> PrimitiveMesh:
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = segs
		m.rings = maxi(4, segs / 2)
		return m)
	_append(a, t, Vector3.ONE * r * 2.0, color, kind, energy, false)
	return self


## Capsule along local Y, total height `h` (>= 2r).
func capsule(r: float, h: float, t: Transform3D, color: Color, kind: int = Kind.FLAT, energy: float = 0.0) -> PartBuilder:
	var hr := snappedf(maxf(h, r * 2.0) / r, 0.25)
	var a := _arrays("cap|%.2f" % hr, func() -> PrimitiveMesh:
		var m := CapsuleMesh.new()
		m.radius = 0.5
		m.height = hr * 0.5
		m.radial_segments = 10
		m.rings = 3
		return m)
	_append(a, t, Vector3.ONE * r * 2.0, color, kind, energy, false)
	return self


## Triangular prism (PrismMesh); `apex` 0..1 moves the ridge left to right.
func prism(size: Vector3, t: Transform3D, color: Color, kind: int = Kind.FLAT, energy: float = 0.0,
		apex: float = 0.5) -> PartBuilder:
	var a := _arrays("prism|%.2f" % apex, func() -> PrimitiveMesh:
		var m := PrismMesh.new()
		m.left_to_right = apex
		return m)
	_append(a, t, size, color, kind, energy, true)
	return self


## Flat quad facing +Z (UV 0..1 kept when keep_uv is set).
func quad(size: Vector2, t: Transform3D, color: Color, kind: int = Kind.FLAT, energy: float = 0.0) -> PartBuilder:
	var a := _arrays("quad", func() -> PrimitiveMesh:
		var m := QuadMesh.new()
		m.size = Vector2.ONE
		return m)
	_append(a, t, Vector3(size.x, size.y, 1.0), color, kind, energy, false)
	return self


## Torus in local XZ; radii in metres.
func torus(inner: float, outer: float, t: Transform3D, color: Color, kind: int = Kind.FLAT,
		energy: float = 0.0, rings: int = 16, segs: int = 6) -> PartBuilder:
	var ratio := snappedf(inner / outer, 0.01)
	var a := _arrays("tor%d|%d|%.2f" % [rings, segs, ratio], func() -> PrimitiveMesh:
		var m := TorusMesh.new()
		m.inner_radius = ratio * 0.5
		m.outer_radius = 0.5
		m.rings = rings
		m.ring_segments = segs
		return m)
	_append(a, t, Vector3(outer * 2.0, outer * 2.0, outer * 2.0), color, kind, energy, false)
	return self


## Tapered limb hanging DOWN from `top` (a pivot-friendly cylinder with
## rounded ends): length `len`, radii at top / bottom.
func limb(r_top: float, r_bot: float, length: float, top: Vector3, color: Color, kind: int = Kind.FLAT,
		rot_deg: Vector3 = Vector3.ZERO) -> PartBuilder:
	var b := Basis.from_euler(rot_deg * (PI / 180.0))
	var centre := top + b * Vector3(0.0, -length * 0.5, 0.0)
	cyl(r_top, r_bot, length, Transform3D(b, centre), color, kind, 0.0, 10)
	sphere(r_top, Transform3D(b, top), color, kind, 0.0, 8)
	sphere(r_bot, Transform3D(b, top + b * Vector3(0.0, -length, 0.0)), color, kind, 0.0, 8)
	return self


## Mirrored pair helper: calls `f(sign)` for sign = +1 and -1.
func pair(f: Callable) -> PartBuilder:
	f.call(1.0)
	f.call(-1.0)
	return self


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _i.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_TANGENT] = _t
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_INDEX] = _i
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func _arrays(key: String, make: Callable) -> Array:
	if not _prims.has(key):
		var pm: PrimitiveMesh = make.call()
		_prims[key] = pm.get_mesh_arrays()
	return _prims[key]


func _append(a: Array, t: Transform3D, size: Vector3, color: Color, kind: int, energy: float,
		hard: bool, taper: Vector2 = Vector2.ONE) -> void:
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var base := _v.size()
	var src_uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if keep_uv else PackedVector2Array()
	var nb := t.basis.inverse().transposed()
	var uv := Vector2(float(kind), energy)
	for k in verts.size():
		var lv := verts[k]  # unit primitive, -0.5..0.5
		var p := lv * size
		if taper != Vector2.ONE and lv.y > 0.0:
			p.x *= taper.x
			p.z *= taper.y
		_v.append(t * p)
		var n := (nb * norms[k]).normalized()
		_n.append(n)
		var od := n
		if hard:
			var s := Vector3(signf(lv.x), signf(lv.y), signf(lv.z))
			od = (t.basis * (s * size)).normalized()
			if od.dot(n) < 0.2:
				od = n
		_t.append_array(PackedFloat32Array([od.x, od.y, od.z, 1.0]))
		_c.append(color)
		_uv.append(src_uv[k] if keep_uv else uv)
	var flip := t.basis.determinant() < 0.0
	for k in range(0, idx.size(), 3):
		if flip:
			_i.append_array(PackedInt32Array([base + idx[k], base + idx[k + 2], base + idx[k + 1]]))
		else:
			_i.append_array(PackedInt32Array([base + idx[k], base + idx[k + 1], base + idx[k + 2]]))
