class_name Updater
extends Node
## Checks the update host, downloads and installs the game, starts it.
##
## Install layout (all next to the launcher, or below --install-root):
##   game/                    the installed game (+ installed_version.txt, .manifest.json)
##   content.cfg              optional content packs the player switched off
##   downloads/<file>.part    a full zip while downloading (fallback / first install)
##   downloads/blobs/<sha256> single files of a delta update (.part while downloading)
##   game.stage/ game.undo/   a delta swap in progress (see DeltaInstaller)
##   preload/                 the next patch, downloaded ahead of its release
##
## Updates are per file when the feed lists files (W15-UPD): only files whose
## sha256 differs are fetched, each is checked against the signed manifest,
## staged, then renamed in with a rollback journal. A full zip (extracted into
## game.new/, swapped in only when complete) remains the first-install path and
## the fallback when the host has no blobs. Downloads pause and resume (HTTP
## Range) and honour a speed limit.

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
	PAUSED,            ## a download is paused; resume() continues it
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
## Pre-load status line changed ("" = nothing pre-loaded or pending).
signal preload_changed(text: String)
## Installed content packs or their selection changed.
signal content_changed

const MANIFEST_TIMEOUT_S: float = 8.0
const DEFAULT_EXE: Dictionary = {"windows": "Cybergram.exe", "linux": "Cybergram.x86_64"}
const PRELOAD_DIR: String = "preload"

var state: State = State.IDLE
var latest_version: String = ""
var latest_notes_md: String = ""
## The feed's "launcher" section ({} when the feed has none).
var latest_launcher: Dictionary = {}
## The feed's "next" block for this platform (ContentManifest.parse_next), or {}.
var latest_next: Dictionary = {}
var last_error: String = ""
## Download speed limit in bytes per second (0 = unlimited).
var limit_bps: int = 0:
	set(v):
		limit_bps = maxi(v, 0)
		if _dl != null:
			_dl.limit_bps = limit_bps
## Start pre-loading a "next" patch in the background when the game is current.
var auto_preload: bool = true
## Tests: pretend the clock reads this unix time (-1 = real clock).
var now_override: int = -1
## Tests: pause the transfer once this many bytes arrived (-1 = never).
var pause_after_bytes: int = -1
## Status line of the pre-load ("" when none).
var preload_text: String = ""

var _install_root: String = ""
var _version_url: String = ""
var _platform: String = ""
var _entry: Dictionary = {}
var _files: Array = []
var _blobs: String = ""
var _http: HTTPRequest
## Set when the feed was accepted without a signature check (no pinned key).
var feed_warning: String = ""
var _downloading: bool = false
var _speed: float = 0.0
var _speed_t: int = 0
var _speed_got: int = 0
var _feed_body: PackedByteArray = PackedByteArray()
var _feed_sig: String = ""
var _dl: LauncherDownloader
## The running transfer: {kind ("zip"|"delta"|"preload"), queue, index, done,
## total, ...}. Empty when idle.
var _job: Dictionary = {}



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


## True while a download, install or verify runs (or is paused).
func is_busy() -> bool:
	return _downloading or state in [State.DOWNLOADING, State.INSTALLING, State.VERIFYING, State.PAUSED]


## Current unix time (UTC), or the test override.
func now_unix() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())


## Fetches version.json and decides between PLAY / UPDATE / offline.
func check() -> void:
	if _platform == "":
		_set_state(State.ERROR, "This platform is not supported by the launcher.")
		return
	if is_busy():
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
	_feed_body = body
	_feed_sig = sig_text
	latest_version = m["version"]
	latest_notes_md = m["notes_md"]
	latest_launcher = m["launcher"]
	_entry = plats[_platform]
	_files = ContentManifest.files_of(_entry)
	_blobs = m["blobs"]
	latest_next = ContentManifest.parse_next(m["next"], _platform)
	manifest_loaded.emit()
	activate_preload_if_due()
	_decide()
	if state == State.UP_TO_DATE and auto_preload:
		start_preload()
	else:
		_refresh_preload_text()


func _decide() -> void:
	var installed: String = installed_version()
	if installed == "":
		_set_state(State.UPDATE_AVAILABLE, "Install Cybergram %s" % latest_version)
	elif LauncherCore.compare_versions(installed, latest_version) < 0:
		_set_state(State.UPDATE_AVAILABLE, "Update %s -> %s available" % [installed, latest_version])
	else:
		_set_state(State.UP_TO_DATE, "Cybergram %s is up to date" % installed)


func _go_offline(msg: String) -> void:
	last_error = msg
	activate_preload_if_due()
	_refresh_preload_text()
	if installed_version() != "":
		_set_state(State.OFFLINE_READY, "%s Installed version %s can still be played." % [msg, installed_version()])
	else:
		_set_state(State.OFFLINE_NONE, "%s Cybergram is not installed yet." % msg)


# --- content packs ------------------------------------------------------------

## Optional groups switched off for this install.
func skip_groups() -> PackedStringArray:
	return ContentManifest.load_skip(_install_root)


## {group: {size, count, optional}} of the latest build (or of the installed
## files when the feed is unknown).
func content_groups() -> Dictionary:
	if not _files.is_empty():
		return ContentManifest.groups(_files)
	return ContentManifest.groups(ContentManifest.load_installed(game_dir()))


## True when every file of `group` in the installed manifest is present.
func group_installed(group: String) -> bool:
	var listed: Array = ContentManifest.load_installed(game_dir())
	var any: bool = false
	for e: Dictionary in listed:
		if e["group"] == group:
			any = true
	return any


## Switches an optional pack on or off. Off deletes its files now; on
## downloads them (when the installed version is the latest, else with the
## next update). Returns "" or an error text.
func set_group_enabled(group: String, on: bool) -> String:
	if not ContentManifest.is_optional(group):
		return "%s is required." % ContentManifest.label(group)
	if is_busy():
		return "Wait until the current download has finished."
	var skip: PackedStringArray = skip_groups()
	if on:
		var i: int = skip.find(group)
		if i >= 0:
			skip.remove_at(i)
	elif not skip.has(group):
		skip.append(group)
	if not ContentManifest.save_skip(_install_root, skip):
		return "Cannot save the content selection."
	content_changed.emit()
	var installed: String = installed_version()
	if installed == "":
		return ""
	if not on:
		return _remove_group(group)
	if not _files.is_empty() and LauncherCore.compare_versions(installed, latest_version) == 0:
		_start_delta(_files, latest_version, "content")
	return ""


func _remove_group(group: String) -> String:
	var listed: Array = ContentManifest.load_installed(game_dir())
	var gone: PackedStringArray = PackedStringArray()
	var keep: Array = []
	for e: Dictionary in listed:
		if e["group"] == group:
			gone.append(e["path"])
		else:
			keep.append(e)
	for e: Dictionary in _files:  # also files the manifest did not record yet
		if e["group"] == group and not gone.has(e["path"]) and FileAccess.file_exists(game_dir().path_join(e["path"])):
			gone.append(e["path"])
	var err: String = DeltaInstaller.swap(game_dir(), _install_root.path_join("game.stage"),
		_install_root.path_join("game.undo"), PackedStringArray(), gone)
	if err != "":
		return "Could not remove %s: %s" % [ContentManifest.label(group), err]
	if not listed.is_empty():
		ContentManifest.save_installed(game_dir(), keep)
	print("LAUNCHER: removed %s (%d files)" % [group, gone.size()])
	content_changed.emit()
	return ""


# --- update entry points ------------------------------------------------------

## Downloads, verifies and installs the latest build (needs a loaded manifest).
## Per file when the feed lists files and something is installed (or packs are
## skipped); a full zip otherwise.
func start_update() -> void:
	if _entry.is_empty() or is_busy():
		return
	if not _files.is_empty() and (installed_version() != "" or not skip_groups().is_empty()):
		_start_delta(_files, latest_version, "update")
	else:
		_start_zip()


## Pauses the running download (the .part file is kept).
func pause() -> void:
	if state != State.DOWNLOADING or _dl == null or not _dl.active:
		return
	_dl.stop()
	_set_state(State.PAUSED, "Paused. %s" % _progress_label())


## Continues a paused download (HTTP Range from where it stopped).
func resume() -> void:
	if state != State.PAUSED or _job.is_empty():
		return
	_set_state(State.DOWNLOADING, "Downloading...")
	if _job["kind"] == "zip":
		_dl.start(LauncherCore.base_url(_version_url) + String(_entry["file"]), _job["part"], int(_entry.get("size", 0)))
	else:
		_fetch_next()


func _start_zip() -> void:
	_downloading = true
	var file_name: String = _entry["file"]
	var dl_dir: String = _install_root.path_join("downloads")
	DirAccess.make_dir_recursive_absolute(dl_dir)
	var part: String = dl_dir.path_join(file_name + ".part")
	_job = {"kind": "zip", "part": part, "done": 0, "total": int(_entry.get("size", 0))}
	_set_state(State.DOWNLOADING, "Downloading %s..." % file_name)
	_reset_speed()
	_ensure_dl()
	_dl.start(LauncherCore.base_url(_version_url) + file_name, part, int(_entry.get("size", 0)))


func _ensure_dl() -> void:
	if _dl == null:
		_dl = LauncherDownloader.new()
		add_child(_dl)
		_dl.finished.connect(_on_dl_finished)
	_dl.limit_bps = limit_bps


func _reset_speed() -> void:
	_speed = 0.0
	_speed_t = 0
	_speed_got = 0


func _blob_dir(kind: String) -> String:
	if kind == "preload":
		return _install_root.path_join(PRELOAD_DIR).path_join("blobs")
	return _install_root.path_join("downloads").path_join("blobs")


## A verified copy of blob `sha` from the download or pre-load cache, or "".
func _cached_blob(e: Dictionary) -> String:
	for dir in [_blob_dir("preload"), _blob_dir("update")]:
		var p: String = String(dir).path_join(e["sha256"])
		if ContentManifest.file_matches(p, int(e["size"]), e["sha256"]):
			return p
	return ""


## Delta: hash what is installed, fetch only the files that differ.
## kind: "update" | "content" | "repair" install `version` now; "preload"
## only fills the pre-load cache.
func _start_delta(all_files: Array, version: String, kind: String) -> void:
	_downloading = true
	var selected: Array = ContentManifest.select(all_files, skip_groups())
	if kind != "preload":
		_set_state(State.VERIFYING, "Comparing installed files...")
	var need: Array = []
	for e: Dictionary in selected:
		if not ContentManifest.file_matches(game_dir().path_join(e["path"]), int(e["size"]), e["sha256"]):
			need.append(e)
		if is_inside_tree():
			await get_tree().process_frame
	var queue: Array = []
	var total: int = 0
	for e: Dictionary in need:
		if _cached_blob(e) == "" and not _queued(queue, e["sha256"]):
			queue.append(e)
			total += int(e["size"])
	_job = {"kind": kind, "version": version, "selected": selected, "need": need, "queue": queue,
		"index": 0, "done": 0, "total": total, "fell_back": false}
	print("LAUNCHER: %s %s: %d of %d files differ, %d to download (%d bytes)" % [
		kind, version, need.size(), selected.size(), queue.size(), total])
	if kind == "preload":
		_set_preload_text("Pre-loading %s..." % version)
	else:
		_set_state(State.DOWNLOADING, "Downloading %d changed files..." % queue.size() if not queue.is_empty()
			else "Installing...")
	_reset_speed()
	_fetch_next()


static func _queued(queue: Array, sha: String) -> bool:
	for q: Dictionary in queue:
		if q["sha256"] == sha:
			return true
	return false


func _fetch_next() -> void:
	var queue: Array = _job["queue"]
	var i: int = _job["index"]
	if i >= queue.size():
		_delta_downloaded()
		return
	var e: Dictionary = queue[i]
	_ensure_dl()
	var dir: String = _blob_dir(_job["kind"])
	_job["part"] = dir.path_join(String(e["sha256"]) + ".part")
	_dl.start(ContentManifest.blob_url(LauncherCore.base_url(_version_url), _blobs, e["sha256"]), _job["part"], int(e["size"]))


func _on_dl_finished(ok: bool, err: String) -> void:
	if _job.is_empty():
		return
	if _job["kind"] == "zip":
		_on_zip_downloaded(ok, err)
		return
	var e: Dictionary = (_job["queue"] as Array)[_job["index"]]
	var part: String = _job["part"]
	if not ok:
		if not FileAccess.file_exists(part) or err.begins_with("HTTP 4"):
			DirAccess.remove_absolute(part)
		_delta_failed("Download of %s failed (%s)." % [e["path"], err], err.begins_with("HTTP 404"))
		return
	if not ContentManifest.file_matches(part, int(e["size"]), e["sha256"]):
		DirAccess.remove_absolute(part)
		_delta_failed("%s is corrupt (checksum mismatch). Nothing was changed." % e["path"], false)
		return
	var blob: String = part.get_basename()  # strip ".part"
	DirAccess.remove_absolute(blob)
	DirAccess.rename_absolute(part, blob)
	_job["done"] = int(_job["done"]) + int(e["size"])
	_job["index"] = int(_job["index"]) + 1
	_fetch_next()


func _delta_failed(msg: String, missing_blob: bool) -> void:
	var kind: String = _job.get("kind", "")
	_job = {}
	if kind == "preload":
		_downloading = false
		_set_preload_text("")
		print("LAUNCHER: pre-load failed: %s" % msg)
		return
	if missing_blob and kind == "update" and not String(_entry.get("file", "")).is_empty():
		print("LAUNCHER: %s Falling back to the full package." % msg)
		_start_zip()
		return
	_fail(msg)


## Every needed blob is cached: stage the files, then swap them in.
func _delta_downloaded() -> void:
	var kind: String = _job["kind"]
	if kind == "preload":
		_finish_preload()
		return
	_set_state(State.INSTALLING, "Installing %s..." % _job["version"])
	progress_changed.emit(1.0, "Installing...")
	var err: String = _apply_files(_job["selected"], _job["need"], String(_job["version"]), kind == "update")
	var version: String = _job["version"]
	_job = {}
	_downloading = false
	if err != "":
		_fail(err)
		return
	_cleanup_caches()
	content_changed.emit()
	if kind == "repair":
		_set_state(State.UP_TO_DATE, "Repaired. Cybergram %s is ready." % version)
	else:
		_set_state(State.UP_TO_DATE, "Cybergram %s installed" % version)
	if auto_preload and not latest_next.is_empty():
		start_preload()


## Stages `need` (from the blob caches) and swaps them into game/, removing
## files the old version had but `selected` does not. Writes the version
## file and the installed manifest. Returns "" or an error text.
func _apply_files(selected: Array, need: Array, version: String, write_version: bool) -> String:
	var stage: String = _install_root.path_join("game.stage")
	LauncherCore.remove_tree(stage)
	var paths: PackedStringArray = PackedStringArray()
	for e: Dictionary in need:
		var src: String = _cached_blob(e)
		if src == "":
			LauncherCore.remove_tree(stage)
			return "%s is missing from the download cache. Nothing was changed." % e["path"]
		var dst: String = stage.path_join(e["path"])
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		if DirAccess.copy_absolute(src, dst) != OK:
			LauncherCore.remove_tree(stage)
			return "Cannot stage %s. Is the disk full?" % e["path"]
		paths.append(e["path"])
	var old: Array = ContentManifest.load_installed(game_dir())
	var remove: PackedStringArray = ContentManifest.stale(old, selected)
	for e: Dictionary in _files:  # switched-off packs the old manifest did not know
		if not _listed(selected, e["path"]) and not remove.has(e["path"]) \
				and FileAccess.file_exists(game_dir().path_join(e["path"])) and ContentManifest.is_optional(e["group"]):
			remove.append(e["path"])
	DirAccess.make_dir_recursive_absolute(game_dir())
	var err: String = DeltaInstaller.swap(game_dir(), stage, _install_root.path_join("game.undo"), paths, remove)
	if err != "":
		LauncherCore.remove_tree(stage)
		return "Update failed: %s. The old version was kept." % err
	var exe: String = game_exe_path()
	if _platform != "windows" and FileAccess.file_exists(exe):
		FileAccess.set_unix_permissions(exe, 493)  # 0755
	ContentManifest.save_installed(game_dir(), selected)
	if write_version or installed_version() != version:
		var vf: FileAccess = FileAccess.open(game_dir().path_join(LauncherCore.VERSION_FILE), FileAccess.WRITE)
		if vf == null:
			return "Cannot write the version file."
		vf.store_string(version + "\n")
		vf.close()
	return ""


static func _listed(files: Array, path: String) -> bool:
	for e: Dictionary in files:
		if e["path"] == path:
			return true
	return false


## Deletes the blob caches that are no longer needed (keeps the pre-load
## while it is still ahead of the installed version).
func _cleanup_caches() -> void:
	LauncherCore.remove_tree(_blob_dir("update"))
	var pv: String = _preload_version()
	if pv == "" or LauncherCore.compare_versions(pv, installed_version()) <= 0:
		LauncherCore.remove_tree(_install_root.path_join(PRELOAD_DIR))
		_refresh_preload_text()


func _progress_label() -> String:
	var got: int = int(_job.get("done", 0)) + (_dl.got if _dl != null and _job.get("kind", "") != "zip" else 0)
	if _job.get("kind", "") == "zip" and _dl != null:
		got = _dl.got
	var total: int = int(_job.get("total", 0))
	if _job.get("kind", "") == "zip" and _dl != null and _dl.total > 0:
		total = _dl.total
	return LauncherCore.progress_text(got, total, _speed)


func _process(_delta: float) -> void:
	if _job.is_empty() or _dl == null or not _dl.active:
		return
	var zip: bool = _job["kind"] == "zip"
	var got: int = _dl.got if zip else int(_job["done"]) + _dl.got
	var total: int = int(_job["total"])
	if zip and _dl.total > 0:
		total = _dl.total
	var frac: float = clampf(float(got) / float(total), 0.0, 1.0) if total > 0 else -1.0
	var now: int = Time.get_ticks_msec()
	if _speed_t == 0 or now - _speed_t >= 500:
		if _speed_t != 0:
			_speed = maxf(0.0, float(got - _speed_got) * 1000.0 / float(now - _speed_t))
		_speed_t = now
		_speed_got = got
	if _job["kind"] == "preload":
		_set_preload_text("Pre-loading %s: %s" % [_job["version"], LauncherCore.progress_text(got, total, _speed)])
		return
	progress_changed.emit(frac, LauncherCore.progress_text(got, total, _speed))
	if pause_after_bytes >= 0 and got >= pause_after_bytes and state == State.DOWNLOADING:
		pause_after_bytes = -1
		pause()


func _on_zip_downloaded(ok: bool, err: String) -> void:
	var part: String = _job["part"]
	if not ok:
		if err.begins_with("HTTP"):
			DirAccess.remove_absolute(part)
		_job = {}
		_fail("Download failed (%s)." % err)
		return
	progress_changed.emit(1.0, "Verifying...")
	if not LauncherCore.sha256_matches(part, String(_entry["sha256"])):
		DirAccess.remove_absolute(part)
		_job = {}
		_fail("The download is corrupt (checksum mismatch). Nothing was changed.")
		return
	_job = {}
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
	# Switched-off packs (Lite) are not kept from the full package.
	var skip: PackedStringArray = skip_groups()
	for e: Dictionary in _files:
		if skip.has(e["group"]) and ContentManifest.is_optional(e["group"]):
			DirAccess.remove_absolute(staging.path_join(e["path"]))
	if not _files.is_empty():
		ContentManifest.save_installed(staging, ContentManifest.select(_files, skip))
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
	_cleanup_caches()
	content_changed.emit()
	_set_state(State.UP_TO_DATE, "Cybergram %s installed" % latest_version)
	if auto_preload and not latest_next.is_empty():
		start_preload()


## Hashes the installed files against the signed manifest and re-downloads
## only the missing or corrupt ones (per file; the full package when the feed
## lists no files). An older install is simply updated.
func verify_and_repair() -> void:
	if _entry.is_empty() or is_busy():
		return
	var installed: String = installed_version()
	if installed == "" or LauncherCore.compare_versions(installed, latest_version) < 0:
		start_update()
		return
	# Ahead of the feed (an activated pre-load): verify against its own list.
	var files: Array = _files if LauncherCore.compare_versions(installed, latest_version) == 0 \
		else ContentManifest.load_installed(game_dir())
	if files.is_empty():
		_set_state(State.ERROR, "The update server publishes no file list, so the install cannot be verified.")
		return
	var selected: Array = ContentManifest.select(files, skip_groups())
	_set_state(State.VERIFYING, "Verifying %d files..." % selected.size())
	if is_inside_tree():
		await get_tree().process_frame  # let the UI show the state before hashing
	var bad: PackedStringArray = PackedStringArray()
	for e: Dictionary in ContentManifest.needed(game_dir(), selected):
		bad.append(e["path"])
	verify_done.emit(bad)
	if bad.is_empty():
		_set_state(State.UP_TO_DATE, "All %d files are intact. Cybergram %s is ready." % [selected.size(), installed])
		return
	print("LAUNCHER: verify found %d bad files, e.g. %s" % [bad.size(), bad[0]])
	if _blobs == "" and String(_entry.get("file", "")) != "" and files == _files:
		_start_zip()
	else:
		_start_delta(files, installed, "repair")


# --- pre-load the next patch --------------------------------------------------

func _preload_dir() -> String:
	return _install_root.path_join(PRELOAD_DIR)


## Version of a completed pre-load on disk ("" when none).
func _preload_version() -> String:
	var info: Dictionary = _preload_info()
	return String(info.get("version", ""))


func _preload_info() -> Dictionary:
	var p: String = _preload_dir().path_join("ready.json")
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Downloads the feed's "next" patch into preload/ without activating it.
func start_preload() -> void:
	if latest_next.is_empty() or is_busy() or not _job.is_empty():
		_refresh_preload_text()
		return
	var installed: String = installed_version()
	var nv: String = latest_next["version"]
	if installed == "" or LauncherCore.compare_versions(nv, installed) <= 0:
		_refresh_preload_text()
		return
	if _preload_version() == nv:
		_refresh_preload_text()
		return
	LauncherCore.remove_tree(_preload_dir().path_join("ready.json"))
	_start_delta(latest_next["files"], nv, "preload")


func _finish_preload() -> void:
	var dir: String = _preload_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var ok: bool = true
	var fb: FileAccess = FileAccess.open(dir.path_join("feed.json"), FileAccess.WRITE)
	if fb == null:
		ok = false
	else:
		fb.store_buffer(_feed_body)
		fb.close()
	var fs: FileAccess = FileAccess.open(dir.path_join("feed.json.sig"), FileAccess.WRITE)
	if fs == null:
		ok = false
	else:
		fs.store_string(_feed_sig)
		fs.close()
	var info: Dictionary = {"version": _job["version"], "activate_at": latest_next["activate_at"]}
	var fi: FileAccess = FileAccess.open(dir.path_join("ready.json"), FileAccess.WRITE) if ok else null
	if fi != null:
		fi.store_string(JSON.stringify(info))
		fi.close()
	_job = {}
	_downloading = false
	print("LAUNCHER: pre-load %s" % ("ready" if fi != null else "failed: cannot write preload/"))
	_refresh_preload_text()


## Status line for a ready pre-load, else "".
func _refresh_preload_text() -> void:
	var info: Dictionary = _preload_info()
	var v: String = String(info.get("version", ""))
	if v == "" or installed_version() == "" or LauncherCore.compare_versions(v, installed_version()) <= 0:
		_set_preload_text("")
		return
	_set_preload_text("Pre-loaded %s, ready at %s" % [v, ContentManifest.local_time_text(int(info.get("activate_at", 0)))])


func _set_preload_text(t: String) -> void:
	if t == preload_text:
		return
	preload_text = t
	preload_changed.emit(t)


## Activates a completed pre-load once its time has come (call on every launch
## and check). The stored feed is re-verified with the pinned key, and every
## file must already be in the pre-load cache, so no network is needed.
## Returns true when the new version is now installed.
func activate_preload_if_due() -> bool:
	if is_busy():
		return false
	var info: Dictionary = _preload_info()
	if info.is_empty():
		return false
	var dir: String = _preload_dir()
	var body: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join("feed.json"))
	var sig: String = FileAccess.get_file_as_string(dir.path_join("feed.json.sig"))
	var v: Dictionary = LauncherCore.verify_feed(body, sig, FeedKey.PEM)
	var m: Dictionary = LauncherCore.parse_manifest(body.get_string_from_utf8()) if v["ok"] else {"ok": false}
	var nx: Dictionary = ContentManifest.parse_next(m.get("next", {}), _platform) if m["ok"] else {}
	if nx.is_empty() or nx["version"] != String(info.get("version", "")):
		print("LAUNCHER: discarding an unusable pre-load")
		LauncherCore.remove_tree(dir)
		return false
	var installed: String = installed_version()
	if installed == "" or LauncherCore.compare_versions(nx["version"], installed) <= 0:
		LauncherCore.remove_tree(dir)
		return false
	if now_unix() < int(nx["activate_at"]):
		return false
	var selected: Array = ContentManifest.select(nx["files"], skip_groups())
	var need: Array = ContentManifest.needed(game_dir(), selected)
	var exe_before: String = String(_entry.get("exe", ""))
	_entry["exe"] = nx["exe"]
	var err: String = _apply_files(selected, need, nx["version"], true)
	if err != "":
		_entry["exe"] = exe_before
		print("LAUNCHER: pre-load activation failed: %s" % err)
		return false
	print("LAUNCHER: activated pre-loaded %s (%d files changed)" % [nx["version"], need.size()])
	LauncherCore.remove_tree(dir)
	LauncherCore.remove_tree(_blob_dir("update"))
	_set_preload_text("")
	content_changed.emit()
	return true


# --- install management -------------------------------------------------------

## Moves the installed game (and its content selection and pre-load) to
## `new_root` and switches this updater to the new root. Tries a rename,
## falls back to copy + delete (other drive). Returns "" on success or an
## error text; the old install stays on failure.
func move_install(new_root: String) -> String:
	var target: String = new_root.path_join(LauncherCore.GAME_DIR)
	if new_root.simplify_path() == _install_root.simplify_path():
		return ""
	if is_busy():
		return "Wait until the current download has finished."
	if DirAccess.dir_exists_absolute(target):
		return "The folder %s already contains a game folder." % new_root
	var err: Error = DirAccess.make_dir_recursive_absolute(new_root)
	if err != OK:
		return "Cannot create %s (%s)." % [new_root, error_string(err)]
	for item in [LauncherCore.GAME_DIR, PRELOAD_DIR]:
		var from: String = _install_root.path_join(item)
		var to: String = new_root.path_join(item)
		if not DirAccess.dir_exists_absolute(from):
			continue
		if DirAccess.rename_absolute(from, to) != OK:
			var cerr: String = LauncherCore.copy_tree(from, to)
			if cerr != "":
				LauncherCore.remove_tree(to)
				if item == PRELOAD_DIR:
					continue  # a pre-load is optional: download it again later
				return "Moving failed: %s. The old install was kept." % cerr
			LauncherCore.remove_tree(from)
	var cfg: String = _install_root.path_join(ContentManifest.CONTENT_CFG)
	if FileAccess.file_exists(cfg):
		if DirAccess.copy_absolute(cfg, new_root.path_join(ContentManifest.CONTENT_CFG)) == OK:
			DirAccess.remove_absolute(cfg)
	LauncherCore.remove_tree(_install_root.path_join("downloads"))
	_install_root = new_root
	return ""


## {"used": bytes of game/ + caches, "free": bytes free on its drive (-1 unknown)}.
func disk_usage() -> Dictionary:
	var used: int = ContentManifest.tree_size(game_dir()) + ContentManifest.tree_size(_preload_dir()) \
		+ ContentManifest.tree_size(_install_root.path_join("downloads"))
	var probe: String = _install_root
	while probe != "" and not DirAccess.dir_exists_absolute(probe):
		var up: String = probe.get_base_dir()
		if up == probe:
			break
		probe = up
	var d: DirAccess = DirAccess.open(probe) if probe != "" else null
	return {"used": used, "free": d.get_space_left() if d != null else -1}


## Folder of the game's own saved settings (Godot user data, next to the
## launcher's own user folder).
static func game_user_dir() -> String:
	return OS.get_user_data_dir().get_base_dir().path_join("Cybergram")


## Deletes the installed game, its caches and content selection. With
## `keep_settings` false the game's saved settings go too. The launcher and
## its own settings stay. Returns "" or an error text.
func uninstall_game(keep_settings: bool, user_dir: String = "") -> String:
	if is_busy():
		return "Wait until the current download has finished."
	for item in [LauncherCore.GAME_DIR, "game.new", "game.old", "game.stage", "game.undo", "downloads", PRELOAD_DIR]:
		if not LauncherCore.remove_tree(_install_root.path_join(item)):
			return "Could not delete %s. Is the game still running?" % _install_root.path_join(item)
	DirAccess.remove_absolute(_install_root.path_join(ContentManifest.CONTENT_CFG))
	if not keep_settings:
		LauncherCore.remove_tree(user_dir if user_dir != "" else game_user_dir())
	print("LAUNCHER: game uninstalled from %s (settings %s)" % [_install_root, "kept" if keep_settings else "deleted"])
	_set_preload_text("")
	content_changed.emit()
	if not _entry.is_empty():
		_decide()
	else:
		_set_state(State.OFFLINE_NONE, "Cybergram is not installed.")
	return ""


func _fail(msg: String) -> void:
	_downloading = false
	_job = {}
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
