class_name LauncherUx
extends Node
## W15-UX controller: owns the NOTES page, the extra Settings cards (Game,
## Launch behaviour, System check, Pinned hero) and what the launcher does
## when the game starts and exits. main.gd only calls into this class.
##
## All data stays on this PC: the hero play history and the game's settings
## file are read from the game's user folder; nothing is uploaded.

const HEROES: Array[String] = ["brannoc", "hex", "juniper_quill", "liora_vale", "ryker_vance", "sable", "vesper_loom"]
const TIP_LOCAL: String = "Worked out on this PC from your local play history.\nNothing is sent or uploaded."

var settings: LauncherSettings
var game_dir: String = ""
var notes_page: NotesPage
var _pid: int = 0
var _poll: float = 0.0
var _indicator: int = -1
var _game_widgets: Array[Control] = []
var _run_note: Label
var _res: OptionButton
var _mode: OptionButton
var _qual: OptionButton
var _game_status: Label
var _sys_box: VBoxContainer
var _sys_info: Dictionary = {}
var _sys_card: Control
var _launch_card: Control


func setup(settings_: LauncherSettings, game_userdir_override: String = "") -> void:
	settings = settings_
	game_dir = GameUserDir.current(game_userdir_override)


func history() -> Array[Dictionary]:
	return HeroHistory.read_file(game_dir.path_join(HeroHistory.FILE_NAME)) if game_dir != "" else ([] as Array[Dictionary])


func refresh_heroes() -> void:
	if notes_page != null:
		var h: Array[Dictionary] = history()
		notes_page.set_heroes(HeroHistory.mains(h, settings.pinned_hero), h)


func build_notes_page() -> NotesPage:
	notes_page = NotesPage.new()
	refresh_heroes()
	return notes_page


## Newest notes arrived from the feed.
func on_notes(version: String, md: String) -> void:
	if notes_page != null and md != "":
		notes_page.set_current(version, md)


func game_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


# --- launch behaviour ----------------------------------------------------------

## Starts the game and applies the launch behaviour. false = could not start.
func launch(exe: String) -> bool:
	if not FileAccess.file_exists(exe):
		return false
	_pid = OS.create_process(exe, PackedStringArray())
	if _pid <= 0:
		_pid = 0
		return false
	_refresh_locked()
	match settings.on_launch:
		"close":
			get_tree().quit()
		"minimise":
			_minimise()
	return true


func _minimise() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		var icon: Texture2D = load("res://icon.svg") as Texture2D
		_indicator = DisplayServer.create_status_indicator(icon, "Cybergram launcher (click to open)", Callable(self, "_on_tray"))
		get_window().hide()
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _on_tray(_button: int, _pos: Vector2i) -> void:
	restore()


## Brings the launcher back (tray click or the game exited).
func restore() -> void:
	if _indicator >= 0:
		DisplayServer.delete_status_indicator(_indicator)
		_indicator = -1
	get_window().show()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()


func _process(delta: float) -> void:
	if _pid <= 0:
		return
	_poll += delta
	if _poll < 1.0:
		return
	_poll = 0.0
	if not OS.is_process_running(_pid):
		_pid = 0
		_refresh_locked()
		refresh_heroes()
		if settings.on_launch == "minimise":
			restore()


# --- settings cards ------------------------------------------------------------

func build_settings_cards() -> Array[Control]:
	_launch_card = _build_launch_card()
	_sys_card = _build_syscheck_card()
	return [_build_game_card(), _launch_card, _sys_card, _build_pin_card()]


## Screenshot helper (--page syscheck / launchsetting): runs the check when
## asked and scrolls the settings page to the card.
func show_card(scroll: ScrollContainer, which: String) -> void:
	if which == "syscheck":
		run_check()
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Control = _sys_card if which == "syscheck" else _launch_card
	scroll.scroll_vertical = int(c.global_position.y - scroll.global_position.y + scroll.scroll_vertical - 20)


func _row(parent: Control, text: String, ctl: Control) -> void:
	var t: UiKitTokens = UiKit.tokens()
	var r: HBoxContainer = HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	var l: Label = UiKit.label(text, &"small", t.text_dim)
	l.custom_minimum_size.x = 170
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(l)
	ctl.custom_minimum_size.x = maxf(ctl.custom_minimum_size.x, 220)
	r.add_child(ctl)
	parent.add_child(r)


func _options(items: Array, selected: int) -> OptionButton:
	var o: OptionButton = OptionButton.new()
	for s in items:
		o.add_item(String(s))
	o.select(clampi(selected, 0, maxi(0, items.size() - 1)))
	return o


func _build_game_card() -> Control:
	var t: UiKitTokens = UiKit.tokens()
	var card: UiCard = UiKit.card("GAME", 16)
	var v: Dictionary = GameSettingsFile.read_values(game_dir.path_join(GameSettingsFile.FILE_NAME))
	var screen: Vector2i = DisplayServer.screen_get_size()
	var sizes: Array[Vector2i] = []
	for r in GameSettingsFile.RESOLUTIONS:
		if r == Vector2i.ZERO or screen.x <= 0 or (r.x <= screen.x and r.y <= screen.y):
			sizes.append(r)
	var cur: Vector2i = Vector2i(int(v["width"]), int(v["height"]))
	if not sizes.has(cur):
		sizes.append(cur)
	var names: Array = []
	for r in sizes:
		names.append(GameSettingsFile.resolution_text(r))
	_res = _options(names, maxi(0, sizes.find(cur)))
	_res.set_meta("sizes", sizes)
	_res.tooltip_text = "Window size when the game starts windowed."
	_row(card.body, "Resolution", _res)
	_mode = _options(GameSettingsFile.WINDOW_MODES, int(v["window_mode"]))
	_row(card.body, "Window mode", _mode)
	_qual = _options(GameSettingsFile.QUALITIES, int(v["quality"]))
	_row(card.body, "Graphics quality", _qual)
	var lang: OptionButton = _options(["English"], 0)
	lang.disabled = true
	lang.tooltip_text = "English is the only language in this version."
	_row(card.body, "Language", lang)
	var btn: Button = UiKit.button("APPLY TO GAME", _apply_game, &"secondary", 38)
	_game_widgets = [_res, _mode, _qual, btn]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(btn)
	_game_status = UiKit.label("", &"small", t.text_dim)
	_game_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_game_status)
	card.body.add_child(row)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_run_note = UiKit.label("The game is running: these settings are read-only until you close it.", &"small", t.warn)
	_run_note.visible = false
	card.body.add_child(_run_note)
	card.body.add_child(UiKit.label("Saved into the game's own settings file. Nothing else in it is changed.", &"caption", t.text_off))
	_refresh_locked()
	return card


func _refresh_locked() -> void:
	var running: bool = game_running()
	for w in _game_widgets:
		if w is OptionButton:
			(w as OptionButton).disabled = running
		elif w is BaseButton:
			(w as BaseButton).disabled = running
	if _run_note != null:
		_run_note.visible = running


func _apply_game() -> void:
	var sizes: Array = _res.get_meta("sizes")
	var r: Vector2i = sizes[_res.selected]
	var ok: bool = GameSettingsFile.write_values(game_dir.path_join(GameSettingsFile.FILE_NAME),
		{"window_mode": _mode.selected, "quality": _qual.selected, "width": r.x, "height": r.y})
	_game_status.text = "Saved." if ok else "Could not write the game's settings file."


func _build_launch_card() -> Control:
	var card: UiCard = UiKit.card("WHEN THE GAME STARTS", 16)
	var ids: Array[String] = ["stay", "minimise", "close"]
	var o: OptionButton = _options(["Stay open", "Minimise (tray where supported)", "Close launcher"], ids.find(settings.on_launch))
	o.tooltip_text = "Minimise puts the launcher in the system tray when the OS supports it, otherwise in the taskbar.\nIt comes back when the game exits."
	o.item_selected.connect(func(i: int) -> void:
		settings.on_launch = ids[i]
		settings.save_file())
	_row(card.body, "Launcher", o)
	return card


func _build_pin_card() -> Control:
	var card: UiCard = UiKit.card("YOUR MAINS (PATCH NOTES)", 16)
	var names: Array = ["Automatic (most played)"]
	var stems: Array[String] = [""]
	var hist: Array[Dictionary] = history()
	var all: Array[String] = HEROES.duplicate()
	for e in hist:
		if not all.has(String(e["hero"])):
			all.append(String(e["hero"]))
	for h in all:
		names.append(ReleaseNotes.hero_display(h))
		stems.append(h)
	var o: OptionButton = _options(names, maxi(0, stems.find(settings.pinned_hero)))
	o.tooltip_text = TIP_LOCAL
	o.item_selected.connect(func(i: int) -> void:
		settings.pinned_hero = stems[i]
		settings.save_file()
		refresh_heroes())
	_row(card.body, "Pinned hero", o)
	var mains: Array[String] = HeroHistory.mains(hist, settings.pinned_hero)
	var txt: String = ", ".join(mains.map(func(h: String) -> String: return ReleaseNotes.hero_display(h))) if not mains.is_empty() else "none yet, play a match first"
	card.body.add_child(UiKit.label("Your mains: " + txt + ". " + TIP_LOCAL.replace("\n", " "), &"caption", UiKit.tokens().text_off))
	return card


func _build_syscheck_card() -> Control:
	var card: UiCard = UiKit.card("SYSTEM CHECK", 16)
	_sys_box = VBoxContainer.new()
	_sys_box.add_theme_constant_override("separation", 4)
	card.body.add_child(_sys_box)
	var run: Button = UiKit.button("RUN SYSTEM CHECK", func() -> void: run_check(), &"secondary", 38)
	run.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.body.add_child(run)
	card.body.add_child(UiKit.label("Local only: nothing is sent anywhere.", &"caption", UiKit.tokens().text_off))
	if not _sys_info.is_empty():
		_show_check()
	return card


## Runs the check and shows the result in the card.
func run_check() -> Dictionary:
	_sys_info = SystemCheck.gather()
	if _sys_box != null:
		_show_check()
	return _sys_info


func _show_check() -> void:
	var t: UiKitTokens = UiKit.tokens()
	for c in _sys_box.get_children():
		c.queue_free()
	for l in SystemCheck.lines(_sys_info):
		var row: HBoxContainer = HBoxContainer.new()
		var k: Label = UiKit.label(String(l[0]), &"small", t.text_off)
		k.custom_minimum_size.x = 140
		row.add_child(k)
		var val: Label = UiKit.label(String(l[1]), &"small", t.text)
		val.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)
		_sys_box.add_child(row)
	var rec: Dictionary = SystemCheck.recommend(_sys_info)
	var q: int = int(rec["quality"])
	_sys_box.add_child(UiKit.spacer(6))
	_sys_box.add_child(UiKit.label("Recommended preset: %s" % GameSettingsFile.QUALITIES[q], &"body", t.accent_hi))
	_sys_box.add_child(UiKit.label(String(rec["reason"]), &"small", t.text_dim))
	var apply: Button = UiKit.button("APPLY %s PRESET" % GameSettingsFile.QUALITIES[q].to_upper(), func() -> void: apply_preset(q), &"primary", 38)
	apply.disabled = game_running()
	apply.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_sys_box.add_child(apply)


## Writes the preset into the game's settings and updates the Game card.
func apply_preset(q: int) -> bool:
	var ok: bool = GameSettingsFile.write_values(game_dir.path_join(GameSettingsFile.FILE_NAME), {"quality": q})
	if ok and _qual != null:
		_qual.select(q)
	if _game_status != null:
		_game_status.text = "Preset applied." if ok else "Could not write the game's settings file."
	return ok


## First launcher run: run the check once and offer the preset.
func first_run(parent: Node) -> void:
	if settings.syscheck_done:
		return
	settings.syscheck_done = true
	settings.save_file()
	var info: Dictionary = run_check()
	var rec: Dictionary = SystemCheck.recommend(info)
	var q: int = int(rec["quality"])
	var body: String = ""
	for l in SystemCheck.lines(info):
		body += "%s: %s\n" % [l[0], l[1]]
	body += "\nRecommended graphics preset: %s. %s\nNothing leaves this PC." % [GameSettingsFile.QUALITIES[q], rec["reason"]]
	UiKit.modal(parent, "SYSTEM CHECK", body, "APPLY %s" % GameSettingsFile.QUALITIES[q].to_upper(),
		func() -> void: apply_preset(q), "LATER")
