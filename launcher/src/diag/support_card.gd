class_name SupportCard
extends VBoxContainer
## Settings > Support (W15): builds the diagnostics zip on click
## (LauncherDiagnostics) in the Downloads folder or a chosen one, then shows it
## in the file manager. Never uploads anything.

var launcher_version: String = ""
## Callable -> String: the installed game version ("" = none).
var game_version: Callable = Callable()
var folder: String = ""
var last_path: String = ""
var _card: UiCard
var _where: Label
var _result: Label
var _show: Button
var _dialog: FileDialog


func _ready() -> void:
	var t: UiKitTokens = UiKit.tokens()
	folder = LauncherDiagnostics.default_folder()
	_card = UiKit.card("SUPPORT", 16)
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_card)
	var info: Label = UiKit.label("A diagnostics zip holds the launcher and game logs (passwords and tokens removed) and basic system info. It is created only when you click and is never uploaded.", &"small", t.text_dim)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 300
	_card.body.add_child(info)
	_where = UiKit.label("", &"small", t.text_off)
	_where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_card.body.add_child(_where)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_card.body.add_child(row)
	row.add_child(UiKit.button("CREATE DIAGNOSTICS ZIP", create, &"secondary", 38))
	row.add_child(UiKit.button("FOLDER...", func() -> void: _dialog.popup_centered(Vector2i(720, 460)), &"secondary", 38))
	_result = UiKit.label("", &"small", t.ok)
	_result.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_result.visible = false
	_card.body.add_child(_result)
	_show = UiKit.button("SHOW IN FOLDER", func() -> void: OS.shell_show_in_file_manager(last_path), &"secondary", 34)
	_show.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_show.visible = false
	_card.body.add_child(_show)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.title = "Where should the diagnostics zip go?"
	_dialog.dir_selected.connect(func(d: String) -> void:
		folder = d
		_paint())
	add_child(_dialog)
	_paint()


func _paint() -> void:
	_where.text = "Saves to: %s" % folder


## Builds the zip now. Returns its path ("" on failure) and shows it.
func create(open_folder: bool = true) -> String:
	var t: UiKitTokens = UiKit.tokens()
	var gv: String = String(game_version.call()) if game_version.is_valid() else ""
	var files: Dictionary = LauncherDiagnostics.collect(LauncherDiagnostics.default_log_dirs(),
		LauncherDiagnostics.system_info(launcher_version, gv))
	last_path = LauncherDiagnostics.write_zip(folder, files)
	_result.visible = true
	if last_path == "":
		_result.text = "Could not write the zip to %s. Choose another folder." % folder
		_result.add_theme_color_override("font_color", t.danger)
		_show.visible = false
		return ""
	_result.text = "Done: %s (%d files)" % [last_path.get_file(), files.size()]
	_result.add_theme_color_override("font_color", t.ok)
	_show.visible = true
	if open_folder and DisplayServer.get_name() != "headless":
		OS.shell_show_in_file_manager(last_path)
	return last_path
