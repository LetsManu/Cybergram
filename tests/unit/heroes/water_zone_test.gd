extends GdUnitTestSuite
## W16-SDWATER: dock water slows 15%, inside the shared motor; strongest slow wins.

const DT: float = 1.0 / 30.0
const MAP_PATH := "res://assets/data/match/map_front.tres"


func _zone(factor: float = 0.85) -> WaterZoneDef:
	var z := WaterZoneDef.new()
	z.bounds = AABB(Vector3(-200, -1, -50), Vector3(400, 3, 100))
	z.speed_factor = factor
	return z


func _hero(zones: Array) -> HeroBody:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	var root: Node3D = NetFixtures.course_scene().instantiate()
	vp.add_child(root)
	var h := HeroBody.new()
	h.setup(MovementDef.new(), Vector3(0.0, 0.05, 0.0), true)
	h.motor.water_zones = zones
	root.add_child(h)
	h.place()
	return h


func _speed(h: HeroBody, scale: float = 1.0) -> float:
	var cmd := InputCommand.new()
	cmd.move = Vector2(0.0, 1.0)
	cmd.yaw = PI / 2.0
	h.state.speed_scale = scale
	for t in 30:
		h.step(cmd, DT)
	return Vector2(h.state.velocity.x, h.state.velocity.z).length()


func test_zone_containment() -> void:
	var md := load(MAP_PATH) as MapDef
	assert_int(md.water_zones.size()).is_equal(2)  # Halo Dock + Cinder Dock
	var z := md.water_zones[0]
	assert_float(z.speed_factor).is_equal(0.85)
	var c := z.bounds.get_center()
	assert_bool(z.contains(Vector3(c.x, 0.05, c.z))).is_true()
	assert_bool(z.contains(Vector3(c.x + 14.0, 0.05, c.z))).is_false()  # beyond the 26 m footprint
	assert_bool(z.contains(Vector3(c.x, 3.0, c.z))).is_false()  # jumped clear
	assert_float(md.water_factor_at(Vector3(c.x, 0.05, c.z))).is_equal(0.85)
	assert_float(md.water_factor_at(Vector3(0, 0.05, -210))).is_equal(1.0)


func test_overlapping_zones_take_the_strongest() -> void:
	assert_float(WaterZoneDef.factor_at([_zone(0.85), _zone(0.7)], Vector3(0, 0, 0))).is_equal(0.7)


func test_speed_in_water_is_85_percent() -> void:
	await get_tree().physics_frame
	var dry := _speed(_hero([]))
	var wet := _speed(_hero([_zone()]))
	assert_float(wet).is_equal_approx(dry * 0.85, 0.01)


func test_strongest_slow_not_multiplied() -> void:
	assert_float(WaterZoneDef.combine(0.7, 0.85)).is_equal_approx(0.7, 0.0001)  # ability slow wins
	assert_float(WaterZoneDef.combine(0.9, 0.85)).is_equal_approx(0.85, 0.0001)  # water wins
	assert_float(WaterZoneDef.combine(1.0, 0.85)).is_equal_approx(0.85, 0.0001)
	assert_float(WaterZoneDef.combine(0.0, 0.85)).is_equal(0.0)  # root stays rooted
	assert_float(WaterZoneDef.combine(1.2, 1.0)).is_equal_approx(1.2, 0.0001)  # haste untouched dry


func test_ability_slow_in_water_runs_at_the_stronger_slow() -> void:
	await get_tree().physics_frame
	var dry := _speed(_hero([]))
	var wet_slowed := _speed(_hero([_zone()]), 0.7)
	assert_float(wet_slowed).is_equal_approx(dry * 0.7, 0.01)


func test_prediction_matches_server_motor_path() -> void:
	await get_tree().physics_frame
	var server := _hero([_zone()])
	var client := _hero([_zone()])
	var predictor := Predictor.new(NetConfig.new(), client)
	var cmd := InputCommand.new()
	cmd.move = Vector2(0.3, 1.0)
	cmd.yaw = PI / 2.0
	for t in 60:
		cmd.yaw = PI / 2.0 + 0.02 * t
		cmd.seq = t + 1
		server.step(cmd, DT)
		predictor.predict(cmd)
		assert_vector(client.state.position).is_equal(server.state.position)
		assert_vector(client.state.velocity).is_equal(server.state.velocity)


func test_water_fx_entry_edge_and_volume_follow_intensity() -> void:
	assert_bool(WaterFx.entered(false, true)).is_true()
	assert_bool(WaterFx.entered(true, true)).is_false()
	assert_bool(WaterFx.entered(true, false)).is_false()
	assert_float(WaterFx.wade_db(0.0, -20.0)).is_less(-60.0)
	assert_float(WaterFx.wade_db(1.0, -20.0)).is_equal_approx(-20.0, 0.001)
	assert_float(WaterFx.wade_db(0.5, -20.0)).is_less(-20.0)
