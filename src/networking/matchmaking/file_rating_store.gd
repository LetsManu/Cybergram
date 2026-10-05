class_name FileRatingStore
extends MemoryRatingStore
## RatingStore on JSON files, following FileAccountStore: `<dir>/<id>.json`
## per account ({"id": ..., "tracks": {track: entry}}), written atomically
## (tmp, flush, rename), folder 0700 and files 0600 on Unix. Everything is
## indexed in memory at open().
##
## Example:
##   var store := FileRatingStore.new("/data/ratings")
##   store.open()

var data_dir: String


func _init(data_dir_: String) -> void:
	data_dir = data_dir_


func open() -> int:
	_by_id.clear()
	var dir := FileAccountStore._abs(data_dir)
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and not DirAccess.dir_exists_absolute(dir):
		return err
	FileAccountStore._owner_only(dir, FileAccountStore.DIR_MODE)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tmp"):
			DirAccess.remove_absolute(dir.path_join(f))
			continue
		if not f.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not _well_formed_file(data) or f != "%s.json" % data.id:
			push_warning("[ratings] skipping unreadable rating file %s" % f.get_basename().left(8))
			continue
		var tracks := {}
		for t in data.tracks:
			tracks[t] = MemoryRatingStore._clean(data.tracks[t])
		_by_id[data.id] = tracks
	return OK


func _persist(account_id: String, tracks: Dictionary) -> bool:
	var dir := FileAccountStore._abs(data_dir)
	var final := dir.path_join("%s.json" % account_id)
	var tmp := final + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	FileAccountStore._owner_only(tmp, FileAccountStore.FILE_MODE)
	f.store_string(JSON.stringify({"id": account_id, "tracks": tracks}, "\t"))
	f.flush()
	f.close()
	if DirAccess.rename_absolute(tmp, final) != OK:
		DirAccess.remove_absolute(final)
		if DirAccess.rename_absolute(tmp, final) != OK:
			DirAccess.remove_absolute(tmp)
			return false
	return true


func _unpersist(account_id: String) -> void:
	DirAccess.remove_absolute(FileAccountStore._abs(data_dir).path_join("%s.json" % account_id))


static func _well_formed_file(data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("id") or not data.has("tracks"):
		return false
	if not (data.id is String) or not RatingStore.is_valid_id(data.id) or not (data.tracks is Dictionary):
		return false
	for t in data.tracks:
		if not (data.tracks[t] is Dictionary) or not RatingStore.is_well_formed(data.tracks[t]):
			return false
	return true
