class_name HeroHistory
extends RefCounted
## Reads the game's local hero play history (user://hero_play_history.cfg in
## the game's user folder, written by the game's HeroPlayHistory) and picks
## "your mains". Local only: this launcher never sends it anywhere.
##
## File format ([hero_stem] sections): matches (int), minutes (int),
## last_played (unix seconds).

const FILE_NAME: String = "hero_play_history.cfg"
## How many mains the "changes for your heroes" block shows.
const MAINS: int = 3


## [{"hero": "ryker_vance", "matches": int, "minutes": int, "last_played": int}]
## from the file at `path` (missing or broken file = empty list).
static func read_file(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	for sec in cfg.get_sections():
		out.append({
			"hero": sec,
			"matches": maxi(0, int(cfg.get_value(sec, "matches", 0))),
			"minutes": maxi(0, int(cfg.get_value(sec, "minutes", 0))),
			"last_played": maxi(0, int(cfg.get_value(sec, "last_played", 0))),
		})
	return out


## Hero stems of the player's mains, best first: the pinned hero (if any),
## then the most played by minutes (ties: matches, then most recent).
static func mains(entries: Array[Dictionary], pinned: String = "", count: int = MAINS) -> Array[String]:
	var sorted: Array[Dictionary] = entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["minutes"]) != int(b["minutes"]):
			return int(a["minutes"]) > int(b["minutes"])
		if int(a["matches"]) != int(b["matches"]):
			return int(a["matches"]) > int(b["matches"])
		if int(a["last_played"]) != int(b["last_played"]):
			return int(a["last_played"]) > int(b["last_played"])
		return String(a["hero"]) < String(b["hero"]))
	var out: Array[String] = []
	var pin: String = pinned.strip_edges().to_lower().trim_prefix("hero_")
	if pin != "":
		out.append(pin)
	for e in sorted:
		if out.size() >= count:
			break
		var h: String = String(e["hero"])
		if not out.has(h):
			out.append(h)
	return out


## The entry for `hero` ({} when never played).
static func entry_for(entries: Array[Dictionary], hero: String) -> Dictionary:
	for e in entries:
		if String(e["hero"]) == hero:
			return e
	return {}
