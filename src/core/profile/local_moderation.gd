class_name LocalModeration
extends RefCounted
## Local chat safety (design/ux/lobby-and-social.md §4): players this client
## has muted / blocked (by player id) and reports recorded **only on this
## machine** (a stub until a moderation backend exists; nothing is sent).
## Muted players' chat lines are hidden; blocked players are also muted.
## Saved in user://moderation.cfg.
##
## Example:
##   var m := LocalModeration.load_from(LocalModeration.DEFAULT_PATH)
##   m.mute(id, "Neo"); m.report(id, "Neo", "spam", Time.get_unix_time_from_system())
##   if m.is_muted(id): skip_line()

const DEFAULT_PATH := "user://moderation.cfg"
const MAX_ENTRIES: int = 200
const REASON_MAX: int = 120

## id -> name (as seen when muted).
var muted: Dictionary = {}
## id -> name.
var blocked: Dictionary = {}
## Array of {id, name, reason, unix_time}.
var reports: Array = []


static func load_from(path: String) -> LocalModeration:
	var m := LocalModeration.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return m
	m.muted = _ids_only(cfg.get_value("moderation", "muted", {}))
	m.blocked = _ids_only(cfg.get_value("moderation", "blocked", {}))
	var r: Variant = cfg.get_value("moderation", "reports", [])
	if r is Array:
		for e in r:
			if e is Dictionary and PlayerProfile.is_hex_id(str(e.get("id", ""))):
				m.reports.append(e)
	return m


func save(path: String) -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("moderation", "muted", muted)
	cfg.set_value("moderation", "blocked", blocked)
	cfg.set_value("moderation", "reports", reports)
	return cfg.save(path)


func mute(id: String, name: String) -> void:
	if PlayerProfile.is_hex_id(id) and muted.size() < MAX_ENTRIES:
		muted[id] = name


func unmute(id: String) -> void:
	muted.erase(id)
	blocked.erase(id)


func block(id: String, name: String) -> void:
	if PlayerProfile.is_hex_id(id) and blocked.size() < MAX_ENTRIES:
		blocked[id] = name
		mute(id, name)


func is_muted(id: String) -> bool:
	return muted.has(id) or blocked.has(id)


## Records a report locally (no network). `unix_time` from the caller.
func report(id: String, name: String, reason: String, unix_time: float) -> void:
	if not PlayerProfile.is_hex_id(id):
		return
	reports.append({"id": id, "name": name, "reason": reason.left(REASON_MAX), "unix_time": int(unix_time)})
	while reports.size() > MAX_ENTRIES:
		reports.remove_at(0)


static func _ids_only(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			if PlayerProfile.is_hex_id(str(k)):
				out[str(k)] = str(v[k])
	return out
