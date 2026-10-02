class_name KillFeedModel
extends RefCounted
## Kill feed queue (design/ux/hud.md §4.10): at most `max_rows` rows, newest
## first, each shown for `duration_s` and faded over its last `fade_s`.
## Wardling kills are not pushed by the HUD (hero KILL events only).


class Entry:
	extends RefCounted
	var killer_name: String = ""
	var victim_name: String = ""
	## MapDef team (-1 = none / environment).
	var killer_team: int = -1
	var victim_team: int = -1
	## The local player is the killer or the victim (light frame, hud.md §4.10).
	var own_involved: bool = false
	var age: float = 0.0

	static func make(killer: String, k_team: int, victim: String, v_team: int, own: bool) -> Entry:
		var e := Entry.new()
		e.killer_name = killer
		e.killer_team = k_team
		e.victim_name = victim
		e.victim_team = v_team
		e.own_involved = own
		return e


var max_rows: int = 5
var duration_s: float = 6.0
var fade_s: float = 0.5
## Newest first.
var entries: Array[Entry] = []


func _init(rows: int = 5, duration: float = 6.0) -> void:
	max_rows = maxi(rows, 1)
	duration_s = maxf(duration, 0.1)


## Adds `e` on top; the oldest rows beyond `max_rows` drop at once.
func push(e: Entry) -> void:
	e.age = 0.0
	entries.push_front(e)
	while entries.size() > max_rows:
		entries.pop_back()


## Ages every row by `dt` and removes expired ones.
func advance(dt: float) -> void:
	for i in range(entries.size() - 1, -1, -1):
		entries[i].age += dt
		if entries[i].age >= duration_s:
			entries.remove_at(i)


## Opacity of `e` (1 until the last `fade_s`, then linear to 0).
func alpha(e: Entry) -> float:
	var left := duration_s - e.age
	return clampf(left / fade_s, 0.0, 1.0) if fade_s > 0.0 else 1.0
