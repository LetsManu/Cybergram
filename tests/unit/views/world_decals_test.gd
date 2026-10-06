extends GdUnitTestSuite
## P7 floor + decals (docs/assets/floor.md): WorldDecals placement is
## deterministic, no view sees more than the cap (design/art-bible.md §10.6),
## lane arrows point toward the enemy side in each half (§6.2), flank arrows
## toward the Mid door, and every decal shows a cell of the one atlas.
## Fixtures are built here (synthetic MapDef + atlas Image): no file access,
## except the last test, which checks the shipped def against the shipped atlas.

const LANE_X := 0.0
const GATE_X := 20.0
const HP_Z := [-60.0, -135.0, -210.0, -285.0, -360.0]
const HQ_A_Z := 0.0
const HQ_B_Z := -420.0
const CELL := 16


# ---------------------------------------------------------------- fixtures

func _map() -> MapDef:
	var md := MapDef.new()
	var lane := LaneDef.new()
	lane.id = &"test"
	for i in HP_Z.size():
		var hp := HardpointDef.new()
		hp.id = StringName("hp%d" % i)
		hp.position = Vector3(LANE_X, 0, HP_Z[i])
		hp.zone_radius = 10.0
		lane.hardpoints.append(hp)
	var fl := FlankLoopDef.new()
	fl.id = &"flank"
	fl.waypoints = PackedVector3Array([Vector3(30, 0, -135), Vector3(40, -4, -170), Vector3(25, 0, -200)])
	fl.outer_door = fl.waypoints[0]
	fl.mid_door = fl.waypoints[2]
	lane.flank_loops.append(fl)
	md.lanes.append(lane)
	for t in 2:
		var hq := HqDef.new()
		hq.team = t
		var z: float = HQ_A_Z if t == 0 else HQ_B_Z
		var dir := -1.0 if t == 0 else 1.0
		hq.sanctum = Vector3(0, 0, z - 5.0 * dir)
		hq.uplink = Vector3(0, 0, z + 30.0 * dir)
		hq.lane_gate = Vector3(GATE_X, 0, z + 40.0 * dir)
		md.hqs.append(hq)
	md.mid_plaza_center = Vector3(LANE_X, 0, HP_Z[2])
	md.mid_plaza_radius = 20.0
	return md


func _def() -> WorldDecalsDef:
	var d := WorldDecalsDef.new()
	var img := Image.create(d.atlas_columns * CELL, 2 * CELL, false, Image.FORMAT_RGBA8)
	for i in d.cells.size():
		# every cell a distinct solid colour, so a texture names its cell
		img.fill_rect(Rect2i((i % d.atlas_columns) * CELL, (i / d.atlas_columns) * CELL, CELL, CELL),
			Color(float(i) / 16.0, 0.5, 1.0 - float(i) / 16.0, 1.0))
	d.cell_px = CELL
	d.atlas_override = img
	return d


## Dense dressing: far more candidates than the cap allows in one view.
func _dense_def() -> WorldDecalsDef:
	var d := _def()
	d.arrow_spacing_m = 3.0
	d.grime_spacing_m = 1.5
	d.grime_chance = 1.0
	d.tag_spacing_m = 4.0
	d.puddle_spacing_m = 3.0
	d.puddle_chance = 1.0
	d.hardpoint_cracks = 12
	return d


func _flat_ground(p: Vector3) -> Dictionary:
	return {"pos": Vector3(p.x, p.y, p.z), "normal": Vector3.UP}


func _no_ground(_p: Vector3) -> Dictionary:
	return {}


## Most decals within `radius` (horizontal) of any camera on a 3 m grid offset from
## the cap's own 4 m grid, plus every decal position itself.
func _max_in_view(ps: Array, radius: float) -> int:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var buckets := {}
	for p: WorldDecals.Placement in ps:
		lo = lo.min(Vector2(p.pos.x, p.pos.z))
		hi = hi.max(Vector2(p.pos.x, p.pos.z))
		var k := Vector2i(floori(p.pos.x / radius), floori(p.pos.z / radius))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(Vector2(p.pos.x, p.pos.z))
	var cams: Array[Vector2] = []
	var x := lo.x - radius + 1.5
	while x <= hi.x + radius:
		var z := lo.y - radius + 1.5
		while z <= hi.y + radius:
			cams.append(Vector2(x, z))
			z += 3.0
		x += 3.0
	for p: WorldDecals.Placement in ps:
		cams.append(Vector2(p.pos.x, p.pos.z))
	var best := 0
	var r2 := radius * radius
	for c in cams:
		var n := 0
		var kc := Vector2i(floori(c.x / radius), floori(c.y / radius))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for q: Vector2 in buckets.get(kc + Vector2i(dx, dz), []):
					if c.distance_squared_to(q) <= r2:
						n += 1
		best = maxi(best, n)
	return best


# ---------------------------------------------------------------- tests

func test_plan_same_seed_is_identical() -> void:
	var md := _map()
	var a := WorldDecals.plan(md, _def())
	var b := WorldDecals.plan(md, _def())
	assert_int(a.size()).is_greater(0)
	assert_int(b.size()).is_equal(a.size())
	for i in a.size():
		assert_str(b[i].cell).is_equal(a[i].cell)
		assert_vector(b[i].pos).is_equal(a[i].pos)
		assert_vector(b[i].forward).is_equal(a[i].forward)


func test_plan_other_seed_moves_the_dressing() -> void:
	var md := _map()
	var d2 := _def()
	d2.placement_seed = 99
	var a := WorldDecals.plan(md, _def())
	var b := WorldDecals.plan(md, d2)
	var moved := false
	for i in mini(a.size(), b.size()):
		if a[i].role == WorldDecals.Role.GRIME or a[i].role == WorldDecals.Role.WEAR:
			if not a[i].pos.is_equal_approx(b[i].pos):
				moved = true
	assert_bool(moved).is_true()


func test_shipped_density_any_view_within_cap() -> void:
	var d := _def()
	var ps := WorldDecals.plan(_map(), d)
	assert_int(_max_in_view(ps, d.visible_radius())).is_less_equal(d.max_visible)


func test_dense_candidates_cap_binds_and_any_view_within_cap() -> void:
	var d := _dense_def()
	var ps := WorldDecals.plan(_map(), d)
	var worst := _max_in_view(ps, d.visible_radius())
	# the cap really cut candidates (the fixture would put > 48 in one view) ...
	assert_int(worst).is_greater_equal(d.max_visible - 8)
	# ... and still no view sees more than the cap
	assert_int(worst).is_less_equal(d.max_visible)


func test_cap_keeps_arrows_before_dressing() -> void:
	var d := _dense_def()
	var ps := WorldDecals.plan(_map(), d)
	var arrows := 0
	for p in ps:
		if p.role == WorldDecals.Role.ARROW:
			arrows += 1
	# every lane arrow outside the zones survives (they come first)
	assert_int(arrows).is_greater(40)


func test_lane_arrows_point_toward_enemy_side_in_each_half() -> void:
	var ps := WorldDecals.plan(_map(), _def())
	var seen := {MapDef.TEAM_CONCORD: 0, MapDef.TEAM_SYNDICATE: 0}
	for p in ps:
		if p.role != WorldDecals.Role.ARROW:
			continue
		var enemy_z := HQ_B_Z if p.team == MapDef.TEAM_CONCORD else HQ_A_Z
		var own_half := p.pos.z > HP_Z[2] if p.team == MapDef.TEAM_CONCORD else p.pos.z < HP_Z[2]
		assert_bool(own_half).is_true()
		# never back toward the own HQ; along the lane axis, toward the enemy HQ
		assert_float(p.forward.z * signf(enemy_z - p.pos.z)).is_greater_equal(-0.001)
		if absf(p.forward.z) > 0.5:
			seen[p.team] += 1
	assert_int(seen[MapDef.TEAM_CONCORD]).is_greater(3)
	assert_int(seen[MapDef.TEAM_SYNDICATE]).is_greater(3)


func test_approach_arrows_turn_toward_the_lane() -> void:
	var ps := WorldDecals.plan(_map(), _def())
	var lateral := 0
	for p in ps:
		if p.role == WorldDecals.Role.ARROW and absf(p.forward.x) > 0.9:
			# on the gate -> lane causeway: pointing from the gate (x = 20) to the lane (x = 0)
			assert_float(p.forward.x * signf(LANE_X - GATE_X)).is_greater(0.0)
			lateral += 1
	assert_int(lateral).is_greater(0)


func test_flank_arrows_point_toward_mid_door() -> void:
	var md := _map()
	var mid_door: Vector3 = md.lanes[0].flank_loops[0].mid_door
	var n := 0
	for p in WorldDecals.plan(md, _def()):
		if p.role == WorldDecals.Role.FLANK_ARROW:
			n += 1
			assert_float(p.forward.dot((mid_door - p.pos) * Vector3(1, 0, 1))).is_greater(0.0)
	assert_int(n).is_greater(3)


func test_hq_glyphs_use_team_colour_and_own_glyph() -> void:
	var d := _def()
	var glyphs := 0
	for p in WorldDecals.plan(_map(), d):
		if p.role != WorldDecals.Role.GLYPH:
			continue
		glyphs += 1
		if p.team == MapDef.TEAM_CONCORD:
			assert_str(p.cell).is_equal("glyph_concord")
			assert_that(p.modulate).is_equal(d.concord_color)
		else:
			assert_str(p.cell).is_equal("glyph_syndicate")
			assert_that(p.modulate).is_equal(d.syndicate_color)
	assert_int(glyphs).is_equal(2)


func test_built_decals_use_atlas_cells() -> void:
	var d := _def()
	var node: WorldDecals = auto_free(WorldDecals.create(_map(), d))
	var ps := WorldDecals.plan(_map(), d)
	node.build(ps, _flat_ground)
	assert_int(node.placed_count()).is_equal(ps.size())
	var atlas := d.atlas_override
	for c in node.get_children():
		var dc := c as Decal
		assert_object(dc).is_not_null()
		var cell: String = dc.get_meta(&"cell")
		var r := d.cell_rect(cell)
		assert_bool(d.cells.has(cell)).is_true()
		var img := (dc.texture_albedo as ImageTexture).get_image()
		assert_vector(Vector2(img.get_size())).is_equal(Vector2(r.size))
		# the texture is that atlas cell (the fixture paints each cell its own colour)
		assert_that(img.get_pixel(CELL / 2, CELL / 2)).is_equal(atlas.get_pixel(r.position.x + CELL / 2, r.position.y + CELL / 2))
		assert_bool(dc.distance_fade_enabled).is_true()
		assert_float(dc.distance_fade_begin + dc.distance_fade_length).is_equal_approx(d.visible_radius(), 0.001)


func test_arrow_decal_image_top_faces_its_forward() -> void:
	var d := _def()
	var p := WorldDecals.Placement.new("arrow", WorldDecals.Role.ARROW, Vector3(3, 0, -7), Vector3(1, 0, 0), Vector2(2, 2))
	p.emission = d.arrow_emission
	var dc: Decal = auto_free(WorldDecals.make_decal(p, p.pos, Vector3.UP, d))
	# the image's top maps to the decal's local -Z
	assert_vector(-dc.transform.basis.z.normalized()).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.001)
	assert_vector(dc.transform.basis.y.normalized()).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
	assert_float(dc.emission_energy).is_less_equal(1.0)  # Accent tier: no bloom
	assert_object(dc.texture_emission).is_not_null()


func test_build_without_floor_places_nothing() -> void:
	var d := _def()
	var node: WorldDecals = auto_free(WorldDecals.create(_map(), d))
	node.build(WorldDecals.plan(_map(), d), _no_ground)
	assert_int(node.placed_count()).is_equal(0)


func test_shipped_def_cells_lie_inside_shipped_atlas() -> void:
	var d := load(WorldDecals.DEF_PATH) as WorldDecalsDef
	assert_object(d).is_not_null()
	var img := WorldDecals.atlas_image(d)
	assert_object(img).is_not_null()
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for cell in d.cells:
		assert_bool(bounds.encloses(d.cell_rect(cell))).is_true()
		assert_object(WorldDecals.atlas_texture(d, cell)).is_not_null()
