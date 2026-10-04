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
static func apply_update(new_dir: String, target_dir: String) -> String:
	var swapped: Array = []  # [target, had_old]
	for file_name in DirAccess.get_files_at(new_dir):
		var target: String = target_dir.path_join(file_name)
		if file_name == "launcher.cfg" and FileAccess.file_exists(target):
			continue
		var had_old: bool = FileAccess.file_exists(target)
		if had_old:
			DirAccess.remove_absolute(target + ".old")
			if DirAccess.rename_absolute(target, target + ".old") != OK:
				_roll_back(swapped)
				return "cannot move %s aside" % file_name
		if DirAccess.rename_absolute(new_dir.path_join(file_name), target) != OK:
			if had_old:
				DirAccess.rename_absolute(target + ".old", target)
			_roll_back(swapped)
			return "cannot install %s" % file_name
		swapped.append([target, had_old])
		if OS.get_name() != "Windows" and file_name.ends_with(".x86_64"):
			FileAccess.set_unix_permissions(target, 493)  # 0755
	return ""


static func _roll_back(swapped: Array) -> void:
	for pair: Array in swapped:
		var target: String = pair[0]
		DirAccess.remove_absolute(target)
		if pair[1]:
			DirAccess.rename_absolute(target + ".old", target)


## Deletes leftovers (*.old) from a previous self-update. Call at startup.
static func cleanup_old(dir_path: String) -> void:
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".old"):
			DirAccess.remove_absolute(dir_path.path_join(file_name))
	LauncherCore.remove_tree(dir_path.path_join("launcher.new"))
