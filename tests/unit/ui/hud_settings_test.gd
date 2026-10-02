extends GdUnitTestSuite
## E12 HUD settings (design/ux/hud.md §13.2, §16): defaults, clamping, config
## round trip (in-memory ConfigFile, no disk) and launch-arg overrides.


func test_defaults() -> void:
	var s := HudSettings.new()
	assert_float(s.ui_scale).is_equal(1.0)
	assert_int(s.colorblind).is_equal(HudPalette.Preset.DEFAULT)
	assert_int(s.damage_numbers).is_equal(DamageNumberModel.Mode.COMPACT)
	assert_bool(s.net_graph).is_false()
	assert_bool(s.clamp_16_9).is_true()


func test_ui_scale_clamped_to_80_120() -> void:
	var s := HudSettings.new()
	s.set_ui_scale(3.0)
	assert_float(s.ui_scale).is_equal(HudSettings.SCALE_MAX)
	s.set_ui_scale(0.1)
	assert_float(s.ui_scale).is_equal(HudSettings.SCALE_MIN)


func test_config_round_trip() -> void:
	var a := HudSettings.new()
	a.set_ui_scale(1.1)
	a.colorblind = HudPalette.Preset.TRITANOPIA
	a.damage_numbers = DamageNumberModel.Mode.OFF
	a.plate_numbers = true
	a.clamp_16_9 = false
	var cfg := ConfigFile.new()
	a.write_config(cfg)
	var b := HudSettings.new()
	b.read_config(cfg)
	assert_float(b.ui_scale).is_equal_approx(1.1, 1e-6)
	assert_int(b.colorblind).is_equal(HudPalette.Preset.TRITANOPIA)
	assert_int(b.damage_numbers).is_equal(DamageNumberModel.Mode.OFF)
	assert_bool(b.plate_numbers).is_true()
	assert_bool(b.clamp_16_9).is_false()


func test_invalid_config_values_fall_back() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(HudSettings.SECTION, "colorblind", "sepia")
	cfg.set_value(HudSettings.SECTION, "damage_numbers", "loud")
	cfg.set_value(HudSettings.SECTION, "ui_scale", 9.0)
	var s := HudSettings.new()
	s.read_config(cfg)
	assert_int(s.colorblind).is_equal(HudPalette.Preset.DEFAULT)
	assert_int(s.damage_numbers).is_equal(DamageNumberModel.Mode.COMPACT)
	assert_float(s.ui_scale).is_equal(HudSettings.SCALE_MAX)


func test_launch_args_override() -> void:
	var s := HudSettings.new()
	s.apply_args(PackedStringArray(["--bots", "--ui-scale", "0.9", "--colorblind", "deuteranopia",
		"--damage-numbers", "full", "--net-graph", "--hud-scoreboard", "--hud-screenshot", "12", "a.png"]))
	assert_float(s.ui_scale).is_equal_approx(0.9, 1e-6)
	assert_int(s.colorblind).is_equal(HudPalette.Preset.DEUTERANOPIA)
	assert_int(s.damage_numbers).is_equal(DamageNumberModel.Mode.FULL)
	assert_bool(s.net_graph).is_true()
	assert_bool(s.debug_scoreboard).is_true()
	assert_int(s.debug_screenshots.size()).is_equal(1)
	assert_str(str(s.debug_screenshots[0][1])).is_equal("a.png")


func test_cycles_wrap() -> void:
	var s := HudSettings.new()
	for i in HudPalette.PRESET_IDS.size():
		s.cycle_colorblind()
	assert_int(s.colorblind).is_equal(HudPalette.Preset.DEFAULT)
	s.cycle_damage_numbers()
	assert_int(s.damage_numbers).is_equal(DamageNumberModel.Mode.FULL)
	s.cycle_damage_numbers()
	assert_int(s.damage_numbers).is_equal(DamageNumberModel.Mode.OFF)


func test_colorblind_presets_change_team_colours() -> void:
	for p in HudPalette.PRESET_IDS.size():
		assert_that(HudPalette.team_color(0, p)).is_not_equal(HudPalette.team_color(1, p))
	assert_that(HudPalette.team_color(1, HudPalette.Preset.DEUTERANOPIA)).is_not_equal(HudPalette.team_color(1, HudPalette.Preset.DEFAULT))
	assert_that(HudPalette.team_color(-1, HudPalette.Preset.TRITANOPIA)).is_equal(HudPalette.NEUTRAL)
	assert_int(HudPalette.preset_from_id("Protanopia")).is_equal(HudPalette.Preset.PROTANOPIA)
