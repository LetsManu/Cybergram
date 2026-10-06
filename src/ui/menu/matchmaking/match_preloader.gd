class_name MatchPreloader
extends RefCounted
## v20: loads the assigned match's map and hero on loader threads while the
## loading screen shows, so the screen can report real progress (to the front,
## which relays it to the other players) and the game session finds both in
## the resource cache. The loaded resources stay referenced until the next
## preload, so the cache keeps them for the session's own load().
##
## Example (MatchmakingFlow):
##   _preload = MatchPreloader.new()
##   _preload.start(["res://assets/data/match/map_slice.tres"])
##   ... every frame: bar.value = _preload.progress(); if _preload.is_done(): hand over

## Kept alive between the preload and the game session's load().
static var _held: Array[Resource] = []

var paths: PackedStringArray = []
var _done: Dictionary = {}


## Paths of the resources a match needs: the map's MapDef and the hero.
static func match_paths(map_name: String, hero_stem: String) -> PackedStringArray:
	var out := PackedStringArray()
	var m := GameSession.map_def_path(map_name) if map_name != "" else ""
	if m != "":
		out.append(m)
	var h := GameSession.HERO_PATH % hero_stem if hero_stem != "" else ""
	if h != "" and ResourceLoader.exists(h):
		out.append(h)
	return out


## Starts the threaded loads (missing paths are skipped).
func start(paths_: PackedStringArray) -> void:
	_held.clear()
	paths = PackedStringArray()
	_done.clear()
	for p in paths_:
		if ResourceLoader.exists(p) and ResourceLoader.load_threaded_request(p, "", true) == OK:
			paths.append(p)


## 0..1 over all paths (a failed load counts as done: the session reports it).
func progress() -> float:
	if paths.is_empty():
		return 1.0
	var sum := 0.0
	for p in paths:
		sum += _progress_of(p)
	return sum / paths.size()


func is_done() -> bool:
	return progress() >= 1.0


func _progress_of(p: String) -> float:
	if _done.has(p):
		return 1.0
	var arr := []
	match ResourceLoader.load_threaded_get_status(p, arr):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return clampf(float(arr[0]) if not arr.is_empty() else 0.0, 0.0, 0.99)
		ResourceLoader.THREAD_LOAD_LOADED:
			var r := ResourceLoader.load_threaded_get(p)
			if r != null:
				_held.append(r)
	_done[p] = true
	return 1.0
