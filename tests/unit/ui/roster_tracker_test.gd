extends GdUnitTestSuite
## E12 client-side roster (scoreboard / kill feed / death recap source):
## replicated entities + KILL events only.


func _ent(id: int, team: int, hp: int = 250, dead: bool = false) -> SnapshotData.EntityState:
	var e := SnapshotData.EntityState.new()
	e.net_id = id
	e.team = team
	e.hp = hp
	e.max_hp = 250
	e.dead = dead
	return e


func test_entities_create_update_and_drop_heroes() -> void:
	var r := RosterTracker.new()
	r.apply_entities([_ent(1, 0), _ent(2, 1, 120)], 1, 0)
	assert_int(r.heroes.size()).is_equal(2)
	assert_int(r.hero(2).hp).is_equal(120)
	r.apply_entities([_ent(1, 0)], 1, 0)
	assert_object(r.hero(2)).is_null()


func test_kills_count_and_last_killer() -> void:
	var r := RosterTracker.new()
	r.apply_entities([_ent(1, 0), _ent(2, 1), _ent(3, 1)], 1, 0)
	assert_bool(r.on_kill(2, 1)).is_true()
	assert_bool(r.on_kill(1, 3)).is_true()
	assert_int(r.hero(1).kills).is_equal(1)
	assert_int(r.hero(1).deaths).is_equal(1)
	assert_int(r.hero(3).kills).is_equal(1)
	assert_int(r.last_killer_id).is_equal(3)
	assert_bool(r.hero(1).dead).is_true()


func test_non_hero_kill_ignored_and_non_hero_killer_counts_death_only() -> void:
	var r := RosterTracker.new()
	r.apply_entities([_ent(1, 0)], 1, 0)
	assert_bool(r.on_kill(99, 1)).is_false()  # a Wardling died: not a hero
	assert_int(r.hero(1).kills).is_equal(0)
	assert_bool(r.on_kill(1, 77)).is_true()  # killed by a Wardling
	assert_int(r.hero(1).deaths).is_equal(1)
	assert_int(r.last_killer_id).is_equal(0)


func test_probe_fills_names_and_rows() -> void:
	var r := RosterTracker.new()
	r.apply_entities([_ent(1, 0), _ent(2, 1)], 1, 0)
	r.probe = func(id: int) -> Dictionary: return {"name": "Hero%d" % id, "level": id + 4, "lumen": 100 * id, "bot": id == 2}
	r.refresh_probe()
	assert_str(r.name_of(2)).is_equal("Hero2")
	var rows := r.rows()
	assert_int(rows.size()).is_equal(2)
	var me: ScoreboardModel.Row = rows.filter(func(x: ScoreboardModel.Row) -> bool: return x.is_self)[0]
	assert_int(me.net_id).is_equal(1)
	assert_int(me.level).is_equal(5)
	var built := ScoreboardModel.build(rows, 0)
	assert_int((built[1][0] as ScoreboardModel.Row).lumen).is_equal(-1)  # enemy Lumen hidden
	assert_bool((built[1][0] as ScoreboardModel.Row).is_bot).is_true()
