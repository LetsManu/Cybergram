class_name RosterTracker
extends RefCounted
## Client-side hero roster for the scoreboard, kill feed, world health plates
## and death recap. Built from replicated data only: snapshot entities (team,
## HP, alive) and KILL events (kills / deaths counted since the HUD joined).
## Names, levels and other heroes' Lumen are not replicated yet; an optional
## `probe` Callable(net_id) -> {name, level, lumen, bot} fills them in (the
## offline session supplies OfflineRosterProbe). Without it rows show
## "Hero <id>" and "-" for level.


class Hero:
	extends RefCounted
	var net_id: int = 0
	var team: int = -1
	var hp: int = 0
	var max_hp: int = 0
	var dead: bool = false
	var kills: int = 0
	var deaths: int = 0
	var name: String = ""
	var level: int = 0
	var lumen: int = -1
	var is_bot: bool = false
	## W11-V1: SnapshotData.EntityState.fork_bits (Fork / Mastery of the 3 basic skills).
	var fork_bits: int = 0


var own_id: int = 0
var own_team: int = 0
## net id -> Hero.
var heroes: Dictionary = {}
var probe: Callable
## Who killed the own hero last (0 = none / not a hero).
var last_killer_id: int = 0


## Applies one snapshot's entity list (SnapshotData.EntityState); heroes no
## longer present are dropped.
func apply_entities(entities: Array, own_id_: int, own_team_: int) -> void:
	own_id = own_id_
	own_team = own_team_
	var seen := {}
	for e in entities:
		var h := hero(e.net_id, true)
		h.team = e.team
		h.hp = e.hp
		h.max_hp = e.max_hp
		h.dead = e.dead
		h.fork_bits = e.fork_bits
		seen[e.net_id] = true
	for id in heroes.keys():
		if not seen.has(id):
			heroes.erase(id)


## Counts a KILL event. Returns true when the victim is a known hero.
func on_kill(victim_id: int, killer_id: int) -> bool:
	var v := hero(victim_id)
	if v == null:
		return false
	v.deaths += 1
	v.dead = true
	var k := hero(killer_id)
	if k != null and killer_id != victim_id:
		k.kills += 1
	if victim_id == own_id:
		last_killer_id = killer_id if k != null else 0
	return true


## Refreshes names / levels / Lumen / bot flags from `probe` (if any).
func refresh_probe() -> void:
	if not probe.is_valid():
		return
	for id in heroes:
		var d: Dictionary = probe.call(id)
		if d.is_empty():
			continue
		var h: Hero = heroes[id]
		h.name = str(d.get("name", h.name))
		h.level = int(d.get("level", h.level))
		h.lumen = int(d.get("lumen", h.lumen))
		h.is_bot = bool(d.get("bot", h.is_bot))


func hero(id: int, create: bool = false) -> Hero:
	var h: Hero = heroes.get(id)
	if h == null and create:
		h = Hero.new()
		h.net_id = id
		heroes[id] = h
	return h


## Display name (empty when unknown; the view supplies the fallback text).
func name_of(id: int) -> String:
	var h := hero(id)
	return h.name if h != null else ""


func team_of(id: int) -> int:
	var h := hero(id)
	return h.team if h != null else -1


## Scoreboard rows (unsorted; see ScoreboardModel.build).
func rows() -> Array:
	var out: Array = []
	for id in heroes:
		var h: Hero = heroes[id]
		var r := ScoreboardModel.Row.make(id, h.name, h.team, h.level, h.kills, h.deaths, h.lumen)
		r.alive = not h.dead
		r.is_self = id == own_id
		r.is_bot = h.is_bot
		r.fork_bits = h.fork_bits
		out.append(r)
	return out
