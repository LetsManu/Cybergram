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


func test_no_argument_launch_is_a_playable_full_map_match_vs_bots() -> void:
	var c := LaunchConfig.parse(PackedStringArray(), false)
	assert_int(c.mode).is_equal(LaunchConfig.Mode.OFFLINE)
	assert_str(c.map_name).is_equal("front")  # W14: Shardline Front, 5v5
	assert_int(GameSession.load_map_def(c.map_name).match_rules.team_size).is_equal(5)
	assert_int(GameSession.load_map_def("slice").match_rules.team_size).is_equal(3)
	# Online server and --bots-only default to the full map as well.
	assert_str(LaunchConfig.parse(PackedStringArray(["--bots-only"]), false).map_name).is_equal("front")
	# Quick Match: the slice with bots.
	var q := LaunchConfig.parse(PackedStringArray(["--map", "slice", "--bots"]), false)
	assert_str(q.map_name).is_equal("slice")
	assert_bool(q.bots).is_true()
	assert_bool(c.bots).is_true()
	assert_bool(c.bots_only).is_false()
	assert_str(c.hero_id).is_equal("")  # GameSession.DEFAULT_PLAYER_HERO = Vesper Loom
	var b := LaunchConfig.parse(PackedStringArray(["--hero", "brannoc"]), false)
	assert_str(b.hero_id).is_equal("brannoc")
	assert_bool(b.bots).is_true()
	# The movement test course stays reachable, without bots.
	var t := LaunchConfig.parse(PackedStringArray(["--map", "test_course"]), false)
	assert_str(t.map_name).is_equal("")
	assert_bool(t.bots).is_false()
	# An explicit --map slice keeps the bot-free debug / evidence setups.
	assert_bool(LaunchConfig.parse(PackedStringArray(["--map", "slice"]), false).bots).is_false()
