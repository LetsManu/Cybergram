extends GdUnitTestSuite
## A hero (HeroBody + HeroMotor, the shipped controller) driven by scripted input
## walks the full Shardline Causeway lane from the Concord Sanctum to the far
## (Syndicate Inner) hardpoint, steering along a navmesh path. The run time must
## match the GDD reference within ±20% (match-flow-and-map.md §3.2: 6.0 m/s;
## Sanctum -> Inner 85 + 60 + 65 + 65 + 60 = 335 m, minus the 12 m zone radius).

const DEF_PATH := "res://assets/data/match/map_slice_lane.tres"
const MOVEMENT_PATH := "res://assets/data/movement/movement_default.tres"
const TICK_HZ := 30
const GDD_SANCTUM_TO_ENEMY_INNER_M := 335.0


func test_hero_walks_the_full_lane_in_gdd_time() -> void:
	var def := load(DEF_PATH) as MapDef
	var far := def.lanes[0].hardpoints[4]
	var movement := load(MOVEMENT_PATH) as MovementDef
	var scene: Node3D = auto_free(def.scene.instantiate())
	add_child(scene)
	var nav_map := (scene.get_node("NavRegion") as NavigationRegion3D).get_navigation_map()
	# Wait until this region is synced into the map (the map may already be live from other suites).
	var probe_a := _def_probe_a()
	for i in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_path(nav_map, probe_a[0], probe_a[1], true).size() > 1:
			break
	var start := def.hq(MapDef.TEAM_CONCORD).spawn_points[0]
	var path := NavigationServer3D.map_get_path(nav_map, start, far.position, true)
	assert_int(path.size()).is_greater(1)
	if path.size() < 2:
		return
	var hero := HeroBody.new()
	hero.setup(movement, start, false)
	scene.add_child(hero)
	hero.place()
	await get_tree().physics_frame
	var dt := 1.0 / TICK_HZ
	var cmd := InputCommand.new()
	var wp := 1
	var expected_s := (GDD_SANCTUM_TO_ENEMY_INNER_M - far.zone_radius) / def.reference_run_speed
	var max_ticks := int(expected_s * 2.0 * TICK_HZ)
	var ticks := 0
	var reached := false
	var min_y := 0.0
	while ticks < max_ticks:
		var pos := hero.global_position
		if Vector2(pos.x - far.position.x, pos.z - far.position.z).length() <= far.zone_radius:
			reached = true
			break
		var to := path[wp] - pos
		to.y = 0.0
		while to.length() < 0.6 and wp < path.size() - 1:
			wp += 1
			to = path[wp] - pos
			to.y = 0.0
		cmd.seq = ticks
		cmd.move = Vector2(0.0, 1.0)
		cmd.yaw = atan2(-to.x, -to.z)
		cmd.buttons = 0
		cmd.quantize()
		hero.step(cmd, dt)
		min_y = minf(min_y, hero.global_position.y)
		ticks += 1
	var seconds := float(ticks) / TICK_HZ
	print("slice walk: %.1f s (expected %.1f s), path %d points" % [seconds, expected_s, path.size()])
	assert_bool(reached).is_true()
	assert_float(min_y).is_greater(-0.5)
	assert_float(seconds).is_between(expected_s * 0.8, expected_s * 1.2)
	hero.queue_free()


func test_offline_session_boots_on_the_slice_map() -> void:
	var launch := LaunchConfig.parse(PackedStringArray(["--map", "slice"]), false)
	var session: GameSession = auto_free(load("res://src/gameplay/world/game_session.tscn").instantiate())
	session.launch_config = launch
	add_child(session)
	await get_tree().physics_frame
	for i in 10:
		session.step_tick()
	var def := load(DEF_PATH) as MapDef
	assert_object(session.map_scene).is_same(def.scene)
	assert_vector(session.server.spawn_point("PlayerSpawn")).is_equal_approx(
		def.hq(MapDef.TEAM_CONCORD).spawn_points[0], Vector3.ONE * 0.01)
	assert_object(session.client.predictor).is_not_null()


## Two far-apart floor points (Concord Sanctum, Syndicate Sanctum) used to detect a synced navmesh.
func _def_probe_a() -> Array[Vector3]:
	var d := load("res://assets/data/match/map_slice_lane.tres") as MapDef
	return [d.hq(MapDef.TEAM_CONCORD).sanctum, d.hq(MapDef.TEAM_SYNDICATE).sanctum]
