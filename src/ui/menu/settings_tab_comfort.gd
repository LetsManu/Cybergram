class_name SettingsTabComfort
extends SettingsTab
## Comfort tab (W16-COMFORT): options against motion sickness. Values live in
## GameSettings' [comfort] section; the tuning rules in ComfortRulesDef.

var rules: ComfortRulesDef = ComfortRulesDef.load_default()


func build() -> void:
	section(tr("HUD_SET_SEC_COMFORT_VIEW"))
	slider(tr("HUD_SET_COMFORT_RECOIL"), 0.0, 100.0, 5.0, s.comfort_camera_recoil * 100.0, "%.0f%%",
		func(v: float) -> void: s.comfort_camera_recoil = v / 100.0)
	check(tr("HUD_SET_COMFORT_BOB"), s.comfort_weapon_bob, func(on: bool) -> void: s.comfort_weapon_bob = on)
	slider(tr("HUD_SET_FOV"), GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0, s.fov_deg, "%.0f°",
		func(v: float) -> void: s.fov_deg = v)
	var note := UiKit.label(tr("HUD_SET_COMFORT_NOTE"), &"small", HudPalette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	section(tr("HUD_SET_SEC_COMFORT_FX"))
	slider(tr("HUD_SET_COMFORT_FX"), 0.0, 100.0, 5.0, s.comfort_fx_intensity * 100.0, "%.0f%%",
		func(v: float) -> void: s.comfort_fx_intensity = v / 100.0)
	check(tr("HUD_SET_REDUCE_MOTION"), s.reduce_motion, func(on: bool) -> void: s.reduce_motion = on)
	section(tr("HUD_SET_SEC_COMFORT_DOT"))
	check(tr("HUD_SET_COMFORT_DOT"), s.comfort_center_dot, func(on: bool) -> void: s.comfort_center_dot = on)
	slider(tr("HUD_SET_COMFORT_DOT_SIZE"), GameSettings.DOT_SIZE_MIN, GameSettings.DOT_SIZE_MAX, 1.0,
		s.comfort_dot_size_px, "%.0f px", func(v: float) -> void: s.comfort_dot_size_px = v)
	slider(tr("HUD_SET_COMFORT_DOT_OPACITY"), GameSettings.DOT_OPACITY_MIN * 100.0, 100.0, 5.0,
		s.comfort_dot_opacity * 100.0, "%.0f%%", func(v: float) -> void: s.comfort_dot_opacity = v / 100.0)
	section(tr("HUD_SET_SEC_COMFORT_MOVE"))
	check(tr("HUD_SET_COMFORT_SMOOTH"), s.comfort_smooth_corrections,
		func(on: bool) -> void: s.comfort_smooth_corrections = on)
	slider(tr("HUD_SET_COMFORT_VIGNETTE"), 0.0, 100.0, 5.0, s.comfort_vignette * 100.0, "%.0f%%",
		func(v: float) -> void: s.comfort_vignette = v / 100.0)
	add_child(HSeparator.new())
	var b := UiKit.button(tr("HUD_SET_COMFORT_PRESET"), _apply_preset, &"primary", 44)
	add_child(b)


func _apply_preset() -> void:
	s.apply_comfort_preset(rules)
	commit.call()
	for c in get_children():
		c.queue_free()
	build.call_deferred()
