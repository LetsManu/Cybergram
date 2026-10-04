class_name PresenceRegistry
extends RefCounted
## Server-side presence (design/ux/lobby-and-social.md §2.4, §4 Privacy):
## who is connected right now and where (lobby / match / menu check-in), with
## their current display name, and the id -> key claim of each connected
## player (so nobody can take a seat with a copied id). **Memory only and
## connection-scoped**: an entry is forgotten when the player disconnects
## (forget()), when a menu check-in expires (ONLINE_TTL_S) or when the match
## ends (end_match()). Nothing is written to disk and nothing is logged.
## `shared()` is per server process; tests build their own with new().
##
## Example:
##   var reg := PresenceRegistry.shared()
##   if reg.claim(id, key, name): reg.set_status(id, LobbyCodec.STATUS_IN_LOBBY, now)
##   reg.forget(id)  # on disconnect

## A main-menu check-in (short presence query) counts as "online" this long.
const ONLINE_TTL_S: float = 25.0
## Most simultaneous entries (a flood of check-ins cannot grow memory).
const MAX_ENTRIES: int = 1024

static var _shared: PresenceRegistry

## id -> {key, name, status, seen_s}
var entries: Dictionary = {}


## The process-wide registry of this server.
static func shared() -> PresenceRegistry:
	if _shared == null:
		_shared = PresenceRegistry.new()
	return _shared


## Seconds on the server's monotonic clock (callers may pass their own).
static func now_s() -> float:
	return Time.get_ticks_msec() / 1000.0


## Registers / verifies `id` with `key` and records its (already validated)
## name. False when the id is malformed, claimed right now with a different
## key, or the registry is full.
func claim(id: String, key: String, name: String, now: float = now_s()) -> bool:
	if not PlayerProfile.is_hex_id(id) or not PlayerProfile.is_hex_id(key):
		return false
	var e: Dictionary = entries.get(id, {})
	if e.is_empty():
		if entries.size() >= MAX_ENTRIES:
			purge(now)
			if entries.size() >= MAX_ENTRIES:
				return false
		entries[id] = {"key": key, "name": name, "status": LobbyCodec.STATUS_ONLINE, "seen_s": now}
		return true
	if e.key != key:
		return false
	e.name = name
	return true


## Sets the status of a claimed id (unknown ids are ignored).
func set_status(id: String, status: int, now: float) -> void:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty():
		return
	e.status = status
	e.seen_s = now


## Drops everything about `id` (the player disconnected).
func forget(id: String) -> void:
	entries.erase(id)


## Effective status of `id` at `now` (unknown or expired = offline).
func status_of(id: String, now: float) -> int:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty():
		return LobbyCodec.STATUS_OFFLINE
	if e.status == LobbyCodec.STATUS_ONLINE and now - float(e.seen_s) > ONLINE_TTL_S:
		return LobbyCodec.STATUS_OFFLINE
	return e.status


## Forgets expired menu check-ins.
func purge(now: float) -> void:
	for id in entries.keys():
		if status_of(id, now) == LobbyCodec.STATUS_OFFLINE:
			entries.erase(id)


## The match ended: its players are forgotten (those who return re-join the
## new lobby and are registered again).
func end_match(now: float) -> void:
	for id in entries.keys():
		if entries[id].status == LobbyCodec.STATUS_IN_MATCH:
			entries.erase(id)
	purge(now)
