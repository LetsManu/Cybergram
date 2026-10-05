extends GdUnitTestSuite
## HeroPlayHistory: local per-hero matches / minutes / last played, and the
## GameSettings window size keys the launcher writes.

const TMP := "user://test_hero_play_history.cfg"


func before_test() -> void:
	DirAccess.remove_absolute(TMP)


func after_test() -> void:
	DirAccess.remove_absolute(TMP)


func test_stem_strips_prefix() -> void:
	assert_str(HeroPlayHistory.stem_of(&"hero_Ryker_Vance")).is_equal("ryker_vance")


func test_record_accumulates() -> void:
	assert_bool(HeroPlayHistory.record(&"hero_sable", 12.4, TMP, 1000)).is_true()
	assert_bool(HeroPlayHistory.record(&"hero_sable", 0.2, TMP, 2000)).is_true()
	var e := HeroPlayHistory.get_entry(&"hero_sable", TMP)
	assert_int(e.matches).is_equal(2)
	assert_int(e.minutes).is_equal(13)  # 12 + at least 1
	assert_int(e.last_played).is_equal(2000)


func test_heroes_are_separate_and_empty_id_rejected() -> void:
	HeroPlayHistory.record(&"hero_hex", 5.0, TMP, 1)
	assert_int(HeroPlayHistory.get_entry(&"hero_sable", TMP).matches).is_equal(0)
	assert_bool(HeroPlayHistory.record(&"", 5.0, TMP)).is_false()


func test_settings_window_size_round_trip() -> void:
	var s := GameSettings.new()
	s.window_w = 1600
	s.window_h = 900
	var cfg := ConfigFile.new()
	s.write_config(cfg)
	var back := GameSettings.new()
	back.read_config(cfg)
	assert_int(back.window_w).is_equal(1600)
	assert_int(back.window_h).is_equal(900)
