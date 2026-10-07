extends GdUnitTestSuite
## LookProfile (docs/lookdev.md): every shipped look loads, stays inside its
## ranges and readability floors, selects from --look, and the panel shader's
## look-dev uniforms default to the pre-look-dev panel (no --look = no change).

const PANEL := "res://assets/shaders/spatial_env_panel.gdshader"


func test_every_profile_loads_and_validates() -> void:
	for key: String in LookProfile.PROFILES:
		var p := LookProfile.load_id(key)
		assert_object(p).override_failure_message("look %s does not load" % key).is_not_null()
		assert_str(p.id).is_equal(key)
		assert_array(Array(p.validate())).override_failure_message("look %s: %s" % [key, p.validate()]).is_empty()


func test_values_stay_in_range() -> void:
	for key: String in LookProfile.PROFILES:
		var p := LookProfile.load_id(key)
		assert_float(p.glow_threshold).is_greater_equal(1.1)  # art bible §10.3
		assert_float(p.emissive_cap).is_less_equal(1.5)  # Set-piece tier, §4.6
		assert_float(p.sun_energy).is_between(0.45, 3.0)  # AmbientMood readability floor
		assert_float(p.ambient_energy).is_between(0.3, 1.5)
		assert_float(p.shadow_value).is_between(0.2, 0.9)
		assert_float(p.fog_density).is_between(0.0, 0.02)
		assert_float(p.contact_ao_min).is_between(0.2, 1.0)
		assert_float(p.floor_roughness).is_between(0.0, 1.0)


func test_validate_flags_a_dark_profile() -> void:
	var p := LookProfile.new()
	p.sun_energy = 0.3
	p.fill_energy = 0.0
	p.ambient_energy = 0.3
	p.glow_threshold = 0.9
	assert_int(p.validate().size()).is_equal(2)


func test_look_flag_parsing() -> void:
	assert_str(LookProfile.id_from_args(PackedStringArray(["--map", "slice", "--look", "B"]))).is_equal("b")
	assert_str(LookProfile.id_from_args(PackedStringArray(["--look=c"]))).is_equal("c")
	assert_str(LookProfile.id_from_args(PackedStringArray(["--map", "slice"]))).is_equal("")
	assert_object(LookProfile.load_id("")).is_null()
	assert_object(LookProfile.load_id("off")).is_null()
	assert_object(LookProfile.load_id("current")).is_null()


func test_grade_is_identity_at_zero_and_clamped() -> void:
	var p := LookProfile.new()
	p.grade_curve = 0.0
	p.grade_shadow_amount = 0.0
	p.grade_highlight_amount = 0.0
	var c := Color(0.3, 0.5, 0.7)
	assert_bool(p.grade(c).is_equal_approx(c)).is_true()
	var g := LookProfile.load_id("a").grade(Color(1, 1, 1))
	assert_float(g.r).is_less_equal(1.0)


func test_panel_look_uniform_defaults_keep_the_old_panel() -> void:
	var src := FileAccess.get_file_as_string(PANEL)
	for d in ["wall_value = 1.0", "wall_saturation = 1.0", "floor_value = 1.0", "albedo_noise : hint_range(0.0, 0.3) = 0.0",
			"edge_wear : hint_range(0.0, 1.0) = 0.0", "contact_ao_min : hint_range(0.2, 1.0) = 0.72",
			"spec_wall : hint_range(0.0, 2.0) = 0.0", "spec_floor : hint_range(0.0, 2.0) = 0.0",
			"floor_env_specular : hint_range(0.0, 1.0) = 0.0"]:
		assert_str(src).override_failure_message("panel default changed: %s" % d).contains(d)


func test_no_flag_selects_the_default_look() -> void:
	LookProfile.override_id = ""
	var p := LookProfile.active()  # the test runner passes no --look
	assert_object(p).is_not_null()
	assert_str(p.id).is_equal(LookProfile.DEFAULT_ID)


func test_default_look_keeps_map_neon_below_bloom() -> void:
	# Owner pick: Neon Night's glow on Signal emissives only; map neon / trims stay
	# Accent tier (<= 1.0, art bible §4.6), so they never cross the 1.1 threshold.
	var p := LookProfile.load_id(LookProfile.DEFAULT_ID)
	assert_float(p.emissive_cap).is_less_equal(1.0)
	assert_float(0.9 * p.trim_gain).is_less(p.glow_threshold)
