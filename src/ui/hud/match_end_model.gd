class_name MatchEndModel
extends RefCounted
## Rows of the post-match screen (W10-W4): the server's final stats
## (ClientWorld.match_summary), display names, hero names and the MVP pick.
## Pure data, no nodes, so it is unit-testable.

const HERO_PATH := "res://assets/data/heroes/hero_%s.tres"
const FORMULA_PATH := "res://assets/data/match/mvp_formula.tres"


class Row:
	extends RefCounted
	var net_id: int = 0
	var team: int = 0
	var name: String = ""
	var hero: String = ""
	var kills: int = 0
	var deaths: int = 0
	var assists: int = 0
	var hero_damage: int = 0
	var healing: int = 0
	var objective_damage: int = 0
	var lumen: int = 0
	var level: int = 1
	var score: float = 0.0
	var is_mvp: bool = false
	var is_self: bool = false


## Builds [team 0 rows, team 1 rows] (sorted by score, best first).
## `names`: net id -> display name (empty = "Hero <id>"). `hero_name`: Callable(index) -> String.
static func build(summary: Dictionary, winner: int, own_id: int, names: Dictionary,
		formula: MvpFormulaDef, hero_name: Callable = Callable()) -> Dictionary:
	var teams: Array = [[], []]
	var mvp := formula.pick_mvp(summary, winner) if formula != null else 0
	for id: int in summary:
		var s: Dictionary = summary[id]
		var r := Row.new()
		r.net_id = id
		r.team = clampi(int(s.get(MatchStats.Stat.TEAM, 0)), 0, 1)
		r.name = str(names.get(id, ""))
		var hi := int(s.get(MatchStats.Stat.HERO, 0))
		r.hero = str(hero_name.call(hi)) if hero_name.is_valid() else ""
		if r.name == "":
			r.name = r.hero if r.hero != "" else "Hero %d" % id
		r.kills = int(s.get(MatchStats.Stat.KILLS, 0))
		r.deaths = int(s.get(MatchStats.Stat.DEATHS, 0))
		r.assists = int(s.get(MatchStats.Stat.ASSISTS, 0))
		r.hero_damage = roundi(float(s.get(MatchStats.Stat.HERO_DAMAGE, 0)))
		r.healing = roundi(float(s.get(MatchStats.Stat.HEALING, 0)))
		r.objective_damage = roundi(float(s.get(MatchStats.Stat.OBJECTIVE_DAMAGE, 0)))
		r.lumen = int(s.get(MatchStats.Stat.LUMEN, 0))
		r.level = int(s.get(MatchStats.Stat.LEVEL, 1))
		r.score = formula.score(s, winner >= 0 and r.team == winner) if formula != null else 0.0
		r.is_mvp = id == mvp
		r.is_self = id == own_id
		teams[r.team].append(r)
	for t in teams:
		t.sort_custom(func(a: Row, b: Row) -> bool:
			return a.score > b.score if not is_equal_approx(a.score, b.score) else a.net_id < b.net_id)
	return {"teams": teams, "mvp": mvp}


## Hero display name for a ContentDB hero index ("" when unknown).
static func hero_display_name(index: int) -> String:
	var id := ContentDB.shared().id_at(ContentDB.HERO, index)
	if id == &"":
		return ""
	var path := HERO_PATH % String(id).trim_prefix("hero_")
	if ResourceLoader.exists(path):
		var d := load(path) as HeroDef
		if d != null:
			return d.display_name
	return String(id)
