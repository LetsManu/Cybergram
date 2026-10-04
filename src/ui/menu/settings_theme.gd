class_name SettingsTheme
extends RefCounted
## Theme for the settings panel, built from HudPalette tokens (night-ink panels,
## 1 px light keylines, team-blue accent for focus / selection).

const ACCENT := Color("#2E86FF")


static func _box(bg: Color, border: Color, bw: int = 1, pad_h: int = 12, pad_v: int = 6) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(bw)
	b.set_corner_radius_all(3)
	b.content_margin_left = pad_h
	b.content_margin_right = pad_h
	b.content_margin_top = pad_v
	b.content_margin_bottom = pad_v
	return b


## The shared theme (Button, OptionButton, CheckButton, HSlider, Label, popup).
static func build() -> Theme:
	var t := Theme.new()
	var idle := _box(Color(HudPalette.PANEL_STRONG, 0.9), HudPalette.KEYLINE)
	var hover := _box(Color(0.09, 0.12, 0.2, 0.95), HudPalette.TEXT_DIM)
	var press := _box(Color(ACCENT, 0.55), ACCENT)
	var focus := _box(Color(0, 0, 0, 0), ACCENT, 2)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, idle)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, press)
		t.set_stylebox("hover_pressed", cls, press)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox("disabled", cls, idle)
		t.set_color("font_color", cls, HudPalette.TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, HudPalette.TEXT_OFF)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", focus)
	t.set_color("font_color", "CheckButton", HudPalette.TEXT_DIM)
	t.set_color("font_pressed_color", "CheckButton", HudPalette.TEXT)
	t.set_color("font_hover_color", "CheckButton", HudPalette.TEXT)
	t.set_color("font_focus_color", "CheckButton", HudPalette.TEXT)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.set_corner_radius_all(2)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(2)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_color("font_color", "Label", HudPalette.TEXT)
	t.set_stylebox("panel", "PopupMenu", _box(HudPalette.PANEL_STRONG, HudPalette.KEYLINE))
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.5), ACCENT, 0, 8, 4))
	t.set_color("font_color", "PopupMenu", HudPalette.TEXT)
	return t


## Tab content frame style.
static func frame() -> StyleBoxFlat:
	return _box(Color(HudPalette.PANEL_STRONG, 0.9), HudPalette.KEYLINE, 1, 16, 12)
