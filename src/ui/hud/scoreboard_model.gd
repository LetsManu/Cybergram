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
	## W19-HUD: HeroDef id (face crop, muted hero name); &"" when unknown.
	var hero_id: StringName = &""

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
## Armory v2 public build of a hero (items-and-armory.md §3.8 rule 7): the own
## hero from ProgressState.inv_items, others from the replicated
## EntityState.build held by their HeroView. Empty when unknown.
static func build_of(client: Node, net_id: int) -> PackedInt32Array:
	if client == null or net_id == 0:
		return PackedInt32Array()
	var session: Variant = client.get("session")
	if session != null and int((session as Object).get("own_net_id")) == net_id:
		var p: Variant = client.get("progress")
		return (p as SnapshotData.ProgressState).inv_items if p != null else PackedInt32Array()
	if client.has_method("remote_views"):
		var v: Variant = (client.call("remote_views") as Dictionary).get(net_id)
		if v is HeroView:
			return (v as HeroView).build
	return PackedInt32Array()


## Catalog the build indices refer to: the client's when it is the v22 one.
static func build_catalog(client: Node) -> ArmoryCatalogDef:
	var c: Variant = client.get("catalog") if client != null else null
	if c is ArmoryCatalogDef and (c as ArmoryCatalogDef).index_of(&"ember_part") >= 0:
		return c
	return ArmoryVisualsData.catalog()


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
