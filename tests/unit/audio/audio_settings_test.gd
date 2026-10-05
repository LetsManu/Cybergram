extends GdUnitTestSuite
## W21-A1: new [audio] keys (music, voice, ambient, night_mode, reduce_music)
## save / load, old configs keep defaults, bus layout, night mode and code ducks.

const TMP := "user://w21_a1_settings_test.cfg"


func after_test() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_new_keys_round_trip() -> void:
	var a := GameSettings.new()
	a.music_volume = 0.35
	a.voice_volume = 0.6
	a.ambient_volume = 0.25
	a.night_mode = true
	a.reduce_music = true
	a.save(TMP)
	var b := GameSettings.new()
	b.load_from_disk(TMP)
	assert_float(b.music_volume).is_equal_approx(0.35, 0.0001)
	assert_float(b.voice_volume).is_equal_approx(0.6, 0.0001)
	assert_float(b.ambient_volume).is_equal_approx(0.25, 0.0001)
	assert_bool(b.night_mode).is_true()
	assert_bool(b.reduce_music).is_true()


func test_old_config_keeps_new_defaults_and_old_values() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", 0.5)
	cfg.set_value("audio", "effects", 0.4)
	cfg.set_value("audio", "ui", 0.3)
	cfg.save(TMP)
	var s := GameSettings.new()
	s.load_from_disk(TMP)
	assert_float(s.master_volume).is_equal_approx(0.5, 0.0001)
	assert_float(s.effects_volume).is_equal_approx(0.4, 0.0001)
	assert_float(s.ui_volume).is_equal_approx(0.3, 0.0001)
	assert_float(s.music_volume).is_equal_approx(0.7, 0.0001)
	assert_float(s.voice_volume).is_equal_approx(1.0, 0.0001)
	assert_float(s.ambient_volume).is_equal_approx(0.8, 0.0001)
	assert_bool(s.night_mode).is_false()
	assert_bool(s.reduce_music).is_false()


func test_out_of_range_values_are_clamped() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", 7.0)
	cfg.set_value("audio", "voice", -1.0)
	cfg.save(TMP)
	var s := GameSettings.new()
	s.load_from_disk(TMP)
	assert_float(s.music_volume).is_equal(1.0)
	assert_float(s.voice_volume).is_equal(0.0)


func test_bus_layout_and_sends() -> void:
	GameSettings.ensure_buses()
	assert_int(GameSettings.ensure_buses()).is_equal(0)
	for entry in GameSettings.BUS_LAYOUT:
		var idx := AudioServer.get_bus_index(entry[0])
		assert_int(idx).is_greater(0)
		assert_str(String(AudioServer.get_bus_send(idx))).is_equal(String(entry[1]))
	var music := AudioServer.get_bus_index(GameSettings.BUS_MUSIC)
	var comp := AudioServer.get_bus_effect(music, 1) as AudioEffectCompressor
	assert_object(comp).is_not_null()
	assert_str(String(comp.sidechain)).is_equal("Voice")
	var master := AudioServer.get_bus_index(&"Master")
	var found_limiter := false
	for i in AudioServer.get_bus_effect_count(master):
		var fx := AudioServer.get_bus_effect(master, i)
		if fx is AudioEffectHardLimiter:
			found_limiter = true
			assert_float((fx as AudioEffectHardLimiter).ceiling_db).is_equal(-1.0)
	assert_bool(found_limiter).is_true()


func test_night_mode_toggles_the_master_compressor() -> void:
	var s := GameSettings.new()
	s.night_mode = true
	s.apply_audio()
	var master := AudioServer.get_bus_index(&"Master")
	assert_bool(AudioServer.is_bus_effect_enabled(master, GameSettings.FX_MASTER_NIGHT)).is_true()
	s.night_mode = false
	s.apply_audio()
	assert_bool(AudioServer.is_bus_effect_enabled(master, GameSettings.FX_MASTER_NIGHT)).is_false()


func test_code_duck_never_boosts() -> void:
	GameSettings.ensure_buses()
	var idx := AudioServer.get_bus_index(GameSettings.BUS_AMBIENT)
	GameSettings.set_bus_duck_db(GameSettings.BUS_AMBIENT, -3.0)
	assert_float((AudioServer.get_bus_effect(idx, 0) as AudioEffectAmplify).volume_db).is_equal(-3.0)
	GameSettings.set_bus_duck_db(GameSettings.BUS_AMBIENT, 2.0)
	assert_float((AudioServer.get_bus_effect(idx, 0) as AudioEffectAmplify).volume_db).is_equal(0.0)
