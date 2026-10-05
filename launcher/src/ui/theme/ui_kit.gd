class_name UiKit
extends RefCounted
## The Cybergram UI kit (design/ux/ui-kit.md): one palette + metrics resource
## (`TOKENS_PATH`, shared with the launcher), a Theme, button styles with
## hover / press tweens and a gamepad focus ring, cards with header strips,
## tab bars, toasts, modals, screen transitions and the animated background.
## Every animation goes through animate(), which honours
## GameSettings.reduce_motion (the end state is applied at once).
##
## Example:
##   root.theme = UiKit.theme()
##   root.add_child(UiKit.background())
##   var play := UiKit.button(tr("HUD_MENU_PLAY"), _play, &"play")
##   var c := UiKit.card(tr("HUD_NEWS_TITLE"))
##   UiKit.toast(root, tr("HUD_ACCOUNT_LOGGED_OUT"))
##   UiKit.transition_in(screen)

## Shared colours and metrics (the launcher loads the same file).
const TOKENS_PATH := "res://assets/ui/ui_kit_tokens.tres"
const DISPLAY_FONT_PATH := "res://assets/fonts/chakrapetch/ChakraPetch-SemiBold.ttf"
## Chakra Petch cuts by weight (static files; display_font() picks the nearest).
const DISPLAY_FONT_FILES := {
	500: "res://assets/fonts/chakrapetch/ChakraPetch-Medium.ttf",
	600: "res://assets/fonts/chakrapetch/ChakraPetch-SemiBold.ttf",
	700: "res://assets/fonts/chakrapetch/ChakraPetch-Bold.ttf"}
## IBM Plex Sans (variable, body text) and IBM Plex Mono (numbers, keys).
const BODY_FONT_PATH := "res://assets/fonts/ibmplexsans/IBMPlexSans-Variable.ttf"
const MONO_FONT_PATH := "res://assets/fonts/ibmplexmono/IBMPlexMono-Medium.ttf"
const BG_SHADER_PATH := "res://assets/shaders/canvas_ui_background.gdshader"
## Button styles accepted by button() / style_button().
const KINDS: Array[StringName] = [&"primary", &"secondary", &"ghost", &"danger", &"play"]
## Text roles accepted by label().
const ROLES: Array[StringName] = [&"display", &"title", &"heading", &"nav", &"body", &"small", &"caption"]
## Name of the toast lane a parent gets on its first toast.
const TOAST_LANE := &"UiKitToasts"

## Tests: -1 = follow GameSettings, 0 = motion on, 1 = reduce motion.
static var force_reduce_motion: int = -1

static var _tokens: UiKitTokens
static var _theme: Theme
static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


# --- tokens, motion ---------------------------------------------------------

## The shared tokens (cached; defaults when the file is missing).
static func tokens() -> UiKitTokens:
	if _tokens == null:
		var r := load(TOKENS_PATH) as UiKitTokens if ResourceLoader.exists(TOKENS_PATH) else null
		_tokens = r if r != null else UiKitTokens.new()
	return _tokens


## Drops the cached tokens / theme / fonts / icons (screens call it when they
## leave the tree, so no static Resource outlives the scene tree at exit;
## live controls keep their own references).
static func clear_cache() -> void:
	_tokens = null
	_theme = null
	_fonts.clear()
	_icons.clear()


## True when animations must be skipped (accessibility setting).
static func reduce_motion() -> bool:
	if force_reduce_motion >= 0:
		return force_reduce_motion == 1
	var gs: Script = _game_script(GAME_SETTINGS_PATH)
	if gs == null:
		return false
	return gs.call("shared").reduce_motion


## Game-only classes (GameSettings, UiSfx) are looked up by path so this file
## also compiles in the launcher project, which shares it but ships neither.
const GAME_SETTINGS_PATH := "res://src/core/app/game_settings.gd"
const UI_SFX_PATH := "res://src/gameplay/views/ui_sfx.gd"
static var _game_scripts: Dictionary = {}


static func _game_script(path: String) -> Script:
	if not _game_scripts.has(path):
		_game_scripts[path] = load(path) as Script if ResourceLoader.exists(path) else null
	return _game_scripts[path]


## Hover / click sounds when the game's UiSfx exists; a no-op in the launcher.
static func _attach_sfx(b: BaseButton) -> void:
	var sfx: Script = _game_script(UI_SFX_PATH)
	if sfx != null:
		sfx.call("attach", b)


## Tweens `target.prop` to `value` over `ms` (default motion_base), bound to
## `owner`. Under reduce motion, or outside the tree, sets it at once and
## returns null.
static func animate(owner: Node, target: Object, prop: String, value: Variant, ms: int = -1) -> Tween:
	if reduce_motion() or owner == null or not owner.is_inside_tree():
		target.set_indexed(prop, value)
		return null
	var tw := owner.create_tween()
	tw.tween_property(target, prop, value, (tokens().motion_base if ms < 0 else ms) / 1000.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw


## Fades `node` in (and slides it by `offset` when its parent is not a
## Container). Instant under reduce motion.
static func transition_in(node: CanvasItem, offset := Vector2(0, 24), ms: int = -1) -> void:
	var dur := tokens().motion_slow if ms < 0 else ms
	if reduce_motion() or not node.is_inside_tree():
		node.modulate.a = 1.0
		return
	node.modulate.a = 0.0
	animate(node, node, "modulate:a", 1.0, dur)
	var c := node as Control
	if c != null and not (c.get_parent() is Container) and offset != Vector2.ZERO:
		var end := c.position
		c.position = end + offset
		animate(c, c, "position", end, dur)


## Fades `node` out, then calls `then` (at once under reduce motion).
static func transition_out(node: CanvasItem, then: Callable, ms: int = -1) -> void:
	var tw := animate(node, node, "modulate:a", 0.0, tokens().motion_base if ms < 0 else ms)
	if tw == null:
		then.call()
	else:
		tw.finished.connect(then)


# --- fonts, labels ----------------------------------------------------------

## The display face (Chakra Petch) at `weight` (500-700 cuts; below 550 =
## Medium, 550-649 = SemiBold, else Bold) with `spacing` px between glyphs;
## Godot's default font, emboldened, if it is missing.
static func display_font(weight: int = 600, spacing: int = 2) -> Font:
	var key := "d%d/%d" % [weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var cut := 500 if weight < 550 else (600 if weight < 650 else 700)
	var path: String = DISPLAY_FONT_FILES[cut]
	var fv := FontVariation.new()
	var base := load(path) as Font if ResourceLoader.exists(path) else null
	if base != null:
		fv.base_font = base
	else:
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = clampf((weight - 400) / 500.0, 0.0, 1.0)
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


## The body face (IBM Plex Sans, variable) at `weight` (100-700).
static func body_font(weight: int = 400) -> Font:
	var key := "b%d" % weight
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	var base := load(BODY_FONT_PATH) as Font if ResourceLoader.exists(BODY_FONT_PATH) else null
	if base != null:
		fv.base_font = base
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight, ts.name_to_tag("wdth"): 100}
	else:
		fv.base_font = ThemeDB.fallback_font
	_fonts[key] = fv
	return fv


## The mono face (IBM Plex Mono Medium): numbers, timers, key letters.
static func mono_font(spacing: int = 0) -> Font:
	var key := "m%d" % spacing
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	var base := load(MONO_FONT_PATH) as Font if ResourceLoader.exists(MONO_FONT_PATH) else null
	fv.base_font = base if base != null else ThemeDB.fallback_font
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


## Letter spacing in px for a tracking of `em` at `size` px (the mockup's
## `letter-spacing: .22em`).
static func track(size: int, em: float) -> int:
	return roundi(size * em)


## An eyebrow: small brass caps in the display face, wide tracking.
static func eyebrow(text: String, color := Color(0, 0, 0, 0), size: int = 13) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", display_font(600, track(size, 0.26)))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color if color.a > 0.0 else tokens().accent)
	return l


## A key chip (Q / E / C / G): a 1 px dim-brass frame with a mono letter.
static func key_chip(key: String, side: int = 28) -> PanelContainer:
	var t := tokens()
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(side, side)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = t.accent_dim
	sb.set_border_width_all(1)
	sb.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", mono_font())
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", t.accent_hi)
	p.add_child(l)
	return p


## A 1 px horizontal hairline (`strong` = the separator tone).
static func hairline(strong := false) -> ColorRect:
	var r := ColorRect.new()
	r.color = tokens().line_strong if strong else tokens().line
	r.custom_minimum_size.y = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Font size of a text role (ROLES).
static func size_of(role: StringName) -> int:
	var t := tokens()
	match role:
		&"display":
			return t.size_display
		&"title":
			return t.size_title
		&"heading":
			return t.size_heading
		&"nav":
			return t.size_nav
		&"small":
			return t.size_small
		&"caption":
			return t.size_caption
		_:
			return t.size_body


## A label in a text role; display / title / heading / nav use the display
## face. `color` alpha 0 = the role's default colour.
static func label(text: String, role: StringName = &"body", color := Color(0, 0, 0, 0),
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var t := tokens()
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size_of(role))
	match role:
		&"display":
			l.add_theme_font_override("font", display_font(600, 1))
		&"title":
			l.add_theme_font_override("font", display_font(600, 1))
		&"heading":
			l.add_theme_font_override("font", display_font(600, 1))
		&"nav":
			l.add_theme_font_override("font", display_font(600, track(t.size_nav, 0.16)))
	var def := t.text if role in [&"display", &"title", &"heading", &"body"] else t.text_dim
	l.add_theme_color_override("font_color", color if color.a > 0.0 else def)
	return l


# --- style boxes ------------------------------------------------------------

## Flat panel box (cards, inputs): `bg`, 1 px `border` (default token line).
static func panel_box(bg: Color, pad: int = 12, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var t := tokens()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border if border.a > 0.0 else t.line
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(t.radius)
	sb.set_content_margin_all(pad)
	return sb


## Keyboard / gamepad focus ring (1 px pale-brass frame, outside the control).
static func focus_box() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = tokens().accent_hi
	f.set_border_width_all(1)
	f.set_expand_margin_all(3)
	return f


## The style box of a button kind at rest (hover is the same box tweened).
static func button_box(kind: StringName) -> UiBevelBox:
	var t := tokens()
	var sb := UiBevelBox.new()
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	match kind:
		&"primary", &"play":
			sb.fill = t.accent
			sb.fill_hover = t.accent_hi
			sb.bevel = t.bevel
			sb.content_margin_left = 28
			sb.content_margin_right = 28
		&"danger":
			sb.fill = Color(t.danger, 0.0)
			sb.fill_hover = Color(t.danger, 0.12)
			sb.border = Color(t.danger, 0.7)
			sb.border_hover = t.danger
		&"ghost":
			sb.fill = Color(t.text, 0.0)
			sb.fill_hover = Color(t.text, 0.03)
			sb.border = t.line
			sb.border_hover = t.text_dim
		_:
			sb.fill = Color(t.text, 0.0)
			sb.fill_hover = Color(t.text, 0.03)
			sb.border = t.line_strong
			sb.border_hover = t.text_dim
	return sb


# --- buttons ----------------------------------------------------------------

## A kit button. `kind`: primary (brass chamfered, ink text), secondary and
## ghost (hairline outline), danger (red hairline), play (the big brass CTA). `height` 0
## = the kind's default. Hover / click sounds through UiSfx.
static func button(text: String, on_press: Callable = Callable(), kind: StringName = &"secondary",
		height: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	var big := kind in [&"primary", &"play"]
	b.custom_minimum_size.y = height if height > 0 else (48 if big else 44)
	style_button(b, kind)
	_attach_sfx(b)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## Applies a kit kind to an existing button: style boxes, fonts, colours, the
## hover tween (fill / frame / glow), the press dip and the focus ring.
static func style_button(b: BaseButton, kind: StringName = &"secondary") -> void:
	var t := tokens()
	var sb := button_box(kind)
	var pressed := sb.duplicate() as UiBevelBox
	pressed.hover = 1.0
	pressed.fill = pressed.fill_hover.darkened(0.15)
	pressed.fill_hover = pressed.fill
	var disabled := sb.duplicate() as UiBevelBox
	disabled.fill = Color(sb.fill, sb.fill.a * 0.4)
	disabled.border = Color(sb.border, sb.border.a * 0.4)
	disabled.glow = Color(0, 0, 0, 0)
	for st in ["normal", "hover"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus_box())
	var big := kind in [&"primary", &"play"]
	if big:
		disabled.fill = Color(t.accent_dim, 0.6)
		for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color",
				"font_hover_pressed_color"]:
			b.add_theme_color_override(c, t.bg)
		b.add_theme_color_override("font_disabled_color", Color(t.bg, 0.7))
		b.add_theme_font_override("font", display_font(700, track(18 if kind == &"play" else 16, 0.2)))
		b.add_theme_font_size_override("font_size", 18 if kind == &"play" else 16)
	else:
		var fg := t.danger if kind == &"danger" else t.text_dim
		b.add_theme_color_override("font_color", fg)
		b.add_theme_color_override("font_hover_color", t.text)
		b.add_theme_color_override("font_focus_color", t.text)
		b.add_theme_color_override("font_pressed_color", t.accent_hi)
		b.add_theme_color_override("font_hover_pressed_color", t.accent_hi)
		b.add_theme_color_override("font_disabled_color", t.text_off)
		b.add_theme_font_override("font", display_font(600, track(15, 0.16)))
		b.add_theme_font_size_override("font_size", 15)
	var on := func() -> void:
		if not b.disabled:
			animate(b, sb, "hover", 1.0, t.motion_fast)
	var off := func() -> void:
		if not (b.is_hovered() or b.has_focus()):
			animate(b, sb, "hover", 0.0, t.motion_base)
	b.mouse_entered.connect(on)
	b.focus_entered.connect(on)
	b.mouse_exited.connect(off)
	b.focus_exited.connect(off)


## A flat swatch-style button tinted `bg` (colour pickers): kit frame, accent
## ring when pressed.
static func swatch_button(b: BaseButton, bg: Color) -> void:
	var t := tokens()
	var sb := panel_box(bg, 2, t.line)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.12)
	hover.border_color = t.line_strong
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.border_color = t.accent_hi
	pressed.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", focus_box())
	var dis := sb.duplicate() as StyleBoxFlat
	dis.bg_color = Color(bg, bg.a * 0.45)
	b.add_theme_stylebox_override("disabled", dis)


## A square ghost button showing a UiIcon glyph (UiIcon.KINDS).
static func icon_button(kind: StringName, on_press: Callable, tooltip := "", side: int = 36) -> Button:
	var t := tokens()
	var b := Button.new()
	b.custom_minimum_size = Vector2(side, side)
	b.tooltip_text = tooltip
	style_button(b, &"ghost")
	var bare := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, bare)
	var icon := UiIcon.make(kind, side * 0.5, t.text_dim)
	icon.position = Vector2(side, side) * 0.25
	icon.size = Vector2(side, side) * 0.5
	b.add_child(icon)
	b.resized.connect(func() -> void:
		icon.position = (b.size - icon.size) * 0.5)
	b.mouse_entered.connect(func() -> void: icon.color = t.text)
	b.mouse_exited.connect(func() -> void: icon.color = t.text_dim)
	_attach_sfx(b)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## An avatar: `icon` (e.g. an EmblemIcon) centred inside a status ring of
## `ring` colour (account chip, friend rows, launcher). `side` px square.
static func avatar(icon: Control, ring: Color, side: float = 44.0) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(side, side)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := UiIcon.make(&"ring", side, ring)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(r)
	var inner := side * 0.72
	icon.position = Vector2.ONE * (side - inner) * 0.5
	icon.size = Vector2(inner, inner)
	icon.custom_minimum_size = Vector2(inner, inner)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	return box


## A tab (toggle) button: muted text, ivory text with a 2 px brass underline
## when selected (no fill). `nav` = the top-bar look (display face).
static func tab_button(text: String, nav := false) -> Button:
	var t := tokens()
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size.y = 40
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0, 0, 0, 0)
	idle.content_margin_left = 14
	idle.content_margin_right = 14
	idle.border_color = Color(0, 0, 0, 0)
	idle.border_width_bottom = 2
	idle.content_margin_left = 16
	idle.content_margin_right = 16
	var hover := idle.duplicate() as StyleBoxFlat
	var sel := idle.duplicate() as StyleBoxFlat
	sel.border_color = t.accent
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("disabled", idle)
	b.add_theme_stylebox_override("focus", focus_box())
	b.add_theme_color_override("font_color", t.text_dim)
	b.add_theme_color_override("font_hover_color", t.text)
	b.add_theme_color_override("font_pressed_color", t.text)
	b.add_theme_color_override("font_hover_pressed_color", t.text)
	b.add_theme_color_override("font_focus_color", t.text)
	b.add_theme_color_override("font_disabled_color", t.text_off)
	if nav:
		b.add_theme_font_override("font", display_font(600, track(t.size_nav, 0.16)))
		b.add_theme_font_size_override("font_size", t.size_nav)
	else:
		b.add_theme_font_override("font", display_font(600, track(13, 0.14)))
		b.add_theme_font_size_override("font_size", 13)
	_attach_sfx(b)
	return b


## A tab bar over already translated `labels`; `on_select(index)` on press.
## The buttons share a ButtonGroup; select with set_pressed_no_signal().
static func tab_bar(labels: Array, on_select: Callable, selected: int = 0, nav := false) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for i in labels.size():
		var b := tab_button(str(labels[i]), nav)
		b.button_group = group
		b.set_pressed_no_signal(i == selected)
		if on_select.is_valid():
			b.pressed.connect(on_select.bind(i))
		bar.add_child(b)
	return bar


## Line edit in the kit look (a hairline underline, brass on focus).
static func line_edit(placeholder: String, max_len: int) -> LineEdit:
	var t := tokens()
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size.y = 38
	var sb := underline_box(t.line_strong)
	e.add_theme_stylebox_override("normal", sb)
	var f := underline_box(t.accent)
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_color_override("font_color", t.text)
	e.add_theme_color_override("font_placeholder_color", t.text_off)
	e.add_theme_color_override("caret_color", t.accent_hi)
	e.add_theme_color_override("selection_color", Color(t.accent, 0.45))
	return e


## Transparent box with only a 1 px bottom rule of `col` (inputs, rows).
static func underline_box(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = col
	sb.border_width_bottom = 1
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	return sb


# --- containers -------------------------------------------------------------

## A layered card with an optional header strip (UiCard; content in .body).
static func card(title: String = "", pad: int = 16) -> UiCard:
	return UiCard.new().setup(title, pad)


## Styles `panel` as a kit screen (login, profile, settings, lobby, launcher
## pages): the rail surface with a hairline frame, a header with `title`
## (display face) over a hairline and an optional `subtitle` on the right, then a padded body column,
## which is returned. Fades in when shown.
static func screen_frame(panel: PanelContainer, title: String, subtitle: String = "", pad: int = 20) -> VBoxContainer:
	var t := tokens()
	var sb := panel_box(t.panel, 0, t.line)
	panel.add_theme_stylebox_override("panel", sb)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	panel.add_child(outer)
	var head := PanelContainer.new()
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0, 0, 0, 0)
	hb.border_color = t.line
	hb.border_width_bottom = 1
	hb.content_margin_left = pad
	hb.content_margin_right = pad
	hb.content_margin_top = 16
	hb.content_margin_bottom = 14
	head.add_theme_stylebox_override("panel", hb)
	outer.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", t.space_m)
	head.add_child(row)
	var tl := label(title.to_upper(), &"title")
	tl.add_theme_font_override("font", display_font(600, track(22, 0.08)))
	tl.add_theme_font_size_override("font_size", 22)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tl)
	if subtitle != "":
		var st := label(subtitle, &"small", t.text_off, HORIZONTAL_ALIGNMENT_RIGHT)
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(st)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, pad)
	outer.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", t.space_s)
	m.add_child(col)
	return col


## A vertical gap.
static func spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


## The menu background (full-rect ColorRect + shader): ground ink, hairline
## arches and a warm spotlight laid out in 1440x810 reference px (move them
## with set_background_layout()). Frozen under reduce motion.
static func background() -> ColorRect:
	var t := tokens()
	var r := ColorRect.new()
	r.name = "UiKitBackground"
	r.color = t.bg
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := load(BG_SHADER_PATH) as Shader if ResourceLoader.exists(BG_SHADER_PATH) else null
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("ink", t.bg)
		m.set_shader_parameter("brass", t.accent)
		m.set_shader_parameter("speed", 0.0 if reduce_motion() else t.bg_speed)
		r.material = m
		r.resized.connect(func() -> void:
			if r.size.y > 0.0:
				m.set_shader_parameter("rect_size", r.size)
				m.set_shader_parameter("aspect", r.size.x / r.size.y))
	return r


## Moves the arches / spotlight of a background() (reference px at 1440x810).
## `arches` false = spotlight only.
static func set_background_layout(bg: ColorRect, arch_x: float, spot: Vector2, radius: float = 290.0,
		arches := true) -> void:
	var m := bg.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("arch_x", arch_x)
	m.set_shader_parameter("spot_center", spot)
	m.set_shader_parameter("spot_radius", radius)
	m.set_shader_parameter("arches", 1.0 if arches else 0.0)


## Re-reads reduce motion into a background made by background().
static func refresh_background(bg: ColorRect) -> void:
	var m := bg.material as ShaderMaterial
	if m != null:
		m.set_shader_parameter("speed", 0.0 if reduce_motion() else tokens().bg_speed)


# --- toasts, modals ---------------------------------------------------------

## A transient message at the top centre of `parent` (a full-rect Control).
## `kind`: info / ok / warn / danger (left stripe colour). Returns the toast.
static func toast(parent: Control, text: String, kind: StringName = &"info", seconds: float = 2.6) -> Control:
	var t := tokens()
	var lane := parent.get_node_or_null(NodePath(TOAST_LANE)) as VBoxContainer
	if lane == null:
		lane = VBoxContainer.new()
		lane.name = TOAST_LANE
		lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lane.set_anchors_preset(Control.PRESET_CENTER_TOP)
		lane.grow_horizontal = Control.GROW_DIRECTION_BOTH
		lane.offset_top = t.top_bar_height + t.space_l
		lane.alignment = BoxContainer.ALIGNMENT_BEGIN
		lane.add_theme_constant_override("separation", t.space_s)
		parent.add_child(lane)
	var stripe: Color = {&"ok": t.ok, &"warn": t.warn, &"danger": t.danger}.get(kind, t.cyan)
	var p := PanelContainer.new()
	var sb := panel_box(t.panel_raised, 0, Color(stripe, 0.5))
	sb.border_width_left = 3
	sb.border_color = stripe
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, &"body")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	p.add_child(l)
	lane.add_child(p)
	if reduce_motion() or not p.is_inside_tree():
		if p.is_inside_tree():
			p.get_tree().create_timer(seconds).timeout.connect(p.queue_free)
		return p
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, t.motion_base / 1000.0)
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, t.motion_slow / 1000.0)
	tw.tween_callback(p.queue_free)
	return p


## A modal dialog over `parent` (dim + card). `on_ok` / `on_cancel` run after
## it closes; `cancel_text` "" = no cancel button. Esc / B cancel. Returns it.
static func modal(parent: Node, title: String, body: String, ok_text: String, on_ok: Callable = Callable(),
		cancel_text: String = "", on_cancel: Callable = Callable(), danger := false) -> UiModal:
	var m := UiModal.new()
	m.build(title, body, ok_text, on_ok, cancel_text, on_cancel, danger)
	parent.add_child(m)
	m.open()
	return m


# --- theme --------------------------------------------------------------------

## The shared Theme (cached): Button, CheckBox, CheckButton, OptionButton,
## PopupMenu, HSlider, LineEdit, Label, ScrollBar, PanelContainer, tooltip.
static func theme() -> Theme:
	if _theme == null:
		_theme = build_theme()
	return _theme


## Builds a fresh Theme from tokens() (theme() caches one).
static func build_theme() -> Theme:
	var t := tokens()
	var th := Theme.new()
	th.default_font_size = t.size_body
	th.default_font = body_font(400)
	var sec := button_box(&"secondary")
	var sec_h := sec.duplicate() as UiBevelBox
	sec_h.hover = 1.0
	var press := button_box(&"secondary")
	press.hover = 1.0
	press.fill = Color(t.accent, 0.12)
	press.fill_hover = press.fill
	press.border = t.accent
	press.border_hover = t.accent_hi
	var dis := button_box(&"secondary")
	dis.fill = Color(0, 0, 0, 0)
	dis.border = t.line
	dis.glow = Color(0, 0, 0, 0)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		th.set_stylebox("normal", cls, sec)
		th.set_stylebox("hover", cls, sec_h)
		th.set_stylebox("pressed", cls, press)
		th.set_stylebox("hover_pressed", cls, press)
		th.set_stylebox("disabled", cls, dis)
		th.set_stylebox("focus", cls, focus_box())
		th.set_color("font_color", cls, t.text_dim)
		th.set_color("font_hover_color", cls, t.text)
		th.set_color("font_pressed_color", cls, t.accent_hi)
		th.set_color("font_hover_pressed_color", cls, t.accent_hi)
		th.set_color("font_focus_color", cls, t.text)
		th.set_color("font_disabled_color", cls, t.text_off)
	th.set_icon("arrow", "OptionButton", _icon(&"chevron"))
	for cls in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var e := StyleBoxFlat.new()
			e.bg_color = Color(t.text, 0.04) if st.begins_with("hover") else Color(0, 0, 0, 0)
			e.set_content_margin_all(4)
			e.set_corner_radius_all(t.radius)
			th.set_stylebox(st, cls, e)
		th.set_stylebox("focus", cls, focus_box())
		th.set_color("font_color", cls, t.text_dim)
		th.set_color("font_hover_color", cls, t.text)
		th.set_color("font_pressed_color", cls, t.text)
		th.set_color("font_hover_pressed_color", cls, t.text)
		th.set_color("font_focus_color", cls, t.text)
		th.set_constant("h_separation", cls, 8)
	th.set_icon("checked", "CheckBox", _icon(&"box_on"))
	th.set_icon("unchecked", "CheckBox", _icon(&"box_off"))
	th.set_icon("checked_disabled", "CheckBox", _icon(&"box_on"))
	th.set_icon("unchecked_disabled", "CheckBox", _icon(&"box_off"))
	th.set_icon("checked", "CheckButton", _icon(&"toggle_on"))
	th.set_icon("unchecked", "CheckButton", _icon(&"toggle_off"))
	th.set_icon("checked_disabled", "CheckButton", _icon(&"toggle_on"))
	th.set_icon("unchecked_disabled", "CheckButton", _icon(&"toggle_off"))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(t.text, 0.12)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = t.accent
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = t.accent_hi
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	th.set_icon("grabber", "HSlider", _icon(&"grabber"))
	th.set_icon("grabber_highlight", "HSlider", _icon(&"grabber_hi"))
	th.set_stylebox("focus", "HSlider", focus_box())
	var le := underline_box(t.line_strong)
	th.set_stylebox("normal", "LineEdit", le)
	var lef := underline_box(t.accent)
	th.set_stylebox("focus", "LineEdit", lef)
	th.set_color("font_color", "LineEdit", t.text)
	th.set_color("font_placeholder_color", "LineEdit", t.text_off)
	th.set_color("caret_color", "LineEdit", t.accent_hi)
	th.set_color("selection_color", "LineEdit", Color(t.accent, 0.35))
	th.set_color("font_color", "Label", t.text)
	th.set_stylebox("panel", "PanelContainer", panel_box(t.panel, 12))
	var pop := panel_box(t.panel_raised, 6, t.line_strong)
	th.set_stylebox("panel", "PopupMenu", pop)
	var pop_h := StyleBoxFlat.new()
	pop_h.bg_color = Color(t.accent, 0.14)
	pop_h.border_color = t.accent
	pop_h.border_width_left = 2
	pop_h.set_content_margin_all(6)
	th.set_stylebox("hover", "PopupMenu", pop_h)
	th.set_color("font_color", "PopupMenu", t.text)
	th.set_color("font_hover_color", "PopupMenu", t.accent_hi)
	th.set_constant("v_separation", "PopupMenu", 8)
	th.set_stylebox("panel", "TooltipPanel", pop)
	th.set_color("font_color", "TooltipLabel", t.text)
	var sep := StyleBoxLine.new()
	sep.color = t.line
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = t.line_strong
	vsep.thickness = 1
	vsep.vertical = true
	th.set_stylebox("separator", "VSeparator", vsep)
	for sc in ["VScrollBar", "HScrollBar"]:
		var bar := StyleBoxFlat.new()
		bar.bg_color = Color(t.text, 0.04)
		bar.set_content_margin_all(2)
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(t.text, 0.22)
		grab.set_corner_radius_all(3)
		grab.set_content_margin_all(3)
		var grab_h := grab.duplicate() as StyleBoxFlat
		grab_h.bg_color = Color(t.accent, 0.7)
		th.set_stylebox("scroll", sc, bar)
		th.set_stylebox("grabber", sc, grab)
		th.set_stylebox("grabber_highlight", sc, grab_h)
		th.set_stylebox("grabber_pressed", sc, grab_h)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = t.line
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = t.accent
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fill)
	return th


## Generated theme icons (toggle, checkbox, grabber, chevron), cached.
static func _icon(id: StringName) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var t := tokens()
	var img: Image
	match id:
		&"toggle_on", &"toggle_off":
			var on := id == &"toggle_on"
			img = _raster(Vector2i(40, 22), func(p: Vector2) -> Color:
				var track := _sd_capsule(p, Vector2(11, 11), Vector2(29, 11), 10.0)
				var knob := (p - Vector2(29 if on else 11, 11)).length() - 7.0
				var col := Color(t.accent, 0.9) if on else Color(t.text, 0.14)
				var c := _cover(col, track)
				return c.blend(_cover(Color.WHITE if on else t.text_dim, knob)))
		&"box_on", &"box_off":
			var on := id == &"box_on"
			img = _raster(Vector2i(20, 20), func(p: Vector2) -> Color:
				var d := _sd_box(p - Vector2(10, 10), Vector2(8, 8))
				var frame := _cover(t.line_strong if not on else t.accent_hi, absf(d) - 0.6)
				var c := _cover(Color(t.accent, 0.85), d) if on else Color(0, 0, 0, 0)
				c = c.blend(frame)
				if on:
					var tick := minf(_sd_segment(p, Vector2(5.5, 10), Vector2(8.6, 13.2)),
						_sd_segment(p, Vector2(8.6, 13.2), Vector2(14.5, 6.5))) - 1.1
					c = c.blend(_cover(Color.WHITE, tick))
				return c)
		&"grabber", &"grabber_hi":
			var hi := id == &"grabber_hi"
			img = _raster(Vector2i(18, 18), func(p: Vector2) -> Color:
				var d := (p - Vector2(9, 9)).length()
				return _cover(t.accent_hi if hi else t.text, d - 6.0).blend(_cover(t.accent, d - 3.0)))
		_:
			img = _raster(Vector2i(14, 14), func(p: Vector2) -> Color:
				var d := minf(_sd_segment(p, Vector2(3, 5), Vector2(7, 9)), _sd_segment(p, Vector2(7, 9), Vector2(11, 5)))
				return _cover(t.text_dim, d - 0.9))
	var tex := ImageTexture.create_from_image(img)
	_icons[id] = tex
	return tex


static func _raster(sz: Vector2i, f: Callable) -> Image:
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	for y in sz.y:
		for x in sz.x:
			img.set_pixel(x, y, f.call(Vector2(x + 0.5, y + 0.5)))
	return img


## `col` with coverage from a signed distance (anti-aliased edge).
static func _cover(col: Color, d: float) -> Color:
	return Color(col, col.a * clampf(0.5 - d, 0.0, 1.0))


static func _sd_box(p: Vector2, half: Vector2) -> float:
	var q := p.abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


static func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()


static func _sd_capsule(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	return _sd_segment(p, a, b) - r
