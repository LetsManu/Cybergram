extends SceneTree
## Greybox generator for the Slice Map "Shardline Causeway"
## (design/gdd/match-flow-and-map.md §3.2 geometry rules, §3.7 slice layout).
##
## Writes, from one set of layout constants:
##   assets/maps/slice/shardline_causeway.tscn          map scene (geometry, anchors, lights, NavRegion)
##   assets/maps/slice/shardline_causeway_navmesh.res   baked NavigationMesh (ground layer)
##   assets/maps/slice/shardline_causeway_overview.tscn debug overview camera + navmesh overlay
##   assets/data/match/map_slice_lane.tres              MapDef (hardpoints, HQs, loops, spawns)
##
## Run (after an import so class_names resolve):
##   godot --headless --path . -s res://tools/maps/build_shardline_causeway.gd
##
## Axis: the lane runs along -Z. GDD lane distance L (Concord back wall = 0, the
## Syndicate HQ edge = 420) maps to z = -L. GDD "south" (flank-loop side) = +X.
## Half B is the mirror of half A across L = 210 (L' = 420 - L).

const MAP_PATH := "res://assets/maps/slice/shardline_causeway.tscn"
const NAV_PATH := "res://assets/maps/slice/shardline_causeway_navmesh.res"
const OVERVIEW_PATH := "res://assets/maps/slice/shardline_causeway_overview.tscn"
const DEF_PATH := "res://assets/data/match/map_slice_lane.tres"

const LANE_LEN := 420.0
const LANE_HALF_W := 8.0          # main path 16 m (GDD: 12-20 m)
const HQ_HALF_W := 30.0           # 60 m wide compound
const HQ_BACK := -6.0             # back wall line (keeps the r 10 Sanctum inside)
const HQ_FRONT := 40.0            # lane gate line
const HQ_WALL_H := 12.0
const RAIL_H := 1.1
const SANCTUM_L := 5.0
const SANCTUM_R := 10.0
const UPLINK_L := 30.0
const MID_L := 210.0
const PLAZA_R := 25.0
const SOCKET_GAP := 15.0          # Barricade socket distance outside the zone edge

const AZURE := Color("#2E86FF")
const EMBER := Color("#FF5A1F")
const NEUTRAL := Color(0.92, 0.9, 1.0)

## Half-A hardpoints: id, name, task, tier, L, radius, half pad size, base duration, generator hp, owner.
var HP_A := [
	[&"s_ai", "Glasswork Gate", HardpointDef.TaskKind.BREACH, HardpointDef.Tier.INNER, 85.0, 12.0, 15.0, 20.0, 6000.0, MapDef.TEAM_CONCORD],
	[&"s_ao", "Signal Market", HardpointDef.TaskKind.PLANT, HardpointDef.Tier.OUTER, 145.0, 10.0, 13.0, 75.0, 0.0, MapDef.TEAM_CONCORD],
]
var HP_B_NAMES := {&"s_ai": [&"s_bi", "Furnace Gate"], &"s_ao": [&"s_bo", "Scrap Bazaar"]}

## Flank loop A (centreline, lateral x, lane L): Outer side door -> Mid side door.
const LOOP_A := [Vector2(13.0, 148.0), Vector2(20.0, 148.0), Vector2(20.0, 188.0), Vector2(12.0, 188.0)]

var map_root: Node3D
var geo: Node3D
var mats := {}


func _initialize() -> void:
	await process_frame  # the root window joins the tree only once the loop runs
	_build_materials()
	map_root = Node3D.new()
	map_root.name = "ShardlineCauseway"
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
		_lane_half(half)
		_loop(half)
	_plaza()
	_hardpoints(anchors)
	_spawns()
	# Bake the ground navmesh from the static colliders under Geometry.
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
	_save_overview(nm)
	_save_map_def()
	quit()


func _check(err: int, what: String) -> void:
	if err != OK:
		push_error("build_shardline_causeway: %s failed (%d)" % [what, err])


# ---------------------------------------------------------------- helpers

static func P(x: float, l: float, y: float = 0.0) -> Vector3:
	return Vector3(x, y, -l)


static func mirror_l(l: float) -> float:
	return LANE_LEN - l


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


func _build_materials() -> void:
	mats.floor_a = _mat(Color(0.3, 0.33, 0.4))
	mats.floor_b = _mat(Color(0.36, 0.31, 0.29))
	mats.floor_hq_a = _mat(Color(0.4, 0.43, 0.5))
	mats.floor_hq_b = _mat(Color(0.2, 0.18, 0.19))
	mats.floor_mid = _mat(Color(0.34, 0.33, 0.37))
	mats.floor_loop = _mat(Color(0.26, 0.22, 0.34))
	mats.wall_a = _mat(Color(0.62, 0.65, 0.72))
	mats.wall_b = _mat(Color(0.2, 0.18, 0.19))
	mats.rail = _mat(Color(0.3, 0.31, 0.36))
	mats.cover_low = _mat(Color(0.58, 0.5, 0.36))
	mats.cover_tall = _mat(Color(0.42, 0.38, 0.5))
	mats.strip = _mat(Color(0.3, 0.32, 0.38))
	mats.socket = _mat(Color(0.95, 0.8, 0.25), 0.4, 0.55, true)
	for key in ["a", "b", "n"]:
		var c: Color = AZURE if key == "a" else (EMBER if key == "b" else NEUTRAL)
		mats["team_" + key] = _mat(c, 1.5)
		mats["glow_" + key] = _mat(c, 2.5, 0.55, true)
		mats["decal_" + key] = _mat(c, 0.0, 0.25)


## Solid box with collision (center = box centre).
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


## Axis-aligned box from lateral range [x0,x1], lane range [l0,l1], height range [y0,y1].
func _slab(parent: Node, n: String, x0: float, x1: float, l0: float, l1: float, y0: float, y1: float, mat: Material, collide := true) -> Node3D:
	return _box(parent, n, Vector3(absf(x1 - x0), y1 - y0, absf(l1 - l0)), P((x0 + x1) * 0.5, (l0 + l1) * 0.5, (y0 + y1) * 0.5), mat, collide)


## Cylinder / cone with a convex collider (or none).
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


func _half_l(half: int, l: float) -> float:
	return l if half == 0 else mirror_l(l)


func _key(half: int) -> String:
	return "a" if half == 0 else "b"


# ---------------------------------------------------------------- environment

func _env() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.17, 0.38)
	sky_mat.sky_horizon_color = Color(0.62, 0.55, 0.75)
	sky_mat.ground_bottom_color = Color(0.12, 0.08, 0.2)
	sky_mat.ground_horizon_color = Color(0.5, 0.42, 0.66)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.7)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.5, 0.7)
	env.fog_density = 0.0015
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	_add(map_root, we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	_add(map_root, sun)


# ---------------------------------------------------------------- HQs

func _hq(half: int) -> void:
	var k := _key(half)
	var g := _node(geo, "HQ_" + ("Concord" if half == 0 else "Syndicate"))
	var wall: Material = mats["wall_" + k]
	var l_back := _half_l(half, HQ_BACK)
	var l_front := _half_l(half, HQ_FRONT)
	_slab(g, "Floor", -HQ_HALF_W, HQ_HALF_W, l_back, l_front, -1.0, 0.0, mats["floor_hq_" + k])
	var lb0 := minf(l_back, l_front)
	var lb1 := maxf(l_back, l_front)
	var back_sign := -1.0 if half == 0 else 1.0
	_slab(g, "WallBack", -HQ_HALF_W - 1, HQ_HALF_W + 1, l_back + back_sign, l_back, 0, HQ_WALL_H, wall)
	_slab(g, "WallLeft", -HQ_HALF_W - 1, -HQ_HALF_W, lb0, lb1, 0, HQ_WALL_H, wall)
	_slab(g, "WallRight", HQ_HALF_W, HQ_HALF_W + 1, lb0, lb1, 0, HQ_WALL_H, wall)
	var f_out := l_front - back_sign
	_slab(g, "WallFrontL", -HQ_HALF_W - 1, -LANE_HALF_W - 1, l_front, f_out, 0, HQ_WALL_H, wall)
	_slab(g, "WallFrontR", LANE_HALF_W + 1, HQ_HALF_W + 1, l_front, f_out, 0, HQ_WALL_H, wall)
	# Gate pylons in team colour (lane gate at x = 40 / 380).
	_slab(g, "GatePylonL", -LANE_HALF_W - 1, -LANE_HALF_W, l_front, f_out, 0, HQ_WALL_H + 2, mats["team_" + k])
	_slab(g, "GatePylonR", LANE_HALF_W, LANE_HALF_W + 1, l_front, f_out, 0, HQ_WALL_H + 2, mats["team_" + k])
	# Sanctum: r 10 no-entry + heal zone (C6), floor decal + ring.
	var s := P(0, _half_l(half, SANCTUM_L))
	_cyl(g, "SanctumZone", SANCTUM_R, SANCTUM_R, 0.03, s + Vector3(0, 0.01, 0), mats["decal_" + k], false, 48)
	_cyl(g, "SanctumCanopy", 3.0, 3.0, 0.4, s + Vector3(0, 6.0, 0), mats["team_" + k], false, 24)
	# Uplink: plinth (steep cone, an obstacle) + spire + core.
	var u := P(0, _half_l(half, UPLINK_L))
	_cyl(g, "UplinkPlinth", 4.5, 3.5, 1.5, u, wall)
	_cyl(g, "UplinkSpire", 0.8, 0.5, 9.0, u + Vector3(0, 1.5, 0), mats["team_" + k])
	_cyl(g, "UplinkCore", 1.6, 1.6, 2.6, u + Vector3(0, 6.0, 0), mats["glow_" + k], false, 6)
	var ol := OmniLight3D.new()
	ol.name = "UplinkLight"
	ol.light_color = AZURE if half == 0 else EMBER
	ol.omni_range = 22.0
	ol.light_energy = 1.6
	ol.position = u + Vector3(0, 7.0, 0)
	_add(g, ol)
	# Foundry (west, -X) and Armory (east, +X) beside the Sanctum.
	var lf := _half_l(half, 10.0)
	_box(g, "Foundry", Vector3(10, 6, 8), P(-19, lf, 3), wall)
	_box(g, "FoundryStack", Vector3(2, 6, 2), P(-22, lf, 9), mats["team_" + k])
	_box(g, "FoundryBand", Vector3(10.1, 0.6, 8.1), P(-19, lf, 4.5), mats["team_" + k], false)
	_box(g, "Armory", Vector3(10, 4, 8), P(19, lf, 2), wall)
	_box(g, "ArmoryCounter", Vector3(8, 1.1, 1), P(19, _half_l(half, 15.0), 0.55), mats["team_" + k])
	# Courtyard cover between Sanctum and gate.
	_box(g, "CourtCoverL", Vector3(3, 1.2, 1.5), P(-10, _half_l(half, 24.0), 0.6), mats.cover_low)
	_box(g, "CourtCoverR", Vector3(3, 1.2, 1.5), P(10, _half_l(half, 24.0), 0.6), mats.cover_low)


# ---------------------------------------------------------------- lane

func _lane_half(half: int) -> void:
	var k := _key(half)
	var g := _node(geo, "Lane_" + k.to_upper())
	var fl: Material = mats["floor_" + k]
	_slab(g, "Floor", -LANE_HALF_W, LANE_HALF_W, _half_l(half, HQ_FRONT), _half_l(half, MID_L), -1, 0, fl)
	# Hardpoint pads.
	for hp in HP_A:
		var l := _half_l(half, hp[4])
		var hw: float = hp[6]
		_slab(g, "Pad_%s" % _hp_id(hp, half), -hw, hw, l - hw, l + hw, -1, 0, fl)
	# Distance strips every 10 m on open lane.
	for l in range(50, 210, 10):
		if _in_pad(l) or l > 182:
			continue
		_box(g, "Strip%d" % l, Vector3(14, 0.02, 0.25), P(0, _half_l(half, l), 0.01), mats.strip, false)
	# Edge rails where the lane meets open sky (Leyfall).
	var rails := [
		# [x, l0, l1]
		[-LANE_HALF_W - 0.25, 40.0, 70.0], [LANE_HALF_W + 0.25, 40.0, 70.0],
		[-LANE_HALF_W - 0.25, 100.0, 132.0], [LANE_HALF_W + 0.25, 100.0, 132.0],
		[-LANE_HALF_W - 0.25, 158.0, 186.5], [LANE_HALF_W + 0.25, 158.0, 185.0],
		[-15.25, 70.0, 100.0], [15.25, 70.0, 100.0],
		[-13.25, 132.0, 158.0], [13.25, 132.0, 145.0], [13.25, 151.0, 158.0],
	]
	for i in rails.size():
		var r: Array = rails[i]
		_slab(g, "Rail%d" % i, r[0] - 0.25, r[0] + 0.25, _half_l(half, r[1]), _half_l(half, r[2]), 0, RAIL_H, mats.rail)
	# Pad front/back rails (between lane edge and pad edge).
	var pad_rails := [[15.0, 70.0], [15.0, 100.0], [13.0, 132.0], [13.0, 158.0]]
	for i in pad_rails.size():
		var pr: Array = pad_rails[i]
		for s in [-1.0, 1.0]:
			_slab(g, "PadRail%d_%d" % [i, int(s)], s * LANE_HALF_W, s * pr[0], _half_l(half, pr[1] - 0.25), _half_l(half, pr[1] + 0.25), 0, RAIL_H, mats.rail)
	# Cover and sightline blockers (sightlines capped near 70 m, §3.2).
	var cover := [
		# [x, l, w, h, d, tall]
		[-4.5, 58.0, 3.0, 1.2, 1.5, false], [4.0, 64.0, 2.0, 2.6, 2.0, true],
		[-9.0, 80.0, 2.0, 1.2, 4.0, false], [9.0, 90.0, 2.0, 1.2, 4.0, false],
		[-4.0, 116.0, 6.0, 3.5, 1.0, true], [5.0, 124.0, 2.0, 1.2, 2.0, false],
		[-7.0, 138.0, 4.0, 1.1, 2.0, false], [7.0, 138.0, 4.0, 1.1, 2.0, false],
		[-7.0, 152.0, 4.0, 1.1, 2.0, false], [7.0, 152.0, 4.0, 1.1, 2.0, false],
		[4.0, 164.0, 6.0, 3.5, 1.0, true], [-5.0, 176.0, 2.0, 1.2, 2.0, false],
	]
	for i in cover.size():
		var c: Array = cover[i]
		var tall: bool = c[5]
		_box(g, "Cover%d" % i, Vector3(c[2], c[3], c[4]), P(c[0], _half_l(half, c[1]), c[3] * 0.5), mats.cover_tall if tall else mats.cover_low)


func _in_pad(l: float) -> bool:
	for hp in HP_A:
		if absf(l - hp[4]) <= hp[6] + 0.5:
			return true
	return false


func _hp_id(hp: Array, half: int) -> StringName:
	return hp[0] if half == 0 else HP_B_NAMES[hp[0]][0]


func _loop(half: int) -> void:
	var k := _key(half)
	var g := _node(geo, "FlankLoop_" + k.to_upper())
	var m: Material = mats.floor_loop
	# Leg 1: AO pad side door -> loop; leg 2: the long run; leg 3: back to the plaza rim.
	_slab(g, "Leg1", 13.0, 23.0, _half_l(half, 145.0), _half_l(half, 151.0), -1, 0, m)
	_slab(g, "Leg2", 17.0, 23.0, _half_l(half, 145.0), _half_l(half, 191.0), -1, 0, m)
	_slab(g, "Leg3", LANE_HALF_W, 23.0, _half_l(half, 185.0), _half_l(half, 191.0), -1, 0, m)
	_slab(g, "RailOuter", 23.0, 23.5, _half_l(half, 145.0), _half_l(half, 191.0), 0, RAIL_H, mats.rail)
	_slab(g, "RailInner", 16.5, 17.0, _half_l(half, 151.0), _half_l(half, 185.0), 0, RAIL_H, mats.rail)
	_slab(g, "RailLeg1", 13.0, 23.5, _half_l(half, 144.5), _half_l(half, 145.0), 0, RAIL_H, mats.rail)
	_slab(g, "RailLeg1b", 13.25, 17.0, _half_l(half, 151.0), _half_l(half, 151.5), 0, RAIL_H, mats.rail)
	_slab(g, "RailLeg3a", LANE_HALF_W + 0.5, 17.0, _half_l(half, 184.5), _half_l(half, 185.0), 0, RAIL_H, mats.rail)
	_slab(g, "RailLeg3b", 16.0, 23.5, _half_l(half, 191.0), _half_l(half, 191.5), 0, RAIL_H, mats.rail)
	_box(g, "LoopCover", Vector3(1.5, 1.2, 2.0), P(19.0, _half_l(half, 168.0), 0.6), mats.cover_low)
	# Door frames (posts + lintel) at both ends.
	for d in [[13.0, 148.0, 0.0], [12.0, 188.0, 0.0]]:
		var l := _half_l(half, d[1])
		var x: float = d[0]
		var along_l := is_equal_approx(x, 13.0)
		if along_l:
			_slab(g, "DoorPostA%d" % int(d[1]), x - 0.3, x + 0.3, l - 3.3, l - 2.7, 0, 3.5, mats["team_" + k])
			_slab(g, "DoorPostB%d" % int(d[1]), x - 0.3, x + 0.3, l + 2.7, l + 3.3, 0, 3.5, mats["team_" + k])
			_slab(g, "DoorLintel%d" % int(d[1]), x - 0.3, x + 0.3, l - 3.3, l + 3.3, 3.5, 4.0, mats["team_" + k], false)


func _plaza() -> void:
	var g := _node(geo, "MidPlaza")
	_cyl(g, "Floor", PLAZA_R, PLAZA_R, 1.0, P(0, MID_L, -1.0), mats.floor_mid, true, 64)
	# Rim rails, skipping where the lane and the loops join.
	var n := 48
	for i in n:
		var a := TAU * (i + 0.5) / n
		var px := sin(a) * (PLAZA_R + 0.25)
		var pl := MID_L + cos(a) * (PLAZA_R + 0.25)
		if absf(px) < LANE_HALF_W + 1.0:
			continue
		if px > 0 and (pl < 191.5 or pl > mirror_l(191.5)):
			continue
		var seg := TAU * (PLAZA_R + 0.25) / n + 0.2
		_box(g, "Rim%d" % i, Vector3(0.5, RAIL_H, seg), P(px, pl, RAIL_H * 0.5), mats.rail, true, Vector3(0, 90.0 - rad_to_deg(a), 0))
	# Four tall cover pillars around the Spindle.
	var i := 0
	for sx in [-1.0, 1.0]:
		for sl in [-1.0, 1.0]:
			_box(g, "Pillar%d" % i, Vector3(2.5, 4.0, 2.5), P(sx * 13.0, MID_L + sl * 13.0, 2.0), mats.cover_tall)
			i += 1


# ---------------------------------------------------------------- hardpoints

func _hardpoints(anchors: Node3D) -> void:
	for half in 2:
		for hp in HP_A:
			var l := _half_l(half, hp[4])
			var key := "a" if half == 0 else "b"
			_hardpoint(anchors, _hp_id(hp, half), hp[2], P(0, l), hp[5], key)
			_sockets(anchors, _hp_id(hp, half), l, hp[5])
	_hardpoint(anchors, &"s_mid", HardpointDef.TaskKind.HOLD, P(0, MID_L), 12.0, "n")
	_sockets(anchors, &"s_mid", MID_L, 12.0)


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
	match task:
		HardpointDef.TaskKind.BREACH:
			# Ward Generator: hex zone, solid core, shield dome; gatehouse arch over the lane.
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
			# Charge Cradle: Y pylon, square pad with corner brackets.
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
			# Market awning over the Socket.
			_box(vis, "Awning", Vector3(6, 0.15, 6), Vector3(0, 4.6, 0), mats["decal_" + k], false)
		HardpointDef.TaskKind.HOLD:
			# Holdstone on the Spindle dais: ring plinth + 12 m light pillar; circle zone.
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
			var ol := OmniLight3D.new()
			ol.name = "PillarLight"
			ol.omni_range = 16.0
			ol.light_energy = 1.2
			ol.position = Vector3(0, 4, 0)
			_add(vis, ol)


func _sockets(anchors: Node3D, id: StringName, l: float, r: float) -> void:
	for side in 2:
		var sl := l - (r + SOCKET_GAP) if side == 0 else l + (r + SOCKET_GAP)
		var s := BarricadeSocketAnchor.new()
		s.name = "Socket_%s_%s" % [String(id).to_upper(), "A" if side == 0 else "B"]
		s.hardpoint_id = id
		s.side = side
		s.span_m = 2 * LANE_HALF_W
		s.position = P(0, sl)
		_add(anchors, s)
		_box(geo, "SocketMark_%s_%d" % [String(id).to_upper(), side], Vector3(2 * LANE_HALF_W, 0.03, 0.6), P(0, sl, 0.015), mats.socket, false)


# ---------------------------------------------------------------- spawns

func _spawn_points(half: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for x in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		out.append(P(x, _half_l(half, 4.0), 0.05))
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
		sd.position = P(0, _half_l(half, 185.0), 0.05)
		_add(team, sd)
	# Session hooks used by GameSession / ServerWorld (same names as the test course).
	# TeamSpawn0/1: ServerWorld respawn points (team 0 = Concord, 1 = Syndicate Sanctum).
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
		var pts := {"Sanctum": P(0, _half_l(half, SANCTUM_L)), "Uplink": P(0, _half_l(half, UPLINK_L)),
			"FoundryPad": P(-19, _half_l(half, 17.0)), "ArmoryPad": P(19, _half_l(half, 17.0)),
			"LaneGate": P(0, _half_l(half, HQ_FRONT))}
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

func _save_overview(nm: NavigationMesh) -> void:
	var ov := Node3D.new()
	ov.name = "ShardlineCausewayOverview"
	get_root().add_child(ov)
	var map: Node3D = (load(MAP_PATH) as PackedScene).instantiate()
	ov.add_child(map)
	map.owner = ov
	# Navmesh overlay (green), slightly above the floor.
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
	var cam := Camera3D.new()
	cam.name = "OverviewCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 440.0
	cam.near = 1.0
	cam.far = 600.0
	cam.current = true
	# Same look as the map, minus distance fog (the camera sits 300 m up).
	var env: Environment = (map.get_node("Env") as WorldEnvironment).environment.duplicate()
	env.fog_enabled = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.1, 0.2)
	cam.environment = env
	# Screen right = -Z (toward the Syndicate), screen up = -X (north), looking down.
	cam.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)), Vector3(-8, 300, -LANE_LEN * 0.5))
	ov.add_child(cam)
	cam.owner = ov
	var packed := PackedScene.new()
	_check(packed.pack(ov), "pack overview")
	_check(ResourceSaver.save(packed, OVERVIEW_PATH), OVERVIEW_PATH)


func _save_map_def() -> void:
	var md := MapDef.new()
	md.id = &"map_slice_lane"
	md.display_name = "Shardline Causeway"
	md.scene = load(MAP_PATH)
	md.reference_run_speed = 6.0
	md.mid_plaza_center = P(0, MID_L)
	md.mid_plaza_radius = PLAZA_R
	md.sudden_death_spawns = PackedVector3Array([P(0, 185.0, 0.05), P(0, 235.0, 0.05)])
	var lane := LaneDef.new()
	lane.id = &"slice"
	var hps: Array[HardpointDef] = []
	var rows := [
		[HP_A[0], 0], [HP_A[1], 0], [null, 0], [HP_A[1], 1], [HP_A[0], 1],
	]
	for i in rows.size():
		var h := HardpointDef.new()
		var src = rows[i][0]
		var half: int = rows[i][1]
		if src == null:
			h.id = &"s_mid"
			h.display_name = "The Spindle"
			h.task = HardpointDef.TaskKind.HOLD
			h.tier = HardpointDef.Tier.MID
			h.position = P(0, MID_L)
			h.zone_radius = 12.0
			h.base_duration_s = 60.0
			h.initial_owner = MapDef.TEAM_NEUTRAL
		else:
			h.id = _hp_id(src, half)
			h.display_name = src[1] if half == 0 else HP_B_NAMES[src[0]][1]
			h.task = src[2]
			h.tier = src[3]
			h.position = P(0, _half_l(half, src[4]))
			h.zone_radius = src[5]
			h.base_duration_s = src[7]
			h.generator_hp = src[8]
			h.initial_owner = MapDef.TEAM_CONCORD if half == 0 else MapDef.TEAM_SYNDICATE
		h.lane_index = i
		h.zone_height = 6.0
		var l := -h.position.z
		h.barricade_sockets = PackedVector3Array([P(0, l - h.zone_radius - SOCKET_GAP), P(0, l + h.zone_radius + SOCKET_GAP)])
		hps.append(h)
	lane.hardpoints = hps
	var loops: Array[FlankLoopDef] = []
	for half in 2:
		var f := FlankLoopDef.new()
		f.id = &"loop_a" if half == 0 else &"loop_b"
		f.from_hardpoint = &"s_ao" if half == 0 else &"s_bo"
		f.to_hardpoint = &"s_mid"
		var wps := PackedVector3Array()
		for w in LOOP_A:
			wps.append(P(w.x, _half_l(half, w.y)))
		f.waypoints = wps
		f.outer_door = wps[0]
		f.mid_door = wps[wps.size() - 1]
		loops.append(f)
	lane.flank_loops = loops
	var lanes: Array[LaneDef] = [lane]
	md.lanes = lanes
	var hqs: Array[HqDef] = []
	for half in 2:
		var q := HqDef.new()
		q.team = half
		q.sanctum = P(0, _half_l(half, SANCTUM_L))
		q.sanctum_radius = SANCTUM_R
		q.uplink = P(0, _half_l(half, UPLINK_L))
		q.foundry = P(-19, _half_l(half, 17.0))
		q.armory = P(19, _half_l(half, 17.0))
		q.lane_gate = P(0, _half_l(half, HQ_FRONT))
		q.spawn_points = _spawn_points(half)
		q.spawn_yaw_deg = 0.0 if half == 0 else 180.0
		hqs.append(q)
	md.hqs = hqs
	_check(ResourceSaver.save(md, DEF_PATH), DEF_PATH)
