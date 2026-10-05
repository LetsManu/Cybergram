extends SceneTree
## Generator for the full 3-lane map "Shardline Front"
## (design/gdd/match-flow-and-map.md §3.2 layout + geometry rules, §3.3 the 15
## hardpoints; game-concept.md C2 lanes, C4 task types, C5 placements).
##
## Writes, from one set of layout constants:
##   assets/maps/front/shardline_front.tscn           map scene (geometry, anchors, lights, NavRegion)
##   assets/maps/front/shardline_front_navmesh.res    baked NavigationMesh (ground + Undercroft)
##   assets/maps/front/shardline_front_overview.tscn  labelled top-down overview camera + navmesh overlay
##   assets/data/match/map_front.tres                 MapDef (3 lanes x 5 hardpoints, HQs, flanks, spawns)
##
## Run (after an import so class_names resolve):
##   godot --headless --path . -s res://tools/maps/build_shardline_front.gd
##
## Axis (same as the slice, MapDef): lanes run along -Z. GDD lane distance L
## (Concord HQ back wall at 0, Syndicate HQ at 420) maps to z = -L. GDD north
## (+y) is world -X: North lane x = -80, Center x = 0, South x = +80.
## Half B mirrors half A across L = 210; South mirrors North across x = 0.
##
## Walkable floors are registered as 2D shapes; every floor edge that faces the
## Leyfall void gets a rail + edge blocker (or a tunnel wall) automatically, so
## joins (pads, spokes, flank doors, the plaza) never get blocked by a rail.

const MAP_PATH := "res://assets/maps/front/shardline_front.tscn"
const NAV_PATH := "res://assets/maps/front/shardline_front_navmesh.res"
const OVERVIEW_PATH := "res://assets/maps/front/shardline_front_overview.tscn"
const DEF_PATH := "res://assets/data/match/map_front.tres"
const RULES_PATH := "res://assets/data/match/match_rules_front.tres"

## Dock water (map spec: slows movement 15%); feet-in-water height band.
const WATER_SPEED_FACTOR := 0.85
const WATER_Y0 := -0.5
const WATER_H := 2.0
const LANE_LEN := 420.0
const HQ_HALF_W := 30.0
const HQ_BACK := -6.0
const HQ_FRONT := 40.0
const HQ_WALL_H := 12.0
const RAIL_H := 1.1
const RAIL_BLOCK_H := 4.0
const SANCTUM_L := 5.0
const SANCTUM_R := 10.0
const UPLINK_L := 30.0
const MID_L := 210.0
const PLAZA_R := 30.0
const SOCKET_GAP := 15.0
const CRADLE_X := -5.0
## North / South lane gates in the HQ front wall (lateral centre, half width).
const GATE_X := 22.0
const GATE_HW := 6.0
## Gate stub and the lateral causeway that carries the N/S roads to their lanes.
const STUB_L1 := 64.0
const CAUSE_L0 := 58.0
const CAUSE_L1 := 70.0
const SPOKE_HW := 5.0
## Undercroft flank tunnels: depth of the junction room, its radius, tunnel width.
const UNDER_Y := -4.0
const JUNCTION_R := 8.0
const FLANK_W := 6.0
const TUNNEL_WALL_H := 3.5
## Overlook platforms (verticality at the hardpoints).
const DECK_H := 3.0
const DECK_W := 4.0

const AZURE := Color("#2E86FF")
const EMBER := Color("#FF5A1F")
const NEUTRAL := Color(0.92, 0.9, 1.0)
const LEYFALL := Color("#8E5CFF")
const TEAL := Color("#34D8C4")

## [id, key, lateral x, main path half width]. Order = MapDef.lanes order.
const LANES := [
	[&"north", "n", -80.0, 10.0],  # Lattice/Rivet Bridge: the 20 m bridge lane
	[&"center", "c", 0.0, 8.0],
	[&"south", "s", 80.0, 8.0],
]
## Per lane, rows [inner, outer, mid] (half A names; the Mid row has one name):
## [name A, name B, task, L, zone r, pad half size, base duration, generator hp]
## (match-flow-and-map.md §3.3: each task type exactly 5 times).
var HP := {
	"n": [
		["Glasswork Gate", "Furnace Gate", HardpointDef.TaskKind.BREACH, 85.0, 12.0, 15.0, 20.0, 6000.0],
		["Lattice Bridge", "Rivet Span", HardpointDef.TaskKind.HOLD, 145.0, 12.0, 15.0, 65.0, 0.0],
		["Belfry Ruin", "", HardpointDef.TaskKind.PLANT, MID_L, 10.0, 14.0, 70.0, 0.0],
	],
	"c": [
		["Concord Atrium", "Boiler Hall", HardpointDef.TaskKind.HOLD, 85.0, 12.0, 15.0, 75.0, 0.0],
		["Signal Market", "Scrap Bazaar", HardpointDef.TaskKind.PLANT, 145.0, 10.0, 14.0, 75.0, 0.0],
		["The Spindle", "", HardpointDef.TaskKind.HOLD, MID_L, 12.0, 0.0, 60.0, 0.0],
	],
	"s": [
		["Prism Locks", "Slag Locks", HardpointDef.TaskKind.PLANT, 85.0, 10.0, 14.0, 80.0, 0.0],
		["Halo Dock", "Cinder Dock", HardpointDef.TaskKind.BREACH, 145.0, 12.0, 15.0, 20.0, 5000.0],
		["Leyfall Pumpworks", "", HardpointDef.TaskKind.BREACH, MID_L, 12.0, 15.0, 20.0, 4500.0],
	],
}
const SLOT_SUFFIX := ["ai", "ao", "mid", "bo", "bi"]
const SLOT_ROW := [0, 1, 2, 1, 0]

var map_root: Node3D
var geo: Node3D
var mats := {}
## Walkable floor shapes (2D, x / L): {t, ...}.
var shapes: Array = []
var rail_jobs: Array = []
var strip_jobs: Array = []
## Flank tunnels for the MapDef: [id, from_hp, to_hp, waypoints (Vector3)].
var flanks: Array = []
## W16-SDWATER: wading zones collected while building the dock water meshes.
var water_zones: Array[WaterZoneDef] = []
var _rail_n := 0


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/maps/front"))
	_build_materials()
	map_root = Node3D.new()
	map_root.name = "ShardlineFront"
	get_root().add_child(map_root)
	_env()
	var nav := NavigationRegion3D.new()
	nav.name = "NavRegion"
	_add(map_root, nav)
	geo = Node3D.new()
	geo.name = "Geometry"
	geo.add_to_group(&"nav_source", true)
	_add(map_root, geo)
	var anchors := _node(map_root, "Anchors")
	for half in 2:
		_hq(half)
	for li in LANES.size():
		_lane(li)
	_plaza()
	for half in 2:
		for s in [-1.0, 1.0]:
			_undercroft(half, s)
	_build_edges()
	_hardpoints(anchors)
	_spawns()
	var nm := _navmesh_settings()
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, map_root)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	print("navmesh: %d verts, %d polys" % [nm.get_vertices().size(), nm.get_polygon_count()])
	_check(ResourceSaver.save(nm, NAV_PATH, ResourceSaver.FLAG_COMPRESS), NAV_PATH)
	nav.navigation_mesh = load(NAV_PATH)
	var packed := PackedScene.new()
	_check(packed.pack(map_root), "pack map")
	_check(ResourceSaver.save(packed, MAP_PATH), MAP_PATH)
	_save_map_def()
	_save_overview(nm)
	print("rails: %d runs" % _rail_n)
	quit()


func _check(err: int, what: String) -> void:
	if err != OK:
		push_error("build_shardline_front: %s failed (%d)" % [what, err])


# ---------------------------------------------------------------- helpers

static func P(x: float, l: float, y: float = 0.0) -> Vector3:
	return Vector3(x, y, -l)


static func mirror_l(l: float) -> float:
	return LANE_LEN - l


func _hl(half: int, l: float) -> float:
	return l if half == 0 else mirror_l(l)


func _key(half: int) -> String:
	return "a" if half == 0 else "b"


func _add(parent: Node, n: Node) -> Node:
	parent.add_child(n, true)
	_own(n)
	return n


func _own(n: Node) -> void:
	n.owner = map_root
	for c in n.get_children():
		_own(c)


func _node(parent: Node, n: String) -> Node3D:
	var x := Node3D.new()
	x.name = n
	_add(parent, x)
	return x


func _mat(c: Color, emissive: float = 0.0, alpha: float = 1.0, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.roughness = 0.85
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Stylised panel material (assets/shaders/spatial_env_panel.gdshader), as the slice.
func _panel(base: Color, seam: Color, size: float = 4.0, trim: Color = Color.BLACK, trim_h: float = 0.0, ao_h: float = 2.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/spatial_env_panel.gdshader")
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("seam_color", seam)
	m.set_shader_parameter("panel_size", size)
	m.set_shader_parameter("trim_color", trim)
	m.set_shader_parameter("trim_height", trim_h)
	m.set_shader_parameter("ao_height", ao_h)
	return m


func _build_materials() -> void:
	var seam_a := Color(0.16, 0.18, 0.34)
	var seam_b := Color(0.14, 0.07, 0.1)
	mats.floor_a = _panel(Color(0.33, 0.37, 0.5), seam_a)
	mats.floor_b = _panel(Color(0.38, 0.3, 0.3), seam_b)
	mats.floor_hq_a = _panel(Color(0.42, 0.46, 0.6), seam_a)
	mats.floor_hq_b = _panel(Color(0.22, 0.18, 0.2), seam_b)
	mats.floor_mid = _panel(Color(0.36, 0.34, 0.47), Color(0.22, 0.14, 0.4), 3.0)
	mats.floor_loop = _panel(Color(0.27, 0.22, 0.4), Color(0.14, 0.1, 0.28))
	mats.wall_a = _panel(Color(0.5, 0.54, 0.68), seam_a, 4.0, AZURE, 9.0, 4.0)
	mats.wall_b = _panel(Color(0.24, 0.2, 0.23), seam_b, 4.0, EMBER, 9.0, 4.0)
	mats.wall_under = _panel(Color(0.22, 0.2, 0.32), Color(0.1, 0.08, 0.2), 3.0, LEYFALL, 3.1, 2.0)
	mats.rail = _panel(Color(0.26, 0.28, 0.38), seam_a, 1.5, Color.BLACK, 0.0, 1.0)
	mats.cover_low = _panel(Color(0.7, 0.58, 0.4), Color(0.3, 0.22, 0.2), 1.5, Color.BLACK, 0.0, 1.0)
	mats.cover_tall = _panel(Color(0.46, 0.4, 0.62), Color(0.15, 0.12, 0.3), 1.5, Color.BLACK, 0.0, 2.0)
	mats.deck = _panel(Color(0.4, 0.42, 0.52), Color(0.18, 0.18, 0.3), 2.0, Color.BLACK, 0.0, 1.5)
	mats.strip = _mat(Color(0.3, 0.32, 0.38))
	mats.socket = _mat(Color(0.95, 0.8, 0.25), 0.4, 0.55, true)
	mats.cache = _mat(TEAL, 0.0, 1.0, true)
	mats.garrison = _mat(TEAL, 0.0, 0.35, true)
	mats.water = _mat(Color(0.45, 0.3, 1.0), 0.0, 0.25, true)
	for key in ["a", "b", "n"]:
		var c: Color = AZURE if key == "a" else (EMBER if key == "b" else NEUTRAL)
		mats["team_" + key] = _mat(c, 0.0, 1.0, true)
		mats["glow_" + key] = _mat(c, 0.0, 0.7, true)
		mats["decal_" + key] = _mat(c, 0.0, 0.16, true)


func _box(parent: Node, n: String, size: Vector3, center: Vector3, mat: Material, collide := true, rot := Vector3.ZERO) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.name = n
	body.position = center
	body.rotation_degrees = rot
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	if not collide:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
	_add(parent, body)
	return body


## Mesh (+ collision when `collide`) box as a child of an existing body, local frame.
func _part(body: Node3D, n: String, size: Vector3, local: Vector3, mat: Material, collide := true) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = local
	if not collide:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	_own(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.name = n + "Shape"
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = local
		body.add_child(cs)
		_own(cs)


func _slab(parent: Node, n: String, x0: float, x1: float, l0: float, l1: float, y0: float, y1: float, mat: Material, collide := true) -> Node3D:
	return _box(parent, n, Vector3(absf(x1 - x0), y1 - y0, absf(l1 - l0)), P((x0 + x1) * 0.5, (l0 + l1) * 0.5, (y0 + y1) * 0.5), mat, collide)


## Invisible wall on top of a rail up to RAIL_BLOCK_H (heroes only; hitscan passes).
func _edge_blocker(rail: Node3D, w: float, d: float, rail_h: float, top: float = RAIL_BLOCK_H) -> void:
	var h := top - rail_h
	var wall := StaticBody3D.new()
	wall.name = "EdgeBlock"
	wall.collision_layer = HeroBody.LAYER_EDGE_BLOCK
	wall.collision_mask = 0
	wall.position = Vector3(0, (rail_h + h) * 0.5, 0)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, h, d)
	cs.shape = sh
	wall.add_child(cs)
	rail.add_child(wall)
	_own(wall)


func _cyl(parent: Node, n: String, r_bottom: float, r_top: float, h: float, base: Vector3, mat: Material, collide := true, segments := 32) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.name = n
	body.position = base + Vector3(0, h * 0.5, 0)
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_top
	cm.height = h
	cm.radial_segments = segments
	cm.rings = 1
	cm.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = cm
	if not collide:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		if is_equal_approx(r_bottom, r_top):
			var sh := CylinderShape3D.new()
			sh.radius = r_bottom
			sh.height = h
			cs.shape = sh
		else:
			cs.shape = cm.create_convex_shape(true, false)
		body.add_child(cs)
	_add(parent, body)
	return body


## Sloped slab between two floor points a, b (x, L, y) of width w; top surface
## passes through both points. Returns the body (local -Z runs from a to b).
func _sloped(parent: Node, n: String, a: Vector3, b: Vector3, w: float, mat: Material, thick := 0.5) -> StaticBody3D:
	var wa := P(a.x, a.y, a.z)
	var wb := P(b.x, b.y, b.z)
	var d := wb - wa
	var hlen := Vector2(d.x, d.z).length()
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, hlen)
	var body := StaticBody3D.new()
	body.name = n
	body.transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), (wa + wb) * 0.5)
	_add(parent, body)
	_part(body, "Floor", Vector3(w, thick, d.length() + 1.0), Vector3(0, -thick * 0.5, 0), mat)
	return body


# ---------------------------------------------------------------- floors + auto edges

## Axis-aligned floor (lateral x0..x1, lane l0..l1), top at `top`.
func _floor_rect(parent: Node, n: String, x0: float, x1: float, l0: float, l1: float, mat: Material, top := 0.0, rails := true) -> void:
	var xa := minf(x0, x1)
	var xb := maxf(x0, x1)
	var la := minf(l0, l1)
	var lb := maxf(l0, l1)
	_slab(parent, n, xa, xb, la, lb, top - 1.0, top, mat)
	shapes.append({t = "rect", x0 = xa, x1 = xb, l0 = la, l1 = lb})
	if rails:
		rail_jobs.append({t = "rect", g = parent, n = n, x0 = xa, x1 = xb, l0 = la, l1 = lb, top = top})


func _floor_disc(parent: Node, n: String, c: Vector2, r: float, mat: Material, top := 0.0, wall_h := 0.0) -> void:
	_cyl(parent, n, r, r, 1.0, P(c.x, c.y, top - 1.0), mat, true, 64)
	shapes.append({t = "disc", c = c, r = r})
	rail_jobs.append({t = "disc", g = parent, n = n, c = c, r = r, top = top, wall = wall_h})


## Flank tunnel segment: sloped floor from a to b (x, L, y), walls where it faces void.
func _floor_strip(parent: Node, n: String, a: Vector3, b: Vector3, w: float) -> void:
	var body := _sloped(parent, n, a, b, w, mats.floor_loop)
	shapes.append({t = "strip", a = Vector2(a.x, a.y), b = Vector2(b.x, b.y), w = w})
	strip_jobs.append({body = body, a = a, b = b, w = w})


func _inside(p: Vector2) -> bool:
	for s in shapes:
		match s.t:
			"rect":
				if p.x >= s.x0 and p.x <= s.x1 and p.y >= s.l0 and p.y <= s.l1:
					return true
			"disc":
				if p.distance_to(s.c) <= s.r:
					return true
			"strip":
				var ab: Vector2 = s.b - s.a
				var t := clampf((p - s.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var q: Vector2 = s.a + ab * t
				var along: float = (p - s.a).dot(ab) / ab.length()
				if along >= -0.3 and along <= ab.length() + 0.3 and p.distance_to(q) <= s.w * 0.5:
					return true
	return false


func _build_edges() -> void:
	for j in rail_jobs:
		if j.t == "rect":
			_rect_rails(j)
		else:
			_disc_rails(j)
	for j in strip_jobs:
		_strip_walls(j)


## Rails (inside the floor edge) on each void-facing run of a rect's 4 edges.
func _rect_rails(j: Dictionary) -> void:
	var edges := [
		# [start (x,l), end (x,l), outward normal]
		[Vector2(j.x0, j.l0), Vector2(j.x1, j.l0), Vector2(0, -1)],
		[Vector2(j.x0, j.l1), Vector2(j.x1, j.l1), Vector2(0, 1)],
		[Vector2(j.x0, j.l0), Vector2(j.x0, j.l1), Vector2(-1, 0)],
		[Vector2(j.x1, j.l0), Vector2(j.x1, j.l1), Vector2(1, 0)],
	]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var nrm: Vector2 = e[2]
		var len := a.distance_to(b)
		var steps := maxi(1, ceili(len / 0.5))
		var run_start := -1.0
		for k in steps + 1:
			var void_here := false
			if k < steps:
				var t0 := float(k) / steps
				var t1 := float(k + 1) / steps
				var mid := a.lerp(b, (t0 + t1) * 0.5)
				void_here = not _inside(mid + nrm * 0.6) and not _inside(mid + nrm * 0.6 + (b - a).normalized() * 0.3) \
					and not _inside(mid + nrm * 0.6 - (b - a).normalized() * 0.3)
			if void_here and run_start < 0.0:
				run_start = float(k) / steps
			elif not void_here and run_start >= 0.0:
				_rail_run(j, a.lerp(b, run_start), a.lerp(b, float(k) / steps), nrm)
				run_start = -1.0


func _rail_run(j: Dictionary, p0: Vector2, p1: Vector2, nrm: Vector2) -> void:
	if p0.distance_to(p1) < 0.4:
		return
	var inset := -nrm * 0.25
	var c := (p0 + p1) * 0.5 + inset
	var along_x := absf(nrm.y) > 0.5
	var size := Vector3(p0.distance_to(p1), RAIL_H, 0.5) if along_x else Vector3(0.5, RAIL_H, p0.distance_to(p1))
	_rail_n += 1
	var body := _box(j.g, "%sRail%d" % [j.n, _rail_n], size, P(c.x, c.y, j.top + RAIL_H * 0.5), mats.rail)
	_edge_blocker(body, size.x, size.z, RAIL_H)


func _disc_rails(j: Dictionary) -> void:
	var r: float = j.r
	var n := maxi(24, int(TAU * r / 2.0))
	var wall: float = j.wall
	for i in n:
		var a := TAU * (i + 0.5) / n
		var dir := Vector2(sin(a), cos(a))
		var c: Vector2 = j.c
		var tang := Vector2(dir.y, -dir.x)
		var probe := c + dir * (r + 0.6)
		if _inside(probe) or _inside(probe + tang * 0.6) or _inside(probe - tang * 0.6):
			continue
		var pos := c + dir * (r - 0.25)
		var seg := TAU * r / n + 0.15
		var h := wall if wall > 0.0 else RAIL_H
		_rail_n += 1
		var body := _box(j.g, "%sRim%d" % [j.n, i], Vector3(0.5, h, seg), P(pos.x, pos.y, j.top + h * 0.5),
			mats.wall_under if wall > 0.0 else mats.rail, true, Vector3(0, 90.0 - rad_to_deg(a), 0))
		if wall <= 0.0:
			_edge_blocker(body, 0.5, seg, RAIL_H)


## Undercroft tunnel walls on void-facing runs of a strip, plus roof ribs.
func _strip_walls(j: Dictionary) -> void:
	var body: StaticBody3D = j.body
	var a: Vector3 = j.a
	var b: Vector3 = j.b
	var w: float = j.w
	var a2 := Vector2(a.x, a.y)
	var b2 := Vector2(b.x, b.y)
	var len3 := Vector3(b.x - a.x, b.z - a.z, b.y - a.y).length()
	var dir2 := (b2 - a2).normalized()
	var hfrac := a2.distance_to(b2) / len3
	# Local +X of the strip in (x, L) space (yaw convention of _sloped).
	var wa := P(a.x, a.y)
	var wb := P(b.x, b.y)
	var yaw := atan2(-(wb - wa).x, -(wb - wa).z)
	var perp := Vector2(cos(yaw), sin(yaw))
	for s in [-1.0, 1.0]:
		var steps := maxi(1, ceili(len3 / 0.5))
		var run0 := -1.0
		for k in steps + 1:
			var void_here := false
			if k < steps:
				var t := (float(k) + 0.5) / steps * len3
				var p2: Vector2 = a2 + dir2 * t * hfrac + perp * s * (w * 0.5 + 0.6)
				void_here = not _inside(p2)
			if void_here and run0 < 0.0:
				run0 = float(k) / steps * len3
			elif not void_here and run0 >= 0.0:
				var t1 := float(k) / steps * len3
				if t1 - run0 > 0.4:
					var zc := len3 * 0.5 - (run0 + t1) * 0.5
					_part(body, "Wall%d_%d" % [int(s), k], Vector3(0.4, TUNNEL_WALL_H, t1 - run0),
						Vector3(s * (w * 0.5 + 0.2), TUNNEL_WALL_H * 0.5, zc), mats.wall_under)
				run0 = -1.0
	var ribs := int(len3 / 6.0)
	for i in range(1, ribs):
		_part(body, "Rib%d" % i, Vector3(w + 0.8, 0.35, 0.5), Vector3(0, TUNNEL_WALL_H + 0.17, len3 * 0.5 - i * 6.0), mats.wall_under, false)
	# Leyfall glow strip down the tunnel ceiling line.
	_part(body, "GlowStrip", Vector3(0.25, 0.08, len3 - 1.0), Vector3(0, TUNNEL_WALL_H + 0.4, 0), mats.glow_n, false)


# ---------------------------------------------------------------- environment

func _env() -> void:
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = GfxQuality.make_environment()
	_add(map_root, we)
	_add(map_root, GfxQuality.make_sun())
	var vis := MapVisuals.new()
	vis.name = "MapVisuals"
	# 3 lanes span x -95..95: keep the skyline dressing outside them.
	vis.skyline_min_x = 150.0
	vis.skyline_max_x = 400.0
	vis.spire_spread = 1.6
	_add(map_root, vis)


func _accent_light(parent: Node, n: String, c: Color, pos: Vector3, range_m: float, energy: float) -> void:
	var ol := OmniLight3D.new()
	ol.name = n
	ol.light_color = c
	ol.omni_range = range_m
	ol.light_energy = energy
	ol.shadow_enabled = false
	ol.position = pos
	_add(parent, ol)


# ---------------------------------------------------------------- HQs

func _hq(half: int) -> void:
	var k := _key(half)
	var g := _node(geo, "HQ_" + ("Concord" if half == 0 else "Syndicate"))
	var wall: Material = mats["wall_" + k]
	var l_back := _hl(half, HQ_BACK)
	var l_front := _hl(half, HQ_FRONT)
	_floor_rect(g, "Floor", -HQ_HALF_W, HQ_HALF_W, l_back, l_front, mats["floor_hq_" + k], 0.0, false)
	var lb0 := minf(l_back, l_front)
	var lb1 := maxf(l_back, l_front)
	var back_sign := -1.0 if half == 0 else 1.0
	_slab(g, "WallBack", -HQ_HALF_W - 1, HQ_HALF_W + 1, l_back + back_sign, l_back, 0, HQ_WALL_H, wall)
	_slab(g, "WallLeft", -HQ_HALF_W - 1, -HQ_HALF_W, lb0, lb1, 0, HQ_WALL_H, wall)
	_slab(g, "WallRight", HQ_HALF_W, HQ_HALF_W + 1, lb0, lb1, 0, HQ_WALL_H, wall)
	var f_out := l_front - back_sign
	# Front wall with three lane gates: North (x -22), Center (x 0), South (x +22).
	var segs := [[-HQ_HALF_W - 1, -GATE_X - GATE_HW], [-GATE_X + GATE_HW, -8.0], [8.0, GATE_X - GATE_HW], [GATE_X + GATE_HW, HQ_HALF_W + 1]]
	for i in segs.size():
		_slab(g, "WallFront%d" % i, segs[i][0], segs[i][1], l_front, f_out, 0, HQ_WALL_H, wall)
	for gx in [-GATE_X, 0.0, GATE_X]:
		var ghw := GATE_HW if gx != 0.0 else 8.0
		for s in [-1.0, 1.0]:
			var px: float = gx + s * ghw
			_slab(g, "GatePylon%d_%d" % [int(gx), int(s)], px - 0.5, px + 0.5, l_front, f_out, 0, HQ_WALL_H + 2, mats["team_" + k])
		_slab(g, "GateLintel%d" % int(gx), gx - ghw, gx + ghw, l_front, f_out, HQ_WALL_H - 2.0, HQ_WALL_H, wall)
	var s := P(0, _hl(half, SANCTUM_L))
	_cyl(g, "SanctumZone", SANCTUM_R, SANCTUM_R, 0.02, s + Vector3(0, 0.02, 0), mats["decal_" + k], false, 48)
	_cyl(g, "SanctumCanopy", 3.0, 3.0, 0.4, s + Vector3(0, 6.0, 0), mats["team_" + k], false, 24)
	var u := P(0, _hl(half, UPLINK_L))
	_cyl(g, "UplinkPlinth", 4.5, 3.5, 1.5, u, wall)
	_cyl(g, "UplinkSpire", 0.8, 0.5, 9.0, u + Vector3(0, 1.5, 0), mats["team_" + k])
	_cyl(g, "UplinkCore", 1.6, 1.6, 2.6, u + Vector3(0, 6.0, 0), mats["glow_" + k], false, 6)
	var hq_c: Color = AZURE if half == 0 else EMBER
	_accent_light(g, "UplinkLight", hq_c, u + Vector3(0, 7.0, 0), 14.0, 0.6)
	_accent_light(g, "HQAccentL", hq_c, P(-18, _hl(half, 20.0), 9.0), 26.0, 1.4)
	_accent_light(g, "HQAccentR", hq_c, P(18, _hl(half, 20.0), 9.0), 26.0, 1.4)
	_accent_light(g, "SanctumAccent", hq_c, s + Vector3(0, 8.0, 0), 22.0, 1.6)
	var lf := _hl(half, 10.0)
	_box(g, "Foundry", Vector3(10, 6, 8), P(-19, lf, 3), wall)
	_box(g, "FoundryStack", Vector3(2, 6, 2), P(-22, lf, 9), mats["team_" + k])
	_box(g, "FoundryBand", Vector3(10.1, 0.6, 8.1), P(-19, lf, 4.5), mats["team_" + k], false)
	_box(g, "Armory", Vector3(10, 4, 8), P(19, lf, 2), wall)
	_box(g, "ArmoryCounter", Vector3(8, 1.1, 1), P(19, _hl(half, 15.0), 0.55), mats["team_" + k])
	_box(g, "CourtCoverL", Vector3(3, 1.2, 1.5), P(-10, _hl(half, 24.0), 0.6), mats.cover_low)
	_box(g, "CourtCoverR", Vector3(3, 1.2, 1.5), P(10, _hl(half, 24.0), 0.6), mats.cover_low)
	# North / South gate stubs and the lateral causeways to the outer lanes.
	var fl: Material = mats["floor_" + k]
	for sgn in [-1.0, 1.0]:
		var nm := "N" if sgn < 0 else "S"
		_floor_rect(g, "Stub" + nm, sgn * (GATE_X - GATE_HW), sgn * (GATE_X + GATE_HW), _hl(half, HQ_FRONT), _hl(half, STUB_L1), fl)
		var lane_far: float = 80.0 + 10.0
		_floor_rect(g, "Causeway" + nm, sgn * (GATE_X - GATE_HW), sgn * lane_far, _hl(half, CAUSE_L0), _hl(half, CAUSE_L1), fl)
		_box(g, "CausewayCover" + nm, Vector3(3.0, 1.2, 1.5), P(sgn * 50.0, _hl(half, 64.0), 0.6), mats.cover_low)
		_box(g, "CausewayPylon" + nm, Vector3(1.5, 3.2, 1.5), P(sgn * 36.0, _hl(half, 61.0), 1.6), mats.cover_tall)


# ---------------------------------------------------------------- lanes

func _lane(li: int) -> void:
	var lane: Array = LANES[li]
	var lk: String = lane[1]
	var lx: float = lane[2]
	var hw: float = lane[3]
	var rows: Array = HP[lk]
	for half in 2:
		var k := _key(half)
		var g := _node(geo, "Lane_%s_%s" % [lk.to_upper(), k.to_upper()])
		var fl: Material = mats["floor_" + k]
		var l0 := HQ_FRONT if lk == "c" else CAUSE_L1
		var l1 := MID_L - PLAZA_R + 1.5 if lk == "c" else MID_L
		_floor_rect(g, "Floor", lx - hw, lx + hw, _hl(half, l0), _hl(half, l1), fl)
		for r in 2:
			var row: Array = rows[r]
			var l := _hl(half, row[3])
			var ph: float = row[5]
			_floor_rect(g, "Pad%d" % r, lx - ph, lx + ph, l - ph, l + ph, fl)
		_lane_cover(g, li, half)
	if lk != "c":
		var mrow: Array = rows[2]
		var ph: float = mrow[5]
		_floor_rect(_node(geo, "Lane_%s_Mid" % lk.to_upper()), "Pad", lx - ph, lx + ph, MID_L - ph, MID_L + ph, mats.floor_mid)


## Cover / sightline blockers per lane half (sightlines capped near 70 m, §3.2;
## the North bridge keeps a clear 90 m line between its end pylons).
func _lane_cover(g: Node3D, li: int, half: int) -> void:
	var lk: String = LANES[li][1]
	var lx: float = LANES[li][2]
	var hw: float = LANES[li][3]
	var side := -1.0 if lx < 0.0 else 1.0
	var cover := [
		[-4.5, 58.0, 3.0, 1.2, 1.5, false], [4.0, 64.0, 2.0, 2.6, 2.0, true],
		[-9.0, 80.0, 2.0, 1.2, 4.0, false], [9.0, 90.0, 2.0, 1.2, 4.0, false],
		[-4.0, 112.0, 6.0, 3.5, 1.0, true], [5.0, 122.0, 2.0, 1.2, 2.0, false],
		[-7.0, 138.0, 4.0, 1.1, 2.0, false], [7.0, 138.0, 4.0, 1.1, 2.0, false],
		[-7.0, 152.0, 4.0, 1.1, 2.0, false], [7.0, 152.0, 4.0, 1.1, 2.0, false],
		[4.0, 168.0, 6.0, 3.5, 1.0, true], [-5.0, 178.0, 2.0, 1.2, 2.0, false],
	]
	for i in cover.size():
		var c: Array = cover[i]
		var l: float = c[1]
		if lk != "c" and l < CAUSE_L1 + 1.0:
			continue
		if lk == "n" and l > 104.0 and l < 186.0:
			continue  # the bridge: no centre cover
		if lk == "c" and l > 176.0:
			continue
		if i >= 6 and i <= 9:
			continue  # Outer pads carry their own dressing (market stalls, bridge, dock skiff)
		var tall: bool = c[5]
		_box(g, "Cover%d" % i, Vector3(c[2], c[3], c[4]), P(lx + c[0], _hl(half, l), c[3] * 0.5), mats.cover_tall if tall else mats.cover_low)
	if lk == "n":
		for l in [116.0, 174.0]:
			for s in [-1.0, 1.0]:
				_box(g, "BridgePylon%d_%d" % [int(l), int(s)], Vector3(1.6, 7.0, 1.6), P(lx + s * (hw - 1.2), _hl(half, l), 3.5), mats.cover_tall)
			_box(g, "BridgeArch%d" % int(l), Vector3(2 * hw - 0.8, 0.8, 1.2), P(lx, _hl(half, l), 7.4), mats["team_" + _key(half)], false)
	if lk == "s":
		# Halo / Cinder Dock: mana-water channel either side of the skiff (visual).
		var l := _hl(half, 145.0)
		_box(g, "DockWater", Vector3(26.0, 0.04, 26.0), P(lx, l, 0.03), mats.water, false)
		# W16-SDWATER: the same footprint as a wading zone (MapDef.water_zones, -15% speed).
		var wz := WaterZoneDef.new()
		wz.bounds = AABB(P(lx - 13.0, l + 13.0, WATER_Y0), Vector3(26.0, WATER_H, 26.0))
		wz.speed_factor = WATER_SPEED_FACTOR
		water_zones.append(wz)
		_box(g, "Skiff", Vector3(5.0, 0.9, 13.0), P(lx + side * 6.5, l, 0.45), mats.cover_low)
	if lk == "c":
		# Signal Market / Scrap Bazaar stalls around the Socket (5 entrances).
		var l := _hl(half, 145.0)
		for st in [[-8.0, -6.0], [8.0, -6.0], [-8.0, 6.0], [8.0, 6.0]]:
			_box(g, "Stall%d_%d" % [int(st[0]), int(st[1])], Vector3(3.0, 1.3, 3.0), P(st[0], l + st[1], 0.65), mats.cover_low)
			_box(g, "Awning%d_%d" % [int(st[0]), int(st[1])], Vector3(4.0, 0.15, 4.0), P(st[0], l + st[1], 3.2), mats["decal_" + _key(half)], false)


# ---------------------------------------------------------------- plaza + spokes

func _plaza() -> void:
	var g := _node(geo, "MidPlaza")
	_floor_disc(g, "Floor", Vector2(0, MID_L), PLAZA_R, mats.floor_mid, 0.02)
	for s in [-1.0, 1.0]:
		_floor_rect(g, "Spoke%s" % ("N" if s < 0 else "S"), s * (PLAZA_R - 3.0), s * (80.0 - 14.0 if s < 0 else 80.0 - 15.0),
			MID_L - SPOKE_HW, MID_L + SPOKE_HW, mats.floor_mid, 0.02)
		_box(g, "SpokeArch%d" % int(s), Vector3(1.2, 0.8, 2 * SPOKE_HW + 1.0), P(s * 50.0, MID_L, 6.2), mats.glow_n, false)
		for e in [-1.0, 1.0]:
			_box(g, "SpokePost%d_%d" % [int(s), int(e)], Vector3(1.2, 6.0, 1.2), P(s * 50.0, MID_L + e * (SPOKE_HW - 0.8), 3.0), mats.cover_tall)
	var i := 0
	for sx in [-1.0, 1.0]:
		for sl in [-1.0, 1.0]:
			_box(g, "Pillar%d" % i, Vector3(2.5, 4.0, 2.5), P(sx * 13.0, MID_L + sl * 13.0, 2.0), mats.cover_tall)
			_box(g, "LowWall%d" % i, Vector3(5.0, 1.2, 1.2), P(sx * 21.0, MID_L + sl * 17.0, 0.6), mats.cover_low, true, Vector3(0, sx * sl * 40.0, 0))
			i += 1
	_accent_light(g, "PlazaLightN", LEYFALL, P(-18, MID_L, 9.0), 24.0, 1.0)
	_accent_light(g, "PlazaLightS", LEYFALL, P(18, MID_L, 9.0), 24.0, 1.0)


# ---------------------------------------------------------------- Undercroft (flanks)

## One X-shaped tunnel pair (§3.2): half A/B, between the Center lane and the
## North (s = -1) or South (s = +1) lane. Diagonals: outer lane's Outer side
## door -> Center Mid (plaza rim), and Center Outer side door -> outer lane's Mid.
func _undercroft(half: int, s: float) -> void:
	var lk := "n" if s < 0.0 else "s"
	var hk := _key(half)
	var g := _node(geo, "Undercroft_%s%s" % [hk.to_upper(), lk.to_upper()])
	var outer_l := _hl(half, 145.0)
	var j := Vector2(s * 40.0, _hl(half, 178.0))
	_floor_disc(g, "Junction", j, JUNCTION_R, mats.floor_loop, UNDER_Y, TUNNEL_WALL_H)
	_accent_light(g, "JunctionLight", LEYFALL, P(j.x, j.y, UNDER_Y + 3.2), 14.0, 1.4)
	_box(g, "JunctionPillar", Vector3(1.6, TUNNEL_WALL_H, 1.6), P(j.x, j.y, UNDER_Y + TUNNEL_WALL_H * 0.5), mats.cover_tall)
	# Doors: outer lane Outer pad edge, Center Outer pad edge, plaza rim, outer lane Mid pad edge.
	var outer_ph: float = HP[lk][1][5]
	var c_ph: float = HP["c"][1][5]
	var mid_ph: float = HP[lk][2][5]
	var door_o := Vector2(s * (80.0 - outer_ph), outer_l)
	var door_c := Vector2(s * c_ph, outer_l)
	var to_c := (Vector2(0, MID_L) - j).normalized()
	var door_pm := Vector2(0, MID_L) - to_c * (PLAZA_R - 0.5)
	var door_mid := Vector2(s * (80.0 - mid_ph), _hl(half, 201.0))
	var legs := [
		[door_o, -1.0, "OuterToMid", true],
		[door_pm, 1.0, "ToPlaza", false],
		[door_c, -1.0, "CenterOuter", false],
		[door_mid, 1.0, "ToMid", true],
	]
	var wp := {}
	for leg in legs:
		var door: Vector2 = leg[0]
		var dir := (door - j).normalized()
		var rim := j + dir * (JUNCTION_R - 0.5)
		var ext := door + dir * 0.5
		var name: String = leg[2]
		_floor_strip(g, name, Vector3(rim.x, rim.y, UNDER_Y), Vector3(ext.x, ext.y, 0.03), FLANK_W)
		# Door frame (posts + lintel) in team colour at the lane end.
		var perp := Vector2(-dir.y, dir.x)
		for e in [-1.0, 1.0]:
			var pp: Vector2 = door + perp * e * (FLANK_W * 0.5 + 0.3) - dir * 0.6
			_box(g, "%sDoorPost%d" % [name, int(e)], Vector3(0.6, 3.5, 0.6), P(pp.x, pp.y, 1.75), mats["team_" + hk], false)
		wp[name] = [door, rim]
	var hk_l := "a" if half == 0 else "b"
	var cid := String(lk) + "_" + ("ao" if half == 0 else "bo")
	var mid_c := &"c_mid"
	var mid_o := StringName(lk + "_mid")
	var c_out := StringName("c_" + ("ao" if half == 0 else "bo"))
	var jv := Vector3(j.x, UNDER_Y, j.y)
	flanks.append([StringName("fx_%s%s_%s" % [hk_l, lk, lk]), StringName(cid), mid_c,
		[_v(wp.OuterToMid[0]), _v(wp.OuterToMid[1], UNDER_Y), _v(j, UNDER_Y), _v(wp.ToPlaza[1], UNDER_Y), _v(wp.ToPlaza[0])]])
	flanks.append([StringName("fx_%s%s_c" % [hk_l, lk]), c_out, mid_o,
		[_v(wp.CenterOuter[0]), _v(wp.CenterOuter[1], UNDER_Y), _v(j, UNDER_Y), _v(wp.ToMid[1], UNDER_Y), _v(wp.ToMid[0])]])
	var _unused := jv


func _v(p: Vector2, y := 0.0) -> Vector3:
	return P(p.x, p.y, y)


# ---------------------------------------------------------------- hardpoints

## Rows of lane `li` in lane order: dicts with the HardpointDef fields.
func _lane_hps(li: int) -> Array:
	var lk: String = LANES[li][1]
	var lx: float = LANES[li][2]
	var out := []
	for i in 5:
		var row: Array = HP[lk][SLOT_ROW[i]]
		var half := 0 if i < 2 else (1 if i > 2 else -1)
		var l: float = row[3] if half <= 0 else mirror_l(row[3])
		out.append({
			id = StringName("%s_%s" % [lk, SLOT_SUFFIX[i]]),
			name = row[0] if half <= 0 else row[1],
			task = row[2], tier = [HardpointDef.Tier.INNER, HardpointDef.Tier.OUTER, HardpointDef.Tier.MID][SLOT_ROW[i]],
			l = l, x = lx, r = row[4], ph = row[5], dur = row[6], gen = row[7],
			owner = MapDef.TEAM_CONCORD if half == 0 else (MapDef.TEAM_SYNDICATE if half == 1 else MapDef.TEAM_NEUTRAL),
			half = half, idx = i,
		})
	return out


func _hardpoints(anchors: Node3D) -> void:
	for li in LANES.size():
		var hps := _lane_hps(li)
		for h in hps:
			var k := "n" if h.half < 0 else _key(h.half)
			_hardpoint(anchors, h.id, h.task, P(h.x, h.l), h.r, k)
			_sockets(anchors, h.id, h.x, h.l, h.r, LANES[li][3])
			_deck(li, h)
			_placements(h)
		for i in 5:
			if hps[i].task == HardpointDef.TaskKind.PLANT:
				var pts := _cradle_points(li, i)
				for team in 2:
					var a := CellCradleAnchor.new()
					a.name = "Cradle_%s_%s" % [String(hps[i].id).to_upper(), "C" if team == 0 else "S"]
					a.hardpoint_id = hps[i].id
					a.team = team
					a.position = pts[team]
					a.gizmo_extents = 1.0
					_add(anchors, a)
					var k := "a" if team == 0 else "b"
					_cyl(geo, "CellCradle_%s_%d" % [String(hps[i].id).to_upper(), team], 0.9, 0.7, 0.5, pts[team], mats["team_" + k], false, 8)
					_cyl(geo, "CellCradleGlow_%s_%d" % [String(hps[i].id).to_upper(), team], 0.35, 0.35, 0.3, pts[team] + Vector3(0, 0.5, 0), mats["glow_" + k], false, 12)


## Gate of lane `li` for `team` (floor, in front of the HQ wall).
func _gate(li: int, team: int) -> Vector3:
	var gx: float = [-GATE_X, 0.0, GATE_X][li]
	return P(gx, _hl(team, HQ_FRONT))


## E14 Cradles for the Plant node at lane index i: [0] Concord's, [1] Syndicate's.
func _cradle_points(li: int, i: int) -> PackedVector3Array:
	var hps := _lane_hps(li)
	var c: Vector3 = P(hps[i - 1].x + CRADLE_X, hps[i - 1].l) if i - 1 >= 0 else _gate(li, 0) + P(CRADLE_X, 8.0)
	var sy: Vector3 = P(hps[i + 1].x + CRADLE_X, hps[i + 1].l) if i + 1 < 5 else _gate(li, 1) + P(CRADLE_X, -8.0)
	return PackedVector3Array([c, sy])


func _hardpoint(anchors: Node3D, id: StringName, task: int, pos: Vector3, r: float, k: String) -> void:
	var a := HardpointAnchor.new()
	a.name = "HP_" + String(id).to_upper()
	a.hardpoint_id = id
	a.task = task
	a.zone_radius = r
	a.position = pos
	a.gizmo_extents = 2.0
	_add(anchors, a)
	var vis := _node(geo, "Hardpoint_" + String(id).to_upper())
	vis.position = pos
	var hp_c: Color = AZURE if k == "a" else (EMBER if k == "b" else LEYFALL)
	_accent_light(vis, "AccentLight", hp_c, Vector3(0, 8.0, 0), maxf(r * 1.6, 18.0), 1.3)
	match task:
		HardpointDef.TaskKind.BREACH:
			_cyl(vis, "Zone", r, r, 0.03, Vector3(0, 0.01, 0), mats["decal_" + k], false, 6)
			_cyl(vis, "GeneratorCore", 1.2, 1.2, 2.4, Vector3.ZERO, mats["team_" + k], true, 6)
			var dome := MeshInstance3D.new()
			dome.name = "ShieldDome"
			var sm := SphereMesh.new()
			sm.radius = 3.4
			sm.height = 3.4
			sm.is_hemisphere = true
			sm.material = mats["glow_" + k]
			dome.mesh = sm
			_add(vis, dome)
			for s in [-1.0, 1.0]:
				_box(vis, "ArchPost%d" % int(s), Vector3(2, 7.5, 2), Vector3(s * 7.5, 3.75, 0), mats.cover_tall)
			_box(vis, "ArchLintel", Vector3(17, 1.5, 2), Vector3(0, 8.25, 0), mats.cover_tall)
		HardpointDef.TaskKind.PLANT:
			var hw := r
			for s in [-1.0, 1.0]:
				_box(vis, "PadEdgeX%d" % int(s), Vector3(0.35, 0.03, 2 * hw), Vector3(s * hw, 0.015, 0), mats["decal_" + k], false)
				_box(vis, "PadEdgeZ%d" % int(s), Vector3(2 * hw, 0.03, 0.35), Vector3(0, 0.015, s * hw), mats["decal_" + k], false)
				for t in [-1.0, 1.0]:
					_box(vis, "BracketX%d%d" % [int(s), int(t)], Vector3(3, 0.5, 0.4), Vector3(s * (hw - 1.5), 0.25, t * hw), mats["team_" + k], false)
					_box(vis, "BracketZ%d%d" % [int(s), int(t)], Vector3(0.4, 0.5, 3), Vector3(s * hw, 0.25, t * (hw - 1.5)), mats["team_" + k], false)
			_box(vis, "PylonStem", Vector3(0.9, 2.2, 0.9), Vector3(0, 1.1, 0), mats["team_" + k])
			_box(vis, "ProngL", Vector3(0.45, 2.0, 0.45), Vector3(-0.55, 2.9, 0), mats["team_" + k], false, Vector3(0, 0, 22))
			_box(vis, "ProngR", Vector3(0.45, 2.0, 0.45), Vector3(0.55, 2.9, 0), mats["team_" + k], false, Vector3(0, 0, -22))
			_cyl(vis, "Socket", 0.35, 0.35, 0.6, Vector3(0, 2.6, 0), mats["glow_" + k], false, 12)
			_box(vis, "Awning", Vector3(6, 0.15, 6), Vector3(0, 4.6, 0), mats["decal_" + k], false)
		HardpointDef.TaskKind.HOLD:
			_cyl(vis, "Dais", 8.0, 7.0, 0.3, Vector3.ZERO, mats.floor_mid, true, 48)
			var ring := MeshInstance3D.new()
			ring.name = "Zone"
			var tm := TorusMesh.new()
			tm.inner_radius = r - 0.3
			tm.outer_radius = r + 0.3
			tm.rings = 64
			tm.material = mats["glow_" + k]
			ring.mesh = tm
			ring.scale = Vector3(1, 0.08, 1)
			ring.position = Vector3(0, 0.05, 0)
			_add(vis, ring)
			_cyl(vis, "Plinth", 2.8, 2.4, 0.6, Vector3(0, 0.3, 0), mats.cover_tall, true, 24)
			_cyl(vis, "LightPillar", 0.7, 0.7, 12.0, Vector3(0, 0.9, 0), mats["glow_" + k], false, 16)


func _sockets(anchors: Node3D, id: StringName, x: float, l: float, r: float, lane_hw: float) -> void:
	for side in 2:
		var sl := l - (r + SOCKET_GAP) if side == 0 else l + (r + SOCKET_GAP)
		var s := BarricadeSocketAnchor.new()
		s.name = "Socket_%s_%s" % [String(id).to_upper(), "A" if side == 0 else "B"]
		s.hardpoint_id = id
		s.side = side
		s.span_m = 2 * lane_hw
		s.position = P(x, sl)
		_add(anchors, s)
		_box(geo, "SocketMark_%s_%d" % [String(id).to_upper(), side], Vector3(2 * lane_hw, 0.03, 0.6), P(x, sl, 0.015), mats.socket, false)


## Lateral side of a hardpoint's pad that has no flank door / spoke: outer lanes
## use their void side; the Center Inner gets decks on both sides; Center Outer
## (two doors) and the Spindle (plaza) get none.
func _deck_sides(li: int, h: Dictionary) -> Array:
	var lk: String = LANES[li][1]
	if lk == "c":
		return [-1.0, 1.0] if h.tier == HardpointDef.Tier.INNER else []
	return [-1.0 if lk == "n" else 1.0]


## Overlook deck (verticality): a 3 m platform on the pad's side strip with a
## ramp toward the Mid, a parapet on the void edge and a low wall on the lane edge.
func _deck(li: int, h: Dictionary) -> void:
	var toward_mid := 1.0 if h.l < MID_L else -1.0
	if h.tier == HardpointDef.Tier.MID:
		toward_mid = 1.0
	var ph: float = h.ph
	for s in _deck_sides(li, h):
		var g := _node(geo, "Deck_%s_%d" % [String(h.id).to_upper(), int(s)])
		var x1: float = h.x + s * (ph - 0.6)
		var x0: float = x1 - s * DECK_W
		var xc := (x0 + x1) * 0.5
		var l_back: float = h.l - toward_mid * 5.0
		var l_front: float = h.l + toward_mid * 6.0
		_slab(g, "Block", x0, x1, l_back, l_front, 0.0, DECK_H, mats.deck)
		_sloped(g, "Ramp", Vector3(xc, l_front - toward_mid * 0.3, DECK_H), Vector3(xc, h.l + toward_mid * (ph - 1.2), 0.0), DECK_W, mats.deck, 0.4)
		var par := _slab(g, "Parapet", x1 - s * 0.4, x1, l_back, l_front, DECK_H, DECK_H + RAIL_H, mats.rail)
		_edge_blocker(par, 0.4, absf(l_front - l_back), RAIL_H)
		var lw_l: float = h.l - toward_mid * 1.0
		_slab(g, "LowWall", x0, x0 + s * 0.4, lw_l - 2.0, lw_l + 2.0, DECK_H, DECK_H + 1.0, mats.cover_low)
		_slab(g, "BackWall", x0, x1, l_back, l_back - toward_mid * 0.4, DECK_H, DECK_H + 1.0, mats.cover_low)


## C5 placements: Garrison posts (3, inside the zone toward the Mid) and the
## Supply Cache (pad side, toward the owner's HQ). Visual markers only.
func _placements(h: Dictionary) -> void:
	var g := _node(geo, "Placements_%s" % String(h.id).to_upper())
	for p in _garrison_points(h):
		_cyl(g, "GarrisonPost", 0.7, 0.7, 0.04, p + Vector3(0, 0.02, 0), mats.garrison, false, 6)
	var c := _cache_point(h)
	_box(g, "SupplyCache", Vector3(1.2, 0.9, 0.9), c + Vector3(0, 0.45, 0), mats.cache, false)
	_box(g, "SupplyCacheLid", Vector3(1.3, 0.12, 1.0), c + Vector3(0, 0.95, 0), mats.cover_tall, false)


func _garrison_points(h: Dictionary) -> PackedVector3Array:
	var toward_mid := 1.0 if h.l < MID_L else -1.0
	var d: float = h.r * 0.55
	var out := PackedVector3Array()
	for off in [Vector2(-4.0, d), Vector2(4.0, d), Vector2(0.0, -d * 0.5)]:
		out.append(P(h.x + off.x, h.l + toward_mid * off.y, 0.0))
	return out


func _cache_point(h: Dictionary) -> Vector3:
	var lk := String(h.id).substr(0, 1)
	if lk == "c" and h.tier == HardpointDef.Tier.MID:
		return P(h.x + 9.0, h.l, 0.0)
	var side := 1.0 if lk == "n" else -1.0  # away from the outer-lane decks
	var back := -1.0 if h.l < MID_L else 1.0
	if h.tier == HardpointDef.Tier.MID:
		back = 1.0
	return P(h.x + side * 9.5, h.l + back * 9.0, 0.0)


# ---------------------------------------------------------------- spawns

func _spawn_points(half: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for x in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		out.append(P(x, _hl(half, 4.0), 0.05))
	return out


func _spawns() -> void:
	var sp := _node(map_root, "Spawns")
	for half in 2:
		var team := _node(sp, "Concord" if half == 0 else "Syndicate")
		var pts := _spawn_points(half)
		for i in pts.size():
			var m := Marker3D.new()
			m.name = "Spawn%d" % (i + 1)
			m.position = pts[i]
			m.rotation_degrees.y = 0.0 if half == 0 else 180.0
			_add(team, m)
		var sd := Marker3D.new()
		sd.name = "SuddenDeathSpawn"
		sd.position = P(0, _hl(half, 185.0), 0.05)
		_add(team, sd)
	var named := {"PlayerSpawn": _spawn_points(0)[0], "DummySpawn1": P(-3, 19, 0.05), "DummySpawn2": P(4, 21, 0.05),
		"TeamSpawn0": _spawn_points(0)[2], "TeamSpawn1": _spawn_points(1)[2]}
	for n in named:
		var m := Marker3D.new()
		m.name = n
		m.position = named[n]
		_add(map_root, m)
	var hq := _node(map_root, "HQAnchors")
	for half in 2:
		var t := "Concord" if half == 0 else "Syndicate"
		var pts := {"Sanctum": P(0, _hl(half, SANCTUM_L)), "Uplink": P(0, _hl(half, UPLINK_L)),
			"FoundryPad": P(-19, _hl(half, 17.0)), "ArmoryPad": P(19, _hl(half, 17.0)),
			"LaneGate": _gate(1, half), "LaneGateNorth": _gate(0, half), "LaneGateSouth": _gate(2, half)}
		for n in pts:
			var m := Marker3D.new()
			m.name = "%s%s" % [t, n]
			m.position = pts[n]
			_add(hq, m)


# ---------------------------------------------------------------- navmesh

func _navmesh_settings() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav_source"
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.region_min_size = 8.0
	return nm


# ---------------------------------------------------------------- overview + data

func _label(parent: Node, text: String, pos: Vector3, size: float, c: Color) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.position = pos
	lb.pixel_size = size
	lb.font_size = 64
	lb.outline_size = 18
	lb.modulate = c
	lb.outline_modulate = Color(0, 0, 0, 0.9)
	lb.no_depth_test = true
	lb.shaded = false
	# Lie flat, text reading along screen-right (= -Z) from the overview camera.
	lb.basis = Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	parent.add_child(lb)
	lb.owner = parent if parent.owner == null else parent.owner


func _save_overview(nm: NavigationMesh) -> void:
	var ov := Node3D.new()
	ov.name = "ShardlineFrontOverview"
	get_root().add_child(ov)
	var map: Node3D = (load(MAP_PATH) as PackedScene).instantiate()
	ov.add_child(map)
	map.owner = ov
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := nm.get_vertices()
	for p in nm.get_polygon_count():
		var poly := nm.get_polygon(p)
		for t in range(1, poly.size() - 1):
			for idx in [poly[0], poly[t + 1], poly[t]]:
				st.add_vertex(v[idx] + Vector3(0, 0.12, 0))
	st.commit(am)
	var mi := MeshInstance3D.new()
	mi.name = "NavmeshOverlay"
	mi.mesh = am
	mi.material_override = _mat(Color(0.2, 1.0, 0.45), 0.0, 0.18, true)
	ov.add_child(mi)
	mi.owner = ov
	var labels := Node3D.new()
	labels.name = "Labels"
	ov.add_child(labels)
	labels.owner = ov
	for li in LANES.size():
		var lx: float = LANES[li][2]
		_label(labels, String(LANES[li][0]).to_upper() + " LANE", P(lx + (-30.0 if lx < 0.0 else 30.0) if lx != 0.0 else 16.0, 115.0, 20.0), 0.1, Color.WHITE)
		for h in _lane_hps(li):
			var task_s: String = ["HOLD", "PLANT", "BREACH"][h.task]
			_label(labels, "%s\n%s" % [String(h.id).to_upper().replace("_", "-"), task_s], P(h.x - h.r - 6.0, h.l, 20.0), 0.07,
				AZURE.lightened(0.4) if h.owner == 0 else (EMBER.lightened(0.3) if h.owner == 1 else Color(0.85, 0.75, 1.0)))
	_label(labels, "MID PLAZA", P(14.0, MID_L, 20.0), 0.08, Color(0.85, 0.75, 1.0))
	_label(labels, "CONCORD HQ", P(-40.0, 16.0, 20.0), 0.09, AZURE.lightened(0.4))
	_label(labels, "SYNDICATE HQ", P(-40.0, 404.0, 20.0), 0.09, EMBER.lightened(0.3))
	for f in flanks:
		var w: Array = f[3]
		_label(labels, String(f[0]).to_upper(), (w[1] + w[2]) * 0.5 + Vector3(0, 24.0, 0), 0.045, Color(0.9, 0.85, 1.0))
	var cam := Camera3D.new()
	cam.name = "OverviewCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 450.0
	cam.near = 1.0
	cam.far = 600.0
	cam.current = true
	var env: Environment = (map.get_node("Env") as WorldEnvironment).environment.duplicate()
	env.fog_enabled = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.1, 0.2)
	cam.environment = env
	cam.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)), Vector3(0, 300, -LANE_LEN * 0.5))
	ov.add_child(cam)
	cam.owner = ov
	var packed := PackedScene.new()
	_check(packed.pack(ov), "pack overview")
	_check(ResourceSaver.save(packed, OVERVIEW_PATH), OVERVIEW_PATH)


func _save_map_def() -> void:
	var md := MapDef.new()
	md.id = &"map_front"
	md.display_name = "Shardline Front"
	md.scene = load(MAP_PATH)
	md.reference_run_speed = 6.0
	md.mid_plaza_center = P(0, MID_L)
	md.mid_plaza_radius = PLAZA_R
	md.sudden_death_spawns = PackedVector3Array([P(0, 185.0, 0.05), P(0, 235.0, 0.05)])
	if ResourceLoader.exists(RULES_PATH):
		md.match_rules = load(RULES_PATH)
	md.water_zones = water_zones
	var lanes: Array[LaneDef] = []
	for li in LANES.size():
		var lane := LaneDef.new()
		lane.id = LANES[li][0]
		var lane_hw: float = LANES[li][3]
		var hps: Array[HardpointDef] = []
		for h in _lane_hps(li):
			var d := HardpointDef.new()
			d.id = h.id
			d.display_name = h.name
			d.task = h.task
			d.tier = h.tier
			d.position = P(h.x, h.l)
			d.zone_radius = h.r
			d.zone_height = 6.0
			d.base_duration_s = h.dur
			d.generator_hp = h.gen
			d.initial_owner = h.owner
			d.lane_index = h.idx
			if d.task == HardpointDef.TaskKind.PLANT:
				d.cell_cradles = _cradle_points(li, h.idx)
			d.barricade_sockets = PackedVector3Array([P(h.x, h.l - h.r - SOCKET_GAP), P(h.x, h.l + h.r + SOCKET_GAP)])
			d.garrison_points = _garrison_points(h)
			d.supply_cache = _cache_point(h)
			var doors := PackedVector3Array()
			for f in flanks:
				var w: Array = f[3]
				if f[1] == h.id:
					doors.append(w[0])
				if f[2] == h.id:
					doors.append(w[w.size() - 1])
			d.side_doors = doors
			hps.append(d)
		lane.hardpoints = hps
		var loops: Array[FlankLoopDef] = []
		for f in flanks:
			if String(f[1]).substr(0, 1) != String(LANES[li][1]):
				continue
			var fl := FlankLoopDef.new()
			fl.id = f[0]
			fl.from_hardpoint = f[1]
			fl.to_hardpoint = f[2]
			var wps := PackedVector3Array()
			for w in f[3]:
				wps.append(w)
			fl.waypoints = wps
			fl.outer_door = wps[0]
			fl.mid_door = wps[wps.size() - 1]
			loops.append(fl)
		lane.flank_loops = loops
		var _hw := lane_hw
		lanes.append(lane)
	md.lanes = lanes
	var hqs: Array[HqDef] = []
	for half in 2:
		var q := HqDef.new()
		q.team = half
		q.sanctum = P(0, _hl(half, SANCTUM_L))
		q.sanctum_radius = SANCTUM_R
		q.uplink = P(0, _hl(half, UPLINK_L))
		q.foundry = P(-19, _hl(half, 17.0))
		q.armory = P(19, _hl(half, 17.0))
		q.lane_gate = _gate(1, half)
		q.lane_gates = PackedVector3Array([_gate(0, half), _gate(1, half), _gate(2, half)])
		q.spawn_points = _spawn_points(half)
		q.spawn_yaw_deg = 0.0 if half == 0 else 180.0
		hqs.append(q)
	md.hqs = hqs
	_check(ResourceSaver.save(md, DEF_PATH), DEF_PATH)
