extends GdUnitTestSuite
## W16-COMFORT: SpreadModel parity with WeaponSim, projection, reconcile; and the
## colour-blind damage colours.

const HZ := 60


func _weapon() -> WeaponDef:
	var w := WeaponDef.new()
	w.spread_base_deg = 0.5
	w.spread_bloom_deg = 0.3
	w.spread_max_deg = 2.0
	w.spread_recovery_deg_s = 6.0
	w.spread_recovery_delay_s = 0.15
	return w


func _cmd(fire: bool) -> InputCommand:
	var c := InputCommand.new()
	c.buttons = InputCommand.BTN_FIRE if fire else 0
	return c


func test_parity_with_weapon_sim_for_the_same_shot_sequence() -> void:
	var w := _weapon()
	var sim := WeaponSim.new(w, HZ, 7)
	var model := SpreadModel.new(w, HZ)
	assert_float(model.spread_deg).is_equal(sim.spread_deg)
	# 40 ticks of fire, 60 idle, 20 fire, 90 idle
	var pattern: Array[bool] = []
	for i in 40: pattern.append(true)
	for i in 60: pattern.append(false)
	for i in 20: pattern.append(true)
	for i in 90: pattern.append(false)
	for t in pattern.size():
		var fired := sim.step(_cmd(pattern[t]), t + 1, true)
		model.step(fired)
		assert_float(model.spread_deg).is_equal_approx(sim.spread_deg, 0.0001)


func test_parity_with_custom_weapon_and_recoil_mult() -> void:
	var w := _weapon()
	var sim := WeaponSim.new(w, HZ, 3)
	sim.recoil_mult = 0.5
	var model := SpreadModel.new(w, HZ)
	model.recoil_mult = 0.5
	for t in 200:
		var fired := sim.step(_cmd(t < 30 or (t > 80 and t < 100)), t + 1, true)
		model.step(fired)
		assert_float(model.spread_deg).is_equal_approx(sim.spread_deg, 0.0001)
	assert_float(model.spread_deg).is_equal_approx(w.spread_base_deg, 0.0001)  # recovered


func test_resets() -> void:
	var w := _weapon()
	var m := SpreadModel.new(w, HZ)
	for i in 10:
		m.step(true)
	assert_float(m.spread_deg).is_greater(w.spread_base_deg)
	m.reset()  # respawn
	assert_float(m.spread_deg).is_equal(w.spread_base_deg)
	for i in 10:
		m.step(true)
	var other := _weapon()
	other.spread_base_deg = 1.0
	m.set_weapon(other)  # weapon swap
	assert_float(m.spread_deg).is_equal(1.0)


func test_unconfirmed_predicted_shots_fall_back_to_base() -> void:
	var w := _weapon()
	var m := SpreadModel.new(w, HZ)
	m.reconcile(100.0, 0.016)
	for i in 6:
		m.step(true)
	m.reconcile(100.0, 0.3)  # no ammo drop yet
	assert_float(m.spread_deg).is_greater(w.spread_base_deg)
	m.reconcile(100.0, 0.3)  # still nothing after 0.6 s: they did not happen
	assert_float(m.spread_deg).is_equal(w.spread_base_deg)
	m.reconcile(100.0, 0.016)  # a snapshot with no predicted shots records the baseline
	for i in 6:
		m.step(true)
	m.reconcile(90.0, 0.3)  # ammo dropped: confirmed
	m.reconcile(90.0, 0.3)
	assert_float(m.spread_deg).is_greater(w.spread_base_deg)


func test_screen_radius_projection() -> void:
	# 45 deg at 90 deg vertical FOV reaches the top edge: half the viewport height.
	assert_float(SpreadModel.screen_radius_px(45.0, 90.0, 720.0)).is_equal_approx(360.0, 0.01)
	assert_float(SpreadModel.screen_radius_px(0.0, 90.0, 720.0)).is_equal(0.0)
	var a := SpreadModel.screen_radius_px(2.0, 90.0, 720.0)
	var b := SpreadModel.screen_radius_px(2.0, 120.0, 720.0)
	assert_float(b).is_less(a)  # a wider FOV shrinks the same cone
	assert_float(b).is_equal_approx(tan(deg_to_rad(2.0)) / tan(deg_to_rad(60.0)) * 360.0, 0.001)


func test_dynamic_crosshair_setting_round_trip() -> void:
	var s := GameSettings.new()
	assert_bool(s.crosshair_dynamic).is_true()
	s.crosshair_dynamic = false
	var cfg := ConfigFile.new()
	s.write_config(cfg)
	var b := GameSettings.new()
	b.read_config(cfg)
	assert_bool(b.crosshair_dynamic).is_false()


func test_damage_colour_follows_colourblind_preset() -> void:
	assert_object(HudPalette.damage_color(HudPalette.Preset.DEFAULT)).is_equal(HudPalette.DANGER)
	for p in [HudPalette.Preset.DEUTERANOPIA, HudPalette.Preset.PROTANOPIA, HudPalette.Preset.TRITANOPIA]:
		var c := HudPalette.damage_color(p)
		assert_object(c).is_equal(HudPalette.TEAM_COLORS[p][1])
		assert_object(c).is_not_equal(HudPalette.DANGER)
	# red-green presets must not use red-dominant, green-poor danger red
	assert_float(HudPalette.damage_color(HudPalette.Preset.DEUTERANOPIA).g).is_greater(0.5)
