class_name Updater
extends Node
## Checks the update host, downloads and installs the game, starts it.
##
## Install layout (all next to the launcher, or below --install-root):
##   game/                    the installed game (+ game/installed_version.txt)
##   downloads/<file>.part    the zip while downloading
## An update extracts into game.new/ first and swaps it in only after the
## sha256 matched and the extraction finished, so a failed update never
## damages the installed version.

## Launcher state, reported through `state_changed`.
enum State {
	IDLE,
	CHECKING,
	UP_TO_DATE,        ## installed == latest: PLAY
	UPDATE_AVAILABLE,  ## installed < latest, or nothing installed: UPDATE / INSTALL
	OFFLINE_READY,     ## host unreachable but a game is installed: PLAY (old version)
	OFFLINE_NONE,      ## host unreachable and nothing installed: RETRY
	DOWNLOADING,
	INSTALLING,
	ERROR,             ## update failed; installed game (if any) is untouched
	VERIFYING,         ## hashing the installed files against the manifest
}

## Emitted whenever the state changes. `message` is a short human line.
signal state_changed(state: State, message: String)
## Emitted while downloading: fraction 0..1 (or -1 if size unknown) and a label.
signal progress_changed(fraction: float, label: String)
## Emitted once the manifest is parsed (news text is `latest_notes_md`).
signal manifest_loaded

## Emitted when a verify run finished: relative paths that were missing or
## corrupt (empty = intact). A repair download starts right after if non-empty.
signal verify_done(bad: PackedStringArray)

const MANIFEST_TIMEOUT_S: float = 8.0
const DEFAULT_EXE: Dictionary = {"windows": "Cybergram.exe", "linux": "Cybergram.x86_64"}

var state: State = State.IDLE
var latest_version: String = ""
var latest_notes_md: String = ""
## The feed's "launcher" section ({} when the feed has none).
var latest_launcher: Dictionary = {}
var last_error: String = ""

var _install_root: String = ""
var _version_url: String = ""
var _platform: String = ""
var _entry: Dictionary = {}
var _http: HTTPRequest
## Set when the feed was accepted without a signature check (no pinned key).
var feed_warning: String = ""
var _downloading: bool = false



## Configures the updater. `install_root` is the folder that holds game/.
func setup(install_root: String, version_url: String, os_name: String = "") -> void:
	_install_root = install_root
	_version_url = version_url
	_platform = LauncherCore.platform_key(os_name if os_name != "" else OS.get_name())


## Platform key ("windows" / "linux" / "").
func platform() -> String:
	return _platform


## Folder that holds game/.
func install_root() -> String:
	return _install_root


## Absolute path of the installed game folder.
func game_dir() -> String:
	return _install_root.path_join(LauncherCore.GAME_DIR)


## Installed version ("" when nothing is installed).
func installed_version() -> String:
	var path: String = game_dir().path_join(LauncherCore.VERSION_FILE)
	if not FileAccess.file_exists(path):
		return ""
	var v: String = FileAccess.get_file_as_string(path).strip_edges()
	if v == "" or not FileAccess.file_exists(game_exe_path()):
		return ""
	return v


## Absolute path of the game executable for this platform.
func game_exe_path() -> String:
	var exe: String = String(_entry.get("exe", DEFAULT_EXE.get(_platform, "")))
	return game_dir().path_join(exe)


## Fetches version.json and decides between PLAY / UPDATE / offline.
func check() -> void:
	if _platform == "":
		_set_state(State.ERROR, "This platform is not supported by the launcher.")
		return
	_set_state(State.CHECKING, "Checking for updates...")
	_clear_http()
	_http = HTTPRequest.new()
	_http.timeout = MANIFEST_TIMEOUT_S
	add_child(_http)
	_http.request_completed.connect(_on_manifest_done)
	var err: Error = _http.request(_version_url)
	if err != OK:
		_go_offline("Cannot reach the update server.")


func _on_manifest_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_go_offline("Cannot reach the update server (%s)." % (
			"HTTP %d" % code if result == HTTPRequest.RESULT_SUCCESS else "network error %d" % result))
		return
	if FeedKey.PEM.strip_edges() == "":
		_accept_manifest(body, "")
		return
	# A key is pinned: fetch version.json.sig (plain HTTP is fine, the
	# signature is what makes the feed trustworthy).
	var sig_http := HTTPRequest.new()
	sig_http.timeout = MANIFEST_TIMEOUT_S
	add_child(sig_http)
	sig_http.request_completed.connect(func(r: int, c: int, _h: PackedStringArray, b: PackedByteArray) -> void:
		sig_http.queue_free()
		_accept_manifest(body, b.get_string_from_utf8() if r == HTTPRequest.RESULT_SUCCESS and c == 200 else ""))
	if sig_http.request(_version_url + LauncherCore.SIG_SUFFIX) != OK:
		sig_http.queue_free()
		_accept_manifest(body, "")


## Verifies the feed signature (LauncherCore.verify_feed), then parses it.
func _accept_manifest(body: PackedByteArray, sig_text: String) -> void:
	var v: Dictionary = LauncherCore.verify_feed(body, sig_text, FeedKey.PEM)
	feed_warning = "" if v["signed"] else String(v["message"])
	if not v["ok"]:
		_go_offline(String(v["message"]))
		return
	if feed_warning != "":
		push_warning("LAUNCHER: " + feed_warning)
	var m: Dictionary = LauncherCore.parse_manifest(body.get_string_from_utf8())
	if not m["ok"]:
		_go_offline("Update server sent bad data: %s" % m["error"])
		return
	var plats: Dictionary = m["platforms"]
	if not plats.has(_platform):
		_go_offline("The update server has no build for this platform.")
		return
	latest_version = m["version"]
	latest_notes_md = m["notes_md"]
	latest_launcher = m["launcher"]
	_entry = plats[_platform]
	manifest_loaded.emit()
	var installed: String = installed_version()
	if installed == "":
		_set_state(State.UPDATE_AVAILABLE, "Install Cybergram %s" % latest_version)
	elif LauncherCore.compare_versions(installed, latest_version) < 0:
		_set_state(State.UPDATE_AVAILABLE, "Update %s -> %s available" % [installed, latest_version])
	else:
		_set_state(State.UP_TO_DATE, "Cybergram %s is up to date" % installed)


func _go_offline(msg: String) -> void:
	last_error = msg
	if installed_version() != "":
		_set_state(State.OFFLINE_READY, "%s Installed version %s can still be played." % [msg, installed_version()])
	else:
		_set_state(State.OFFLINE_NONE, "%s Cybergram is not installed yet." % msg)


## Downloads, verifies and installs the latest build (needs a loaded manifest).
func start_update() -> void:
	if _entry.is_empty() or _downloading:
		return
	_downloading = true
	var file_name: String = _entry["file"]
	var dl_dir: String = _install_root.path_join("downloads")
	DirAccess.make_dir_recursive_absolute(dl_dir)
	var part: String = dl_dir.path_join(file_name + ".part")
	DirAccess.remove_absolute(part)
	_set_state(State.DOWNLOADING, "Downloading %s..." % file_name)
	_clear_http()
	_http = HTTPRequest.new()
	_http.download_file = part
	_http.download_chunk_size = 1 << 20
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_download_done.bind(part))
	var err: Error = _http.request(LauncherCore.base_url(_version_url) + file_name)
	if err != OK:
		_fail("Could not start the download (%s)." % error_string(err))


func _process(_delta: float) -> void:
	if state != State.DOWNLOADING or _http == null:
		return
	var got: int = _http.get_downloaded_bytes()
	var total: int = _http.get_body_size()
	if total <= 0:
		total = int(_entry.get("size", 0))
	var frac: float = clampf(float(got) / float(total), 0.0, 1.0) if total > 0 else -1.0
	progress_changed.emit(frac, "%.1f / %.1f MB" % [got / 1048576.0, total / 1048576.0])


func _on_download_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, part: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		_fail("Download failed (%s)." % (
			"HTTP %d" % code if result == HTTPRequest.RESULT_SUCCESS else "network error %d" % result))
		return
	progress_changed.emit(1.0, "Verifying...")
	if not LauncherCore.sha256_matches(part, String(_entry["sha256"])):
		DirAccess.remove_absolute(part)
		_fail("The download is corrupt (checksum mismatch). Nothing was changed.")
		return
	_install(part)


func _install(zip_path: String) -> void:
	_set_state(State.INSTALLING, "Installing %s..." % latest_version)
	progress_changed.emit(1.0, "Unpacking...")
	var staging: String = _install_root.path_join("game.new")
	var backup: String = _install_root.path_join("game.old")
	LauncherCore.remove_tree(staging)
	LauncherCore.remove_tree(backup)
	var err: String = LauncherCore.extract_zip(zip_path, staging)
	if err != "":
		LauncherCore.remove_tree(staging)
		_fail("Unpacking failed: %s. Nothing was changed." % err)
		return
	var exe_path: String = staging.path_join(String(_entry["exe"]))
	if not FileAccess.file_exists(exe_path):
		LauncherCore.remove_tree(staging)
		_fail("The package does not contain %s. Nothing was changed." % _entry["exe"])
		return
	if _platform != "windows":
		FileAccess.set_unix_permissions(exe_path, 493)  # 0755
	var vf: FileAccess = FileAccess.open(staging.path_join(LauncherCore.VERSION_FILE), FileAccess.WRITE)
	if vf == null:
		LauncherCore.remove_tree(staging)
		_fail("Cannot write the version file.")
		return
	vf.store_string(latest_version + "\n")
	vf.close()
	# Swap: game -> game.old, game.new -> game; roll back if the second step fails.
	var had_old: bool = DirAccess.dir_exists_absolute(game_dir())
	if had_old and DirAccess.rename_absolute(game_dir(), backup) != OK:
		LauncherCore.remove_tree(staging)
		_fail("Cannot replace the installed game. Is it still running?")
		return
	if DirAccess.rename_absolute(staging, game_dir()) != OK:
		if had_old:
			DirAccess.rename_absolute(backup, game_dir())
		LauncherCore.remove_tree(staging)
		_fail("Cannot move the new version into place. The old version was kept.")
		return
	LauncherCore.remove_tree(backup)
	DirAccess.remove_absolute(zip_path)
	_downloading = false
	_set_state(State.UP_TO_DATE, "Cybergram %s installed" % latest_version)


## Hashes the installed files against the manifest's per-file sha256 list and
## re-downloads the whole build when anything is missing or corrupt (the host
## serves zips, not single files). Needs a loaded manifest and an installed
## game of the latest version; an older install is simply updated.
func verify_and_repair() -> void:
	if _entry.is_empty() or _downloading:
		return
	var installed: String = installed_version()
	if installed == "" or LauncherCore.compare_versions(installed, latest_version) != 0:
		start_update()
		return
	var files: Array = _entry.get("files", [])
	if files.is_empty():
		_set_state(State.ERROR, "The update server publishes no file list, so the install cannot be verified.")
		return
	_set_state(State.VERIFYING, "Verifying %d files..." % files.size())
	await get_tree().process_frame  # let the UI show the state before hashing
	var bad: PackedStringArray = LauncherCore.verify_files(game_dir(), files)
	verify_done.emit(bad)
	if bad.is_empty():
		_set_state(State.UP_TO_DATE, "All %d files are intact. Cybergram %s is ready." % [files.size(), installed])
	else:
		print("LAUNCHER: verify found %d bad files, e.g. %s" % [bad.size(), bad[0]])
		start_update()


## Moves the installed game to `new_root`/game and switches this updater to
## the new root. Tries a rename, falls back to copy + delete (other drive).
## Returns "" on success or an error text; the old install stays on failure.
func move_install(new_root: String) -> String:
	var target: String = new_root.path_join(LauncherCore.GAME_DIR)
	if new_root.simplify_path() == _install_root.simplify_path():
		return ""
	if DirAccess.dir_exists_absolute(target):
		return "The folder %s already contains a game folder." % new_root
	var err: Error = DirAccess.make_dir_recursive_absolute(new_root)
	if err != OK:
		return "Cannot create %s (%s)." % [new_root, error_string(err)]
	if DirAccess.dir_exists_absolute(game_dir()):
		if DirAccess.rename_absolute(game_dir(), target) != OK:
			var cerr: String = LauncherCore.copy_tree(game_dir(), target)
			if cerr != "":
				LauncherCore.remove_tree(target)
				return "Moving failed: %s. The old install was kept." % cerr
			LauncherCore.remove_tree(game_dir())
	_install_root = new_root
	return ""


func _fail(msg: String) -> void:
	_downloading = false
	last_error = msg
	_set_state(State.ERROR, msg)


## Starts the installed game. Returns true when the process was created.
func launch_game(extra_args: PackedStringArray = PackedStringArray()) -> bool:
	var exe: String = game_exe_path()
	if not FileAccess.file_exists(exe):
		return false
	return OS.create_process(exe, extra_args) > 0


func _set_state(s: State, msg: String) -> void:
	state = s
	state_changed.emit(s, msg)


func _clear_http() -> void:
	if _http != null:
		_http.cancel_request()
		_http.queue_free()
		_http = null
