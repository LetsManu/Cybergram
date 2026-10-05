class_name SettingsTabVideo
extends SettingsTab
## Video tab: window mode, render scale, VSync, FPS cap, quality preset.


func build() -> void:
	section(tr("HUD_SET_TAB_VIDEO"))
	option(tr("HUD_SET_WINDOW_MODE"), [tr("HUD_SET_WM_WINDOWED"), tr("HUD_SET_WM_FULLSCREEN"),
		tr("HUD_SET_WM_BORDERLESS")], s.window_mode, func(i: int) -> void: s.window_mode = i)
	slider(tr("HUD_SET_RENDER_SCALE"), GameSettings.RENDER_SCALE_MIN * 100.0, GameSettings.RENDER_SCALE_MAX * 100.0,
		5.0, s.render_scale * 100.0, "%.0f%%", func(v: float) -> void: s.render_scale = v / 100.0)
	check(tr("HUD_SET_VSYNC"), s.vsync, func(on: bool) -> void: s.vsync = on)
	var caps: Array = []
	for c in GameSettings.FPS_CAPS:
		caps.append(tr("HUD_SET_FPS_UNLIMITED") if c == 0 else str(c))
	option(tr("HUD_SET_FPS_CAP"), caps, s.fps_cap_index, func(i: int) -> void: s.fps_cap_index = i)
	option(tr("HUD_SET_QUALITY"), [tr("HUD_SET_Q_LOW"), tr("HUD_SET_Q_MEDIUM"), tr("HUD_SET_Q_HIGH"),
		tr("HUD_SET_Q_ULTRA")], s.graphics_quality, func(i: int) -> void: s.graphics_quality = i)
	# --- W18-LIFE ---
	option(tr("HUD_SET_AMBIENCE"), [tr("HUD_SET_Q_LOW"), tr("HUD_SET_Q_MEDIUM"), tr("HUD_SET_Q_HIGH")],
		s.ambient_level, func(i: int) -> void: s.ambient_level = i)
	check(tr("HUD_SET_AMBIENT_RAIN"), s.ambient_rain, func(on: bool) -> void: s.ambient_rain = on)
	# --- end W18-LIFE ---
	check(tr("HUD_SET_REDUCE_MOTION"), s.reduce_motion, func(on: bool) -> void: s.reduce_motion = on)
