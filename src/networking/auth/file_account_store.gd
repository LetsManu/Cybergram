class_name FileAccountStore
extends AccountStore
## AccountStore on plain JSON files: `<data_dir>/accounts/<id>.json`, one per
## account, written atomically (write `<id>.json.tmp`, flush, rename over the
## old file), so a crash never leaves a half-written account. All accounts are
## indexed in memory at open() (username -> id). No SQLite, no GDExtension.
##
## Example:
##   var store := FileAccountStore.new("/data")      # or "user://accounts"
##   store.open()
##   store.put(AccountStore.new_account(id, "neo", pw, profile, now))

var data_dir: String
var _by_id: Dictionary = {}
var _by_name: Dictionary = {}  # lower-case username -> id


func _init(data_dir_: String) -> void:
	data_dir = data_dir_


func accounts_dir() -> String:
	return data_dir.path_join("accounts")


func open() -> int:
	_by_id.clear()
	_by_name.clear()
	var dir := _abs(accounts_dir())
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and not DirAccess.dir_exists_absolute(dir):
		return err
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tmp"):
			DirAccess.remove_absolute(dir.path_join(f))  # an interrupted write: the old file is intact
			continue
		if not f.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not (data is Dictionary) or not AccountStore.is_well_formed(data) or f != "%s.json" % data.id:
			push_warning("[accounts] skipping unreadable account file %s" % f.get_basename().left(8))
			continue
		_by_id[data.id] = data
		_by_name[str(data.username).to_lower()] = data.id
	return OK


func count() -> int:
	return _by_id.size()


func get_by_id(id: String) -> Dictionary:
	var a: Dictionary = _by_id.get(id, {})
	return a.duplicate(true)


func find_username(username: String) -> Dictionary:
	var id: String = _by_name.get(username.to_lower(), "")
	return get_by_id(id) if id != "" else {}


func ids() -> PackedStringArray:
	return PackedStringArray(_by_id.keys())


func put(account: Dictionary) -> bool:
	if not AccountStore.is_well_formed(account):
		return false
	var id: String = account.id
	var final := _abs(accounts_dir()).path_join("%s.json" % id)
	var tmp := final + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(account, "\t"))
	f.flush()
	f.close()
	if DirAccess.rename_absolute(tmp, final) != OK:
		# Platforms whose rename does not replace: remove, then rename.
		DirAccess.remove_absolute(final)
		if DirAccess.rename_absolute(tmp, final) != OK:
			DirAccess.remove_absolute(tmp)
			return false
	var old: Dictionary = _by_id.get(id, {})
	if not old.is_empty():
		_by_name.erase(str(old.username).to_lower())
	_by_id[id] = account.duplicate(true)
	_by_name[str(account.username).to_lower()] = id
	return true


func _remove(id: String) -> bool:
	var a: Dictionary = _by_id.get(id, {})
	if a.is_empty():
		return false
	DirAccess.remove_absolute(_abs(accounts_dir()).path_join("%s.json" % id))
	_by_name.erase(str(a.username).to_lower())
	_by_id.erase(id)
	return true


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("user://") or p.begins_with("res://") else p
