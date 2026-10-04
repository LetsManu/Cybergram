extends GdUnitTestSuite
## LobbyStatusWriter: anonymous counts only, atomic file, disabled without a path.


func _tmp() -> String:
	return OS.get_cache_dir().path_join("cybergram_status_test_%d.json" % Time.get_ticks_usec())


func test_build_in_lobby_counts_players_as_lobby() -> void:
	var d: Dictionary = JSON.parse_string(LobbyStatusWriter.build(3, false, 0, 7))
	assert_int(int(d["online"])).is_equal(3)
	assert_int(int(d["in_lobby"])).is_equal(3)
	assert_int(int(d["in_match"])).is_equal(0)


func test_build_in_match_counts_players_as_match() -> void:
	var d: Dictionary = JSON.parse_string(LobbyStatusWriter.build(4, true, 0, 7))
	assert_int(int(d["in_match"])).is_equal(4)
	assert_int(int(d["in_lobby"])).is_equal(0)


func test_build_has_no_names_or_ids() -> void:
	var d: Dictionary = JSON.parse_string(LobbyStatusWriter.build(2, false, 0, 1))
	for key: String in d:
		assert_bool(key in ["online", "in_lobby", "in_match", "max_players", "updated"]).is_true()


func test_disabled_without_path_writes_nothing() -> void:
	var w := LobbyStatusWriter.new("")
	if w.enabled():
		return  # CYBERGRAM_STATUS_FILE is set in this environment
	assert_bool(w.tick(99.0, 1, false, 0)).is_false()


func test_tick_writes_on_change_and_skips_unchanged() -> void:
	var path: String = _tmp()
	var w := LobbyStatusWriter.new(path)
	assert_bool(w.tick(0.1, 2, false, 0)).is_true()
	assert_bool(w.tick(0.1, 2, false, 0)).is_false()
	assert_bool(w.tick(0.1, 3, false, 0)).is_true()
	assert_bool(w.tick(LobbyStatusWriter.REFRESH_S, 3, false, 0)).is_true()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_int(int(d["online"])).is_equal(3)
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()
	DirAccess.remove_absolute(path)


func test_unwritable_path_returns_false() -> void:
	var w := LobbyStatusWriter.new("/nonexistent_dir_cybergram/status.json")
	assert_bool(w.write_now("{}")).is_false()
