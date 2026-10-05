class_name UpdCli
extends Node
## W15-UPD glue between the launcher window (main.gd) and the Updater:
## extra command-line modes for tests and CI, the pause / resume control,
## the pre-load line and the AppImage self-update. main.gd only calls the
## hooks below (each inside a "# --- W15-UPD ---" block).
##
## Flags (after `--`):
##   --speed-limit <KiB/s>    limit downloads (overrides the saved setting)
##   --pause-after <bytes>    pause a download after this many bytes (tests);
##                            headless runs then exit 13 and a rerun resumes
##   --now <ISO UTC>          pretend the clock reads this (pre-load tests)
##   --preload                headless: check, pre-load the feed's "next" block;
##                            exit 0 pre-loaded / 11 nothing to pre-load / 1 failed
##   --set-pack <group>=on|off  headless: switch an optional content pack;
##                            exit 0 done / 1 failed
##   --uninstall              headless: delete the installed game (+ --keep-settings)

const EXIT_PAUSED: int = 13

## "" (window or a main.gd headless mode), "preload", "set-pack" or "uninstall".
var mode: String = ""
var headless: bool = false
var prefs: InstallPrefs

var _u: Updater
var _opts: Dictionary = {}
var _started: bool = false
var _detail: Label
var _button: LauncherPlayButton
var _status: Label
var _pause_link: Button
var _restart_args: PackedStringArray = PackedStringArray()
var _ai: AppImageUpdater


## Parses the W15 flags. Unknown flags are ignored (main.gd has its own).
static func parse(all: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < all.size():
		var a: String = all[i]
		var key: String = a.substr(2) if a.begins_with("--") else ""
		if key in ["speed-limit", "pause-after", "now", "set-pack"] and i + 1 < all.size():
			out[key] = all[i + 1]
			i += 1
		elif key in ["preload", "uninstall", "keep-settings"]:
			out[key] = true
		i += 1
	return out


## Creates the controller as a child of `host`. `headless_` = main.gd already
## runs a headless mode. Returns it; check `mode` afterwards.
static func attach(host: Node, updater: Updater, all_args: PackedStringArray, settings_path: String,
		headless_: bool) -> UpdCli:
	var c := UpdCli.new()
	c.name = "UpdCli"
	host.add_child(c)
	c._setup(updater, parse(all_args), settings_path, headless_)
	return c


func _setup(updater: Updater, opts: Dictionary, settings_path: String, headless_: bool) -> void:
	_u = updater
	_opts = opts
	prefs = InstallPrefs.new(settings_path).load_file()
	for m in ["preload", "set-pack", "uninstall"]:
		if opts.has(m):
			mode = m
	headless = headless_ or mode != ""
	_u.limit_bps = int(opts.get("speed-limit", prefs.speed_limit_kib)) * 1024
	if opts.has("pause-after"):
		_u.pause_after_bytes = int(opts["pause-after"])
	if opts.has("now"):
		_u.now_override = ContentManifest.parse_iso_utc(String(opts["now"]))
	_u.auto_preload = not headless
	_u.state_changed.connect(_on_state)
	_u.preload_changed.connect(_on_preload)
	_restart_args = OS.get_cmdline_user_args()
	if mode == "uninstall":
		var err: String = _u.uninstall_game(opts.has("keep-settings"))
		print("LAUNCHER: uninstall %s" % ("ok" if err == "" else "failed: " + err))
		_quit.call_deferred(0 if err == "" else 1)


func _quit(code: int) -> void:
	get_tree().quit(code)


## main.gd _headless_state hook: true when this controller handles `s`.
func handles(s: Updater.State) -> bool:
	return mode != "" or s == Updater.State.PAUSED


func _on_state(s: Updater.State, msg: String) -> void:
	if headless:
		_headless(s, msg)
	else:
		_window(s)


func _headless(s: Updater.State, msg: String) -> void:
	if s == Updater.State.PAUSED:
		print("LAUNCHER: [PAUSED] %s" % msg)
		_quit(EXIT_PAUSED)
		return
	if mode == "":
		return
	print("LAUNCHER: [%s] %s" % [Updater.State.keys()[s], msg])
	match s:
		Updater.State.OFFLINE_NONE, Updater.State.OFFLINE_READY, Updater.State.ERROR:
			_quit(1)
		Updater.State.UPDATE_AVAILABLE, Updater.State.UP_TO_DATE:
			if mode == "uninstall":
				return
			if _started:
				if mode == "set-pack" and s == Updater.State.UP_TO_DATE:
					_quit(0)
				return
			_started = true
			if mode == "preload":
				if _u.latest_next.is_empty() or s != Updater.State.UP_TO_DATE:
					print("LAUNCHER: nothing to pre-load")
					_quit(11)
					return
				_u.start_preload()
				if _u.preload_text.begins_with("Pre-loaded"):
					print("LAUNCHER: %s" % _u.preload_text)
					_quit(0)
				elif not _u.is_busy():
					_quit(11)
			elif mode == "set-pack":
				var spec: PackedStringArray = String(_opts["set-pack"]).split("=")
				var err: String = "use --set-pack <group>=on|off" if spec.size() != 2 else \
					_u.set_group_enabled(spec[0], spec[1] == "on")
				print("LAUNCHER: set-pack %s: %s" % [_opts["set-pack"], "ok" if err == "" else err])
				if err != "":
					_quit(1)
				elif not _u.is_busy():
					_quit(0)


func _on_preload(text: String) -> void:
	if headless:
		if mode == "preload" and _started:
			if text.begins_with("Pre-loaded"):
				print("LAUNCHER: %s" % text)
				_quit(0)
			elif text == "":
				_quit(1)
		return
	_paint_detail()


# --- window hooks ---------------------------------------------------------------

## main.gd _build_play_panel hook: adds the Pause / Resume link.
func add_play_links(links: HBoxContainer, make_link: Callable, button: LauncherPlayButton, detail: Label,
		status: Label) -> void:
	_button = button
	_detail = detail
	_status = status
	_pause_link = make_link.call("Pause download", toggle_pause)
	_pause_link.add_theme_font_size_override("font_size", 12)
	_pause_link.visible = false
	links.add_child(_pause_link)
	links.move_child(_pause_link, 0)


func toggle_pause() -> void:
	if _u.state == Updater.State.DOWNLOADING:
		_u.pause()
	elif _u.state == Updater.State.PAUSED:
		_u.resume()


## main.gd _on_button hook: true when the click was handled here.
func on_button() -> bool:
	if _u.state == Updater.State.PAUSED:
		_u.resume()
		return true
	return false


func _window(s: Updater.State) -> void:
	if _button == null:
		return
	if _pause_link != null:
		_pause_link.visible = s in [Updater.State.DOWNLOADING, Updater.State.PAUSED]
		_pause_link.text = "Resume download" if s == Updater.State.PAUSED else "Pause download"
	if s == Updater.State.PAUSED:
		_button.show_idle("RESUME")
	_paint_detail.call_deferred()


## Shows the pre-load line under the status when the game is ready to play.
func _paint_detail() -> void:
	if _detail == null or _u.preload_text == "":
		return
	if _u.state in [Updater.State.UP_TO_DATE, Updater.State.OFFLINE_READY]:
		_detail.text = _u.preload_text


## Applies a new speed limit (KiB/s, 0 = unlimited) and saves it.
func set_speed_limit(kib: int) -> void:
	prefs.speed_limit_kib = maxi(0, kib)
	prefs.save_file()
	_u.limit_bps = prefs.speed_limit_kib * 1024


# --- AppImage self-update ---------------------------------------------------------

## main.gd _on_manifest hook (running as an AppImage): true when the feed
## carries a new AppImage and the replacement started.
func start_appimage_update(entry: Dictionary, base_url: String) -> bool:
	if not entry.has("appimage"):
		return false
	var target: String = OS.get_environment("APPIMAGE")
	print("LAUNCHER: self-update (AppImage) -> %s" % entry["version"])
	if _status != null:
		_status.text = "Updating the launcher to %s..." % entry["version"]
		_button.show_busy("UPDATING LAUNCHER", "", -1.0)
	_ai = AppImageUpdater.new()
	add_child(_ai)
	_ai.finished.connect(_on_appimage_done.bind(target))
	_ai.start(entry, target, base_url, _u.limit_bps)
	return true


func _on_appimage_done(ok: bool, message: String, target: String) -> void:
	print("LAUNCHER: self-update: %s" % message)
	if headless:
		_quit(0 if ok else 1)
		return
	if not ok:
		if _status != null:
			_status.text = message
		_u.check()
		return
	var args: PackedStringArray = _restart_args.duplicate()
	args.append("--self-updated")
	OS.create_process(target, args)
	_quit(0)
