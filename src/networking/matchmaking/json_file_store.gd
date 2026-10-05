class_name JsonFileStore
extends RefCounted
## Owner-only JSON files for the front's small stores (match history,
## lockouts): folder 0700, file 0600 on Unix, written atomically (tmp, flush,
## rename), like FileAccountStore.


## The parsed JSON of `<dir>/<file>`, or null when missing / unreadable.
static func load_json(dir: String, file: String) -> Variant:
	var path := FileAccountStore._abs(dir).path_join(file)
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_warning("[store] unreadable %s, starting empty" % file)
	return data


static func save_json(dir: String, file: String, data: Variant) -> bool:
	var d := FileAccountStore._abs(dir)
	if not DirAccess.dir_exists_absolute(d):
		if DirAccess.make_dir_recursive_absolute(d) != OK:
			return false
		FileAccountStore._owner_only(d, FileAccountStore.DIR_MODE)
	var final := d.path_join(file)
	var tmp := final + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	FileAccountStore._owner_only(tmp, FileAccountStore.FILE_MODE)
	f.store_string(JSON.stringify(data))
	f.flush()
	f.close()
	if DirAccess.rename_absolute(tmp, final) != OK:
		DirAccess.remove_absolute(final)
		if DirAccess.rename_absolute(tmp, final) != OK:
			DirAccess.remove_absolute(tmp)
			return false
	return true
