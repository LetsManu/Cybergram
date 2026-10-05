class_name MmKit
extends RefCounted
## W17B-UI: small UI builders shared by the matchmaking screens, on top of
## UiKit (premium dark: ink, brass action colour, teal status; Chakra Petch
## captions, IBM Plex body / mono numbers). Layout px are the menu's
## 1440x810 reference (the menu scales its whole stage).


## Caps caption in the body face with wide tracking (lobby style).
static func caption(text: String, size: int = 11, col := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", LobbyScreen.caps_font(size, 0.22))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col if col.a > 0.0 else UiKit.tokens().text_dim)
	return l


## A big display-face title.
static func title(text: String, size: int = 26, col := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(size, 0.12)))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col if col.a > 0.0 else UiKit.tokens().text)
	return l


## A mono number (timers, ratings).
static func mono(text: String, size: int = 26, col := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiKit.mono_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col if col.a > 0.0 else UiKit.tokens().accent)
	return l


## The quiet "← BACK" style link of the lobby header.
static func back_link(text: String, on_press: Callable) -> Button:
	var t := UiKit.tokens()
	var b := Button.new()
	b.text = "←  " + text
	b.custom_minimum_size.y = 32
	var bare := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, bare)
	b.add_theme_stylebox_override("focus", UiKit.focus_box())
	b.add_theme_font_override("font", UiKit.display_font(600, UiKit.track(13, 0.2)))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", t.text_dim)
	b.add_theme_color_override("font_hover_color", t.text)
	b.add_theme_color_override("font_focus_color", t.text)
	b.pressed.connect(on_press)
	UiSfx.attach(b)
	return b


## A toggle chip (lane picker, map / mode chips): hairline frame, brass when on.
static func chip(text: String, group: ButtonGroup = null, min_w: int = 92) -> Button:
	var b := UiKit.tab_button(text)
	b.custom_minimum_size = Vector2(min_w, 34)
	b.add_theme_font_override("font", LobbyScreen.caps_font(12, 0.14))
	b.add_theme_font_size_override("font_size", 12)
	if group != null:
		b.button_group = group
	return b


## A hairline-framed panel (cards without a header strip).
static func frame(pad: int = 16, bg := Color(0, 0, 0, 0), border := Color(0, 0, 0, 0)) -> PanelContainer:
	var t := UiKit.tokens()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.panel_box(bg if bg.a > 0.0 else Color(t.panel_raised, 0.85), pad,
		border))
	return p


## A thin progress line (brass fill on a hairline track).
static func progress(fill_col := Color(0, 0, 0, 0), h: int = 3) -> ProgressBar:
	var t := UiKit.tokens()
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.custom_minimum_size.y = h
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = t.line
	bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col if fill_col.a > 0.0 else t.accent
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## A banner strip with a coloured left stripe (lockouts, dodge warnings).
static func banner(text: String, kind: StringName = &"warn") -> PanelContainer:
	var t := UiKit.tokens()
	var stripe: Color = {&"ok": t.ok, &"warn": t.warn, &"danger": t.danger}.get(kind, t.cyan)
	var p := PanelContainer.new()
	var sb := UiKit.panel_box(Color(t.panel_raised, 0.95), 0, Color(stripe, 0.45))
	sb.border_width_left = 3
	sb.border_color = stripe
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", sb)
	var l := UiKit.label(text, &"body")
	l.name = "Text"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	return p


## Sets the text of a banner() made strip.
static func set_banner_text(p: PanelContainer, text: String) -> void:
	(p.get_node("Text") as Label).text = text


## A key chip + action caption ("[Enter] ACCEPT"), for keyboard / pad hints.
static func key_hint(key: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(UiKit.key_chip(key, 24))
	var l := caption(text, 11)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


## A full-rect Control laid out in reference px (screens are built on it).
static func stage(name_: String) -> Control:
	var c := Control.new()
	c.name = name_
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Places `c` at `pos` with width `w` (0 = keep) inside a plain Control.
static func place(c: Control, pos: Vector2, w: float = 0.0) -> Control:
	c.position = pos
	if w > 0.0:
		c.custom_minimum_size.x = w
		c.size.x = w
	return c


## A player row card for the pick screens: hero badge (ring = state colour),
## name (+ "(you)"), hero / lane line and a status caption. `right` mirrors
## it for the enemy column.
static func seat_card(s: Dictionary, is_you: bool, right: bool, status: String, status_col: Color,
		highlight: bool) -> PanelContainer:
	var t := UiKit.tokens()
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(t.accent, 0.10) if highlight else Color(0, 0, 0, 0)
	sb.border_color = t.accent if highlight else Color(0, 0, 0, 0)
	if right:
		sb.border_width_right = 2
	else:
		sb.border_width_left = 2
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	if right:
		row.layout_direction = Control.LAYOUT_DIRECTION_RTL
	card.add_child(row)
	var badge := HeroBadge.make(MmView.hero_index(StringName(s.get("hero", &""))), 56.0,
		t.accent if highlight else status_col)
	badge.ring_width = 2.0
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.layout_direction = Control.LAYOUT_DIRECTION_LTR
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var nm := UiKit.label(str(s.get("name", "")) + ("  (%s)" % TranslationServer.translate("HUD_LOBBY_YOU").to_lower()
		if is_you else ""), &"body", t.text, align)
	nm.add_theme_font_override("font", UiKit.body_font(600))
	nm.clip_text = true
	col.add_child(nm)
	var hero := MmView.hero_name(StringName(s.get("hero", &"")))
	var lane := StringName(s.get("lane", &""))
	var line: String = hero if hero != "" else TranslationServer.translate("HUD_LOBBY_NO_HERO")
	if lane != &"":
		line = "%s  ·  %s" % [TranslationServer.translate(MmView.lane_key(lane)), line]
	if bool(s.get("bot", false)):
		line = TranslationServer.translate("HUD_MM_BOT_TAG") + "  ·  " + line
	var hl := UiKit.label(line, &"small", t.text_dim, align)
	hl.clip_text = true
	col.add_child(hl)
	var st := caption(status, 11, status_col)
	st.horizontal_alignment = align
	st.name = "Status"
	col.add_child(st)
	return card
