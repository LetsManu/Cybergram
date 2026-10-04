class_name PresenceRegistry
extends RefCounted
## Server-side presence (design/ux/lobby-and-social.md §2.4): every player id
## the server has seen, its last validated name and its status (online in the
## menu / in the lobby / in a match / offline). Also the id -> key claims that
## stop one player from taking another's id. `shared()` lives for the whole
## server process, so it survives the scene reload between matches; tests
## build their own with new().
##
## Example:
##   var reg := PresenceRegistry.shared()
##   if reg.claim(id, key, name): reg.set_status(id, LobbyCodec.STATUS_IN_LOBBY, now)
##   transport.send(peer, ch0, LobbyCodec.encode_presence(reg.answer(ids, names, now)))

## A menu check-in counts as "online" for this long.
const ONLINE_TTL_S: float = 25.0
## Most ids remembered (oldest offline entries are forgotten first).
const MAX_ENTRIES: int = 4096
## A name lookup returns at most this many players per name.
const MAX_MATCHES_PER_NAME: int = 3

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
## name. False when the id is malformed or claimed with a different key.
func claim(id: String, key: String, name: String) -> bool:
	if not PlayerProfile.is_hex_id(id) or not PlayerProfile.is_hex_id(key):
		return false
	var e: Dictionary = entries.get(id, {})
	if e.is_empty():
		if entries.size() >= MAX_ENTRIES:
			_evict()
		entries[id] = {"key": key, "name": name, "status": LobbyCodec.STATUS_OFFLINE, "seen_s": 0.0}
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


## Effective status of `id` at `now` (an expired menu check-in is offline).
func status_of(id: String, now: float) -> int:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty():
		return LobbyCodec.STATUS_OFFLINE
	if e.status == LobbyCodec.STATUS_ONLINE and now - float(e.seen_s) > ONLINE_TTL_S:
		return LobbyCodec.STATUS_OFFLINE
	return e.status


## Players marked in a match go offline (a new lobby opened; returning
## players re-join it and become "in lobby" again).
func end_match(now: float) -> void:
	for id in entries:
		if entries[id].status == LobbyCodec.STATUS_IN_MATCH:
			entries[id].status = LobbyCodec.STATUS_OFFLINE
			entries[id].seen_s = now


## Presence reply entries ({id, status, name}) for `ids` plus every player
## whose name matches one of `names` (case-insensitive; "Name#TAG" also
## matches the tag). Unknown ids come back offline with an empty name.
func answer(ids: PackedStringArray, names: PackedStringArray, now: float) -> Array:
	var out: Array = []
	var seen := {}
	for id in ids:
		if seen.has(id) or out.size() >= LobbyCodec.MAX_PRESENCE_REPLY:
			continue
		seen[id] = true
		var e: Dictionary = entries.get(id, {})
		out.append({"id": id, "status": status_of(id, now), "name": str(e.get("name", ""))})
	for raw in names:
		var parsed := FriendList.parse(raw)
		if parsed.is_empty():
			continue
		var want := String(parsed[0]).to_lower()
		var tag: String = parsed[1]
		var hits := 0
		for id in entries:
			if hits >= MAX_MATCHES_PER_NAME or out.size() >= LobbyCodec.MAX_PRESENCE_REPLY:
				break
			if seen.has(id) or String(entries[id].name).to_lower() != want:
				continue
			if tag != "" and PlayerProfile.tag_of(id) != tag:
				continue
			seen[id] = true
			hits += 1
			out.append({"id": id, "status": status_of(id, now), "name": entries[id].name})
	return out


func _evict() -> void:
	var oldest := ""
	var oldest_s := INF
	for id in entries:
		var e: Dictionary = entries[id]
		if e.status != LobbyCodec.STATUS_IN_LOBBY and e.status != LobbyCodec.STATUS_IN_MATCH and e.seen_s < oldest_s:
			oldest_s = e.seen_s
			oldest = id
	if oldest != "":
		entries.erase(oldest)
