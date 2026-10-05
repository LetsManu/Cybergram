class_name NotesPage
extends HBoxContainer
## The NOTES rail page: a version history list on the left; on the right the
## selected patch rendered from Markdown (MdBbcode), with a "Changes for your
## heroes" block on top. Works offline: older notes are bundled with the
## launcher and notes seen through the feed are cached.

signal section_opened(index: int)

var _list: VBoxContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _entries: Array[Dictionary] = []
var _current_version: String = ""
var _selected: String = ""
var _mains: Array[String] = []
var _history: Array[Dictionary] = []
var _cards: Array[Control] = []
var _buttons: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 0)
	var t: UiKitTokens = UiKit.tokens()
	var side: PanelContainer = PanelContainer.new()
	side.custom_minimum_size.x = 232
	side.add_theme_stylebox_override("panel", UiKit.panel_box(Color(t.panel, 0.9), 0))
	add_child(side)
	var sv: VBoxContainer = VBoxContainer.new()
	side.add_child(sv)
	var m: MarginContainer = MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 14)
	sv.add_child(m)
	m.add_child(UiKit.eyebrow("VERSION HISTORY", t.text_dim, 12))
	var ls: ScrollContainer = ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(ls)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	ls.add_child(_list)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 24)
	_scroll.add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	margin.add_child(_box)
	_entries = ReleaseNotes.load_all()
	_rebuild()


## The feed's newest notes (also cached for offline use). Selects them.
func set_current(version: String, md: String) -> void:
	_current_version = version.trim_prefix("v")
	ReleaseNotes.cache(_current_version, md)
	_entries = ReleaseNotes.merge(_entries, [{"version": _current_version, "md": md}] as Array[Dictionary])
	_selected = _current_version
	_rebuild()


## Mains (hero stems) and the play history behind them, for the hero block.
func set_heroes(mains: Array[String], history: Array[Dictionary]) -> void:
	_mains = mains
	_history = history
	_rebuild()


## Opens version `v` ("" = newest).
func select(v: String) -> void:
	_selected = v
	_rebuild()
	_scroll.scroll_vertical = 0


## Scrolls to the card of section `index` of the shown notes.
func focus_section(index: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if index >= 0 and index < _cards.size() and is_instance_valid(_cards[index]):
		_scroll.scroll_vertical = int(_cards[index].global_position.y - _box.global_position.y + 24)


func _shown() -> Dictionary:
	for e in _entries:
		if String(e["version"]) == _selected:
			return e
	return _entries[0] if not _entries.is_empty() else {}


func _rebuild() -> void:
	var t: UiKitTokens = UiKit.tokens()
	for c in _list.get_children():
		c.queue_free()
	for c in _box.get_children():
		c.queue_free()
	_cards.clear()
	_buttons.clear()
	var shown: Dictionary = _shown()
	if shown.is_empty():
		_box.add_child(UiKit.label("Patch notes appear here once the update server answers.", &"body", t.text_off))
		return
	_selected = String(shown["version"])
	for e in _entries:
		_list.add_child(_version_button(e))
	var md: String = String(shown["md"])
	var parts: Dictionary = LauncherCore.split_notes(md)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_box.add_child(head)
	var title: Label = UiKit.label(String(parts["headline"]) if parts["headline"] != "" else "v" + _selected, &"title")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if ReleaseNotes.is_draft(md):
		head.add_child(UiKit.label("DRAFT", &"small", t.warn))
	var heroes: Control = _heroes_block(md)
	if heroes != null:
		_box.add_child(heroes)
	if parts["intro"] != "":
		_box.add_child(_rich(String(parts["intro"])))
	for sec in parts["sections"]:
		if String(sec["title"]).to_lower() == "hero changes":
			continue
		var card: UiCard = UiKit.card(String(sec["title"]).to_upper(), 14)
		card.body.add_child(_rich(String(sec["md"])))
		_box.add_child(card)
		_cards.append(card)
	var hs: Dictionary = ReleaseNotes.hero_sections(md)
	if not hs.is_empty():
		var all: UiCard = UiKit.card("HERO CHANGES", 14)
		all.body.add_child(_rich(_hero_md(hs)))
		_box.add_child(all)
		_cards.append(all)


func _hero_md(hs: Dictionary) -> String:
	var s: String = ""
	for k in hs:
		s += "### %s\n%s\n\n" % [k, hs[k]]
	return s


## "Changes for your heroes": one row per main, or null when there is no
## history and no pin.
func _heroes_block(md: String) -> Control:
	if _mains.is_empty():
		return null
	var t: UiKitTokens = UiKit.tokens()
	var hs: Dictionary = ReleaseNotes.hero_sections(md)
	var card: UiCard = UiKit.card("CHANGES FOR YOUR HEROES", 14)
	card.tooltip_text = "Worked out on this PC from your local play history.\nNothing is sent or uploaded."
	card.body.add_child(UiKit.label("Based on your play history on this PC. Nothing is uploaded.", &"caption", t.text_off))
	for h in _mains:
		var e: Dictionary = HeroHistory.entry_for(_history, h)
		var line: String = "### %s" % ReleaseNotes.hero_display(h)
		if not e.is_empty():
			line += "\n*%d matches, %d min played*" % [int(e["matches"]), int(e["minutes"])]
		var sec: String = ReleaseNotes.section_for(hs, h)
		line += "\n" + (sec if sec != "" else "*No changes listed for this hero in this patch.*")
		card.body.add_child(_rich(line))
	return card


func _version_button(e: Dictionary) -> Button:
	var t: UiKitTokens = UiKit.tokens()
	var v: String = String(e["version"])
	var b: Button = Button.new()
	b.toggle_mode = true
	b.button_pressed = v == _selected
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	var tt: String = ReleaseNotes.short_title(String(e["md"]))
	b.text = "v%s%s" % [v, ("  " + tt) if tt != "" else ""]
	b.tooltip_text = b.text
	var on: StyleBoxFlat = UiKit.panel_box(Color(t.accent, 0.12), 8)
	on.border_width_left = 2
	on.border_color = t.accent
	var off: StyleBoxFlat = UiKit.panel_box(Color(0, 0, 0, 0), 8)
	off.border_color = Color(0, 0, 0, 0)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, on if (v == _selected) else off)
	b.add_theme_stylebox_override("focus", UiKit.focus_box())
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", t.text if v == _selected else t.text_dim)
	b.add_theme_color_override("font_hover_color", t.accent_hi)
	b.pressed.connect(select.bind(v))
	_buttons[v] = b
	return b


func _rich(md: String) -> RichTextLabel:
	var t: UiKitTokens = UiKit.tokens()
	var rt: RichTextLabel = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.selection_enabled = false
	rt.meta_underlined = true
	rt.add_theme_color_override("default_color", t.text_dim)
	rt.add_theme_font_override("mono_font", UiKit.mono_font())
	for f in ["normal", "bold", "italics", "bold_italics", "mono"]:
		rt.add_theme_font_size_override(f + "_font_size", t.size_small + 1)
	rt.text = MdBbcode.convert(md.strip_edges(), t, ReleaseNotes.BUNDLE_DIR)
	rt.meta_clicked.connect(func(meta: Variant) -> void:
		var u: String = String(meta)
		if u.begins_with("https://") or u.begins_with("http://"):
			OS.shell_open(u))
	return rt
