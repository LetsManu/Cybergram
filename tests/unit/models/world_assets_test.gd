extends GdUnitTestSuite
## Phase 6 asset validator (docs/art-bible.md §6, §7): every world asset built on
## the hero pipeline loads with its pieces, stays in its triangle budget, has the
## right scale and pivot, ships the full texture set and binds it in the toon
## material. One row per asset in ASSETS; a new asset must add its row.

## key -> {pieces, max_tris, height (min, max) m, tex size, pivot}. Pivot "base":
## the bounds start at y = 0 (default); "centre": the bounds are centred on y = 0
## (objects the runtime moves by their centre, like the Mana Cell). Picket
## Wardlings have their own checks (tier budget, leg pivots) further down.
const ASSETS := {
	&"uplink": {"pieces": ["main", "ring_0", "ring_1", "ring_2", "ring_3", "ring_4"], "max_tris": 80000,
		"height": Vector2(44.0, 47.0), "tex": 1024},
	&"holdstone": {"pieces": ["main", "crystal"], "max_tris": 25000, "height": Vector2(4.2, 5.2), "tex": 1024},
	&"cell_cradle": {"pieces": ["cell_cradle"], "max_tris": 10000, "height": Vector2(1.3, 1.7), "tex": 1024},
	&"mana_cell": {"pieces": ["mana_cell"], "max_tris": 2500, "height": Vector2(0.7, 0.9), "tex": 512, "pivot": "centre"},
	&"charge_cradle": {"pieces": ["main", "bracket"], "max_tris": 10000, "height": Vector2(3.9, 4.4), "tex": 1024},
}
const PICKET_PIECES: Array[String] = ["body", "tier2", "tier3", "leg_l", "leg_r", "sash", "sash_own", "pennant", "elite"]


func test_every_world_asset_meets_its_spec() -> void:
	for key: StringName in ASSETS:
		var spec: Dictionary = ASSETS[key]
		assert_bool(WorldModel.exists(key)).override_failure_message("%s: glb missing" % key).is_true()
		var inst: Node3D = auto_free(WorldModel.instantiate(key, ModelPalette.TEAM_CONCORD))
		add_child(inst)
		var tris := 0
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for p: String in spec.pieces:
			var mi := WorldModel.piece(inst, StringName(p))
			assert_object(mi).override_failure_message("%s: piece %s missing" % [key, p]).is_not_null()
			if mi == null:
				continue
			for s in mi.mesh.get_surface_count():
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var bb := mi.global_transform * mi.get_aabb()
			lo = lo.min(bb.position)
			hi = hi.max(bb.end)
			var m := mi.material_override as ShaderMaterial
			assert_float(float(m.get_shader_parameter("use_maps"))).override_failure_message(
				"%s: maps not bound" % key).is_equal(1.0)
		assert_int(tris).override_failure_message("%s: %d tris over budget" % [key, tris]).is_less_equal(int(spec.max_tris))
		var h := hi.y - lo.y
		assert_bool(h >= spec.height.x and h <= spec.height.y).override_failure_message(
			"%s: height %.1f m outside %s" % [key, h, spec.height]).is_true()
		if spec.get("pivot", "base") == "centre":
			assert_float((lo.y + hi.y) * 0.5).override_failure_message("%s: pivot not at the centre" % key).is_between(-0.05, 0.05)
		else:
			assert_float(lo.y).override_failure_message("%s: pivot not at the base (min y %.2f)" % [key, lo.y]).is_between(-0.2, 0.2)
		for kind in ["albedo", "normal", "mask"]:
			var tex := load((WorldModel.ROOT % [key, key]) + "_%s.png" % kind) as Texture2D
			assert_object(tex).is_not_null()
			if tex != null:
				var want: int = spec.tex / 2 if kind == "mask" else spec.tex
				assert_int(tex.get_width()).override_failure_message("%s %s size" % [key, kind]).is_equal(want)


func test_world_material_is_the_hero_toon_shader() -> void:
	var m := WorldModel.material(&"uplink", ModelPalette.TEAM_SYNDICATE)
	assert_str(m.shader.resource_path).is_equal(RiggedHeroModel.TOON_SHADER)
	assert_object(m.next_pass).is_not_null()  # ink hull


func test_uplink_model_uses_the_baked_frame_and_keeps_its_rings() -> void:
	var u: UplinkModel = auto_free(UplinkModel.new())
	add_child(u)
	u.setup(ModelPalette.TEAM_CONCORD, 7.3)
	assert_bool(u.is_baked()).is_true()
	assert_int(u._rings.size()).is_equal(UplinkModel.RING_Y.size())
	# ring pivots sit at their ring height (pieces are centred), so judder rocks in place
	for i in u._rings.size():
		assert_float(u._rings[i].position.y).is_equal_approx(UplinkModel.RING_Y[i], 0.6)
	u.set_state(true, false, 0.4)
	u._process(0.1)
	assert_int(u.stage).is_equal(2)


func test_picket_skins_have_every_piece_and_full_maps() -> void:
	for key: StringName in [&"picket_c", &"picket_s"]:
		assert_bool(WorldModel.exists(key)).override_failure_message("%s: glb missing" % key).is_true()
		var inst: Node3D = auto_free(WorldModel.instantiate(key, ModelPalette.TEAM_CONCORD))
		for p in PICKET_PIECES:
			assert_object(WorldModel.piece(inst, StringName(p))).override_failure_message("%s: piece %s missing" % [key, p]).is_not_null()
		for kind in ["albedo", "normal", "mask"]:
			var tex := load((WorldModel.ROOT % [key, key]) + "_%s.png" % kind) as Texture2D
			assert_object(tex).override_failure_message("%s %s missing" % [key, kind]).is_not_null()


func test_picket_uses_the_faction_bake_and_stays_in_the_wardling_budget() -> void:
	for team in [ModelPalette.TEAM_CONCORD, ModelPalette.TEAM_SYNDICATE]:
		var w: WardlingModel = auto_free(WardlingModelBuilder.build(&"picket", 3, team))
		add_child(w)
		assert_str(String(w.baked_key)).is_equal("picket_s" if team == ModelPalette.TEAM_SYNDICATE else "picket_c")
		# art bible §10.6: 4k tris for a Wardling, at the top tier with a sash
		assert_int(w.triangle_count()).is_less(ModelCatalog.WARDLING_TRI_BUDGET)
		var m := w._body.material_override as ShaderMaterial
		assert_str(m.shader.resource_path).is_equal(RiggedHeroModel.TOON_SHADER)
		assert_float(float(m.get_shader_parameter("use_maps"))).is_equal(1.0)
		assert_bool(w._tier_mi.visible).is_true()
		w.set_tier(1)
		assert_bool(w._tier_mi.visible).is_false()


func test_picket_legs_swing_from_the_hip() -> void:
	var w: WardlingModel = auto_free(WardlingModelBuilder.build(&"picket", 1, ModelPalette.TEAM_CONCORD))
	add_child(w)
	for leg in w._legs:
		var mi := leg.get_child(0) as MeshInstance3D
		var bb := mi.get_aabb()
		# rebased to the hip: the leg hangs below its pivot and its top is at it
		assert_float(bb.end.y).is_between(-0.02, 0.08)
		assert_float(bb.position.y).is_between(-0.3, -0.2)


func test_plant_hardpoint_uses_the_baked_cell_and_cradles() -> void:
	var d := HardpointDef.new()
	d.id = &"t_plant"
	d.task = HardpointDef.TaskKind.PLANT
	d.zone_radius = 10.0
	d.initial_owner = MapDef.TEAM_NEUTRAL
	d.cell_cradles = PackedVector3Array([Vector3(30, 0, 0), Vector3(-30, 0, 0)])
	var v: HardpointView = auto_free(HardpointView.new())
	add_child(v)
	v.setup(d)
	assert_object(v._cell_model).is_not_null()
	assert_object(v.get_node_or_null("ChargeCradle")).is_not_null()
	assert_int(v._cradle_art.size()).is_equal(5)  # pylon + 4 corner brackets
	for team in 2:
		var c := v.get_node_or_null("CellCradle_%d" % team) as Node3D
		assert_object(c).is_not_null()
		assert_vector(c.global_position).is_equal_approx(d.cell_cradles[team], Vector3.ONE * 0.01)
	# brackets sit on the zone's square corners
	var corners := 0
	for n in v._cradle_art:
		if absf(absf(n.position.x) - 10.0) < 0.01 and absf(absf(n.position.z) - 10.0) < 0.01:
			corners += 1
	assert_int(corners).is_equal(4)
