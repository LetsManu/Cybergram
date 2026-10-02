extends GdUnitTestSuite
## The shipped game_session.tscn boots offline (server in an isolated world,
## client, two dummies) and runs ticks without errors.


func test_offline_session_boots_and_replicates_dummies() -> void:
	var session: GameSession = auto_free(load("res://src/gameplay/world/game_session.tscn").instantiate())
	add_child(session)
	await get_tree().physics_frame
	for i in 20:
		session.step_tick()
	assert_object(session.client.predictor).is_not_null()
	assert_int(session.client.view_count()).is_equal(2)
	assert_int(session.server.registry.count()).is_equal(3)
	assert_str(session.debug_text()).contains("corrections")


func test_launch_config_parses_server_and_net_sim() -> void:
	var c := LaunchConfig.parse(PackedStringArray(["--net-sim", "100ms_2pct", "--quit-after-ticks", "90"]), false)
	assert_int(c.mode).is_equal(LaunchConfig.Mode.OFFLINE)
	assert_str(c.net_sim_name).is_equal("100ms_2pct")
	assert_int(c.quit_after_ticks).is_equal(90)
	assert_int(LaunchConfig.parse(PackedStringArray(), true).mode).is_equal(LaunchConfig.Mode.DEDICATED)
	assert_int(LaunchConfig.parse(PackedStringArray(["--server"]), false).mode).is_equal(LaunchConfig.Mode.DEDICATED)
