class_name MenuStyle
extends RefCounted
## Compatibility shim over UiKit (src/ui/theme/ui_kit.gd, design/ux/ui-kit.md)
## for the menu screens written before the kit. New code calls UiKit directly.
##
## Example:
##   add_child(MenuStyle.label(tr("HUD_PROFILE_TITLE"), 28, HudPalette.TEXT))
##   add_child(MenuStyle.button(tr("HUD_PROFILE_SAVE"), _save, true))


static func label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, &"body", color, align)
	l.add_theme_font_size_override("font_size", size)
	return l


## A menu button; `primary` = the kit's filled violet call to action.
static func button(text: String, on_press: Callable, primary := false, height := 0) -> Button:
	return UiKit.button(text, on_press, &"primary" if primary else &"secondary", height)


## Swatch-style button tinted `bg` (emblem / accent pickers).
static func style_button(b: BaseButton, bg: Color) -> void:
	UiKit.swatch_button(b, bg)


## A translucent panel with the kit keyline.
static func panel(bg := HudPalette.PANEL_STRONG, pad := 12) -> StyleBoxFlat:
	return UiKit.panel_box(bg if bg != HudPalette.PANEL_STRONG else UiKit.tokens().panel, pad)


## A PanelContainer with `panel()` style.
static func panel_container(bg := HudPalette.PANEL_STRONG, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel(bg, pad))
	return p


static func spacer(h: int) -> Control:
	return UiKit.spacer(h)


## Line edit in the kit look.
static func line_edit(placeholder: String, max_len: int) -> LineEdit:
	return UiKit.line_edit(placeholder, max_len)
