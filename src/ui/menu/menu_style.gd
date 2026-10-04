class_name MenuStyle
extends RefCounted
## Shared look of the menu screens (main menu, profile, lobby, friends):
## labels, buttons and panels in the HUD palette (art bible §9).
##
## Example:
##   add_child(MenuStyle.label(tr("HUD_PROFILE_TITLE"), 28, HudPalette.TEXT))
##   add_child(MenuStyle.button(tr("HUD_PROFILE_SAVE"), _save, true))


static func label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A menu button; `primary` = the filled violet call to action.
static func button(text: String, on_press: Callable, primary := false, height := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = height if height > 0 else (52 if primary else 40)
	b.add_theme_font_size_override("font_size", 20 if primary else 15)
	style_button(b, Color(HudPalette.NEUTRAL, 0.85) if primary else HudPalette.PANEL_STRONG)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## Flat button styles from `bg` (hover / focus lighter, pressed accent rim).
static func style_button(b: BaseButton, bg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = HudPalette.KEYLINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.15)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.border_color = HudPalette.TEXT
	pressed.set_border_width_all(2)
	var disabled := sb.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(bg, bg.a * 0.45)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", _focus())
	b.add_theme_stylebox_override("disabled", disabled)


## A translucent panel with the light keyline.
static func panel(bg := HudPalette.PANEL_STRONG, pad := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = HudPalette.KEYLINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(pad)
	return sb


## A PanelContainer with `panel()` style.
static func panel_container(bg := HudPalette.PANEL_STRONG, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel(bg, pad))
	return p


static func spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


## Keyboard / gamepad focus ring.
static func _focus() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = HudPalette.TEXT
	f.set_border_width_all(2)
	f.set_corner_radius_all(4)
	return f


## Line edit in the menu look.
static func line_edit(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size.y = 36
	var sb := panel(Color(0.02, 0.025, 0.05, 0.9), 6)
	e.add_theme_stylebox_override("normal", sb)
	var f := sb.duplicate() as StyleBoxFlat
	f.border_color = HudPalette.TEXT
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_color_override("font_color", HudPalette.TEXT)
	e.add_theme_color_override("font_placeholder_color", HudPalette.TEXT_OFF)
	return e
