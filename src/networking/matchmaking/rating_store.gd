class_name RatingStore
extends RefCounted
## Rating storage interface (W17-MM). One entry per account per track
## (&"normal", &"ranked", &"all_random"):
##   {rating: float, rd: float, vol: float, games: int, updated_at: int}
## Nothing else: no IP, no name, no match list (GDPR data minimisation;
## PRIVACY.md "Ratings"). Kept until the account is deleted
## (erase_account() from the account deletion cascade). Implementations:
## MemoryRatingStore (tests, dev), FileRatingStore (JSON file per account).
## Getters return copies; a change is only kept after put_entry().

const ENTRY_KEYS: Array[String] = ["rating", "rd", "vol", "games", "updated_at"]


## Loads stored ratings. OK or an error code.
func open() -> int:
	return ERR_UNAVAILABLE


## Copy of the entry for `account_id` on `track`, or {} when unrated.
func get_entry(_account_id: String, _track: StringName) -> Dictionary:
	return {}


## Saves one entry durably. False on failure or a malformed entry.
func put_entry(_account_id: String, _track: StringName, _entry: Dictionary) -> bool:
	return false


## Deletes every track of `account_id`. False when there was nothing.
func erase_account(_account_id: String) -> bool:
	return false


## Every account id with at least one entry.
func ids() -> PackedStringArray:
	return PackedStringArray()


## True when `e` has exactly the entry keys with sane values.
static func is_well_formed(e: Dictionary) -> bool:
	if e.size() != ENTRY_KEYS.size():
		return false
	for k in ENTRY_KEYS:
		if not e.has(k) or not (e[k] is float or e[k] is int):
			return false
	return float(e.rd) > 0.0 and float(e.vol) > 0.0 and int(e.games) >= 0


## Account ids are 32 lower-case hex (AccountStore); also guards file paths.
static func is_valid_id(id: String) -> bool:
	if id.length() != 32:
		return false
	for c in id:
		if not (c in "0123456789abcdef"):
			return false
	return true
