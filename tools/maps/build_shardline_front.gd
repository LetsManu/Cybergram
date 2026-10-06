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
## W18-GEO: jungle navmesh (its own region on MapDef.JUNGLE_NAV_LAYER) and the
## background-life anchors (docs/architecture/ambient-anchors.md).
const NAV_JUNGLE_PATH := "res://assets/maps/front/shardline_front_navmesh_jungle.res"
const AMBIENT_PATH := "res://assets/data/match/ambient_front.tres"
const Kit := preload("res://tools/maps/kit/map_kit.gd")

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
const CRADLE_DL := 3.0
## Armory pad (HqDef.armory): beside the spawn at the Sanctum's edge, in view of
## a fresh spawn (owner decision 2026-10-06: "like the LoL shop at the spawn").
## The old Armory building stays as HQ structure.
const ARMORY_X := 8.0
const ARMORY_L := 12.0
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

## W18-GEO rolling lanes: per lane key, cosine bumps [L0, L1, amplitude m] in
## half-A lane distance (half B mirrors). Max slope = |A| * PI / (L1 - L0):
## all <= 17 degrees (owner: 2-4 m hills, walkable <= ~20 degrees). Hardpoint
## pads, the HQ causeways and the plaza stay flat at y = 0.
const ROLL := {
	"n": [[100.0, 130.0, -2.0], [160.0, 196.0, 3.5]],  # dip, then the high bridge span
	"c": [[40.0, 70.0, 2.0], [159.0, 181.5, 2.0]],
	"s": [[160.0, 196.0, 2.5]],
}
## Center market (half-A L): sunken street between the C-AI and C-AO pads.
const MARKET_L0 := 100.0
const MARKET_L1 := 131.0
const STREET_HW := 5.0
const STREET_Y := -3.5
const TERRACE_U1 := 9.0
const SHOPROW_U1 := 16.0
## Floors within this height of each other count as one level (edge rules).
## HeroMotor has no step-up (the capsule rides lips of ~0.1 m at most), so any
## bigger lip is a wall or a drop, never a seam.
const LEVEL_TOL := 0.12
const KERB_H := 0.6
enum Edge { SAME, WALL, DROP, VOID }

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
## W18-GEO: jungle (own nav group / region), non-nav dressing, building markers.
var jungle: Node3D
var dressing: Node3D
var buildings: Node3D
var links: Node3D
var ambient := AmbientAnchorsDef.new()
var amb_root: Node3D
var jungle_paths: Array[PackedVector3Array] = []
var jungle_pockets: Array[JunglePocketDef] = []
## Labels for the overview: [text, world pos, colour].
var ov_labels: Array = []


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
	# W18-GEO: the between-lane jungle bakes into its own region (layer 2).
	var nav_j := NavigationRegion3D.new()
	nav_j.name = "NavRegionJungle"
	nav_j.navigation_layers = MapDef.JUNGLE_NAV_LAYER
	_add(map_root, nav_j)
	jungle = Node3D.new()
	jungle.name = "Jungle"
	jungle.add_to_group(&"nav_jungle", true)
	_add(map_root, jungle)
	dressing = _node(map_root, "Dressing")
	buildings = _node(map_root, "Buildings")
	links = _node(map_root, "NavLinks")
	amb_root = _node(map_root, "AmbientAnchors")
	var anchors := _node(map_root, "Anchors")
	for half in 2:
		_hq(half)
	for li in LANES.size():
		_lane(li)
	_plaza()
	for half in 2:
		for s in [-1.0, 1.0]:
			_undercroft(half, s)
	# W18-GEO living map: multi-level lane features, buildings, jungle, dressing.
	for half in 2:
		_market(half)
		_bridge_walkway(half)
		_guardhouse(half)
		_docks(half)
		_bridge_towers(half)
		for s in [-1.0, 1.0]:
			_jungle(half, s)
		_city_rows(half)
	_plaza_bridge()
	for li in LANES.size():
		for half in 2:
			_lane_cover(_lane_group(li, half), li, half)
	_build_edges()
	_hardpoints(anchors)
	_spawns()
	_sky_routes()
	var nm := _bake(&"nav_source")
	_check(ResourceSaver.save(nm, NAV_PATH, ResourceSaver.FLAG_COMPRESS), NAV_PATH)
	nav.navigation_mesh = load(NAV_PATH)
	var nmj := _bake(&"nav_jungle")
	_check(ResourceSaver.save(nmj, NAV_JUNGLE_PATH, ResourceSaver.FLAG_COMPRESS), NAV_JUNGLE_PATH)
	nav_j.navigation_mesh = load(NAV_JUNGLE_PATH)
	_check(ResourceSaver.save(ambient, AMBIENT_PATH), AMBIENT_PATH)
	var packed := PackedScene.new()
	_check(packed.pack(map_root), "pack map")
	_check(ResourceSaver.save(packed, MAP_PATH), MAP_PATH)
	_save_map_def()
	_save_overview([nm, nmj])
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
	# W18-GEO living map kit (same panel shader, lane identities).
	mats.stairs = _panel(Color(0.42, 0.42, 0.5), Color(0.16, 0.16, 0.26), 1.0, Color.BLACK, 0.0, 1.0)
	mats.floor_house = _panel(Color(0.3, 0.27, 0.3), Color(0.12, 0.1, 0.14), 1.5)
	mats.floor_market = _panel(Color(0.32, 0.24, 0.36), Color(0.5, 0.12, 0.42), 2.0)
	mats.floor_jungle = _panel(Color(0.25, 0.24, 0.32), Color(0.1, 0.09, 0.16), 2.0, Color.BLACK, 0.0, 3.0)
	mats.floor_dock = _panel(Color(0.36, 0.33, 0.3), Color(0.16, 0.13, 0.1), 2.5)
	mats.wall_n = _panel(Color(0.38, 0.45, 0.52), Color(0.14, 0.2, 0.26), 3.0, TEAL, 4.2, 3.0)
	mats.wall_s = _panel(Color(0.45, 0.36, 0.3), Color(0.2, 0.14, 0.1), 3.0, Color("#FFB347"), 4.2, 3.0)
	mats.wall_city = _panel(Color(0.24, 0.22, 0.34), Color(0.1, 0.09, 0.18), 4.0, LEYFALL, 7.0, 4.0)
	mats.wall_jungle = _panel(Color(0.28, 0.24, 0.36), Color(0.12, 0.08, 0.18), 3.0, Color("#FF3FA4"), 3.4, 3.0)
	mats.neon_pink = _mat(Color("#FF3FA4"), 0.0, 0.85, true)
	mats.neon_violet = _mat(Color("#B266FF"), 0.0, 0.9, true)
	mats.cargo_a = _panel(Color(0.62, 0.3, 0.2), Color(0.3, 0.12, 0.08), 0.8, Color.BLACK, 0.0, 1.5)
	mats.cargo_b = _panel(Color(0.2, 0.42, 0.55), Color(0.08, 0.18, 0.26), 0.8, Color.BLACK, 0.0, 1.5)
	mats.crane = _panel(Color(0.85, 0.62, 0.18), Color(0.3, 0.2, 0.05), 1.5, Color.BLACK, 0.0, 0.0)
	mats.trim_a = _mat(AZURE, 0.0, 1.0, true)
	mats.trim_n = _mat(TEAL, 0.0, 1.0, true)
	mats.mount_billboard = _mat(Color(0.3, 0.6, 1.0), 0.0, 0.35, true)
	mats.mount_neon = _mat(Color("#FF3FA4"), 0.0, 0.55, true)
	mats.mount_shop = _mat(Color("#FFD36A"), 0.0, 0.55, true)
	mats.mount_vent = _mat(Color(0.7, 0.7, 0.8), 0.0, 0.3, true)
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
	_reg({t = "rect", x0 = xa, x1 = xb, l0 = la, l1 = lb, top = top}, parent, n, rails)


## Registers a walkable (or solid) shape; `rails` queues automatic edge rails.
func _reg(sh: Dictionary, parent: Node, n: String, rails := true) -> Dictionary:
	shapes.append(sh)
	if rails:
		rail_jobs.append({s = sh, g = parent, n = n})
	return sh


func _floor_disc(parent: Node, n: String, c: Vector2, r: float, mat: Material, top := 0.0, wall_h := 0.0) -> void:
	_cyl(parent, n, r, r, 1.0, P(c.x, c.y, top - 1.0), mat, true, 64)
	var sh := {t = "disc", c = c, r = r, top = top}
	shapes.append(sh)
	rail_jobs.append({s = sh, g = parent, n = n, wall = wall_h})


## Flank tunnel segment: sloped floor from a to b (x, L, y), walls where it faces void.
func _floor_strip(parent: Node, n: String, a: Vector3, b: Vector3, w: float) -> void:
	var body := _sloped(parent, n, a, b, w, mats.floor_loop)
	shapes.append({t = "strip", a = a, b = b, w = w})
	strip_jobs.append({body = body, a = a, b = b, w = w})


## W18-GEO: solid block (building, retaining wall, quay) from `base` to `top`.
## `walk` = its top is a walkable floor (rooftop route, terrace, quay).
func _solid(parent: Node, n: String, x0: float, x1: float, l0: float, l1: float, top: float, base: float, mat: Material, walk := false, rails := true) -> Node3D:
	var xa := minf(x0, x1)
	var xb := maxf(x0, x1)
	var la := minf(l0, l1)
	var lb := maxf(l0, l1)
	var body := _slab(parent, n, xa, xb, la, lb, base, top, mat)
	_reg({t = "rect", x0 = xa, x1 = xb, l0 = la, l1 = lb, top = top, solid = true, base = base, walk = walk}, parent, n, rails and walk)
	return body


## W18-GEO: solid wedge (ramp, or stairs when `stairs`) over x0..x1 / l0..l1
## rising along `axis` (0 = x, 1 = L) from y_lo at the low coordinate to y_hi
## at the high one. Collider is the smooth wedge (HeroMotor has no step-up);
## stairs get non-colliding step dressing.
func _wedge(parent: Node, n: String, x0: float, x1: float, l0: float, l1: float, axis: int, y_lo: float, y_hi: float, mat: Material, stairs := false, base := NAN) -> void:
	var xa := minf(x0, x1)
	var xb := maxf(x0, x1)
	var la := minf(l0, l1)
	var lb := maxf(l0, l1)
	if is_nan(base):
		base = minf(y_lo, y_hi) - 0.6
	# World z = -L: the low-L side is the high-z side.
	var pts: PackedVector3Array
	if axis == 0:
		pts = Kit.wedge_points(xa, xb, -lb, -la, 0, y_lo, y_hi, base)
	else:
		pts = Kit.wedge_points(xa, xb, -lb, -la, 2, y_hi, y_lo, base)
	var body := StaticBody3D.new()
	body.name = n
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = Kit.convex(pts)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = Kit.hexa_mesh(pts, mat)
	body.add_child(mi)
	if stairs:
		var st := MeshInstance3D.new()
		st.name = "Steps"
		if axis == 0:
			st.mesh = Kit.steps_mesh(xa, xb, -lb, -la, 0, y_lo, y_hi, mats.stairs)
		else:
			st.mesh = Kit.steps_mesh(xa, xb, -lb, -la, 2, y_hi, y_lo, mats.stairs)
		body.add_child(st)
	_add(parent, body)
	_reg({t = "rect", x0 = xa, x1 = xb, l0 = la, l1 = lb, ramp = [axis, y_lo, y_hi], solid = true, base = base, walk = true}, parent, n)


## W18-GEO rolling floor (trimesh) for lane `lk` between world L l0..l1.
func _terrain(parent: Node, n: String, x0: float, x1: float, l0: float, l1: float, lk: String, mat: Material) -> void:
	var la := minf(l0, l1)
	var lb := maxf(l0, l1)
	var steps := maxi(4, ceili((lb - la) / 1.5))
	var zs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for i in steps + 1:
		var l := lerpf(lb, la, float(i) / steps)  # increasing z = -L
		zs.append(-l)
		ys.append(lane_h(lk, l))
	var built: Array = Kit.terrain_strip(minf(x0, x1), maxf(x0, x1), zs, ys, 1.0, mat)
	var body := StaticBody3D.new()
	body.name = n
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = built[0]
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = built[1]
	body.add_child(cs)
	_add(parent, body)
	_reg({t = "rect", x0 = minf(x0, x1), x1 = maxf(x0, x1), l0 = la, l1 = lb, prof = lk}, parent, n)


## Lane height profile (ROLL) at world lane distance l (mirrored for half B).
static func lane_h(lk: String, l: float) -> float:
	var la := l if l <= MID_L else LANE_LEN - l
	for seg in ROLL.get(lk, []):
		if la > seg[0] and la < seg[1]:
			var t: float = (la - seg[0]) / (seg[1] - seg[0])
			return seg[2] * 0.5 * (1.0 - cos(TAU * t))
	return 0.0


## Height of shape `s` at p (x, L), NAN outside it.
func _shape_h(s: Dictionary, p: Vector2) -> float:
	match s.t:
		"rect":
			if p.x < s.x0 or p.x > s.x1 or p.y < s.l0 or p.y > s.l1:
				return NAN
			if s.has("prof"):
				return lane_h(s.prof, p.y)
			if s.has("ramp"):
				var r: Array = s.ramp
				var t: float = (p.x - s.x0) / (s.x1 - s.x0) if r[0] == 0 else (p.y - s.l0) / (s.l1 - s.l0)
				return lerpf(r[1], r[2], t)
			return s.top
		"disc":
			return s.top if p.distance_to(s.c) <= s.r else NAN
		"strip":
			var a := Vector2(s.a.x, s.a.y)
			var b := Vector2(s.b.x, s.b.y)
			var ab := b - a
			var along: float = (p - a).dot(ab) / ab.length()
			var t := clampf(along / ab.length(), 0.0, 1.0)
			if along >= -0.3 and along <= ab.length() + 0.3 and p.distance_to(a + ab * t) <= s.w * 0.5:
				return lerpf(s.a.z, s.b.z, t)
	return NAN


## Highest walkable floor at (x, L) at or below `below` (NAN if none).
func _ground(x: float, l: float, below := 50.0) -> float:
	var best := NAN
	for s in shapes:
		if s.get("solid", false) and not s.get("walk", false):
			continue
		var h := _shape_h(s, Vector2(x, l))
		if not is_nan(h) and h <= below + 0.01 and (is_nan(best) or h > best):
			best = h
	return best


## What lies just beyond a floor edge at p for a floor at height y.
func _probe(p: Vector2, y: float) -> int:
	var wall := false
	var drop := false
	for s in shapes:
		var h := _shape_h(s, p)
		if is_nan(h):
			continue
		var walk: bool = not s.get("solid", false) or s.get("walk", false)
		if walk and absf(h - y) <= LEVEL_TOL:
			return Edge.SAME
		if s.get("solid", false) and h > y and s.get("base", -50.0) < y + 0.5:
			wall = true
		elif walk and h < y:
			drop = true
	if wall:
		return Edge.WALL
	if drop:
		return Edge.DROP
	return Edge.VOID


func _build_edges() -> void:
	for j in rail_jobs:
		if j.s.t == "rect":
			_rect_rails(j)
		else:
			_disc_rails(j)
	for j in strip_jobs:
		_strip_walls(j)


## Edge treatment on each run of a rect's 4 edges: rail + edge blocker over the
## void, a jump-over kerb above a lower floor (drop edge), nothing where it
## meets a floor at the same level or a wall.
func _rect_rails(j: Dictionary) -> void:
	var s: Dictionary = j.s
	var edges := [
		[Vector2(s.x0, s.l0), Vector2(s.x1, s.l0), Vector2(0, -1)],
		[Vector2(s.x0, s.l1), Vector2(s.x1, s.l1), Vector2(0, 1)],
		[Vector2(s.x0, s.l0), Vector2(s.x0, s.l1), Vector2(-1, 0)],
		[Vector2(s.x1, s.l0), Vector2(s.x1, s.l1), Vector2(1, 0)],
	]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var nrm: Vector2 = e[2]
		var len := a.distance_to(b)
		var steps := maxi(1, ceili(len / 0.5))
		var tang := (b - a).normalized()
		var run_start := -1.0
		var run_kind := -1
		for k in steps + 1:
			var kind := Edge.SAME
			if k < steps:
				var mid := a.lerp(b, (float(k) + 0.5) / steps)
				var y := _shape_h(s, mid - nrm * 0.05)
				kind = Edge.VOID
				for off in [0.0, 0.3, -0.3]:
					# Probe just past the edge: a neighbouring stair / ramp must be
					# compared at the shared edge, not 0.6 m down its slope.
					var r := _probe(mid + nrm * 0.15 + tang * off, y)
					kind = mini(kind, r)
			# W18-GEO: HeroMotor has no step-up, so a stair / ramp side against a
			# higher block gets a stringer kerb: the navmesh then never cuts across
			# the small lip near the top that the capsule cannot climb.
			if kind == Edge.WALL and s.has("ramp"):
				kind = Edge.DROP
			var railed := kind == Edge.VOID or kind == Edge.DROP
			if run_start >= 0.0 and (not railed or kind != run_kind):
				_rail_run(j, a.lerp(b, run_start), a.lerp(b, float(k) / steps), nrm, run_kind)
				run_start = -1.0
			if railed and run_start < 0.0:
				run_start = float(k) / steps
				run_kind = kind


func _rail_run(j: Dictionary, p0: Vector2, p1: Vector2, nrm: Vector2, kind: int) -> void:
	var total := p0.distance_to(p1)
	if total < 0.4:
		return
	var s: Dictionary = j.s
	var flat := not s.has("prof") and not s.has("ramp")
	var pieces := 1 if flat else maxi(1, ceili(total / 2.0))
	for i in pieces:
		var q0 := p0.lerp(p1, float(i) / pieces)
		var q1 := p0.lerp(p1, float(i + 1) / pieces)
		var y0 := _shape_h(s, q0 - nrm * 0.05)
		var y1 := _shape_h(s, q1 - nrm * 0.05)
		_rail_piece(j.g, "%s%s%d" % [j.n, "Rail" if kind == Edge.VOID else "Kerb", _rail_n], q0 - nrm * 0.25, q1 - nrm * 0.25, y0, y1, kind == Edge.VOID)
		_rail_n += 1


## One straight rail / kerb piece from (x, L) q0 at floor height y0 to q1 at y1.
func _rail_piece(g: Node, n: String, q0: Vector2, q1: Vector2, y0: float, y1: float, blocker: bool) -> void:
	var h := RAIL_H if blocker else KERB_H
	var a := P(q0.x, q0.y, y0)
	var b := P(q1.x, q1.y, y1)
	var x_axis := (b - a).normalized()
	var z_axis := x_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var body := StaticBody3D.new()
	body.name = n
	body.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (a + b) * 0.5 + y_axis * h * 0.5)
	_add(g, body)
	var size := Vector3(a.distance_to(b) + 0.1, h, 0.5)
	_part(body, "Bar", size, Vector3.ZERO, mats.rail)
	if blocker:
		var wall := StaticBody3D.new()
		wall.name = "EdgeBlock"
		wall.collision_layer = HeroBody.LAYER_EDGE_BLOCK
		wall.collision_mask = 0
		wall.position = Vector3(0, (RAIL_BLOCK_H - RAIL_H) * 0.5 + RAIL_H * 0.5, 0)
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var sh := BoxShape3D.new()
		sh.size = Vector3(size.x, RAIL_BLOCK_H - RAIL_H, 0.5)
		cs.shape = sh
		wall.add_child(cs)
		body.add_child(wall)
		_own(wall)


func _disc_rails(j: Dictionary) -> void:
	var s: Dictionary = j.s
	var r: float = s.r
	var n := maxi(24, int(TAU * r / 2.0))
	var wall: float = j.get("wall", 0.0)
	for i in n:
		var a := TAU * (i + 0.5) / n
		var dir := Vector2(sin(a), cos(a))
		var c: Vector2 = s.c
		var tang := Vector2(dir.y, -dir.x)
		var probe := c + dir * (r + 0.6)
		var kind := mini(mini(_probe(probe, s.top), _probe(probe + tang * 0.6, s.top)), _probe(probe - tang * 0.6, s.top))
		if kind == Edge.SAME or kind == Edge.WALL:
			continue
		var pos := c + dir * (r - 0.25)
		var seg := TAU * r / n + 0.15
		var h := wall if wall > 0.0 else (RAIL_H if kind == Edge.VOID else KERB_H)
		_rail_n += 1
		var body := _box(j.g, "%sRim%d" % [j.n, i], Vector3(0.5, h, seg), P(pos.x, pos.y, s.top + h * 0.5),
			mats.wall_under if wall > 0.0 else mats.rail, true, Vector3(0, 90.0 - rad_to_deg(a), 0))
		if wall <= 0.0 and kind == Edge.VOID:
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
				var kind := _probe(p2, lerpf(a.z, b.z, t / len3))
				void_here = kind == Edge.VOID or kind == Edge.DROP
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
		_lane_floor(g, lk, lx, hw, half, l0, l1, fl)
		for r in 2:
			var row: Array = rows[r]
			var l := _hl(half, row[3])
			var ph: float = row[5]
			_floor_rect(g, "Pad%d" % r, lx - ph, lx + ph, l - ph, l + ph, fl)
	if lk != "c":
		var mrow: Array = rows[2]
		var ph: float = mrow[5]
		_floor_rect(_node(geo, "Lane_%s_Mid" % lk.to_upper()), "Pad", lx - ph, lx + ph, MID_L - ph, MID_L + ph, mats.floor_mid)


func _lane_group(li: int, half: int) -> Node3D:
	var lk: String = LANES[li][1]
	return geo.get_node("Lane_%s_%s" % [lk.to_upper(), _key(half).to_upper()]) as Node3D


## W18-GEO: one lane half's floor from half-A L l0..l1: flat runs as slabs,
## ROLL segments as rolling trimesh; the Center market run is left to _market().
func _lane_floor(g: Node3D, lk: String, lx: float, hw: float, half: int, l0: float, l1: float, fl: Material) -> void:
	var cuts := []  # [a, b, kind]
	for seg in ROLL.get(lk, []):
		cuts.append([seg[0], seg[1], "roll"])
	if lk == "c":
		cuts.append([MARKET_L0, MARKET_L1, "market"])
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var cur := l0
	var i := 0
	for c in cuts:
		var a: float = maxf(c[0], l0)
		var b: float = minf(c[1], l1)
		if b <= a:
			continue
		if a > cur + 0.01:
			_floor_rect(g, "Floor%d" % i, lx - hw, lx + hw, _hl(half, cur), _hl(half, a), fl)
			i += 1
		if c[2] == "roll":
			_terrain(g, "Rolling%d" % i, lx - hw, lx + hw, _hl(half, a), _hl(half, b), lk, fl)
			i += 1
		cur = b
	if l1 > cur + 0.01:
		_floor_rect(g, "Floor%d" % i, lx - hw, lx + hw, _hl(half, cur), _hl(half, l1), fl)


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
		if lk == "c" and l > MARKET_L0 and l < MARKET_L1:
			continue  # W18-GEO: the sunken market street has its own stalls
		var tall: bool = c[5]
		var gy := _ground(lx + c[0], _hl(half, l), 10.0)
		_box(g, "Cover%d" % i, Vector3(c[2], c[3], c[4]), P(lx + c[0], _hl(half, l), gy + c[3] * 0.5), mats.cover_tall if tall else mats.cover_low)
	if lk == "n":
		for l in [116.0, 174.0]:
			for s in [-1.0, 1.0]:
				_box(g, "BridgePylon%d_%d" % [int(l), int(s)], Vector3(1.6, 7.0, 1.6), P(lx + s * (hw - 1.2), _hl(half, l), lane_h(lk, l) + 3.5), mats.cover_tall)
			_box(g, "BridgeArch%d" % int(l), Vector3(2 * hw - 0.8, 0.8, 1.2), P(lx, _hl(half, l), lane_h(lk, l) + 7.4), mats["team_" + _key(half)], false)
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


# ---------------------------------------------------------------- W18-GEO living map
# Owner decisions 2026-10-05 (verticality, buildings, lane identities, jungle).
# Every feature below is authored in half-A coordinates (lateral x or the
# between-lane offset u, lane distance l <= 210) and placed through _hl(), so
# half B is its exact mirror across L = 210.

## Lateral x of a between-lane offset u on side s (-1 = North gap, +1 = South gap).
static func X(s: float, u: float) -> float:
	return s * u


## Floor slab in half-A coords (l mirrored per half). `jg` = jungle nav group.
func _hrect(g: Node, n: String, half: int, x0: float, x1: float, l0: float, l1: float, top: float, mat: Material, rails := true) -> void:
	_floor_rect(g, n, x0, x1, _hl(half, l0), _hl(half, l1), mat, top, rails)


func _hsolid(g: Node, n: String, half: int, x0: float, x1: float, l0: float, l1: float, top: float, base: float, mat: Material, walk := false) -> Node3D:
	return _solid(g, n, x0, x1, _hl(half, l0), _hl(half, l1), top, base, mat, walk)


## Wedge in half-A coords: y_a at the (x0 | l0) end, y_b at the (x1 | l1) end.
## axis 0 = along x, 1 = along l. Mirroring flips the l end heights.
func _hwedge(g: Node, n: String, half: int, x0: float, x1: float, l0: float, l1: float, axis: int, y_a: float, y_b: float, mat: Material, stairs := false) -> void:
	var xa := minf(x0, x1)
	var xb := maxf(x0, x1)
	var ya := y_a
	var yb := y_b
	if axis == 0 and x1 < x0:
		ya = y_b
		yb = y_a
	var la := _hl(half, l0)
	var lb := _hl(half, l1)
	if axis == 1 and lb < la:
		var t := ya
		ya = yb
		yb = t
	_wedge(g, n, xa, xb, minf(la, lb), maxf(la, lb), axis, ya, yb, mat, stairs)


## Marker (Buildings/ jungle / anchors) at half-A (x, l, y).
func _marker(parent: Node, n: String, half: int, x: float, l: float, y: float, meta := {}) -> Marker3D:
	var m := Marker3D.new()
	m.name = n
	m.position = P(x, _hl(half, l), y)
	for k in meta:
		m.set_meta(k, meta[k])
	_add(parent, m)
	return m


## Mount transform on a building face: centre (x, l, y) in half-A coords and
## the outward normal in (x, l) (mirrored per half). +Z = outward.
func _mount(half: int, x: float, l: float, y: float, nx: float, nl: float) -> Transform3D:
	var n := Vector3(nx, 0.0, -nl if half == 0 else nl).normalized()
	var right := Vector3.UP.cross(n).normalized()
	return Transform3D(Basis(right, Vector3.UP, n), P(x, _hl(half, l), y))


func _add_mount(kind: String, id: String, xf: Transform3D, size: Vector2) -> void:
	match kind:
		"billboard":
			ambient.billboard_ids.append(id)
			ambient.billboard_xforms.append(xf)
			ambient.billboard_sizes.append(size)
		"neon":
			ambient.neon_ids.append(id)
			ambient.neon_xforms.append(xf)
			ambient.neon_sizes.append(size)
		"shop":
			ambient.shop_sign_ids.append(id)
			ambient.shop_sign_xforms.append(xf)
			ambient.shop_sign_sizes.append(size)
		"vent":
			ambient.steam_vent_ids.append(id)
			ambient.steam_vent_xforms.append(xf)
	# W18-LIFE contract (docs/architecture/ambient-world.md in that chunk):
	# Node3D children of the map's AmbientAnchors node, name prefix + group.
	var pre: String = {"billboard": "Billboard", "neon": "Neon", "shop": "ShopSign", "vent": "SteamVent"}[kind]
	var an := Node3D.new()
	an.name = "%s_%s" % [pre, id]
	an.transform = xf
	if kind != "vent":
		an.set_meta("size", size)
	an.add_to_group(StringName("ambient_" + {"billboard": "billboard", "neon": "neon", "shop": "shop_sign", "vent": "steam_vent"}[kind]), true)
	_add(amb_root, an)
	# A dim placeholder plate so the mount reads in the evidence renders.
	var plate := MeshInstance3D.new()
	plate.name = "Mount_" + id
	var qm := QuadMesh.new()
	qm.size = size if kind != "vent" else Vector2(0.8, 0.8)
	qm.material = mats["mount_" + kind]
	plate.mesh = qm
	plate.transform = xf.translated_local(Vector3(0, 0, 0.06))
	if kind == "vent":
		plate.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), xf.origin + Vector3(0, 0.03, 0))
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(dressing, plate)


## Enterable building (owner: 1-2 rooms, >= 1 window, a back door, doorways
## >= 2 m, tall ceiling). Half-A box x0..x1 / l0..l1, floor at `fy`. Openings
## per wall key ("x0", "x1", "l0", "l1"): [[from, to, y0, y1, kind], ...] with
## from/to along the wall (x for l-walls, l for x-walls) and kind "door" |
## "window". `part` = [axis "x"|"l", at, gap_from, gap_to] interior partition.
## Rooms: [[x, l], ...] interior marker points. Writes Buildings/<id>/ markers.
func _house(half: int, id: String, x0: float, x1: float, l0: float, l1: float, fy: float, ops: Dictionary, part: Array, rooms: Array, wall_mat: Material, trim: Color) -> void:
	var g := _node(geo, "House_%s_%s" % [id, _key(half).to_upper()])
	var h := 4.6
	var t := 0.4
	_hrect(g, "Floor", half, x0, x1, l0, l1, fy, mats.floor_house, false)
	var walls := {
		"x0": [x0, x0 + t, l0, l1, "l"], "x1": [x1 - t, x1, l0, l1, "l"],
		"l0": [x0, x1, l0, l0 + t, "x"], "l1": [x0, x1, l1 - t, l1, "x"],
	}
	var meta_root := _node(buildings, "%s_%s" % [id, _key(half).to_upper()])
	var di := 0
	var wi := 0
	for key in walls:
		var w: Array = walls[key]
		var along_x: bool = w[4] == "x"
		var a0: float = w[0] if along_x else w[2]
		var a1: float = w[1] if along_x else w[3]
		var wops: Array = ops.get(key, [])
		for i in Kit.wall_pieces(a0, a1, h, wops).size():
			var pc: Array = Kit.wall_pieces(a0, a1, h, wops)[i]
			if along_x:
				_hsolid(g, "Wall_%s_%d" % [key, i], half, pc[0], pc[1], w[2], w[3], fy + pc[3], fy + pc[2], wall_mat)
			else:
				_hsolid(g, "Wall_%s_%d" % [key, i], half, w[0], w[1], pc[0], pc[1], fy + pc[3], fy + pc[2], wall_mat)
		for o in wops:
			var mid: float = (o[0] + o[1]) * 0.5
			var cx: float = mid if along_x else (w[0] + w[1]) * 0.5
			var cl: float = (w[2] + w[3]) * 0.5 if along_x else mid
			var is_door: bool = o[4] == "door"
			var nm := ("Door%d" % di) if is_door else ("Window%d" % wi)
			if is_door:
				di += 1
			else:
				wi += 1
			_marker(meta_root, nm, half, cx, cl, fy + (0.0 if is_door else o[2]),
				{width = o[1] - o[0], height = o[3] - o[2], wall = key, axis = w[4], floor_y = fy})
			# Lit frame over each opening.
			var fw: float = o[1] - o[0]
			var trim_mat := _mat(trim, 0.0, 1.0, true)
			if along_x:
				_box(g, nm + "Lintel", Vector3(fw + 0.3, 0.15, t + 0.1), P(cx, _hl(half, cl), fy + o[3] + 0.08), trim_mat, false)
			else:
				_box(g, nm + "Lintel", Vector3(t + 0.1, 0.15, fw + 0.3), P(cx, _hl(half, cl), fy + o[3] + 0.08), trim_mat, false)
	if not part.is_empty():
		var pops := [[part[2], part[3], 0.0, 2.8, "door"]]
		var ia0: float = x0 + t if part[0] == "x" else l0 + t
		var ia1: float = x1 - t if part[0] == "x" else l1 - t
		for i in Kit.wall_pieces(ia0, ia1, h, pops).size():
			var pc: Array = Kit.wall_pieces(ia0, ia1, h, pops)[i]
			if part[0] == "x":
				_hsolid(g, "Partition%d" % i, half, pc[0], pc[1], part[1] - 0.15, part[1] + 0.15, fy + pc[3], fy + pc[2], wall_mat)
			else:
				_hsolid(g, "Partition%d" % i, half, part[1] - 0.15, part[1] + 0.15, pc[0], pc[1], fy + pc[3], fy + pc[2], wall_mat)
		var pm: float = (part[2] + part[3]) * 0.5
		_marker(meta_root, "InnerDoor", half, pm if part[0] == "x" else part[1], part[1] if part[0] == "x" else pm, fy,
			{width = part[3] - part[2], height = 2.8, wall = "part", axis = part[0], floor_y = fy})
	# Roof: blocks shots, kept out of every nav group (no unreachable islands).
	var roof := _slab(dressing, "Roof_%s_%s" % [id, _key(half).to_upper()], x0 - 0.3, x1 + 0.3, _hl(half, l0 - 0.3), _hl(half, l1 + 0.3), fy + h, fy + h + 0.5, wall_mat)
	_part(roof, "RoofTrim", Vector3(absf(x1 - x0) + 0.8, 0.2, absf(l1 - l0) + 0.8), Vector3(0, 0.3, 0), _mat(trim, 0.0, 1.0, true), false)
	var ri := 0
	for r in rooms:
		_marker(meta_root, "Interior%d" % ri, half, r[0], r[1], fy)
		_accent_light(g, "RoomLight%d" % ri, trim, P(r[0], _hl(half, r[1]), fy + 3.6), 7.0, 0.8)
		ri += 1
	meta_root.set_meta("floor_y", fy)
	meta_root.set_meta("ceiling_y", fy + h)


## Exterior-only building: solid block from `base` to `top` with lit window
## bands on the face pointing along (nx, nl), a roof trim and a mount.
func _tower(g: Node, n: String, half: int, x0: float, x1: float, l0: float, l1: float, top: float, base: float, mat: Material, nx: float, nl: float, accent: Color, mount := "", walk := false) -> void:
	var body := _hsolid(g, n, half, x0, x1, l0, l1, top, base, mat, walk)
	var w := absf(x1 - x0) if nl != 0.0 else absf(l1 - l0)
	var face_x := (x1 if nx > 0.0 else x0) if nx != 0.0 else (x0 + x1) * 0.5
	var face_l := (l1 if nl > 0.0 else l0) if nl != 0.0 else (l0 + l1) * 0.5
	var win := _mat(accent.lerp(Color.WHITE, 0.35), 0.0, 1.0, true)
	var y := 5.5
	var bi := 0
	while y < top - 1.5:
		var c := P(face_x + nx * 0.05, _hl(half, face_l + nl * 0.05), y)
		var size := Vector3(0.1, 0.35, w * 0.8) if nx != 0.0 else Vector3(w * 0.8, 0.35, 0.1)
		_box(dressing, "%sWin%d" % [n, bi], size, c, win, false)
		bi += 1
		y += 3.2
	var cap := absf(top - base)
	# Lit crown: a thin trim band around the roof edge (outside walkable roofs).
	var tm: Material = mats["trim_" + ("a" if accent == AZURE else "n")]
	var cx := (x0 + x1) * 0.5
	var cl := (l0 + l1) * 0.5
	var wx := absf(x1 - x0)
	var wl := absf(l1 - l0)
	for e in [-1.0, 1.0]:
		_box(dressing, n + "CrownX%d" % int(e), Vector3(0.18, 0.35, wl + 0.36), P(cx + e * (wx * 0.5 + 0.09), _hl(half, cl), top - 0.175), tm, false)
		_box(dressing, n + "CrownL%d" % int(e), Vector3(wx + 0.36, 0.35, 0.18), P(cx, _hl(half, cl + e * (wl * 0.5 + 0.09)), top - 0.175), tm, false)
	var _u := [body, cap]
	if mount != "":
		var my := minf(top - 2.5, 9.0) if mount == "billboard" else minf(top - 1.5, 4.2)
		var size := Vector2(minf(w * 0.7, 9.0), 4.5) if mount == "billboard" else Vector2(minf(w * 0.6, 3.5), 1.2)
		_add_mount(mount, "%s_%s" % [n, _key(half)], _mount(half, face_x + nx * 0.02, face_l + nl * 0.02, my, nx, nl), size)


# ---- Center: the neon market (sunken street, terraces, shops) ----------------

func _market(half: int) -> void:
	var g := _node(geo, "Market_" + _key(half).to_upper())
	var fl: Material = mats["floor_" + _key(half)]
	var l0 := MARKET_L0
	var l1 := MARKET_L1
	# Sunken street (stairs down at both ends) between solid walkways.
	_hwedge(g, "StreetStairsIn", half, -STREET_HW, STREET_HW, l0, l0 + 6.0, 1, 0.0, STREET_Y, mats.stairs, true)
	_hrect(g, "Street", half, -STREET_HW, STREET_HW, l0 + 6.0, l1 - 6.0, STREET_Y, mats.floor_market)
	_hwedge(g, "StreetStairsOut", half, -STREET_HW, STREET_HW, l1 - 6.0, l1, 1, STREET_Y, 0.0, mats.stairs, true)
	for s in [-1.0, 1.0]:
		_hsolid(g, "Walkway%d" % int(s), half, s * STREET_HW, s * 8.0, l0, l1, 0.0, STREET_Y - 1.0, fl, true)
		# Terraces with shopfronts: stairs up at both ends.
		_hwedge(g, "TerraceStairsIn%d" % int(s), half, s * 8.0, s * 14.0, l0, l0 + 8.0, 1, 0.0, 2.5, mats.stairs, true)
		_hsolid(g, "Terrace%d" % int(s), half, s * 8.0, s * 14.0, l0 + 8.0, l1 - 8.0, 2.5, STREET_Y - 1.0, mats.deck, true)
		_hwedge(g, "TerraceStairsOut%d" % int(s), half, s * 8.0, s * 14.0, l1 - 8.0, l1, 1, 2.5, 0.0, mats.stairs, true)
		# Street stalls (cover in the street) with neon awnings.
		for sl in [112.0, 120.0]:
			_box(g, "StreetStall%d_%d" % [int(s), int(sl)], Vector3(2.2, 1.2, 3.0), P(s * 2.6, _hl(half, sl), STREET_Y + 0.6), mats.cover_low)
			_box(g, "StreetAwning%d_%d" % [int(s), int(sl)], Vector3(3.0, 0.12, 3.6), P(s * 2.6, _hl(half, sl), STREET_Y + 2.7), mats.neon_pink, false)
		_add_mount("neon", "market_street_%d_%s" % [int(s), _key(half)], _mount(half, s * STREET_HW, 116.0, STREET_Y + 2.2, -s, 0.0), Vector2(3.0, 0.9))
		# Market shop (enterable): front door + window onto the terrace, back
		# door onto the jungle alley (ShopAlley -> V2).
		var front := "x0" if s > 0.0 else "x1"
		var x0 := minf(s * 14.0, s * 23.0)
		var x1 := maxf(s * 14.0, s * 23.0)
		_hsolid(g, "ShopPlinth%d" % int(s), half, x0, x1, 109.0, 121.0, 1.5, -14.0, mats.wall_jungle)
		_house(half, "Shop%s" % ("N" if s < 0.0 else "S"), x0, x1, 109.0, 121.0, 2.5, {
			front: [[112.0, 114.6, 0.0, 2.8, "door"], [116.0, 120.0, 1.0, 2.2, "window"]],
			"l1": [[minf(s * 19.0, s * 21.6), maxf(s * 19.0, s * 21.6), 0.0, 2.8, "door"]],
		}, ["l", s * 18.5, 116.0, 118.4], [[s * 16.2, 115.0], [s * 20.7, 113.0]], mats.wall_jungle, Color("#FF3FA4"))
		# Planter cover on each terrace (breaks the terrace-to-terrace line).
		_box(g, "TerracePlanter%d" % int(s), Vector3(2.0, 1.1, 2.0), P(s * 11.0, _hl(half, 116.0), 2.5 + 0.55), mats.cover_low)
	# Shop sign slots (W18-LIFE ShopSign*): over each shopfront, facing the lane.
	for s in [-1.0, 1.0]:
		for sl in [[104.0, 6.2, 6.0], [115.25, 6.3, 7.0], [129.0, 5.0, 6.0]]:
			_add_mount("shop", "market_%d_%d_%s" % [int(s), int(sl[0]), _key(half)], _mount(half, s * 13.98, sl[0], sl[1], -s, 0.0), Vector2(sl[2], 1.4))
	_accent_light(g, "StreetGlow", Color("#FF3FA4"), P(0, _hl(half, 116.0), STREET_Y + 4.0), 18.0, 1.6)
	ov_labels.append(["SUNKEN\nSTREET", P(0, _hl(half, 116.0)), Color("#FF8AD0")])


# ---- North: the high bridge (service walkway, towers, guardhouse) ------------

func _bridge_walkway(half: int) -> void:
	var g := _node(geo, "ServiceWalk_" + _key(half).to_upper())
	var y := -4.5
	# Landings follow the span's rolling profile so they meet the lane flush.
	_terrain(g, "Landing0", -100.0, -90.0, _hl(half, 160.0), _hl(half, 164.0), "n", mats.deck)
	_hwedge(g, "StairsDown", half, -96.0, -90.0, 164.0, 172.0, 1, lane_h("n", 164.0), y, mats.stairs, true)
	_hrect(g, "Walk", half, -96.0, -90.0, 172.0, 184.0, y, mats.deck)
	_hrect(g, "UnderBay", half, -90.0, -81.0, 174.0, 182.0, y, mats.deck)
	_hwedge(g, "StairsUp", half, -96.0, -90.0, 184.0, 192.0, 1, y, lane_h("n", 192.0), mats.stairs, true)
	_terrain(g, "Landing1", -96.0, -90.0, _hl(half, 192.0), _hl(half, 196.0), "n", mats.deck)
	_box(g, "BayCrate", Vector3(2.0, 1.2, 2.0), P(-84.0, _hl(half, 178.0), y + 0.6), mats.cover_low)
	_box(g, "WalkCrate", Vector3(1.6, 1.1, 1.6), P(-94.5, _hl(half, 178.5), y + 0.55), mats.cover_low)
	_accent_light(g, "BayLight", TEAL, P(-86.0, _hl(half, 178.0), y + 3.2), 12.0, 1.2)
	# Girders under the span (dressing).
	for l in [168.0, 188.0]:
		_box(dressing, "SpanGirder%d_%s" % [int(l), _key(half)], Vector3(22.0, 1.2, 0.8), P(-80.0, _hl(half, l), lane_h("n", l) - 1.8), mats.rail, false)
	ov_labels.append(["SERVICE\nWALK", P(-102.0, _hl(half, 178.0)), Color("#9BE8DF")])


func _bridge_towers(half: int) -> void:
	var g := _node(geo, "BridgeTowers_" + _key(half).to_upper())
	for l in [161.0, 189.0]:
		var n := "GuardTower%d" % int(l)
		_tower(g, n, half, -69.5, -64.5, l, l + 5.0, 10.0, -18.0, mats.wall_n, 1.0, 0.0, TEAL, "neon")
		_box(dressing, n + "Cabin_%s" % _key(half), Vector3(6.4, 2.6, 6.4), P(-67.0, _hl(half, l + 2.5), 11.3), mats.cover_tall, false)
		_box(dressing, n + "Lamp_%s" % _key(half), Vector3(6.6, 0.4, 6.6), P(-67.0, _hl(half, l + 2.5), 12.8), mats.glow_n, false)
		_accent_light(g, n + "Light", TEAL, P(-67.0, _hl(half, l + 2.5), 13.5), 20.0, 1.2)
	# Wind banners on the span (static; W18-LIFE may animate).
	for l in [170.0, 186.0]:
		for s in [-1.0, 1.0]:
			_box(dressing, "Banner%d_%d_%s" % [int(l), int(s), _key(half)], Vector3(0.1, 3.0, 1.4), P(-80.0 + s * 9.6, _hl(half, l), lane_h("n", l) + 6.0), mats["team_" + _key(half)], false)


func _guardhouse(half: int) -> void:
	# Bridge guardhouse by N-AO (replaces that pad's overlook deck). Front door
	# and a window onto the HOLD zone; back door to the porch and the walkway.
	_house(half, "Guardhouse", -103.0, -95.0, 133.0, 151.0, 0.0, {
		"x1": [[135.0, 137.6, 0.0, 2.8, "door"], [144.0, 148.0, 1.0, 2.2, "window"]],
		"x0": [[138.0, 141.0, 1.0, 2.2, "window"]],
		"l1": [[-101.6, -99.0, 0.0, 2.8, "door"]],
	}, ["l", 142.0, -100.4, -97.8], [[-99.0, 137.5], [-99.0, 146.5]], mats.wall_n, TEAL)
	var g := _node(geo, "GuardPorch_" + _key(half).to_upper())
	_hrect(g, "Porch", half, -103.0, -95.0, 151.0, 160.0, 0.0, mats.deck)
	_box(g, "PorchCrate", Vector3(1.6, 1.1, 1.6), P(-97.0, _hl(half, 155.0), 0.55), mats.cover_low)


# ---- South: the docks (warehouse, loading ramp, raised quay, cranes) ---------

func _docks(half: int) -> void:
	_house(half, "Warehouse", 88.0, 100.0, 101.0, 117.0, 0.0, {
		"x0": [[104.0, 106.6, 0.0, 3.2, "door"], [110.0, 114.0, 1.0, 2.2, "window"]],
		"l0": [[95.0, 98.0, 1.0, 2.2, "window"]],
		"l1": [[92.0, 94.6, 0.0, 3.2, "door"]],
	}, ["x", 94.0, 108.0, 110.6], [[91.0, 109.0], [97.0, 109.0]], mats.wall_s, Color("#FFB347"))
	var g := _node(geo, "Docks_" + _key(half).to_upper())
	_hrect(g, "Apron", half, 88.0, 103.0, 117.0, 121.0, 0.0, mats.floor_dock)
	_hwedge(g, "LoadingRamp", half, 96.0, 103.0, 121.0, 129.0, 1, 0.0, 2.5, mats.deck)
	_hsolid(g, "Quay", half, 95.0, 103.0, 129.0, 158.0, 2.5, -6.0, mats.floor_dock, true)
	_hwedge(g, "QuayStairs", half, 89.0, 95.0, 154.0, 159.0, 0, 0.0, 2.5, mats.stairs, true)
	# Stacked cargo on the quay (cover for and against the holder).
	_box(g, "QuayCargo0", Vector3(2.5, 2.6, 6.0), P(100.5, _hl(half, 141.0), 2.5 + 1.3), mats.cargo_a)
	_box(g, "QuayCargo1", Vector3(2.5, 2.6, 6.0), P(100.5, _hl(half, 141.0), 2.5 + 3.9), mats.cargo_b)
	_box(g, "QuayCrate", Vector3(1.5, 1.1, 1.5), P(97.0, _hl(half, 133.0), 2.5 + 0.55), mats.cover_low)
	# Cargo stacks along the rolling run toward the Mid.
	for c in [[74.5, 168.0, 2], [85.5, 175.0, 1], [74.5, 184.0, 1], [85.5, 190.0, 2]]:
		var y := lane_h("s", c[1])
		for k in c[2]:
			_box(g, "LaneCargo%d_%d" % [int(c[1]), k], Vector3(2.5, 2.6, 6.0), P(c[0], _hl(half, c[1]), y + 1.3 + 2.6 * k), mats.cargo_a if k == 0 else mats.cargo_b)
	# Static cranes on the seaward side; "Boom" is the pivot for W18-LIFE.
	for l in [134.0, 153.0]:
		var cn := "Crane%d_%s" % [int(l), _key(half).to_upper()]
		var crane := _node(dressing, cn)
		crane.position = P(107.0, _hl(half, l), 0.0)
		for e in [-1.0, 1.0]:
			_box(crane, "Leg%d" % int(e), Vector3(1.0, 30.0, 1.0), Vector3(0, 0.0, e * 2.5), mats.crane, false)
		_box(crane, "Cab", Vector3(3.0, 2.5, 6.0), Vector3(0, 15.0, 0), mats.crane, false)
		var boom := Node3D.new()
		boom.name = "Boom"
		boom.position = Vector3(0, 16.5, 0)
		_add(crane, boom)
		_box(boom, "Arm", Vector3(26.0, 1.0, 1.2), Vector3(-9.0, 0.0, 0), mats.crane, false)
		_box(boom, "Hook", Vector3(0.3, 6.0, 0.3), Vector3(-18.0, -3.5, 0), mats.rail, false)
		ambient.crane_booms.append("Dressing/%s/Boom" % cn)
	var wl := _hl(half, 145.0)
	_accent_light(g, "QuayLight", Color("#FFB347"), P(99.0, wl, 7.0), 18.0, 1.0)
	ov_labels.append(["QUAY", P(108.0, _hl(half, 145.0)), Color("#FFD08A")])


# ---- Mid Plaza: the bridge over the North spoke ------------------------------

func _plaza_bridge() -> void:
	var g := _node(geo, "PlazaBridge")
	var y := 4.5
	# Deck over the spoke mouth (spoke L 205..215 passes beneath, 4 m clear);
	# ramps down into the plaza clear of the Undercroft doors (L 191.6 / 228.4).
	_solid(g, "Deck", -33.0, -28.0, 200.5, 219.5, y, y - 0.5, mats.deck, true)
	for half in 2:
		_hwedge(g, "Ramp" + _key(half).to_upper(), half, -28.0, -13.0, 200.5, 205.0, 0, y, 0.02, mats.deck)
		_box(g, "Pier" + _key(half).to_upper(), Vector3(2.0, 30.0, 2.0), P(-30.5, _hl(half, 202.0), y - 15.5), mats.cover_tall)
	_box(g, "SignArch", Vector3(0.6, 1.0, 19.0), P(-33.3, 210.0, y + 2.6), mats.neon_violet, false)
	_add_mount("billboard", "plaza_bridge", _mount(0, -27.9, 210.0, y - 1.7, 1.0, 0.0), Vector2(8.0, 2.4))
	ov_labels.append(["PLAZA\nBRIDGE", P(-38.0, 210.0), Color("#C9B5FF")])


# ---- City rows: exterior buildings framing the outer lanes -------------------

func _city_rows(half: int) -> void:
	var g := _node(dressing, "City_" + _key(half).to_upper())
	g.remove_from_group(&"nav_source")
	var rows := [[-1.0, -132.0, -106.0, 72.0, 207.0, AZURE], [1.0, 112.0, 132.0, 72.0, 207.0, Color("#FFB347")]]
	for r in rows:
		var l: float = r[3]
		var i := 0
		while l < r[4] - 6.0:
			var w: float = 8.0 + float((i * 7 + 3) % 6)
			var l_end := minf(l + w, r[4])
			var top: float = 10.0 + float((i * 11 + 5) % 19)
			var depth_in: float = float((i * 5) % 4)
			var face_s: float = -r[0]  # faces the lane
			var x0: float = r[1] + (depth_in if r[0] < 0.0 else 0.0)
			var x1: float = r[2] - (0.0 if r[0] < 0.0 else depth_in)
			var mount := "billboard" if i % 3 == 0 else "neon"
			_tower(g, "Row%d_%d" % [int(r[0]), i], half, x0, x1, l, l_end, top, -30.0, mats.wall_city, face_s, 0.0, r[5], mount)
			l = l_end + 2.0
			i += 1


# ---- Jungle: the between-lane network ----------------------------------------
# One quadrant per (half, side). u = |x| offset from the Center lane axis;
# outer lane inner edge at u = lane_edge, its Inner pad edge at u = pad_edge.

func _jungle(half: int, s: float) -> void:
	var lk := "n" if s < 0.0 else "s"
	var q := "%s%s" % [_key(half).to_upper(), lk.to_upper()]
	var g := _node(jungle, "Jungle_" + q)
	var lane_edge: float = 80.0 - LANES[0 if s < 0.0 else 2][3]
	var pad_edge: float = 80.0 - HP[lk][0][5]
	var fl: Material = mats.floor_jungle
	var blk: Material = mats.wall_jungle
	var R := func(n: String, u0: float, u1: float, l0: float, l1: float, top := 0.0) -> void:
		_hrect(g, n, half, X(s, u0), X(s, u1), l0, l1, top, fl)
	var B := func(n: String, u0: float, u1: float, l0: float, l1: float, top: float, walk := false) -> void:
		var accent: Color = Color("#FF3FA4") if (int(u0) + int(l0)) % 2 == 0 else TEAL
		_tower(g, n, half, X(s, u0), X(s, u1), l0, l1, top, -14.0, blk, 0.0, 0.0, accent, "", walk)
	# Low route: alleys and pockets at y = 0.
	R.call("A1", 15.0, 38.0, 74.0, 79.0)                       # from the C-AI pad
	R.call("A4", 42.0, pad_edge, 72.0, 77.0)                   # from the outer Inner pad
	R.call("C1", 42.0, 47.0, 77.0, 79.0)
	R.call("P1", 33.0, 47.0, 79.0, 93.0)                       # pocket: Courtyard
	R.call("V1", 42.0, 47.0, 93.0, 112.0)
	R.call("F1", 33.0, 42.0, 109.0, 112.0)
	R.call("A5", 30.0, 58.0, 112.0, 117.0)                     # to the outer lane mid-run
	var ly := lane_h(lk, 114.5)
	_hwedge(g, "A5Ramp", half, X(s, 58.0), X(s, lane_edge), 112.0, 117.0, 0, 0.0, ly, fl)
	R.call("V2", 30.0, 35.0, 117.0, 133.0)
	R.call("A3", 14.0, 35.0, 133.0, 138.0)                     # from the C-AO pad
	R.call("C2", 47.0, 52.0, 117.0, 122.0)
	R.call("P2", 42.0, 56.0, 122.0, 136.0)                     # pocket: Night Plaza
	R.call("V3", 40.0, 44.0, 136.0, 160.0)                     # catwalk to the Undercroft
	_hwedge(g, "UnderStairs", half, X(s, 40.0), X(s, 44.0), 160.0, 172.0, 1, 0.0, UNDER_Y, mats.stairs, true)
	# Market back alley: shop back door -> ramp down into V2.
	_hrect(g, "ShopAlley", half, X(s, 14.0), X(s, 23.0), 121.0, 125.0, 2.5, fl)
	_hwedge(g, "ShopAlleyRamp", half, X(s, 23.0), X(s, 30.0), 121.0, 125.0, 0, 2.5, 0.0, fl)
	# City blocks framing the alleys (some roofs are the high route).
	B.call("B1", 15.0, 33.0, 79.0, 100.0, 4.5, true)
	B.call("B2", 14.0, 30.0, 100.0, 108.5, 7.5)
	B.call("B3", 23.0, 30.0, 108.5, 121.0, 7.5)
	B.call("B4", 47.0, pad_edge, 79.0, 102.0, 4.5, true)
	B.call("B6", 38.0, 42.0, 93.0, 109.0, 3.0)
	B.call("B7", 38.0, 42.0, 72.0, 79.0, 6.0)
	B.call("B8", 57.0, lane_edge, 102.0, 112.0, 8.0)
	B.call("B9", 47.0, 52.0, 102.0, 112.0, 3.0)
	B.call("B10", 35.0, 42.0, 117.0, 133.0, 4.5, true)
	B.call("B11", 52.0, lane_edge, 117.0, 122.0, 6.5)
	B.call("B12", 56.0, 65.0, 122.0, 140.0, 4.5, true)
	B.call("B13", 14.0, 30.0, 125.0, 133.0, 6.0)
	# High route: stairs up from the alleys, footbridges over the pockets.
	B.call("S1Top", 33.0, 38.0, 93.0, 97.0, 4.5, true)
	_hwedge(g, "S1", half, X(s, 33.0), X(s, 38.0), 97.0, 109.0, 1, 4.5, 0.0, mats.stairs, true)
	_hrect(g, "Bridge1", half, X(s, 33.0), X(s, 47.0), 85.0, 88.0, 4.5, mats.deck)
	_hwedge(g, "S2", half, X(s, 52.0), X(s, 57.0), 102.0, 112.0, 1, 4.5, 0.0, mats.stairs, true)
	_hwedge(g, "S3", half, X(s, 52.0), X(s, 56.0), 125.5, 136.0, 1, 0.0, 4.5, mats.stairs, true)
	B.call("S3Top", 52.0, 56.0, 136.0, 140.0, 4.5, true)
	_hrect(g, "Bridge2", half, X(s, 42.0), X(s, 56.0), 122.0, 125.0, 4.5, mats.deck)
	# Cover and ambush pockets.
	for c in [[36.0, 84.0, 1.8, 1.2], [44.0, 89.0, 1.4, 1.6], [26.0, 114.5, 0.0, 0.0], [46.0, 128.0, 1.8, 1.2],
			[53.0, 132.5, 1.4, 1.6], [20.0, 135.5, 1.6, 1.1], [42.0, 98.0, 1.4, 1.2], [36.0, 76.5, 1.4, 1.1]]:
		if c[2] <= 0.0:
			continue
		_box(g, "Crate%d_%d" % [int(c[0]), int(c[1])], Vector3(c[2], c[3], c[2]), P(X(s, c[0]), _hl(half, c[1]), c[3] * 0.5), mats.cover_low)
	# Neon + steam vents for W18-LIFE (alley walls, pocket corners).
	var ni := 0
	for m in [[33.0, 76.5, 1.0, 0.0], [47.0, 86.0, -1.0, 0.0], [42.0, 102.0, 1.0, 0.0], [35.0, 125.0, -1.0, 0.0],
			[56.0, 129.0, -1.0, 0.0], [30.0, 135.5, 0.0, -1.0], [44.0, 150.0, 1.0, 0.0]]:
		var nx: float = m[2] * s
		_add_mount("neon", "jungle_%s_%d" % [q.to_lower(), ni], _mount(half, X(s, m[0]), m[1], 3.0, nx, m[3]), Vector2(2.4, 0.8))
		ni += 1
	var vi := 0
	for v in [[40.0, 91.0], [44.5, 104.0], [32.5, 130.0], [49.5, 119.5]]:
		_add_mount("vent", "jungle_%s_%d" % [q.to_lower(), vi], _mount(half, X(s, v[0]), v[1], 0.02, 0.0, 1.0), Vector2.ONE)
		vi += 1
	_accent_light(g, "P1Light", Color("#FF3FA4"), P(X(s, 40.0), _hl(half, 86.0), 3.5), 14.0, 1.3)
	_accent_light(g, "P2Light", TEAL, P(X(s, 49.0), _hl(half, 129.0), 3.5), 14.0, 1.3)
	_accent_light(g, "A5Light", Color("#B266FF"), P(X(s, 44.0), _hl(half, 114.5), 3.0), 12.0, 1.0)
	_accent_light(g, "V3Light", TEAL, P(X(s, 42.0), _hl(half, 150.0), 3.0), 12.0, 0.9)
	# Pockets (future neutral camps) and centrelines (minimap / overview / tests).
	for p in [["courtyard", 40.0, 86.0, 14.0, 14.0], ["night_plaza", 49.0, 129.0, 14.0, 14.0]]:
		var jp := JunglePocketDef.new()
		jp.id = StringName("%s_%s" % [p[0], q.to_lower()])
		jp.center = P(X(s, p[1]), _hl(half, p[2]), 0.0)
		jp.size = Vector2(p[3], p[4])
		jungle_pockets.append(jp)
		ov_labels.append([String(p[0]).to_upper().replace("_", " "), jp.center, Color("#FFC2EA")])
	var Y := func(u: float, l: float, y := 0.0) -> Vector3:
		return P(X(s, u), _hl(half, l), y)
	for path in [
		[Y.call(15.0, 76.5), Y.call(35.5, 76.5), Y.call(35.5, 86.0), Y.call(44.5, 86.0), Y.call(44.5, 74.5), Y.call(pad_edge, 74.5)],
		[Y.call(44.5, 86.0), Y.call(44.5, 114.5), Y.call(lane_edge, 114.5, ly)],
		[Y.call(28.0, 123.0, 1.0), Y.call(32.5, 123.0), Y.call(32.5, 135.5), Y.call(14.0, 135.5)],
		[Y.call(32.5, 114.5), Y.call(49.5, 114.5), Y.call(49.5, 129.0), Y.call(42.0, 136.0), Y.call(42.0, 160.0), Y.call(42.0, 172.0, UNDER_Y)],
		[Y.call(24.0, 89.0, 4.5), Y.call(40.0, 86.5, 4.5), Y.call(55.0, 89.0, 4.5), Y.call(54.5, 107.0, 2.0)],
		[Y.call(38.5, 125.0, 4.5), Y.call(49.0, 123.5, 4.5), Y.call(54.0, 131.0, 2.5), Y.call(60.0, 134.0, 4.5)],
	]:
		jungle_paths.append(PackedVector3Array(path))
	# Nav links: the jungle navmesh (layer 2) joins the lane navmesh at each mouth.
	var li := 0
	for lk_pair in [
		[Y.call(13.5, 76.5), Y.call(16.5, 76.5)],
		[Y.call(pad_edge + 1.5, 74.5), Y.call(pad_edge - 1.5, 74.5)],
		[Y.call(lane_edge + 1.5, 114.5, ly), Y.call(lane_edge - 1.5, 114.5, ly)],
		[Y.call(12.5, 135.5), Y.call(15.5, 135.5)],
		[Y.call(42.0, 174.0, UNDER_Y), Y.call(42.0, 169.0, UNDER_Y + 1.0)],
		[Y.call(12.5, 123.0, 2.5), Y.call(15.5, 123.0, 2.5)],
	]:
		var nl := NavigationLink3D.new()
		nl.name = "Link_%s_%d" % [q, li]
		nl.bidirectional = true
		nl.navigation_layers = MapDef.JUNGLE_NAV_LAYER
		nl.start_position = lk_pair[0]
		nl.end_position = lk_pair[1]
		_add(links, nl)
		li += 1


# ---- Sky routes for W18-LIFE ---------------------------------------------------

static func _loop(cx: float, cz: float, hx: float, hz: float, y: float, r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var corners := [Vector2(hx - r, hz - r), Vector2(-(hx - r), hz - r), Vector2(-(hx - r), -(hz - r)), Vector2(hx - r, -(hz - r))]
	for ci in 4:
		for k in 5:
			var a := PI * 0.5 * ci + PI * 0.5 * k / 4.0
			var c: Vector2 = corners[ci]
			out.append(Vector3(cx + c.x + cos(a) * r, y, cz + c.y + sin(a) * r))
	return out


## Sky routes, all outside the playable box (x -100..100 per W18-LIFE) and to
## the sides of it, so night traffic trails never cross a lane sightline down
## the map. Exported as Path3D under AmbientAnchors (TrafficPath*, DronePath*,
## SkyTrain) and mirrored into the AmbientAnchorsDef resource.
func _sky_routes() -> void:
	var cz := -MID_L
	var i := 0
	for side in [-1.0, 1.0]:
		for lane in [[168.0, 58.0], [196.0, 74.0]]:
			var loop := _loop(side * lane[0], cz, 12.0, 330.0, lane[1], 10.0)
			ambient.traffic_path_ids.append("side_%d_%d" % [int(side), i])
			ambient.traffic_paths.append(loop)
			_path3d("TrafficPath%d" % i, loop, &"ambient_traffic_path")
			i += 1
		# Drone weave over the outer city rows (x 112..132), 36 m up.
		_path3d("DronePath%d" % int(side > 0.0), _loop(side * 122.0, cz, 6.0, 120.0, 36.0, 5.0), &"ambient_drone_path")
	# Open sky-train track along the North side, 44 m up, past both HQ ends.
	var train := PackedVector3Array()
	for k in 12:
		var z := lerpf(140.0, -560.0, k / 11.0)
		train.append(Vector3(-146.0 + 6.0 * sin(k * 0.6), 44.0, z))
	ambient.sky_train_route = train
	_path3d("SkyTrain", train, &"ambient_skytrain")


func _path3d(n: String, pts: PackedVector3Array, group: StringName) -> void:
	var p := Path3D.new()
	p.name = n
	var c := Curve3D.new()
	for v in pts:
		c.add_point(v)
	p.curve = c
	p.add_to_group(group, true)
	_add(amb_root, p)


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
	# Each Cradle sits CRADLE_DL toward its own team's HQ: a Mid between two Plant
	# nodes hosts one Cradle of each team, which must not share the spot (mirror
	# symmetric, so neither team's Cradle is closer to the fight).
	var c: Vector3 = P(hps[i - 1].x + CRADLE_X, hps[i - 1].l - CRADLE_DL) if i - 1 >= 0 else _gate(li, 0) + P(CRADLE_X, 8.0)
	var sy: Vector3 = P(hps[i + 1].x + CRADLE_X, hps[i + 1].l + CRADLE_DL) if i + 1 < 5 else _gate(li, 1) + P(CRADLE_X, -8.0)
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
			# W18-GEO: a chest-high plinth so no single raised spot sees the whole ring.
			_cyl(vis, "Plinth", 2.8, 2.4, 1.8, Vector3(0, 0.3, 0), mats.cover_tall, true, 24)
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
		var gy := _ground(x, sl, 10.0)
		gy = 0.0 if is_nan(gy) else gy
		s.position.y = gy
		_box(geo, "SocketMark_%s_%d" % [String(id).to_upper(), side], Vector3(2 * lane_hw, 0.03, 0.6), P(x, sl, gy + 0.015), mats.socket, false)


## Lateral side of a hardpoint's pad that has no flank door / spoke: outer lanes
## use their void side; the Center Inner gets decks on both sides; Center Outer
## (two doors) and the Spindle (plaza) get none.
func _deck_sides(li: int, h: Dictionary) -> Array:
	var lk: String = LANES[li][1]
	if lk == "c":
		return [-1.0, 1.0] if h.tier == HardpointDef.Tier.INNER else []
	if h.tier == HardpointDef.Tier.OUTER:
		return []  # W18-GEO: the guardhouse (North) / raised quay (South) take this side
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
		if h.tier == HardpointDef.Tier.MID:
			# W18-GEO: the neutral Mid deck is symmetric across L = 210 (ramps both ways).
			l_back = h.l - 3.0
			l_front = h.l + 3.0
			_solid(g, "Block", x0, x1, l_back, l_front, DECK_H, -1.0, mats.deck, true)
			_wedge(g, "RampA", minf(x0, x1), maxf(x0, x1), h.l - ph + 1.2, l_back, 1, 0.0, DECK_H, mats.deck)
			_wedge(g, "RampB", minf(x0, x1), maxf(x0, x1), l_front, h.l + ph - 1.2, 1, DECK_H, 0.0, mats.deck)
			var parm := _slab(g, "Parapet", x1 - s * 0.4, x1, l_back - 0.0, l_front, DECK_H, DECK_H + RAIL_H, mats.rail)
			_edge_blocker(parm, 0.4, absf(l_front - l_back), RAIL_H)
			continue
		_solid(g, "Block", x0, x1, l_back, l_front, DECK_H, -1.0, mats.deck, true)
		var lr: float = h.l + toward_mid * (ph - 1.2)
		var lf: float = l_front
		if lr < lf:
			_wedge(g, "Ramp", minf(x0, x1), maxf(x0, x1), lr, lf, 1, 0.0, DECK_H, mats.deck)
		else:
			_wedge(g, "Ramp", minf(x0, x1), maxf(x0, x1), lf, lr, 1, DECK_H, 0.0, mats.deck)
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
			"FoundryPad": P(-19, _hl(half, 17.0)), "ArmoryPad": P(ARMORY_X, _hl(half, ARMORY_L)),
			"LaneGate": _gate(1, half), "LaneGateNorth": _gate(0, half), "LaneGateSouth": _gate(2, half)}
		for n in pts:
			var m := Marker3D.new()
			m.name = "%s%s" % [t, n]
			m.position = pts[n]
			_add(hq, m)


# ---------------------------------------------------------------- navmesh

func _bake(group: StringName) -> NavigationMesh:
	var nm := _navmesh_settings(group)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, map_root)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	print("navmesh %s: %d verts, %d polys" % [group, nm.get_vertices().size(), nm.get_polygon_count()])
	return nm


func _navmesh_settings(group: StringName = &"nav_source") -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = group
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


## Height colour for the overview (W18-GEO): blue below the lanes, green at
## lane level, yellow at +2.5 m, red at +4.5 m and above.
static func _height_color(y: float) -> Color:
	if y < -0.4:
		return Color(0.25, 0.45, 1.0).lerp(Color(0.3, 0.95, 1.0), clampf((y + 4.5) / 4.0, 0.0, 1.0))
	if y < 0.4:
		return Color(0.25, 1.0, 0.45)
	if y < 2.6:
		return Color(0.25, 1.0, 0.45).lerp(Color(1.0, 0.9, 0.2), clampf(y / 2.6, 0.0, 1.0))
	return Color(1.0, 0.9, 0.2).lerp(Color(1.0, 0.25, 0.2), clampf((y - 2.6) / 2.0, 0.0, 1.0))


func _save_overview(navs: Array) -> void:
	var ov := Node3D.new()
	ov.name = "ShardlineFrontOverview"
	get_root().add_child(ov)
	var map: Node3D = (load(MAP_PATH) as PackedScene).instantiate()
	ov.add_child(map)
	map.owner = ov
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for nm: NavigationMesh in navs:
		var v := nm.get_vertices()
		for p in nm.get_polygon_count():
			var poly := nm.get_polygon(p)
			for t in range(1, poly.size() - 1):
				for idx in [poly[0], poly[t + 1], poly[t]]:
					st.set_color(_height_color(v[idx].y))
					st.add_vertex(v[idx] + Vector3(0, 0.12, 0))
	st.commit(am)
	var mi := MeshInstance3D.new()
	mi.name = "NavmeshOverlay"
	mi.mesh = am
	var om := _mat(Color.WHITE, 0.0, 0.55, true)
	om.vertex_color_use_as_albedo = true
	mi.material_override = om
	ov.add_child(mi)
	mi.owner = ov
	# Jungle centrelines drawn as thin magenta strips above everything.
	var jm := _mat(Color("#FF3FA4"), 0.0, 0.9, true)
	for path in jungle_paths:
		for i in path.size() - 1:
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.8, 0.1, Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) + 0.8)
			bm.material = jm
			seg.mesh = bm
			seg.position = (a + b) * 0.5 + Vector3(0, 12.0, 0)
			seg.rotation.y = atan2(b.x - a.x, b.z - a.z)
			ov.add_child(seg)
			seg.owner = ov
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
	for ol in ov_labels:
		_label(labels, ol[0], ol[1] + Vector3(0, 22.0, 0), 0.045, ol[2])
	for b in buildings.get_children():
		_label(labels, String(b.name).replace("_", " ").to_upper(), (b.get_child(0) as Node3D).position + Vector3(0, 22.0, 0), 0.04, Color(1.0, 0.95, 0.8))
	_label(labels, "HEIGHT  blue < 0 | green 0 | yellow +2.5 | red +4.5 m", P(-118.0, 212.0, 20.0), 0.06, Color.WHITE)
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
	md.ambient_anchors = load(AMBIENT_PATH)
	md.jungle_paths = jungle_paths
	md.jungle_pockets = jungle_pockets
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
		q.armory = P(ARMORY_X, _hl(half, ARMORY_L))
		q.lane_gate = _gate(1, half)
		q.lane_gates = PackedVector3Array([_gate(0, half), _gate(1, half), _gate(2, half)])
		q.spawn_points = _spawn_points(half)
		q.spawn_yaw_deg = 0.0 if half == 0 else 180.0
		hqs.append(q)
	md.hqs = hqs
	_check(ResourceSaver.save(md, DEF_PATH), DEF_PATH)
