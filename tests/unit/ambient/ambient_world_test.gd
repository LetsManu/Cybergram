extends GdUnitTestSuite
## W18-LIFE: the ambient layer never runs on the server / headless, nor inside
## the offline ServerWorld's map copy; debug args and the online seed.


func test_not_built_headless() -> void:
	var n: Node = auto_free(Node.new())
	assert_bool(AmbientWorld.should_build(n, true, PackedStringArray())).is_false()
	# The test runner itself is headless: the real hook builds nothing.
	assert_bool(GfxQuality.is_headless()).is_true()
	var host: Node = auto_free(Node.new())
	assert_object(AmbientWorld.create_for(host, null)).is_null()
	assert_int(host.get_child_count()).is_equal(0)


func test_built_on_a_client() -> void:
	var n: Node = auto_free(Node.new())
	assert_bool(AmbientWorld.should_build(n, false, PackedStringArray())).is_true()


func test_not_built_inside_server_world() -> void:
	var sw: Node = auto_free(ServerWorld.new())
	var map := Node3D.new()
	sw.add_child(map)
	var vis := Node.new()
	map.add_child(vis)
	assert_bool(AmbientWorld.should_build(vis, false, PackedStringArray())).is_false()


func test_ambient_off_flag() -> void:
	var n: Node = auto_free(Node.new())
	assert_bool(AmbientWorld.should_build(n, false, PackedStringArray(["--ambient-off"]))).is_false()


func test_map_visuals_headless_builds_no_ambient() -> void:
	var root: Node3D = auto_free(Node3D.new())
	var vis := MapVisuals.new()
	root.add_child(vis)
	add_child(root)
	await get_tree().process_frame
	assert_object(vis.get_node_or_null("AmbientWorld")).is_null()
	remove_child(root)


func test_debug_args() -> void:
	var d := AmbientWorld.parse_debug_args(PackedStringArray([
		"--ambient-time", "night", "--ambient-weather", "rain", "--ambient-level", "low",
		"--ambient-fx", "0", "--ambient-reduce-motion", "--ambient-seed", "9"]))
	assert_int(d.mood).is_equal(AmbientMood.Mood.NIGHT)
	assert_int(d.weather).is_equal(AmbientMood.Weather.RAIN)
	assert_int(d.level).is_equal(AmbientComfort.LOW)
	assert_float(d.fx).is_equal(0.0)
	assert_bool(d.reduce_motion).is_true()
	assert_int(d.seed).is_equal(9)
	assert_bool(AmbientWorld.parse_debug_args(PackedStringArray()).is_empty()).is_true()


func test_online_seed_agrees_across_clients() -> void:
	# Two clients see the same match start at different snapshot ticks.
	var hz := 60
	var a := AmbientWorld.seed_from_match_clock(90000 + 600, 10.0, hz)
	var b := AmbientWorld.seed_from_match_clock(90000 + 3600, 60.0, hz)
	assert_int(a).is_equal(b)
