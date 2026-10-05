class_name MatchHostFiles
extends RefCounted
## File hand-over between the supervisor and its match processes (W17).
## Boot and match-setup files carry a per-process secret, a ticket key and
## account ids, so they are created owner-only (0600) inside an owner-only
## directory (0700) BEFORE any content is written, and the match process
## deletes each file right after reading it. Overridden in tests (memory).

const MAX_BYTES := 65536

## Directory for the files ("" = <OS temp>/cybergram-host-<pid>).
var run_dir: String = ""


func _init(run_dir_: String = "") -> void:
	run_dir = run_dir_ if run_dir_ != "" else OS.get_temp_dir().path_join("cybergram-host-%d" % OS.get_process_id())


## Creates run_dir (0700). False on failure.
func prepare() -> bool:
	if not DirAccess.dir_exists_absolute(run_dir) and DirAccess.make_dir_recursive_absolute(run_dir) != OK:
		return false
	return FileAccess.set_unix_permissions(run_dir, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
		| FileAccess.UNIX_EXECUTE_OWNER) == OK


## Writes `data` as JSON to run_dir/<name>, owner-only. Returns the absolute
## path or "" on failure.
func write_secure(file_name: String, data: Dictionary) -> String:
	var path := run_dir.path_join(file_name.validate_filename())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ""
	f.close()
	if FileAccess.set_unix_permissions(tmp, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER) != OK:
		DirAccess.remove_absolute(tmp)
		return ""
	f = FileAccess.open(tmp, FileAccess.READ_WRITE)
	if f == null:
		DirAccess.remove_absolute(tmp)
		return ""
	f.store_string(JSON.stringify(data))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return ""
	return path


## Reads a JSON object from `path` and deletes the file. {} on any error.
func read_and_delete(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_buffer(mini(f.get_length(), MAX_BYTES)).get_string_from_utf8()
	f.close()
	DirAccess.remove_absolute(path)
	var v: Variant = JSON.parse_string(text)
	return v if v is Dictionary else {}


func remove(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func exists(path: String) -> bool:
	return path != "" and FileAccess.file_exists(path)


## Replaces `path` with `text` atomically (health/status file).
func write_atomic(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true
