class_name HeroPlayHistory
extends RefCounted
## Local-only record of how much each hero was played: matches, minutes and
## the last time, in user://hero_play_history.cfg (one [hero_stem] section per
## hero). Nothing here is ever sent over the network: the launcher reads the
## file on the same PC to show "Changes for your heroes" in the patch notes.
## Privacy: PRIVACY.md lists it as a local file; deleting it resets the history.
##
## Example:
##   HeroPlayHistory.record(&"hero_ryker_vance", 12.5)  # a finished match

const PATH := "user://hero_play_history.cfg"


## "hero_ryker_vance" -> "ryker_vance" (lower case, no prefix).
static func stem_of(hero_id: StringName) -> String:
	return String(hero_id).to_lower().trim_prefix("hero_")


## Adds one finished match of `minutes` (rounded to whole minutes, at least 1)
## to `hero_id`. Returns false when the id is empty or the file cannot be written.
static func record(hero_id: StringName, minutes: float, path: String = PATH, now_unix: int = -1) -> bool:
	var stem := stem_of(hero_id)
	if stem == "":
		return false
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is fine
	cfg.set_value(stem, "matches", int(cfg.get_value(stem, "matches", 0)) + 1)
	cfg.set_value(stem, "minutes", int(cfg.get_value(stem, "minutes", 0)) + maxi(1, roundi(minutes)))
	cfg.set_value(stem, "last_played", int(Time.get_unix_time_from_system()) if now_unix < 0 else now_unix)
	return cfg.save(path) == OK


## {"matches": int, "minutes": int, "last_played": int} for a hero (zeros if none).
static func get_entry(hero_id: StringName, path: String = PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	var stem := stem_of(hero_id)
	cfg.load(path)
	return {"matches": int(cfg.get_value(stem, "matches", 0)),
		"minutes": int(cfg.get_value(stem, "minutes", 0)),
		"last_played": int(cfg.get_value(stem, "last_played", 0))}


## Starts timing `client`'s match: when it ends, one match is recorded for `hero`.
## `client` is the ClientWorld (duck-typed: it has a match_ended signal).
static func track(client: Object, hero: Resource) -> void:
	if client == null or hero == null:
		return
	var started := Time.get_ticks_msec()
	var hero_id: StringName = hero.get("id")
	client.connect("match_ended", func(_w: int, _r: int) -> void:
		record(hero_id, (Time.get_ticks_msec() - started) / 60000.0), CONNECT_ONE_SHOT)
