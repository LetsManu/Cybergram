class_name AccountStore
extends RefCounted
## Server-side account storage interface (design/ux/lobby-and-social.md §6).
## An account is a JSON-safe Dictionary with exactly these keys:
##   id (32 hex), username, password {algo, hash, salt, iterations},
##   profile {display_name, emblem, accent, favourite_hero},
##   friends [ids], requests_in [ids], requests_out [ids], blocks [ids],
##   created_at, last_login_at (unix seconds).
## Nothing else: no e-mail, no IP, no hardware ids. Implementations:
## FileAccountStore (JSON files, atomic writes). Getters return copies; a
## change is only kept after put().

const ACCOUNT_KEYS: Array[String] = ["id", "username", "password", "profile", "friends", "requests_in",
	"requests_out", "blocks", "created_at", "last_login_at"]
const LIST_KEYS: Array[String] = ["friends", "requests_in", "requests_out", "blocks"]


## Loads existing accounts. Returns OK or an error code.
func open() -> int:
	return ERR_UNAVAILABLE


func count() -> int:
	return 0


## Copy of the account with `id`, or {}.
func get_by_id(_id: String) -> Dictionary:
	return {}


## Copy of the account whose username matches (case-insensitive), or {}.
func find_username(_username: String) -> Dictionary:
	return {}


## Saves (creates or replaces) an account durably. False on failure.
func put(_account: Dictionary) -> bool:
	return false


## Every account id (for sweeps).
func ids() -> PackedStringArray:
	return PackedStringArray()


## Removes the account file only (see delete_cascade()).
func _remove(_id: String) -> bool:
	return false


## Deletes `id` and removes it from every other account's friends, requests
## and blocks. Returns false when there was no such account.
func delete_cascade(id: String) -> bool:
	var a := get_by_id(id)
	if a.is_empty():
		return false
	var touched := {}
	for k in LIST_KEYS:
		for other in a.get(k, []):
			touched[str(other)] = true
	# A block by someone else is not listed on the deleted account: scan all.
	for other_id in ids():
		if other_id == id:
			continue
		var o := get_by_id(other_id)
		var changed := touched.has(other_id)
		for k in LIST_KEYS:
			var l: Array = o.get(k, [])
			if l.has(id):
				l.erase(id)
				changed = true
		if changed:
			put(o)
	return _remove(id)


## Deletes accounts whose last login (or creation) is older than `days`.
## Returns the deleted ids.
func sweep_inactive(now_unix: int, days: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cutoff := now_unix - days * 86400
	for id in ids():
		var a := get_by_id(id)
		var last := maxi(int(a.get("last_login_at", 0)), int(a.get("created_at", 0)))
		if last < cutoff:
			out.append(id)
	for id in out:
		delete_cascade(id)
	return out


## A new account Dictionary with every key present.
static func new_account(id: String, username: String, password: Dictionary, profile: Dictionary, now_unix: int) -> Dictionary:
	return {"id": id, "username": username, "password": password, "profile": profile, "friends": [],
		"requests_in": [], "requests_out": [], "blocks": [], "created_at": now_unix, "last_login_at": now_unix}


## True when `a` has exactly the account keys with sane types.
static func is_well_formed(a: Dictionary) -> bool:
	if a.size() != ACCOUNT_KEYS.size():
		return false
	for k in ACCOUNT_KEYS:
		if not a.has(k):
			return false
	if not PlayerProfile.is_hex_id(str(a.id)) or not (a.password is Dictionary) or not (a.profile is Dictionary):
		return false
	for k in LIST_KEYS:
		if not (a[k] is Array):
			return false
	return true
