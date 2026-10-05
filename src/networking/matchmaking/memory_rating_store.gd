class_name MemoryRatingStore
extends RatingStore
## RatingStore held in memory only (tests, local dev). FileRatingStore adds
## persistence on top.

var _by_id: Dictionary = {}  # account id -> {track (String): entry}


func open() -> int:
	return OK


func get_entry(account_id: String, track: StringName) -> Dictionary:
	var tracks: Dictionary = _by_id.get(account_id, {})
	var e: Dictionary = tracks.get(String(track), {})
	return e.duplicate()


func put_entry(account_id: String, track: StringName, entry: Dictionary) -> bool:
	if not RatingStore.is_valid_id(account_id) or String(track) == "" or not RatingStore.is_well_formed(entry):
		return false
	var tracks: Dictionary = (_by_id.get(account_id, {}) as Dictionary).duplicate(true)
	tracks[String(track)] = _clean(entry)
	if not _persist(account_id, tracks):
		return false
	_by_id[account_id] = tracks
	return true


func erase_account(account_id: String) -> bool:
	if not _by_id.has(account_id):
		return false
	_unpersist(account_id)
	_by_id.erase(account_id)
	return true


func ids() -> PackedStringArray:
	return PackedStringArray(_by_id.keys())


## Hook for FileRatingStore: write all tracks of one account.
func _persist(_account_id: String, _tracks: Dictionary) -> bool:
	return true


## Hook for FileRatingStore: delete the stored account.
func _unpersist(_account_id: String) -> void:
	pass


static func _clean(e: Dictionary) -> Dictionary:
	return {"rating": float(e.rating), "rd": float(e.rd), "vol": float(e.vol),
		"games": int(e.games), "updated_at": int(e.updated_at)}
