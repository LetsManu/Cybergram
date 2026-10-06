extends GdUnitTestSuite
## Floor decals never paint characters (owner plan Part 4: decals only on valid
## surfaces; floor review found boots inside the 1 m projection box): decals
## cull the character layer, and rigged characters live only on that layer.


func test_decal_mask_excludes_the_character_layer() -> void:
	assert_int(GfxQuality.decal_cull_mask() & GfxQuality.character_layers()).is_equal(0)
	assert_int(GfxQuality.decal_cull_mask() & 1).is_equal(1)  # the map (layer 1) still gets decals


func test_built_decals_and_rigged_characters_do_not_meet() -> void:
	var def := load(WorldDecals.DEF_PATH) as WorldDecalsDef
	var p := WorldDecals.Placement.new("arrow", WorldDecals.Role.ARROW, Vector3.ZERO, Vector3.FORWARD, Vector2(2, 2))
	var d := WorldDecals.make_decal(p, Vector3.ZERO, Vector3.UP, def)
	if d == null:
		return  # atlas not built
	auto_free(d)
	if not WardlingRig.available(ModelPalette.TEAM_CONCORD):
		return
	var rig: WardlingRig = auto_free(WardlingRig.new())
	rig.setup(ModelPalette.TEAM_CONCORD)
	add_child(rig)
	var meshes := rig.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_greater(0)
	for mi: MeshInstance3D in meshes:
		assert_int(d.cull_mask & mi.layers).override_failure_message("%s layers %d" % [mi.name, mi.layers]).is_equal(0)
