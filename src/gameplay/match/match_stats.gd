class_name MatchStats
extends RefCounted
## Server-side per-hero match statistics for the post-match screen
## (W10-W4; design: the Match-end screen). Counts kills, deaths, assists, hero
## damage dealt, healing done, objective damage (Uplink / Generator) and, at
## summary time, Lumen earned and level. Server-authoritative; the totals go to
## every client once, as GameEvent.PLAYER_STAT records when the match ends.
##
## Assist: a hero that damaged the victim within `assist_window_ticks` before
## the death (and is not the killer) gets one assist.

enum Stat { KILLS, DEATHS, ASSISTS, HERO_DAMAGE, HEALING, OBJECTIVE_DAMAGE, LUMEN, LEVEL, TEAM, HERO }

const STAT_COUNT: int = 10

## Seconds before a death in which a damager is credited with an assist.
var assist_window_ticks: int = 300

## net id -> PackedFloat64Array indexed by Stat (counters only; LUMEN..HERO are filled at summary).
var _rows: Dictionary = {}
## victim net id -> {attacker net id -> last damage tick}.
var _damagers: Dictionary = {}


func _init(assist_window_ticks_: int = 300) -> void:
	assist_window_ticks = assist_window_ticks_


func _row(id: int) -> PackedFloat64Array:
	var r: PackedFloat64Array = _rows.get(id, PackedFloat64Array())
	if r.is_empty():
		r.resize(STAT_COUNT)
		_rows[id] = r
	return r


func _add(id: int, stat: int, amount: float) -> void:
	if id <= 0 or amount <= 0.0:
		return
	var r := _row(id)
	r[stat] += amount
	_rows[id] = r


## Damage `amount` (HP removed) dealt by `attacker` to hero `victim` at `tick`.
func record_damage(attacker: int, victim: int, amount: float, tick: int) -> void:
	if attacker <= 0 or attacker == victim or amount <= 0.0:
		return
	_add(attacker, Stat.HERO_DAMAGE, amount)
	var d: Dictionary = _damagers.get(victim, {})
	d[attacker] = tick
	_damagers[victim] = d


## HP restored by `healer` (self heals are credited to the hero itself).
func record_heal(healer: int, amount: float) -> void:
	_add(healer, Stat.HEALING, amount)


## Damage `amount` dealt to an enemy Uplink / Generator by `attacker`.
func record_objective(attacker: int, amount: float) -> void:
	_add(attacker, Stat.OBJECTIVE_DAMAGE, amount)


## A hero death. `killer` may be 0 or not a hero (no kill credit then).
func record_death(victim: int, killer: int, tick: int, killer_is_hero: bool = true) -> void:
	_add(victim, Stat.DEATHS, 1.0)
	if killer_is_hero and killer != victim:
		_add(killer, Stat.KILLS, 1.0)
	var d: Dictionary = _damagers.get(victim, {})
	for a: int in d:
		if a != killer and a != victim and tick - int(d[a]) <= assist_window_ticks:
			_add(a, Stat.ASSISTS, 1.0)
	_damagers.erase(victim)


## Counter of `stat` for hero `id` (0 when unknown).
func value(id: int, stat: int) -> float:
	var r: PackedFloat64Array = _rows.get(id, PackedFloat64Array())
	return r[stat] if not r.is_empty() else 0.0


## Final rows: net id -> Dictionary{Stat -> float}, counters plus the identity
## fields supplied per hero in `identity` (net id -> {team, hero, lumen, level}).
func summary(identity: Dictionary) -> Dictionary:
	var out := {}
	for id: int in identity:
		var row := {}
		for s in STAT_COUNT:
			row[s] = value(id, s)
		var idn: Dictionary = identity[id]
		row[Stat.TEAM] = float(idn.get("team", 0))
		row[Stat.HERO] = float(idn.get("hero", 0))
		row[Stat.LUMEN] = float(idn.get("lumen", 0))
		row[Stat.LEVEL] = float(idn.get("level", 1))
		out[id] = row
	return out


## Summary rows as the PLAYER_STAT events sent at match end (one per hero and stat).
static func to_events(rows: Dictionary) -> Array[GameEvent]:
	var evs: Array[GameEvent] = []
	for id: int in rows:
		var row: Dictionary = rows[id]
		for s: int in row:
			evs.append(GameEvent.player_stat(id, s, float(row[s])))
	return evs
