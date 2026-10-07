class_name WorldProps
extends Node3D
## World prop dressing for Shardline Front (docs/assets/props.md; art bible
## §6.1-6.2 lane identities and dressing, §4.6 neon, §10.6 budgets). Client only,
## visual only: the props have NO collision, so the placement guarantees they
## never stand where heroes or Wardlings walk.
##
## Placement (deterministic: WorldPropsDef.placement_seed + the map):
##   1. Wall props. The walkable navmesh's border edges are walked every
##      `edge_step_m`. At each point a horizontal ray along the outward normal
##      must hit a vertical collision face within `wall_search_m`; the same
##      face must be hit at both ends of the prop's width (no door openings,
##      no corners); the prop's back goes on that face, its floor footprint is at
##      most `max_wall_depth_m` deep from it, the floor under the footprint is
##      flat, and a box query over the prop's whole mesh bounds finds no
##      collision. So a prop only ever fills the strip along a wall that the
##      navmesh agent radius (0.5 m) and the wall already make awkward to walk.
##   2. Roof props. Downward rays on a `roof_step_m` grid; a roof is a flat
##      top at `roof_min_y` or higher (above every walkable floor and jump).
##   3. Keep-out: hardpoint zones (+ margin), Armory pad, spawns + Sanctum,
##      Uplink, Foundry, lane gates, side doors, Barricade sockets, Cell
##      Cradles, Supply Caches, Garrison posts, and the lane corridors (the
##      polyline HQ A gate -> hardpoints -> HQ B gate, +- corridor_half_width_m).
##   4. Team pieces (kiosk, cargo) only inside an HQ, with that HQ's team material.
##
## Rendering: one MultiMeshInstance3D per (piece, team, chunk_m cell) sharing
## the kit's toon material (WorldModel.material), so each batch is frustum and
## range culled on its own; a batch of one is a plain MeshInstance3D.
##
## Use (client): WorldProps.spawn(parent, map_def), which places itself after
## the next physics frame (the map's collision must be in the same World3D).

const DEF_PATH := "res://assets/data/world/world_props.tres"

## One placed prop.
class Placement:
	## Kit piece name (mesh node in the glb).
	var piece: StringName
	## MapDef team whose material it uses (-1 = neutral).
	var team: int = -1
	## World transform of the piece.
	var xform: Transform3D
	## &"wall" or &"roof".
	var kind: StringName
	## Zone it was placed in (lane, plaza, hq, flank, roof).
	var zone: StringName
	## Unit vector from the prop towards its wall (wall props), Vector3.ZERO on roofs.
	var wall_dir: Vector3 = Vector3.ZERO
	## Floor footprint corners in world space (back-left, back-right, front-right, front-left).
	var foot: PackedVector3Array = PackedVector3Array()
	## Radius of the floor footprint around its centre (m).
	var foot_radius: float = 0.0


## Accepts a placement only when PlacementValidator finds nothing wrong with it
## against the level and it overlaps no prop accepted before (docs/placement.md).
class Checker:
	var space: PhysicsDirectSpaceState3D
	var bounds: Dictionary
	var v: PlacementValidator
	var taken: Array = []

	func _init(space_: PhysicsDirectSpaceState3D, bounds_: Dictionary) -> void:
		space = space_
		bounds = bounds_
		v = PlacementValidator.new(MapPlacementAudit.rules())

	## Props keep off the floor decals' boxes (a decal would paint the prop).
	func avoid_decals(md: MapDef) -> void:
		if not ResourceLoader.exists(WorldDecals.DEF_PATH):
			return
		var ddef := load(WorldDecals.DEF_PATH) as WorldDecalsDef
		var keep := WorldDecals.plausible_filter(space, ddef)
		for p: WorldDecals.Placement in WorldDecals.plan(md, ddef):
			var hit := WorldDecals.physics_ground(space, p.pos)
			if not hit.is_empty() and keep.call(p, hit):
				taken.append(v.decal_obb(space, WorldDecals.decal_item(p, hit, ddef)))

	func accept(pl: Placement) -> bool:
		if not bounds.has(pl.piece):
			return true
		var it := MapPlacementAudit.item_of(pl, bounds[pl.piece])
		var found := v.check_item(space, it)
		if not found.is_empty():
			WorldProps._reject(StringName("implausible_" + String((found[0] as PlacementValidator.Violation).rule)))
			return false
		var o := v.solid_obb(it)
		if not o.is_empty():
			for t in taken:
				if PlacementKit.obb_overlap(o, t):
					WorldProps._reject(&"overlaps_prop")
					return false
			taken.append(o)
		return true


## Placements built by the last place() call of this node.
var placements: Array = []
var _md: MapDef
var _def: WorldPropsDef


## Creates the dressing for `md` under `parent` with the default rules
## (DEF_PATH). Null when the rules or the kit are missing.
static func spawn(parent: Node, md: MapDef) -> WorldProps:
	var def := load(DEF_PATH) as WorldPropsDef if ResourceLoader.exists(DEF_PATH) else null
	if parent == null or md == null or def == null or md.id != def.map_id:
		return null
	var props := WorldProps.new()
	props.name = "WorldProps"
	props.setup(md, def)
	parent.add_child(props)
	return props


## Gives the node its map and rules; call before add_child.
func setup(md: MapDef, def: WorldPropsDef) -> void:
	_md = md
	_def = def


func _ready() -> void:
	if _md == null or _def == null or not WorldModel.exists(_def.model_key):
		return
	# Physics queries need the map's bodies in the broadphase: wait one step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var meshes := piece_meshes(_def.model_key)
	placements = place(_md, _def, get_world_3d().direct_space_state, bounds_of(meshes))
	build(placements, meshes)


## {piece name: Mesh} of the kit (empty when the glb is missing).
static func piece_meshes(key: StringName) -> Dictionary:
	var out := {}
	if not WorldModel.exists(key):
		return out
	var inst := (load(WorldModel.glb_path(key)) as PackedScene).instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh != null and m.transform.is_equal_approx(Transform3D.IDENTITY):
			out[StringName(m.name)] = m.mesh
		elif m.mesh != null:
			# bake a non-identity node transform into a copy (should not happen: pieces export at the origin)
			push_warning("[WorldProps] piece %s has a node transform; using mesh bounds as-is" % m.name)
			out[StringName(m.name)] = m.mesh
	inst.free()
	return out


## {piece name: AABB} of the given meshes.
static func bounds_of(meshes: Dictionary) -> Dictionary:
	var out := {}
	for k in meshes:
		out[k] = (meshes[k] as Mesh).get_aabb()
	return out


## Deterministic placement of the kit on `md`'s map (see the class doc).
## `space` must see the map's collision; `bounds` = {piece: local AABB}.
static func place(md: MapDef, def: WorldPropsDef, space: PhysicsDirectSpaceState3D, bounds: Dictionary) -> Array:
	var out: Array = []
	var grid := {}
	rejects = {}
	var corridors := lane_corridors(md)
	var sb := scaled_bounds(def, bounds)
	var border := border_points(def.navmesh, def.edge_step_m)
	# Every candidate also passes the physical-plausibility rules (docs/placement.md).
	var check := Checker.new(space, bounds)
	check.avoid_decals(md)
	# pass 1: street lamps at a steady rhythm along lane / plaza edges
	var lamps := {}  # edge grid of lamp spots
	if sb.has(def.lamp_piece):
		for c in border:
			var p: Vector3 = c[0]
			var zone := zone_of(md, def, p)
			if not def.lamp_zones.has(zone) or out.size() >= def.max_props:
				continue
			if _near_same_edge(lamps, p, c[1], def.lamp_spacing_m):
				continue
			var pl := _fit_wall(def, space, p, c[1], def.lamp_piece, sb[def.lamp_piece], _scale(def, def.lamp_piece))
			if pl == null:
				continue
			var centre := _foot_centre(pl)
			if excluded(md, def, centre, pl.foot_radius, corridors) != "" or _crowded(grid, centre, def.min_spacing_m) \
					or not check.accept(pl):
				continue
			pl.zone = zone
			pl.team = MapDef.TEAM_NEUTRAL
			_mark_edge(lamps, p, c[1], def.lamp_spacing_m)
			_mark(grid, centre, def.min_spacing_m)
			out.append(pl)
	# pass 2: clusters (a primary piece + companions along the same edge)
	var heads := {}
	for c in border:
		if out.size() >= def.max_props:
			break
		var p: Vector3 = c[0]
		var n: Vector3 = c[1]
		var zone := zone_of(md, def, p)
		var rng := _rng(def, p)
		if rng.randf() >= float(def.density.get(zone, 0.0)):
			continue
		var spacing := float(def.cluster_spacing.get(zone, def.min_spacing_m))
		if _near_same_edge(heads, p, n, spacing):
			continue
		var pieces := _pick(def, zone, md.nearest_lane(p), md, rng)
		for piece: StringName in pieces:
			if not sb.has(piece) or piece == def.lamp_piece and zone != &"hq":
				continue
			var pl := _fit_wall(def, space, p, n, piece, sb[piece], _scale(def, piece))
			if pl == null:
				continue
			pl.zone = zone
			pl.team = _team_for(md, def, piece, p)
			var centre := _foot_centre(pl)
			if excluded(md, def, centre, pl.foot_radius, corridors) != "" or _crowded(grid, centre, def.min_spacing_m) \
					or not check.accept(pl):
				continue
			_mark(grid, centre, def.min_spacing_m)
			_mark_edge(heads, p, n, spacing)
			out.append(pl)
			_add_companions(md, def, space, sb, pl, p, n, rng, corridors, out, check)
			break
	# roofs
	var walk := NavIndex.new(def.walk_navmeshes if not def.walk_navmeshes.is_empty() else [def.navmesh])
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v in def.navmesh.get_vertices():
		lo = lo.min(v)
		hi = hi.max(v)
	var x := floorf(lo.x / def.roof_step_m) * def.roof_step_m
	while x <= hi.x and out.size() < def.max_props:
		var z := floorf(lo.z / def.roof_step_m) * def.roof_step_m
		while z <= hi.z and out.size() < def.max_props:
			var p := Vector3(x, 0, z)
			var rng := _rng(def, p)
			if rng.randf() < def.roof_density:
				var pieces := _pick(def, &"roof", md.nearest_lane(p), md, rng)
				if not pieces.is_empty() and sb.has(pieces[0]):
					var pl := _fit_roof(def, space, p, pieces[0], sb[pieces[0]], rng, _scale(def, pieces[0]))
					if pl != null and not walk.on_walkable(pl.xform.origin, 1.5) and not _crowded(grid, pl.xform.origin, def.min_spacing_m) \
							and excluded(md, def, pl.xform.origin, pl.foot_radius, corridors) == "" and check.accept(pl):
						pl.zone = &"roof"
						_mark(grid, pl.xform.origin, def.min_spacing_m)
						out.append(pl)
			z += def.roof_step_m
		x += def.roof_step_m
	return out


## Navmesh border sample points: [[point, outward unit normal (XZ)], ...], in a
## stable order. A border edge belongs to exactly one polygon (vertices are
## matched by position, so tile seams do not count as borders).
static func border_points(nm: NavigationMesh, step: float) -> Array:
	var out: Array = []
	if nm == null:
		return out
	var verts := nm.get_vertices()
	var keyof := func(v: Vector3) -> Vector3i:
		return Vector3i(roundi(v.x * 20.0), roundi(v.y * 4.0), roundi(v.z * 20.0))
	var count := {}
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		for j in poly.size():
			var a: Vector3i = keyof.call(verts[poly[j]])
			var b: Vector3i = keyof.call(verts[poly[(j + 1) % poly.size()]])
			var k := [a, b] if (a.x < b.x or (a.x == b.x and a.z < b.z)) else [b, a]
			count[k] = int(count.get(k, 0)) + 1
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var cen := Vector3.ZERO
		for idx in poly:
			cen += verts[idx]
		cen /= float(poly.size())
		for j in poly.size():
			var va := verts[poly[j]]
			var vb := verts[poly[(j + 1) % poly.size()]]
			var a: Vector3i = keyof.call(va)
			var b: Vector3i = keyof.call(vb)
			var k := [a, b] if (a.x < b.x or (a.x == b.x and a.z < b.z)) else [b, a]
			if int(count[k]) != 1:
				continue
			var e := vb - va
			e.y = 0.0
			var length := e.length()
			if length < 0.5:
				continue
			var nrm := Vector3(e.z, 0, -e.x).normalized()
			var mid := (va + vb) * 0.5
			if nrm.dot(mid - cen) < 0.0:
				nrm = -nrm
			var t := step * 0.5
			while t < length:
				out.append([va.lerp(vb, t / length), nrm])
				t += step
	return out


## Lane polylines (XZ): per lane, HQ A gate -> hardpoints -> HQ B gate.
static func lane_corridors(md: MapDef) -> Array:
	var out: Array = []
	for li in md.lanes.size():
		var pts := PackedVector3Array()
		var a := md.hq(MapDef.TEAM_CONCORD)
		var b := md.hq(MapDef.TEAM_SYNDICATE)
		if a != null:
			pts.append(a.gate_for_lane(li))
		for h in md.lanes[li].hardpoints:
			pts.append(h.position)
		if b != null:
			pts.append(b.gate_for_lane(li))
		out.append(pts)
	return out


## XZ distance from `p` to the polyline `pts`.
static func polyline_distance(pts: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


## The keep-out rule that a footprint of radius `r` at `p` breaks, or "" when it
## may stand there. `corridors` = lane_corridors(md) (passed in to avoid rebuilding).
static func excluded(md: MapDef, def: WorldPropsDef, p: Vector3, r: float, corridors: Array = []) -> String:
	var flat := func(a: Vector3) -> float:
		return Vector2(a.x - p.x, a.z - p.z).length()
	for lane in md.lanes:
		for h in lane.hardpoints:
			if flat.call(h.position) < h.zone_radius + def.hardpoint_margin_m + r:
				return "hardpoint"
			for s in h.barricade_sockets:
				if flat.call(s) < def.socket_radius_m + r:
					return "barricade"
			for s in h.cell_cradles:
				if s.is_finite() and flat.call(s) < def.cradle_radius_m + r:
					return "cradle"
			for s in h.side_doors:
				if flat.call(s) < def.door_radius_m + r:
					return "door"
			for s in h.garrison_points:
				if flat.call(s) < def.cradle_radius_m + r:
					return "garrison"
			if h.supply_cache.is_finite() and flat.call(h.supply_cache) < def.cradle_radius_m + r:
				return "cache"
		for f in lane.flank_loops:
			for s in [f.outer_door, f.mid_door]:
				if flat.call(s) < def.door_radius_m + r:
					return "door"
	for hq in md.hqs:
		if flat.call(hq.armory) < def.armory_radius_m + r:
			return "armory"
		if flat.call(hq.sanctum) < hq.sanctum_radius + def.sanctum_margin_m + r:
			return "sanctum"
		for s in hq.spawn_points:
			if flat.call(s) < def.spawn_radius_m + r:
				return "spawn"
		if flat.call(hq.uplink) < def.uplink_radius_m + r:
			return "uplink"
		if flat.call(hq.foundry) < def.foundry_radius_m + r:
			return "foundry"
		for g in hq.lane_gates:
			if flat.call(g) < def.gate_radius_m + r:
				return "gate"
		if flat.call(hq.lane_gate) < def.gate_radius_m + r:
			return "gate"
	var cs := corridors if not corridors.is_empty() else lane_corridors(md)
	for pts in cs:
		if polyline_distance(pts, p) < def.corridor_half_width_m + r:
			return "corridor"
	return ""


## The HQ (team) whose compound holds `p`, or -1.
static func hq_team_at(md: MapDef, def: WorldPropsDef, p: Vector3) -> int:
	for hq in md.hqs:
		var gz := hq.lane_gate.z
		var inside := (p.z - gz) * signf(hq.sanctum.z - gz) > 1.0
		if inside and absf(p.x - hq.sanctum.x) <= def.hq_half_width_m:
			return hq.team
	return -1


## Zone of a wall spot: hq, plaza (hardpoint rims, Mid Plaza), flank or lane.
static func zone_of(md: MapDef, def: WorldPropsDef, p: Vector3) -> StringName:
	if hq_team_at(md, def, p) >= 0:
		return &"hq"
	for lane in md.lanes:
		for h in lane.hardpoints:
			if Vector2(h.position.x - p.x, h.position.z - p.z).length() < h.zone_radius + def.plaza_rim_m:
				return &"plaza"
		for f in lane.flank_loops:
			if polyline_distance(f.waypoints, p) < def.flank_band_m:
				return &"flank"
	if Vector2(md.mid_plaza_center.x - p.x, md.mid_plaza_center.z - p.z).length() < md.mid_plaza_radius:
		return &"plaza"
	return &"lane"


## Placement counts {piece: n}, {zone: n}, {team: n} and the total.
static func stats(list: Array) -> Dictionary:
	var by_piece := {}
	var by_zone := {}
	var by_team := {}
	for pl in list:
		by_piece[pl.piece] = int(by_piece.get(pl.piece, 0)) + 1
		by_zone[pl.zone] = int(by_zone.get(pl.zone, 0)) + 1
		by_team[pl.team] = int(by_team.get(pl.team, 0)) + 1
	return {"total": list.size(), "piece": by_piece, "zone": by_zone, "team": by_team}


## Builds the render nodes: one batch per (piece, team, chunk). Returns the
## number of batches (MultiMeshInstance3D or MeshInstance3D children).
func build(list: Array, meshes: Dictionary) -> int:
	var groups := {}
	for pl in list:
		var cell := Vector2i(floori(pl.xform.origin.x / _def.chunk_m), floori(pl.xform.origin.z / _def.chunk_m))
		var k := [pl.piece, pl.team, cell]
		if not groups.has(k):
			groups[k] = []
		groups[k].append(pl)
	var keys := groups.keys()
	keys.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	for k in keys:
		var items: Array = groups[k]
		var mesh: Mesh = meshes.get(k[0])
		if mesh == null:
			continue
		var tall := mesh.get_aabb().size.y >= 1.5
		var centre := Vector3.ZERO
		for pl in items:
			centre += pl.xform.origin
		centre /= float(items.size())
		var gi: GeometryInstance3D
		if items.size() == 1:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.transform = items[0].xform
			gi = mi
		else:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = items.size()
			for i in items.size():
				var t: Transform3D = items[i].xform
				t.origin -= centre
				mm.set_instance_transform(i, t)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = centre
			gi = mmi
		gi.name = "%s_%d_%d_%d" % [k[0], k[1] + 1, k[2].x, k[2].y]
		gi.material_override = WorldModel.material(_def.model_key, k[1])
		gi.visibility_range_end = _def.range_tall_m if tall else _def.range_small_m
		gi.visibility_range_end_margin = 8.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if not tall and not GfxQuality.small_prop_shadows(GfxQuality.level()):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gi)
	return keys.size()


## Point-on-navmesh lookup (XZ grid of polygon bounds), for the roof rule.
class NavIndex:
	const CELL := 8.0
	var _polys: Array = []  # [PackedVector3Array]
	var _grid := {}

	func _init(meshes: Array) -> void:
		for nm: NavigationMesh in meshes:
			if nm == null:
				continue
			var verts := nm.get_vertices()
			for i in nm.get_polygon_count():
				var pts := PackedVector3Array()
				var lo := Vector2(INF, INF)
				var hi := -lo
				for idx in nm.get_polygon(i):
					pts.append(verts[idx])
					lo = lo.min(Vector2(verts[idx].x, verts[idx].z))
					hi = hi.max(Vector2(verts[idx].x, verts[idx].z))
				var id := _polys.size()
				_polys.append(pts)
				for gx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
					for gz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
						var c := Vector2i(gx, gz)
						if not _grid.has(c):
							_grid[c] = []
						_grid[c].append(id)

	## True when `p` lies inside a navmesh polygon (XZ) whose height is within `dy`.
	func on_walkable(p: Vector3, dy: float) -> bool:
		for id: int in _grid.get(Vector2i(floori(p.x / CELL), floori(p.z / CELL)), []):
			var pts: PackedVector3Array = _polys[id]
			var poly := PackedVector2Array()
			var y := 0.0
			for v in pts:
				poly.append(Vector2(v.x, v.z))
				y += v.y
			y /= float(pts.size())
			if absf(y - p.y) <= dy and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
				return true
		return false


# ------------------------------------------------------------------ internals
static func _rng(def: WorldPropsDef, p: Vector3) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([def.placement_seed, roundi(p.x * 10.0), roundi(p.y * 10.0), roundi(p.z * 10.0)])
	return rng


## Up to companion_max small pieces beside `pl` along the same wall
## (WorldPropsDef.companions), alternating sides, same rules as any wall prop;
## they share the primary's spacing slot.
static func _add_companions(md: MapDef, def: WorldPropsDef, space: PhysicsDirectSpaceState3D, sb: Dictionary,
		pl: Placement, p: Vector3, n: Vector3, rng: RandomNumberGenerator, corridors: Array, out: Array,
		check: Checker) -> void:
	var options: Array = def.companions.get(pl.piece, [])
	if options.is_empty() or not sb.has(pl.piece):
		return
	var tangent := pl.xform.basis.x.normalized()
	var reach := {1.0: (sb[pl.piece] as AABB).size.x * 0.5, -1.0: (sb[pl.piece] as AABB).size.x * 0.5}
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	for _i in def.companion_max:
		if rng.randf() >= def.companion_chance or out.size() >= def.max_props:
			return
		var piece := StringName(options[rng.randi_range(0, options.size() - 1)])
		if not sb.has(piece):
			continue
		var w := (sb[piece] as AABB).size.x
		var off: float = reach[side] + w * 0.5 + rng.randf_range(0.1, 0.4)
		var c := _fit_wall(def, space, p + tangent * off * side, n, piece, sb[piece], _scale(def, piece))
		if c != null and excluded(md, def, _foot_centre(c), c.foot_radius, corridors) == "" and check.accept(c):
			c.zone = pl.zone
			c.team = _team_for(md, def, piece, _foot_centre(c))
			out.append(c)
			reach[side] = off + w * 0.5
		side = -side


## Bounds scaled by WorldPropsDef.piece_scale (placement works in scaled space).
static func scaled_bounds(def: WorldPropsDef, bounds: Dictionary) -> Dictionary:
	var out := {}
	for k in bounds:
		var s := _scale(def, k)
		var b: AABB = bounds[k]
		out[k] = AABB(b.position * s, b.size * s)
	return out


static func _scale(def: WorldPropsDef, piece: StringName) -> float:
	return float(def.piece_scale.get(piece, 1.0))


## True when a spot on an edge facing the same way (outward normals within
## 45 degrees) lies within `spacing`: the two sides of a lane keep their own rhythm.
static func _near_same_edge(grid: Dictionary, p: Vector3, n: Vector3, spacing: float) -> bool:
	var cell := Vector2i(floori(p.x / spacing), floori(p.z / spacing))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for e: Array in grid.get(cell + Vector2i(dx, dz), []):
				var q: Vector3 = e[0]
				if (e[1] as Vector3).dot(n) > 0.7 and absf(q.y - p.y) < 3.0 \
						and Vector2(q.x - p.x, q.z - p.z).length() < spacing:
					return true
	return false


static func _mark_edge(grid: Dictionary, p: Vector3, n: Vector3, spacing: float) -> void:
	var cell := Vector2i(floori(p.x / spacing), floori(p.z / spacing))
	if not grid.has(cell):
		grid[cell] = []
	grid[cell].append([p, n])


## Up to two pieces to try, by the zone's weights (lane-specific table first:
## "<zone>_<lane id>", then "<zone>").
static func _pick(def: WorldPropsDef, zone: StringName, lane: int, md: MapDef, rng: RandomNumberGenerator) -> Array:
	var table: Dictionary = {}
	if lane >= 0 and lane < md.lanes.size():
		table = def.weights.get(StringName("%s_%s" % [zone, md.lanes[lane].id]), {})
	if table.is_empty():
		table = def.weights.get(zone, {})
	if table.is_empty():
		return []
	# sort as Strings: StringNames compare by their interned pointer, which changes
	# from run to run (the first build placed different props in every process)
	var pairs: Array = []
	for k in table.keys():
		pairs.append([String(k), float(table[k])])
	pairs.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var total := 0.0
	for e in pairs:
		total += e[1]
	var out: Array = []
	for _i in 2:
		var r := rng.randf() * total
		for e in pairs:
			r -= e[1]
			if r <= 0.0:
				if not out.has(StringName(e[0])):
					out.append(StringName(e[0]))
				break
	return out


static func _team_for(md: MapDef, def: WorldPropsDef, piece: StringName, p: Vector3) -> int:
	return hq_team_at(md, def, p) if def.team_pieces.has(piece) else MapDef.TEAM_NEUTRAL


## Floor footprint of a piece in its local space: Rect2 over (x, z), back at max z.
static func _foot_rect(def: WorldPropsDef, piece: StringName, box: AABB) -> Rect2:
	if def.foot_override.has(piece):
		var f: Vector2 = def.foot_override[piece]
		return Rect2(Vector2(-f.x * 0.5, box.end.z - f.y), f)
	return Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))


## Rays see the visible world only (not the invisible rail edge blockers).
static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, HeroBody.LAYER_WORLD)
	q.collide_with_areas = false
	q.hit_back_faces = false
	return space.intersect_ray(q)


static func _wall_hit(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float) -> Dictionary:
	var h := _ray(space, from, from + dir * length)
	if h.is_empty() or absf((h.normal as Vector3).y) > 0.3:
		return {}
	return h


## Rejections per _fit_wall reason since the last place() (diagnostics for
## docs/assets/props.md; never read by the placement itself).
static var rejects: Dictionary = {}


static func _reject(why: StringName) -> Placement:
	rejects[why] = int(rejects.get(why, 0)) + 1
	return null


static func _fit_wall(def: WorldPropsDef, space: PhysicsDirectSpaceState3D, p: Vector3, n: Vector3,
		piece: StringName, box: AABB, scale: float = 1.0) -> Placement:
	# the navmesh floats up to ~0.5 m over the floor: measure from the floor itself
	var g0 := _ray(space, p + Vector3(0, 1.0, 0), p - Vector3(0, 1.5, 0))
	if g0.is_empty() or (g0.normal as Vector3).y < 0.9:
		return _reject(&"no_floor")
	p = Vector3(p.x, (g0.position as Vector3).y, p.z)
	var probe_h := 0.6
	var h := _wall_hit(space, p + Vector3(0, probe_h, 0) - n * 0.3, n, def.wall_search_m + 0.3)
	if h.is_empty():
		return _reject(&"no_wall")
	var wn: Vector3 = h.normal
	var wall_dir := Vector3(-wn.x, 0, -wn.z).normalized()
	if wall_dir.dot(n) < 0.7:
		return _reject(&"wall_angle")
	var wall_pt: Vector3 = h.position
	var tangent := Vector3.UP.cross(wall_dir).normalized()
	var foot := _foot_rect(def, piece, box)
	var depth := foot.size.y
	if depth + def.wall_gap_m > def.max_wall_depth_m:
		return _reject(&"too_deep")
	# local frame: +Z towards the wall, +X = tangent, origin on the floor
	var basis := Basis(tangent, Vector3.UP, wall_dir)
	# the wall must run along the whole width (ends and centre), same plane
	var dist0 := (wall_pt - (p + Vector3(0, probe_h, 0))).dot(wall_dir)
	var anchor := p + Vector3(0, probe_h, 0)
	var half_anchor := def.min_anchor_len_m * 0.5
	for s: float in [minf(foot.position.x, -half_anchor), maxf(foot.end.x, half_anchor), 0.0]:
		var a := anchor + tangent * s - wall_dir * 0.3
		var hh := _wall_hit(space, a, wall_dir, def.wall_search_m + 0.6)
		if hh.is_empty():
			return _reject(&"edge_short")
		var d := ((hh.position as Vector3) - anchor).dot(wall_dir)
		if absf(d - dist0) > 0.15:
			return _reject(&"edge_uneven")
	# a real wall, not a low crate or kerb: it reaches min_wall_h_m
	var lowtop := anchor + Vector3(0, def.min_wall_h_m - probe_h, 0) - wall_dir * 0.3
	var hl := _wall_hit(space, lowtop, wall_dir, def.wall_search_m + 0.6)
	if hl.is_empty() or absf(((hl.position as Vector3) - lowtop).dot(wall_dir) - 0.3 - dist0) > 0.15:
		return _reject(&"edge_low")
	# wall-mounted pieces need the wall up to their top (not a 1.1 m rail)
	if def.wall_mounted.has(piece):
		var top := anchor + Vector3(0, box.end.y - 0.2 - probe_h, 0) - wall_dir * 0.3
		var ht := _wall_hit(space, top, wall_dir, def.wall_search_m + 0.6)
		if ht.is_empty() or absf(((ht.position as Vector3) - top).dot(wall_dir) - 0.3 - dist0) > 0.15:
			return _reject(&"wall_mount_low")
	# origin: back of the mesh bounds on the wall face (minus the gap)
	var target := anchor + wall_dir * (dist0 - def.wall_gap_m)
	var origin := target - basis * Vector3(0, 0, box.end.z)
	origin -= basis * Vector3((foot.position.x + foot.end.x) * 0.5, 0, 0)
	# floor: flat under every footprint corner and the centre
	var corners := PackedVector3Array()
	for c: Vector2 in [Vector2(foot.position.x, foot.end.y), Vector2(foot.end.x, foot.end.y),
			Vector2(foot.end.x, foot.position.y), Vector2(foot.position.x, foot.position.y)]:
		corners.append(origin + basis * Vector3(c.x, 0, c.y))
	var ys: Array[float] = []
	for c in corners:
		var g := _ray(space, Vector3(c.x, p.y + 1.2, c.z), Vector3(c.x, p.y - 1.2, c.z))
		if g.is_empty() or (g.normal as Vector3).y < 0.9:
			return _reject(&"floor_missing")
		ys.append((g.position as Vector3).y)
	var y_lo: float = ys.min()
	var y_hi: float = ys.max()
	if y_hi - y_lo > def.max_floor_spread_m or absf(y_lo - p.y) > 0.6:
		return _reject(&"floor_uneven")
	origin.y = y_lo
	for i in corners.size():
		corners[i].y = y_lo
	var xf := Transform3D(basis, origin)
	if not _clear(space, xf, box, y_hi - y_lo):
		return _reject(&"blocked")
	# final check, the rule itself: from every footprint corner at the floor the
	# wall is within max_wall_depth_m (catches steps, gaps under a rail, slopes)
	for c in corners:
		var from := c + Vector3(0, probe_h, 0) - wall_dir * 0.02
		if _wall_hit(space, from, wall_dir, def.max_wall_depth_m + 0.03).is_empty():
			return _reject(&"corner_far")
	var pl := Placement.new()
	pl.piece = piece
	pl.kind = &"wall"
	pl.xform = Transform3D(xf.basis.scaled(Vector3.ONE * scale), xf.origin)
	pl.wall_dir = wall_dir
	pl.foot = corners
	pl.foot_radius = foot.size.length() * 0.5
	return pl


static func _fit_roof(def: WorldPropsDef, space: PhysicsDirectSpaceState3D, p: Vector3, piece: StringName,
		box: AABB, rng: RandomNumberGenerator, scale: float = 1.0) -> Placement:
	var g := _ray(space, Vector3(p.x, 80, p.z), Vector3(p.x, -20, p.z))
	if g.is_empty() or (g.normal as Vector3).y < 0.95 or (g.position as Vector3).y < def.roof_min_y:
		return null
	var y: float = (g.position as Vector3).y
	var basis := Basis(Vector3.UP, rng.randi_range(0, 3) * PI * 0.5)
	var origin := Vector3(p.x, y, p.z) - basis * Vector3(box.get_center().x, 0, box.get_center().z)
	var corners := PackedVector3Array()
	var m := 0.4  # the roof must reach this far past the footprint
	for c: Vector2 in [Vector2(box.position.x - m, box.end.z + m), Vector2(box.end.x + m, box.end.z + m),
			Vector2(box.end.x + m, box.position.z - m), Vector2(box.position.x - m, box.position.z - m)]:
		var w := origin + basis * Vector3(c.x, 0, c.y)
		var gg := _ray(space, Vector3(w.x, y + 3.0, w.z), Vector3(w.x, y - 0.5, w.z))
		if gg.is_empty() or absf((gg.position as Vector3).y - y) > 0.05:
			return null
		corners.append(Vector3(w.x, y, w.z))
	var xf := Transform3D(basis, origin)
	if not _clear(space, xf, box, 0.0):
		return null
	var pl := Placement.new()
	pl.piece = piece
	pl.kind = &"roof"
	pl.xform = Transform3D(xf.basis.scaled(Vector3.ONE * scale), xf.origin)
	pl.foot = corners
	pl.foot_radius = Vector2(box.size.x, box.size.z).length() * 0.5
	return pl


## True when the piece's mesh bounds (lifted off the floor by `lift` + 5 cm,
## shrunk 5 cm a side) overlap no collision.
static func _clear(space: PhysicsDirectSpaceState3D, xf: Transform3D, box: AABB, lift: float) -> bool:
	var shape := BoxShape3D.new()
	var size := box.size - Vector3(0.1, 0.1 + lift, 0.1)
	if size.x <= 0.02 or size.y <= 0.02 or size.z <= 0.02:
		size = size.max(Vector3(0.02, 0.02, 0.02))
	shape.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collide_with_areas = false
	var c := box.get_center()
	c.y = box.position.y + 0.05 + lift + size.y * 0.5
	q.transform = Transform3D(xf.basis, xf * c)
	return space.intersect_shape(q, 1).is_empty()


static func _foot_centre(pl: Placement) -> Vector3:
	var c := Vector3.ZERO
	for v in pl.foot:
		c += v
	return c / float(maxi(pl.foot.size(), 1))


static func _crowded(grid: Dictionary, p: Vector3, spacing: float) -> bool:
	var cell := Vector2i(floori(p.x / spacing), floori(p.z / spacing))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q: Vector3 in grid.get(cell + Vector2i(dx, dz), []):
				if Vector2(q.x - p.x, q.z - p.z).length() < spacing and absf(q.y - p.y) < 3.0:
					return true
	return false


static func _mark(grid: Dictionary, p: Vector3, spacing: float) -> void:
	var cell := Vector2i(floori(p.x / spacing), floori(p.z / spacing))
	if not grid.has(cell):
		grid[cell] = []
	grid[cell].append(p)
