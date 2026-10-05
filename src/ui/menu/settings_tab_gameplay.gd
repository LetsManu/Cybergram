class_name SettingsTabGameplay
extends SettingsTab
## Gameplay tab: crosshair style / colour (GameSettings) and the HUD options
## the F6-F9 keys also change (colour-blind preset, damage numbers, UI scale;
## HudSettings, [hud] section of settings.cfg).

var _hud: HudSettings
var _preview: SettingsCrosshairPreview


func build() -> void:
	_hud = HudSettings.load_user()
	section(tr("HUD_SET_TAB_GAMEPLAY"))
	option(tr("HUD_SET_CROSSHAIR_STYLE"), [tr("HUD_SET_XH_CROSS_DOT"), tr("HUD_SET_XH_CROSS"),
		tr("HUD_SET_XH_DOT"), tr("HUD_SET_XH_CIRCLE")], s.crosshair_style, func(i: int) -> void:
			s.crosshair_style = i
			_update_preview())
	var names := [tr("HUD_SET_COL_WHITE"), tr("HUD_SET_COL_GREEN"), tr("HUD_SET_COL_CYAN"),
		tr("HUD_SET_COL_YELLOW"), tr("HUD_SET_COL_MAGENTA"), tr("HUD_SET_COL_RED")]
	var row := _row(tr("HUD_SET_CROSSHAIR_COLOUR"))
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in names.size():
		o.add_icon_item(_swatch(GameSettings.CROSSHAIR_COLORS[i]), names[i])
	o.selected = s.crosshair_color
	o.item_selected.connect(func(i: int) -> void:
		s.crosshair_color = i
		_update_preview()
		commit.call())
	row.add_child(o)
	_preview = SettingsCrosshairPreview.new()
	row.add_child(_preview)
	_update_preview()
	check(tr("HUD_SET_XH_DYNAMIC"), s.crosshair_dynamic, func(on: bool) -> void: s.crosshair_dynamic = on)
	section(tr("HUD_SET_SEC_HUD"))
	option(tr("HUD_SET_DMG_NUMBERS"), [tr("HUD_DMG_OFF"), tr("HUD_DMG_COMPACT"), tr("HUD_DMG_FULL")],
		_hud.damage_numbers, func(i: int) -> void: _hud.damage_numbers = i; _save_hud())
	var cb: Array = []
	for k in HudPalette.PRESET_KEYS:
		cb.append(tr(k))
	option(tr("HUD_SET_COLORBLIND"), cb, _hud.colorblind, func(i: int) -> void: _hud.colorblind = i; _save_hud())
	slider(tr("HUD_SET_UI_SCALE"), HudSettings.SCALE_MIN * 100.0, HudSettings.SCALE_MAX * 100.0, 10.0,
		_hud.ui_scale * 100.0, "%.0f%%", func(v: float) -> void: _hud.set_ui_scale(v / 100.0); _save_hud())
	# --- W19-HUD: v0.12 text scale and idle fade (hud-v0.12.md §3, §4.3) ---
	slider(tr("HUD_SET_TEXT_SCALE"), HudSettings.TEXT_SCALE_MIN * 100.0, HudSettings.TEXT_SCALE_MAX * 100.0, 10.0,
		_hud.text_scale * 100.0, "%.0f%%", func(v: float) -> void: _hud.set_text_scale(v / 100.0); _save_hud())
	option(tr("HUD_SET_IDLE_FADE"), [tr("HUD_IDLE_FADE_OFF"), tr("HUD_IDLE_FADE_4"), tr("HUD_IDLE_FADE_8")],
		_hud.idle_fade, func(i: int) -> void: _hud.idle_fade = i; _save_hud())
	# --- end W19-HUD ---


func _swatch(c: Color) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _update_preview() -> void:
	_preview.style = s.crosshair_style
	_preview.color = GameSettings.CROSSHAIR_COLORS[s.crosshair_color]
	_preview.queue_redraw()


## Persists the [hud] section and tells a running HUD to re-read it.
func _save_hud() -> void:
	_hud.save_user()
	GameSettings.hud_revision += 1
