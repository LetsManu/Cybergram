class_name UpdPanels
extends HBoxContainer
## Settings page sections of W15-UPD, side by side:
##   CONTENT  optional packs (HD hero textures, languages) with their sizes and
##            the "Lite install" switch; off deletes the files, on downloads them
##   STORAGE  disk used / free, download speed limit, uninstall the game
## Built from the launcher UI kit (design/ux/ui-kit.md).

var _u: Updater
var _cli: UpdCli
var _host: Control
var _content_rows: VBoxContainer
var _lite: CheckButton
var _usage: Label
var _speed: OptionButton
var _uninstall: Button
var _note: Label
var _busy_guard: bool = false


## `host` is the launcher window (the uninstall dialog opens over it).
static func create(host: Control, updater: Updater, cli: UpdCli) -> UpdPanels:
	var p := UpdPanels.new()
	p._host = host
	p._u = updater
	p._cli = cli
	cli.panels = p
	p._build()
	updater.content_changed.connect(p.refresh)
	updater.state_changed.connect(func(_s: Updater.State, _m: String) -> void: p.refresh())
	return p


func _build() -> void:
	var t := UiKit.tokens()
	add_theme_constant_override("separation", 12)
	var content := UiKit.card("CONTENT", 16)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)
	_lite = CheckButton.new()
	_lite.text = "Lite install"
	_lite.tooltip_text = "Skips the HD hero textures: a smaller download for weaker PCs."
	_lite.toggled.connect(func(on: bool) -> void:
		if not _busy_guard:
			_toggle("heroes_hd", not on))
	content.body.add_child(_lite)
	var lite_hint := UiKit.label("Smaller download for weaker PCs. Heroes keep their flat team colours.", &"small", t.text_off)
	lite_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.body.add_child(lite_hint)
	content.body.add_child(UiKit.spacer(t.space_s))
	_content_rows = VBoxContainer.new()
	_content_rows.add_theme_constant_override("separation", 6)
	content.body.add_child(_content_rows)

	var storage := UiKit.card("STORAGE", 16)
	storage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(storage)
	_usage = UiKit.label("", &"small", t.text_dim)
	storage.body.add_child(_usage)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	storage.body.add_child(row)
	row.add_child(UiKit.label("Download speed", &"small", t.text_dim))
	_speed = OptionButton.new()
	for kib in InstallPrefs.SPEED_STEPS:
		_speed.add_item(InstallPrefs.speed_text(kib))
	_speed.select(maxi(0, Array(InstallPrefs.SPEED_STEPS).find(_cli.prefs.speed_limit_kib)))
	_speed.item_selected.connect(func(i: int) -> void: _cli.set_speed_limit(InstallPrefs.SPEED_STEPS[i]))
	row.add_child(_speed)
	storage.body.add_child(UiKit.spacer(t.space_xs))
	_uninstall = UiKit.button("UNINSTALL GAME", _confirm_uninstall, &"danger", 38)
	_uninstall.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	storage.body.add_child(_uninstall)
	_note = UiKit.label(launcher_removal_hint(OS.get_name(), LauncherCore.is_appimage(OS.get_environment("APPIMAGE"))),
		&"small", t.text_off)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	storage.body.add_child(_note)
	refresh()


## How to remove the launcher itself (the button only removes the game).
static func launcher_removal_hint(os_name: String, appimage: bool) -> String:
	if os_name == "Windows":
		return "This removes the game only. To remove the launcher too, use Windows Settings > Apps (Add or remove programs)."
	if appimage:
		return "This removes the game only. To remove the launcher too, delete the Cybergram AppImage file."
	return "This removes the game only. To remove the launcher too, run uninstall.sh in the install folder."


func refresh() -> void:
	if not is_inside_tree() and _usage == null:
		return
	var t := UiKit.tokens()
	var busy: bool = _u.is_busy()
	var skip: PackedStringArray = _u.skip_groups()
	var groups: Dictionary = _u.content_groups()
	if not groups.has("heroes_hd"):
		groups["heroes_hd"] = {"size": 0, "count": 0, "optional": true}
	_busy_guard = true
	_lite.button_pressed = skip.has("heroes_hd")
	_lite.disabled = busy
	_busy_guard = false
	for c in _content_rows.get_children():
		c.queue_free()
	var names: Array = groups.keys()
	names.sort()
	var langs: int = 0
	for g: String in names:
		if not ContentManifest.is_optional(g):
			continue
		langs += 1 if g.begins_with("lang_") else 0
		_content_rows.add_child(_pack_row(g, int(groups[g]["size"]), not skip.has(g), busy))
	if langs == 0:
		_content_rows.add_child(UiKit.label("Language packs: none available yet (English is built in).", &"small", t.text_off))
	var du: Dictionary = _u.disk_usage()
	var free: int = int(du["free"])
	_usage.text = "Game: %s used   ·   %s free on this drive" % [
		ContentManifest.size_text(int(du["used"])), ContentManifest.size_text(free) if free >= 0 else "unknown"]
	_uninstall.disabled = busy or _u.installed_version() == ""


func _pack_row(group: String, size: int, on: bool, busy: bool) -> Control:
	var t := UiKit.tokens()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sw := CheckButton.new()
	sw.text = ContentManifest.label(group)
	sw.button_pressed = on
	sw.disabled = busy
	sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw.tooltip_text = ContentManifest.blurb(group)
	sw.toggled.connect(func(v: bool) -> void: _toggle(group, v))
	row.add_child(sw)
	var sz := UiKit.label(ContentManifest.size_text(size) if size > 0 else "size unknown", &"small", t.text_dim)
	sz.add_theme_font_override("font", UiKit.mono_font())
	row.add_child(sz)
	return row


func _toggle(group: String, on: bool) -> void:
	var err: String = _u.set_group_enabled(group, on)
	if err != "":
		UiKit.toast(_host, err, &"danger")
	else:
		UiKit.toast(_host, "%s %s." % [ContentManifest.label(group),
			"will be downloaded" if on else "removed"], &"info")
	refresh.call_deferred()


## Opens the uninstall confirmation (screenshots use this directly).
func open_uninstall() -> void:
	_confirm_uninstall()


## Confirm modal: uninstall the game, optionally keeping the saved settings.
func _confirm_uninstall() -> void:
	var keep := CheckBox.new()
	keep.text = "Keep my settings (keybinds, graphics, sign-in name)"
	keep.button_pressed = true
	var m := UiKit.modal(_host, "UNINSTALL CYBERGRAM",
		"This deletes the installed game from\n%s\nThe launcher stays, so you can install it again later." % _u.install_root(),
		"UNINSTALL", func() -> void:
			var err: String = _u.uninstall_game(keep.button_pressed)
			UiKit.toast(_host, err if err != "" else "Cybergram was uninstalled.", &"danger" if err != "" else &"info")
			refresh(),
		"Cancel", Callable(), true)
	m.card.body.add_child(keep)
	m.card.body.move_child(keep, m.card.body.get_child_count() - 2)
