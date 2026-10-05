extends GdUnitTestSuite
## W15 Discord Rich Presence: opt-in only, configured app id only, and the
## activity never carries names, ids or the server address.


func test_off_without_opt_in_or_app_id() -> void:
	var def := PresenceDef.new()
	def.discord_app_id = "123456789012345678"
	var p := GamePresence.new()
	p.setup(false, def)
	assert_bool(p.enabled).is_false()
	p.apply(GamePresence.State.IN_LOBBY)  # silently nothing
	p.free()
	var q := GamePresence.new()
	q.setup(true, PresenceDef.new())  # placeholder: no app id yet
	assert_bool(q.enabled).is_false()
	q.free()


func test_default_config_is_the_placeholder() -> void:
	assert_str(PresenceDef.load_default().discord_app_id).is_equal("")


func test_activity_states() -> void:
	assert_str(str(GamePresence.activity_for(GamePresence.State.IN_LAUNCHER, "").details)).is_equal("In launcher")
	assert_str(str(GamePresence.activity_for(GamePresence.State.IN_LOBBY, "").details)).is_equal("In lobby")
	var m := GamePresence.activity_for(GamePresence.State.IN_MATCH, "Quick 3v3", 1000)
	assert_str(str(m.details)).is_equal("In match (Quick 3v3)")
	assert_int(int(m.timestamps.start)).is_equal(1000)


func test_activity_has_nothing_personal() -> void:
	var a := GamePresence.activity_for(GamePresence.State.IN_MATCH, "Neo#1A2B cyber.djboeck.at:7777", 5)
	assert_str(str(a.details)).is_equal("In match")
	for k: String in a:
		assert_bool(k in ["details", "timestamps", "assets"]).is_true()
	assert_bool(str(a).contains("djboeck") or str(a).contains("Neo")).is_false()


func test_mode_of_args() -> void:
	assert_str(GamePresence.mode_of(PackedStringArray(["--connect", "h:1", "--token", "5"]))).is_equal("Online")
	assert_str(GamePresence.mode_of(PackedStringArray(["--map", "slice", "--bots"]))).is_equal("Quick 3v3")
	assert_str(GamePresence.mode_of(PackedStringArray(["--hero", "sable"]))).is_equal("vs Bots")
	assert_str(GamePresence.mode_of(PackedStringArray(["--map", "test_course"]))).is_equal("Test course")


func test_vendored_client_fails_silently_headless() -> void:
	var def := PresenceDef.new()
	def.discord_app_id = "123456789012345678"
	var p := GamePresence.new()
	p.setup(true, def)
	assert_bool(p.enabled).is_true()
	add_child(p)
	p.apply(GamePresence.State.IN_LOBBY)
	await get_tree().process_frame
	assert_bool(p.get_child(0).is_processing()).is_false()  # headless: the client stays idle
	p.queue_free()
	await get_tree().process_frame
