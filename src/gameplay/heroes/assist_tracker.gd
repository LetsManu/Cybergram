class_name AssistTracker
extends RefCounted
## Who assisted a hero kill, for Kindle (design/gdd/items-and-armory.md §3.5.3,
## §5 "Kindle counts heal-beam assists"). Server only; ServerWorld feeds it.
##
## Assist = (a) a hero that damaged the victim within `window_ticks` before the
## death, or (b) a hero that healed the killer or one of those damagers within
## the window (heal-beam assists). The killer and the victim never assist.
## Same window as MatchStats (MvpFormulaDef.assist_window_s).

var window_ticks: int
var _damagers: Dictionary = {}  # victim id -> {attacker id -> tick}
var _healers: Dictionary = {}   # healed hero id -> {healer id -> tick}


func _init(window_ticks_: int = 300) -> void:
	window_ticks = window_ticks_


## Hero `attacker` damaged hero `victim` at `tick`.
func record_damage(attacker: int, victim: int, tick: int) -> void:
	if attacker <= 0 or attacker == victim:
		return
	var d: Dictionary = _damagers.get(victim, {})
	d[attacker] = tick
	_damagers[victim] = d


## Hero `healer` healed hero `target` at `tick` (self heals ignored).
func record_heal(healer: int, target: int, tick: int) -> void:
	if healer <= 0 or healer == target:
		return
	var d: Dictionary = _healers.get(target, {})
	d[healer] = tick
	_healers[target] = d


## The assisters of `victim`'s death by `killer` at `tick` (forgets the victim's
## damagers and heals received).
func assisters(victim: int, killer: int, tick: int) -> Array[int]:
	var out: Array[int] = []
	var helped: Array[int] = []
	if killer > 0:
		helped.append(killer)
	var d: Dictionary = _damagers.get(victim, {})
	for a: int in d:
		if tick - int(d[a]) <= window_ticks:
			helped.append(a)
			if a != killer and a != victim and not out.has(a):
				out.append(a)
	for h: int in helped:
		var heals: Dictionary = _healers.get(h, {})
		for healer: int in heals:
			if tick - int(heals[healer]) <= window_ticks and healer != killer and healer != victim \
					and not out.has(healer):
				out.append(healer)
	_damagers.erase(victim)
	_healers.erase(victim)
	return out
