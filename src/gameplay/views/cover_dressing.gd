class_name CoverDressing
extends Node3D
## Replaces the greybox look of the map's low cover boxes (the orange
## `cover_low` crates of tools/maps/build_shardline_front.gd) with kit crates
## that fill each box exactly (owner plan 2026-10-06 Part 4, docs/placement.md).
## The cover's collision is untouched: the kit pieces stand inside the box's
## volume, so what you see is what stops you. Client only, visual only.
##
## Fill: each box is tiled with the CANDIDATES piece and layer count (1-3)
## that needs the least stretch; every cell's scale must stay within
## MIN_SCALE..MAX_SCALE with axes within MAX_ANISO of each other. A box no
## piece fits keeps its greybox (reported by the placement audit).
## Deterministic (box size).
##
## Use: CoverDressing.spawn(map_root) after the map is in the tree.

const KIT_KEY: StringName = &"world_props"
## The greybox cover material's base colour (cover_low).
const COVER_BASE := Color(0.7, 0.58, 0.4)
## Kit pieces a cover box may be filled with (best fit wins).
const CANDIDATES: Array[StringName] = [&"crate", &"cargo", &"crate_stack", &"barrier"]
## A piece may be scaled evenly within [MIN_SCALE, MAX_SCALE], and its axes
## may differ by at most MAX_ANISO (a 1.4 m crate is fine, a squashed one is not).
const MIN_SCALE: float = 0.7
const MAX_SCALE: float = 1.6
const MAX_ANISO: float = 1.5
## Range culling like the other dressing (m), per CHUNK_M cell: the range is
## measured to a batch's centre, so one map-wide batch would vanish everywhere.
const RANGE_M: float = 120.0
const CHUNK_M: float = 40.0

## [box world transform, box size] of every dressed box (validator, tests).
var boxes: Array = []
## [box world transform, box size] of boxes left greybox (no plausible fill).
var skipped: Array = []
## [piece, world transform] of every placed piece.
var pieces: Array = []
var _root: Node3D


## Dresses `map_root`'s cover boxes; null when the kit is not built.
static func spawn(map_root: Node3D) -> CoverDressing:
	if map_root == null or not WorldModel.exists(KIT_KEY):
		return null
	var d := CoverDressing.new()
	d.name = "CoverDressing"
	d._root = map_root
	map_root.add_child(d)
	return d


func _ready() -> void:
	if _root != null:
		dress(_root)


## True when `mi` is a greybox low-cover box.
static func is_cover(mi: MeshInstance3D) -> bool:
	var bm := mi.mesh as BoxMesh
	if bm == null:
		return false
	var m := bm.material as ShaderMaterial
	if m == null:
		return false
	var c: Variant = m.get_shader_parameter("base_color")
	return c is Color and (c as Color).is_equal_approx(COVER_BASE)


## The pieces filling a box of `size` (local to the box centre): [piece, Transform3D].
## Tries every CANDIDATES piece in 1-3 layers and keeps the least stretched
## fill. `bounds` = {piece: AABB}. Pure.
static func fill(size: Vector3, bounds: Dictionary) -> Array:
	var best: Array = []
	var best_err := INF
	for piece: StringName in CANDIDATES:
		if not bounds.has(piece):
			continue
		var pb: AABB = bounds[piece]
		var long := maxf(size.x, size.z)
		var short := minf(size.x, size.z)
		var p_long := maxf(pb.size.x, pb.size.z)
		var p_short := minf(pb.size.x, pb.size.z)
		for layers in [1, 2, 3]:
			for nl in _counts(long / p_long):
				for ns in _counts(short / p_short):
					var f := _fill_with(size, pb, piece, layers, nl, ns)
					var err := _stretch_error(f)
					if err < best_err - 0.001:
						best_err = err
						best = f
	return best


## Fill of `size` with `piece` (bounds `pb`): `layers` layers of n_long x
## n_short pieces. Pure.
## Piece counts to try along a side that fits `ratio` pieces (round down and up).
static func _counts(ratio: float) -> Array:
	var lo := maxi(1, floori(ratio))
	return [lo] if lo == maxi(1, ceili(ratio)) else [lo, maxi(1, ceili(ratio))]


static func _fill_with(size: Vector3, pb: AABB, piece: StringName, layers: int, n_long: int, n_short: int) -> Array:
	var out: Array = []
	var lh := size.y / float(layers)
	var long := maxf(size.x, size.z)
	var short := minf(size.x, size.z)
	var along_x := size.x >= size.z
	var cell_long := long / n_long
	var cell_short := short / n_short
	# per-axis scale in the piece's own frame (its long side may be local X or Z)
	var piece_x_long := pb.size.x >= pb.size.z
	var sx := (cell_long / pb.size.x) if piece_x_long else (cell_short / pb.size.x)
	var sz := (cell_short / pb.size.z) if piece_x_long else (cell_long / pb.size.z)
	var sy := lh / pb.size.y
	var turn := Basis() if piece_x_long == along_x else Basis(Vector3.UP, PI * 0.5)
	for layer in layers:
		for i in n_long:
			for j in n_short:
				var u := -long * 0.5 + cell_long * (i + 0.5)
				var v := -short * 0.5 + cell_short * (j + 0.5)
				var c := Vector3(u, 0.0, v) if along_x else Vector3(v, 0.0, u)
				c.y = -size.y * 0.5 + lh * layer
				var basis := turn * Basis().scaled(Vector3(sx, sy, sz))
				# centre the piece's bounds on the cell, base on the layer floor
				var off := basis * Vector3(pb.get_center().x, pb.position.y, pb.get_center().z)
				out.append([piece, Transform3D(basis, c - off)])
	return out


## Worst per-axis deviation from the piece's own size, plus a large penalty
## for any piece outside stretch_ok (0 = unscaled). Pure.
static func _stretch_error(f: Array) -> float:
	var e := 0.0
	for x in f:
		var t: Transform3D = x[1]
		var sc := t.basis.get_scale()
		for k in 3:
			e = maxf(e, absf(log(sc[k])))
		if not stretch_ok(t):
			e += 10.0
	return e


## True when a piece's scale is plausible (see MIN_SCALE / MAX_ANISO). Pure.
static func stretch_ok(t: Transform3D) -> bool:
	var s := t.basis.get_scale()
	var lo := minf(s.x, minf(s.y, s.z))
	var hi := maxf(s.x, maxf(s.y, s.z))
	return lo >= MIN_SCALE and hi <= MAX_SCALE and hi / lo <= MAX_ANISO


func dress(map_root: Node3D) -> void:
	var meshes := WorldProps.piece_meshes(KIT_KEY)
	var bounds := WorldProps.bounds_of(meshes)
	if not bounds.has(&"crate"):
		return
	var batches := {}
	for mi: MeshInstance3D in map_root.find_children("*", "MeshInstance3D", true, false):
		if not is_cover(mi):
			continue
		var size := (mi.mesh as BoxMesh).size
		var bx := mi.global_transform
		var f_all := fill(size, bounds)
		if f_all.is_empty() or not f_all.all(func(x: Array) -> bool: return stretch_ok(x[1])):
			skipped.append([bx, size])
			continue  # nothing fits without distortion: keep the greybox
		boxes.append([bx, size])
		for f in f_all:
			var wt: Transform3D = bx * (f[1] as Transform3D)
			pieces.append([f[0], wt])
			var key := [f[0], floori(bx.origin.x / CHUNK_M), floori(bx.origin.z / CHUNK_M)]
			if not batches.has(key):
				batches[key] = []
			batches[key].append(wt)
		mi.visible = false
	var mat := WorldModel.material(KIT_KEY, ModelPalette.TEAM_NEUTRAL)
	for key: Array in batches:
		var p: StringName = key[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[p]
		var list: Array = batches[key]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cover_%s_%d_%d" % [p, key[1], key[2]]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.visibility_range_end = RANGE_M
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
