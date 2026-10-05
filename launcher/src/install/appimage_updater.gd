class_name AppImageUpdater
extends Node
## Replaces the running AppImage with the newer one named in the signed feed
## (W15-UPD): download next to $APPIMAGE as <name>.part (resumable), check the
## sha256 from the signed feed, copy to <name>.new, chmod +x, rename over
## $APPIMAGE (atomic on the same filesystem), then the caller relaunches.
## A running AppImage keeps working after its file is replaced (the kernel
## holds the old inode until it exits).

## Emitted once: ok, a human message.
signal finished(ok: bool, message: String)

var _target: String = ""
var _sha: String = ""
var _dl: LauncherDownloader


## Downloads `entry["appimage"]` (from LauncherCore.launcher_update_for) from
## `base_url` and replaces `appimage_path`.
func start(entry: Dictionary, appimage_path: String, base_url: String, limit_bps: int = 0) -> void:
	var ai: Dictionary = entry.get("appimage", {})
	_target = appimage_path
	_sha = String(ai.get("sha256", ""))
	if ai.is_empty() or _target == "":
		finished.emit(false, "The update feed has no AppImage for this launcher.")
		return
	if not FileAccess.file_exists(_target):
		finished.emit(false, "The running AppImage was not found at %s." % _target)
		return
	_dl = LauncherDownloader.new()
	_dl.limit_bps = limit_bps
	add_child(_dl)
	_dl.finished.connect(_on_done)
	var url: String = String(ai.get("url", ""))
	_dl.start(url if url != "" else base_url + String(ai["file"]), _target + ".part", int(ai.get("size", 0)))


func _on_done(ok: bool, err: String) -> void:
	var part: String = _target + ".part"
	if not ok:
		if err.begins_with("HTTP"):
			DirAccess.remove_absolute(part)
		finished.emit(false, "AppImage download failed (%s)." % err)
		return
	var rerr: String = replace(part, _target, _sha)
	if rerr != "":
		finished.emit(false, "AppImage update failed: %s. The old AppImage was kept." % rerr)
		return
	finished.emit(true, "Launcher updated.")


## Verifies `part` against `sha`, then swaps it in for `target` via
## `<target>.new` + rename. Returns "" or an error text; `target` is untouched
## on any failure and `part` is deleted when its checksum is wrong.
static func replace(part: String, target: String, sha: String) -> String:
	if not LauncherCore.sha256_matches(part, sha):
		DirAccess.remove_absolute(part)
		return "checksum mismatch"
	var tmp: String = target + ".new"
	DirAccess.remove_absolute(tmp)
	if DirAccess.rename_absolute(part, tmp) != OK:
		if DirAccess.copy_absolute(part, tmp) != OK:
			return "cannot write next to %s (read-only folder?)" % target.get_file()
		DirAccess.remove_absolute(part)
	FileAccess.set_unix_permissions(tmp, 493)  # 0755
	if DirAccess.rename_absolute(tmp, target) != OK:
		DirAccess.remove_absolute(tmp)
		return "cannot replace %s" % target.get_file()
	return ""
