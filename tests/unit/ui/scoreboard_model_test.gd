extends GdUnitTestSuite
## E12 minimal scoreboard (design/ux/hud.md §8): own team first, sort order,
## enemy Lumen hidden.

const OWN: int = 0
const ENEMY: int = 1


func _rows() -> Array:
	return [
		ScoreboardModel.Row.make(11, "Brannoc", ENEMY, 6, 4, 2, 900),
		ScoreboardModel.Row.make(3, "Vesper Loom", OWN, 7, 2, 1, 1240),
		ScoreboardModel.Row.make(4, "Brannoc", OWN, 5, 5, 3, 300),
		ScoreboardModel.Row.make(5, "Vesper Loom", OWN, 9, 2, 1, 50),
		ScoreboardModel.Row.make(12, "Vesper Loom", ENEMY, 4, 4, 2, 700),
		ScoreboardModel.Row.make(6, "Brannoc", OWN, 9, 2, 1, 75),
	]


func test_splits_teams_own_first() -> void:
	var t := ScoreboardModel.build(_rows(), OWN)
	assert_int(t[0].size()).is_equal(4)
	assert_int(t[1].size()).is_equal(2)
	for r in t[0]:
		assert_int(r.team).is_equal(OWN)
	var flipped := ScoreboardModel.build(_rows(), ENEMY)
	assert_int(flipped[0].size()).is_equal(2)


func test_sort_kills_then_deaths_then_level_then_name() -> void:
	var own: Array = ScoreboardModel.build(_rows(), OWN)[0]
	var ids := own.map(func(r: ScoreboardModel.Row) -> int: return r.net_id)
	# 4 has most kills; 6 and 5 tie on K/D/level -> name ("Brannoc" < "Vesper Loom"); 3 is level 7.
	assert_array(ids).is_equal([4, 6, 5, 3])
	var enemy: Array = ScoreboardModel.build(_rows(), OWN)[1]
	# 11 and 12 tie on K/D; level 6 ranks above level 4.
	assert_array(enemy.map(func(r: ScoreboardModel.Row) -> int: return r.net_id)).is_equal([11, 12])


func test_identical_rows_order_by_net_id() -> void:
	var a := ScoreboardModel.Row.make(9, "X", OWN, 3, 1, 1)
	var b := ScoreboardModel.Row.make(2, "X", OWN, 3, 1, 1)
	assert_bool(ScoreboardModel.before(b, a)).is_true()
	assert_bool(ScoreboardModel.before(a, b)).is_false()


func test_enemy_lumen_hidden_own_lumen_kept() -> void:
	var t := ScoreboardModel.build(_rows(), OWN)
	for r in t[1]:
		assert_int(r.lumen).is_equal(-1)
	var own_lumen := (t[0] as Array).map(func(r: ScoreboardModel.Row) -> int: return r.lumen)
	assert_array(own_lumen).contains([1240, 300, 50, 75])


func test_team_totals() -> void:
	var t := ScoreboardModel.build(_rows(), OWN)
	assert_that(ScoreboardModel.totals(t[0])).is_equal(Vector2i(11, 6))
	assert_that(ScoreboardModel.totals(t[1])).is_equal(Vector2i(8, 4))
