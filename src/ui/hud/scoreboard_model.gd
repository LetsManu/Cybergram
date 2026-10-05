class_name ScoreboardModel
extends RefCounted
## Minimal scoreboard (design/ux/hud.md §8, slice subset §19): own team on top,
## enemy below; per hero name, level, K / D, Lumen (own team only: enemy Lumen
## is hidden), bot tag and alive state. Sort inside a team: kills desc, deaths
## asc, level desc, name asc, net id asc (stable and deterministic).


class Row:
	extends RefCounted
	var net_id: int = 0
	var name: String = ""
	var team: int = 0
	## 0 = unknown.
	var level: int = 0
	var kills: int = 0
	var deaths: int = 0
	## -1 = unknown or hidden.
	var lumen: int = -1
	var alive: bool = true
	var is_self: bool = false
	var is_bot: bool = false
	## W11-V1: Fork / Mastery bits of the 3 basic skills (SnapshotData.EntityState.fork_bits).
	var fork_bits: int = 0

	static func make(id: int, name_: String, team_: int, level_: int, k: int, d: int, lumen_: int = -1) -> Row:
		var r := Row.new()
		r.net_id = id
		r.name = name_
		r.team = team_
		r.level = level_
		r.kills = k
		r.deaths = d
		r.lumen = lumen_
		return r


## Splits and sorts `rows` (Array of Row): returns [own_team_rows, enemy_rows].
## Enemy rows get lumen = -1 (hidden, hud.md §8).
static func build(rows: Array, own_team: int) -> Array:
	var own: Array[Row] = []
	var enemy: Array[Row] = []
	for r: Row in rows:
		if r.team == own_team:
			own.append(r)
		else:
			r.lumen = -1
			enemy.append(r)
	own.sort_custom(before)
	enemy.sort_custom(before)
	return [own, enemy]


## Sort predicate: true when `a` ranks above `b`.
static func before(a: Row, b: Row) -> bool:
	if a.kills != b.kills:
		return a.kills > b.kills
	if a.deaths != b.deaths:
		return a.deaths < b.deaths
	if a.level != b.level:
		return a.level > b.level
	if a.name != b.name:
		return a.name < b.name
	return a.net_id < b.net_id


## Team totals [kills, deaths] for a header line.
static func totals(rows: Array) -> Vector2i:
	var t := Vector2i.ZERO
	for r: Row in rows:
		t.x += r.kills
		t.y += r.deaths
	return t
