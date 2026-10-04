extends GdUnitTestSuite
## W10-W4: MatchStats counters (kills, deaths, assists, damage, healing,
## objective damage) and the MvpFormulaDef score / pick; MatchEndModel rows.

const S := MatchStats.Stat


func _row(team: int, k: float, d: float, a: float, dmg: float = 0.0, heal: float = 0.0, obj: float = 0.0) -> Dictionary:
	return {S.TEAM: float(team), S.KILLS: k, S.DEATHS: d, S.ASSISTS: a, S.HERO_DAMAGE: dmg,
		S.HEALING: heal, S.OBJECTIVE_DAMAGE: obj}


func _formula() -> MvpFormulaDef:
	return load("res://assets/data/match/mvp_formula.tres") as MvpFormulaDef


func test_damage_kill_and_assist_counters() -> void:
	var m := MatchStats.new(100)
	m.record_damage(1, 9, 40.0, 10)
	m.record_damage(2, 9, 30.0, 50)
	m.record_death(9, 1, 60)
	assert_float(m.value(1, S.HERO_DAMAGE)).is_equal(40.0)
	assert_float(m.value(1, S.KILLS)).is_equal(1.0)
	assert_float(m.value(2, S.ASSISTS)).is_equal(1.0)
	assert_float(m.value(1, S.ASSISTS)).is_equal(0.0)
	assert_float(m.value(9, S.DEATHS)).is_equal(1.0)


func test_old_damage_is_not_an_assist() -> void:
	var m := MatchStats.new(100)
	m.record_damage(2, 9, 30.0, 10)
	m.record_death(9, 1, 500)
	assert_float(m.value(2, S.ASSISTS)).is_equal(0.0)


func test_self_damage_and_zero_amounts_are_ignored() -> void:
	var m := MatchStats.new()
	m.record_damage(3, 3, 50.0, 1)
	m.record_heal(3, 0.0)
	m.record_objective(3, -5.0)
	assert_float(m.value(3, S.HERO_DAMAGE)).is_equal(0.0)
	assert_float(m.value(3, S.HEALING)).is_equal(0.0)
	assert_float(m.value(3, S.OBJECTIVE_DAMAGE)).is_equal(0.0)


func test_heal_and_objective_counters() -> void:
	var m := MatchStats.new()
	m.record_heal(4, 25.0)
	m.record_heal(4, 5.0)
	m.record_objective(4, 100.0)
	assert_float(m.value(4, S.HEALING)).is_equal(30.0)
	assert_float(m.value(4, S.OBJECTIVE_DAMAGE)).is_equal(100.0)


func test_score_formula_matches_documented_weights() -> void:
	var f := _formula()
	var row := _row(0, 2.0, 1.0, 3.0, 800.0, 400.0, 600.0)
	# 2*3 + 3*1.5 - 1*1.5 + 800/400 + 400/400 + 600/600 = 13.0 (+5 win bonus)
	assert_float(f.score(row, false)).is_equal_approx(13.0, 1e-4)
	assert_float(f.score(row, true)).is_equal_approx(18.0, 1e-4)


func test_mvp_is_best_of_the_winning_team() -> void:
	var rows := {1: _row(0, 5, 2, 1), 2: _row(0, 1, 5, 0), 3: _row(1, 20, 0, 0)}
	assert_int(_formula().pick_mvp(rows, 0)).is_equal(1)  # team 1's star cannot win it
	assert_int(_formula().pick_mvp(rows, 1)).is_equal(3)


func test_mvp_on_draw_is_best_overall_and_ties_break_by_net_id() -> void:
	var rows := {5: _row(0, 3, 1, 0), 2: _row(1, 3, 1, 0), 7: _row(1, 1, 0, 0)}
	assert_int(_formula().pick_mvp(rows, -1)).is_equal(2)
	assert_int(_formula().pick_mvp({}, 0)).is_equal(0)


func test_events_round_trip_through_the_codec() -> void:
	var rows := {6: _row(1, 4, 2, 3, 123.0, 7.0, 55.0)}
	rows[6][S.LUMEN] = 900.0
	var evs := MatchStats.to_events(rows)
	var wire := EventCodec.encode(10, evs)
	var out: Array[GameEvent] = []
	assert_int(EventCodec.decode(wire, out)).is_equal(10)
	var back := {}
	for e in out:
		assert_int(e.kind).is_equal(GameEvent.PLAYER_STAT)
		back[e.flags] = e.amount
	assert_float(back[S.HERO_DAMAGE]).is_equal(123.0)
	assert_float(back[S.LUMEN]).is_equal(900.0)
	assert_float(back[S.ASSISTS]).is_equal(3.0)


func test_model_sorts_rows_and_marks_mvp() -> void:
	var rows := {1: _row(0, 5, 2, 1), 2: _row(0, 1, 5, 0), 3: _row(1, 2, 0, 0)}
	var model := MatchEndModel.build(rows, 0, 2, {1: "Ann"}, _formula())
	assert_int(model.mvp).is_equal(1)
	assert_int(model.teams[0].size()).is_equal(2)
	assert_int(model.teams[0][0].net_id).is_equal(1)
	assert_bool(model.teams[0][0].is_mvp).is_true()
	assert_bool(model.teams[0][1].is_self).is_true()
	assert_str(model.teams[0][0].name).is_equal("Ann")
	assert_str(model.teams[0][1].name).is_equal("Hero 2")
