class_name MvpFormulaDef
extends Resource
## Data-driven MVP score for the post-match screen (assets/data/match/mvp_formula.tres).
##
## score = kills * w_kill + assists * w_assist - deaths * w_death
##       + hero_damage / damage_per_point + healing / healing_per_point
##       + objective_damage / objective_per_point
##       + win_bonus   (only for a hero on the winning team)
##
## The MVP is the best-scoring hero of the winning team (`winners_only`); on a
## draw, or with winners_only off, of everyone. Ties: more kills, then fewer
## deaths, then the lower net id (deterministic).

@export_range(0.0, 20.0, 0.1) var w_kill: float = 3.0
@export_range(0.0, 20.0, 0.1) var w_assist: float = 1.5
@export_range(0.0, 20.0, 0.1) var w_death: float = 1.5
## Hero damage / healing / objective damage that is worth one point.
@export_range(1.0, 10000.0, 1.0) var damage_per_point: float = 400.0
@export_range(1.0, 10000.0, 1.0) var healing_per_point: float = 400.0
@export_range(1.0, 10000.0, 1.0) var objective_per_point: float = 600.0
@export_range(0.0, 50.0, 0.5) var win_bonus: float = 5.0
@export var winners_only: bool = true
## Seconds before a death in which a damager is credited with an assist.
@export_range(1.0, 30.0, 0.5) var assist_window_s: float = 10.0


## Score of one summary row (Dictionary Stat -> float, see MatchStats).
func score(row: Dictionary, won: bool) -> float:
	var s := float(row.get(MatchStats.Stat.KILLS, 0.0)) * w_kill
	s += float(row.get(MatchStats.Stat.ASSISTS, 0.0)) * w_assist
	s -= float(row.get(MatchStats.Stat.DEATHS, 0.0)) * w_death
	s += float(row.get(MatchStats.Stat.HERO_DAMAGE, 0.0)) / damage_per_point
	s += float(row.get(MatchStats.Stat.HEALING, 0.0)) / healing_per_point
	s += float(row.get(MatchStats.Stat.OBJECTIVE_DAMAGE, 0.0)) / objective_per_point
	if won:
		s += win_bonus
	return s


## Net id of the MVP among `rows` (net id -> row), or 0 when there are none.
## `winner` is the winning team, -1 for a draw.
func pick_mvp(rows: Dictionary, winner: int) -> int:
	var best := 0
	var best_score := -INF
	var restrict := winners_only and winner >= 0
	for id: int in rows:
		var row: Dictionary = rows[id]
		var won := winner >= 0 and int(row.get(MatchStats.Stat.TEAM, -1)) == winner
		if restrict and not won:
			continue
		var sc := score(row, won)
		if best == 0 or _better(id, sc, row, best, best_score, rows[best]):
			best = id
			best_score = sc
	return best


func _better(id: int, sc: float, row: Dictionary, bid: int, bsc: float, brow: Dictionary) -> bool:
	if not is_equal_approx(sc, bsc):
		return sc > bsc
	var k := float(row.get(MatchStats.Stat.KILLS, 0.0))
	var bk := float(brow.get(MatchStats.Stat.KILLS, 0.0))
	if k != bk:
		return k > bk
	var d := float(row.get(MatchStats.Stat.DEATHS, 0.0))
	var bd := float(brow.get(MatchStats.Stat.DEATHS, 0.0))
	if d != bd:
		return d < bd
	return id < bid
