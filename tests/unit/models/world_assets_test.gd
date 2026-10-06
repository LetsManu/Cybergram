extends GdUnitTestSuite
## Phase 6 asset validator (docs/art-bible.md §6, §7): every world asset built on
## the hero pipeline loads with its pieces, stays in its triangle budget, has the
## right scale and pivot, ships the full texture set and binds it in the toon
## material. One row per asset in ASSETS; a new asset must add its row.

## key -> {pieces, max_tris, height (min, max) m, pivot: base on y = 0, tex size}
const ASSETS := {
	&"uplink": {"pieces": ["main", "ring_0", "ring_1", "ring_2", "ring_3", "ring_4"], "max_tris": 80000,
		"height": Vector2(44.0, 47.0), "tex": 1024},
}


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
