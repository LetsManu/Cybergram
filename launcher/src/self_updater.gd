class_name SelfUpdater
extends Node
## Replaces the launcher's own files with a newer package from the update feed.
##
## Steps: download <file>.part, verify sha256, unpack into <launcher_dir>/launcher.new,
## then swap file by file. Every file being replaced is first renamed to
## <name>.old (a running exe can be renamed on Windows and Linux, but not
## overwritten), the new one is moved in, and the .old files are deleted on the
## next start (`cleanup_old`). A failed swap is rolled back. launcher.cfg is the
## player's own config and is never overwritten.

## Emitted once: ok, a human message, and the new version when ok.
signal finished(ok: bool, message: String, new_version: String)

var _launcher_dir: String = ""
var _work_dir: String = ""
var _base_url: String = ""
var _entry: Dictionary = {}
var _http: HTTPRequest


## `launcher_dir` holds the launcher exe; `work_dir` gets the download.
func setup(launcher_dir: String, work_dir: String, base_url: String) -> void:
	_launcher_dir = launcher_dir
	_work_dir = work_dir
	_base_url = base_url


## Starts the download of `entry` (from LauncherCore.launcher_update_for).
func start(entry: Dictionary) -> void:
	_entry = entry
	DirAccess.make_dir_recursive_absolute(_work_dir)
	var part: String = _work_dir.path_join(String(entry["file"]) + ".part")
	DirAccess.remove_absolute(part)
	_http = HTTPRequest.new()
	_http.download_file = part
	_http.timeout = 120.0
	add_child(_http)
	_http.request_completed.connect(_on_downloaded.bind(part))
	var err: Error = _http.request(_base_url + String(entry["file"]))
	if err != OK:
		finished.emit(false, "Could not start the launcher download (%s)." % error_string(err), "")


func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray, part: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		finished.emit(false, "Launcher download failed (%s)." % (
			"HTTP %d" % code if result == HTTPRequest.RESULT_SUCCESS else "network error %d" % result), "")
		return
	if not LauncherCore.sha256_matches(part, String(_entry["sha256"])):
		DirAccess.remove_absolute(part)
		finished.emit(false, "The launcher download is corrupt (checksum mismatch). Nothing was changed.", "")
		return
	var staging: String = _launcher_dir.path_join("launcher.new")
	LauncherCore.remove_tree(staging)
	var err: String = LauncherCore.extract_zip(part, staging)
	DirAccess.remove_absolute(part)
	if err == "" and not FileAccess.file_exists(staging.path_join(String(_entry["exe"]))):
		err = "the package has no %s" % _entry["exe"]
	if err == "":
		err = apply_update(staging, _launcher_dir)
	LauncherCore.remove_tree(staging)
	if err != "":
		finished.emit(false, "Launcher update failed: %s. The old launcher was kept." % err, "")
		return
	finished.emit(true, "Launcher updated to %s." % _entry["version"], String(_entry["version"]))


## Swaps every file below `new_dir` into `target_dir` (see class doc).
## Returns "" on success or an error text (after rolling back).
## `remover` (optional, for tests) replaces the delete of a leftover: it takes a
## path and returns true when the path is gone.
static func apply_update(new_dir: String, target_dir: String, remover: Callable = Callable()) -> String:
	var swapped: Array = []  # [target, had_old]
	for file_name in DirAccess.get_files_at(new_dir):
		var target: String = target_dir.path_join(file_name)
		if file_name == "launcher.cfg" and FileAccess.file_exists(target):
			continue
		var had_old: bool = FileAccess.file_exists(target)
		var aside: String = ""
		if had_old:
			aside = move_aside(target, remover)
			if aside == "":
				_roll_back(swapped)
				return "cannot move %s aside" % file_name
		if DirAccess.rename_absolute(new_dir.path_join(file_name), target) != OK:
			if had_old:
				DirAccess.rename_absolute(aside, target)
			_roll_back(swapped)
			return "cannot install %s" % file_name
		swapped.append([target, aside])
		if OS.get_name() != "Windows" and file_name.ends_with(".x86_64"):
			FileAccess.set_unix_permissions(target, 493)  # 0755
	return ""


static func _roll_back(swapped: Array) -> void:
	for pair: Array in swapped:
		var target: String = pair[0]
		DirAccess.remove_absolute(target)
		if String(pair[1]) != "":
			DirAccess.rename_absolute(String(pair[1]), target)


## Renames `target` to `<target>.old`, or to `<target>.old.<n>` when that name
## is taken and cannot be deleted (a locked file on Windows, a virus scanner,
## the previous launcher process still exiting). Returns the new path, or ""
## when no name worked. Never loops: at most MAX_ASIDE_TRIES names are tried.
static func move_aside(target: String, remover: Callable = Callable()) -> String:
	for n in range(MAX_ASIDE_TRIES):
		var candidate: String = target + (".old" if n == 0 else ".old.%d" % n)
		if FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate):
			var gone: bool = remover.call(candidate) if remover.is_valid() else _remove_any(candidate)
			if not gone:
				continue  # cannot delete it: try the next name
		if DirAccess.rename_absolute(target, candidate) == OK:
			return candidate
	return ""


static func _remove_any(path: String) -> bool:
	LauncherCore.remove_tree(path)  # directories too
	DirAccess.remove_absolute(path)
	return not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)


static var _LEFTOVER_RX: RegEx = RegEx.create_from_string("\\.old(\\.\\d+)?$")


## True for `x.old` and `x.old.<n>` leftovers (not e.g. `my.old.notes.txt`).
static func is_leftover(file_name: String) -> bool:
	return _LEFTOVER_RX.search(file_name) != null


## Deletes leftovers (*.old, *.old.<n>) from earlier self-updates, best effort:
## a file that is still locked is skipped and tried again next start. Returns
## how many leftovers could not be removed. Call at startup.
static func cleanup_old(dir_path: String) -> int:
	var left: int = 0
	for file_name in DirAccess.get_files_at(dir_path):
		if is_leftover(file_name):
			DirAccess.remove_absolute(dir_path.path_join(file_name))
			if FileAccess.file_exists(dir_path.path_join(file_name)):
				left += 1
	for dir_name in DirAccess.get_directories_at(dir_path):
		if is_leftover(dir_name) and not LauncherCore.remove_tree(dir_path.path_join(dir_name)):
			left += 1
	LauncherCore.remove_tree(dir_path.path_join("launcher.new"))
	return left


## A failed self-update of `version` is not retried for this many seconds.
const RETRY_COOLDOWN_SEC: int = 86400
const MAX_ASIDE_TRIES: int = 8


## True when an update to `version` may be attempted now: it did not fail
## within the cooldown. `failed_version`/`failed_at` come from LauncherSettings.
static func may_attempt(version: String, failed_version: String, failed_at: int, now: int) -> bool:
	if failed_version != version or failed_at <= 0:
		return true
	return now - failed_at >= RETRY_COOLDOWN_SEC or now < failed_at  # clock went back: allow
