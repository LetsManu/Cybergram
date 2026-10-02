extends GdUnitTestSuite
## E11 GoalSelector (architecture.md §9 utility goals): constructed blackboards
## pick push / defend / fight / retreat / siege as designed.

const HZ: int = 30
const K := BotGoal.Kind


func _profile() -> BotProfile:
	return load("res://assets/data/ai/bot_profile_normal.tres") as BotProfile


## A Concord bot at the Mid approach, full HP, front = Scrap Bazaar (index 3).
func _bb() -> BotBlackboard:
	var bb := BotBlackboard.new()
	bb.tick_hz = HZ
	bb.tick = 100 * HZ
	bb.team = 0
	bb.pos = Vector3(0.0, 0.0, -200.0)
	bb.hp_frac = 1.0
	bb.front_index = 3
	bb.front_pos = Vector3(0.0, 0.0, -275.0)
	bb.front_is_own = false
	bb.home_pos = Vector3(0.0, 0.0, -5.0)
	return bb


func _see_enemy(bb: BotBlackboard, dist: float, damaged_s_ago: float = 99.0) -> void:
	bb.target_id = 77
	bb.target_is_hero = true
	bb.target_dist = dist
	bb.target_pos = bb.pos + Vector3(0.0, 0.0, -dist)
	bb.last_seen_enemy_tick = bb.tick
	bb.last_damaged_tick = bb.tick - roundi(damaged_s_ago * HZ)
	bb.last_attacker_id = 77


func _pick(bb: BotBlackboard) -> int:
	var g := GoalSelector.new().pick(bb, _profile())
	return g.kind if g != null else -1


func test_quiet_lane_pushes_the_front() -> void:
	var bb := _bb()
	assert_int(_pick(bb)).is_equal(K.PUSH)
	var g := GoalSelector.new()
	assert_vector(g.goal(K.PUSH).destination(bb)).is_equal(bb.front_pos)


func test_nothing_to_do_picks_no_goal() -> void:
	var bb := _bb()
	bb.front_index = -1
	assert_int(_pick(bb)).is_equal(-1)


func test_own_hardpoint_under_capture_is_defended() -> void:
	var bb := _bb()
	bb.defend_index = 1
	bb.defend_pos = Vector3(0.0, 0.0, -145.0)
	bb.defend_progress = 0.4
	assert_int(_pick(bb)).is_equal(K.DEFEND)


func test_visible_enemy_hero_is_fought_over_pushing() -> void:
	var bb := _bb()
	_see_enemy(bb, 20.0)
	assert_int(_pick(bb)).is_equal(K.FIGHT)


func test_enemy_out_of_engage_range_does_not_pull_the_bot() -> void:
	var bb := _bb()
	_see_enemy(bb, _profile().engage_range_m + 5.0)
	assert_int(_pick(bb)).is_equal(K.PUSH)


func test_enemy_wardling_alone_does_not_start_a_fight() -> void:
	var bb := _bb()
	_see_enemy(bb, 10.0)
	bb.target_is_hero = false
	assert_int(_pick(bb)).is_equal(K.PUSH)


func test_close_attacker_beats_a_half_lost_defence_but_not_a_nearly_lost_one() -> void:
	var bb := _bb()
	bb.defend_index = 2
	bb.defend_pos = bb.pos
	bb.defend_progress = 0.5
	_see_enemy(bb, 10.0, 0.5)
	assert_int(_pick(bb)).is_equal(K.FIGHT)
	bb.defend_progress = 0.9
	assert_int(_pick(bb)).is_equal(K.DEFEND)


func test_low_hp_under_fire_retreats_home() -> void:
	var bb := _bb()
	_see_enemy(bb, 15.0, 0.2)
	bb.hp_frac = 0.2
	assert_int(_pick(bb)).is_equal(K.RETREAT)
	assert_vector(GoalSelector.new().goal(K.RETREAT).destination(bb)).is_equal(bb.home_pos)


func test_low_hp_without_threat_keeps_pushing() -> void:
	var bb := _bb()
	bb.hp_frac = 0.2
	assert_int(_pick(bb)).is_equal(K.PUSH)


func test_retreat_holds_until_return_threshold_or_calm() -> void:
	var p := _profile()
	var bb := _bb()
	bb.current_goal = K.RETREAT
	bb.hp_frac = (p.retreat_hp_frac + p.return_hp_frac) * 0.5  # above retreat, below return
	bb.last_seen_enemy_tick = bb.tick - roundi(p.retreat_calm_s * 0.5 * HZ)
	assert_int(_pick(bb)).is_equal(K.RETREAT)
	bb.last_seen_enemy_tick = bb.tick - roundi((p.retreat_calm_s + 1.0) * HZ)
	assert_int(_pick(bb)).is_equal(K.PUSH)
	bb.current_goal = -1  # a fresh bot at the same HP does not start retreating
	bb.last_seen_enemy_tick = bb.tick
	assert_int(_pick(bb)).is_not_equal(K.RETREAT)


func test_exposed_enemy_uplink_is_sieged() -> void:
	var bb := _bb()
	bb.enemy_uplink_exposed = true
	bb.enemy_uplink_id = 9
	bb.siege_pos = Vector3(0.0, 0.0, -342.0)
	assert_int(_pick(bb)).is_equal(K.SIEGE)
	assert_vector(GoalSelector.new().goal(K.SIEGE).destination(bb)).is_equal(bb.siege_pos)


func test_current_goal_gets_hysteresis() -> void:
	var p := _profile()
	var bb := _bb()
	_see_enemy(bb, 20.0)
	var sel := GoalSelector.new()
	sel.pick(bb, p)
	var fight := sel.last_scores[K.FIGHT]
	assert_float(fight).is_greater(0.0)
	# Make push score within the stickiness margin above fight: the current goal (fight) stays.
	var p2 := p.duplicate() as BotProfile
	p2.w_push = (fight + p.stickiness * 0.5)
	bb.current_goal = K.FIGHT
	assert_int(sel.pick(bb, p2).kind).is_equal(K.FIGHT)
	bb.current_goal = K.PUSH
	assert_int(sel.pick(bb, p2).kind).is_equal(K.PUSH)


func test_low_hp_bot_finishes_a_weaker_hero_instead_of_retreating() -> void:
	var bb := _bb()
	_see_enemy(bb, 12.0, 0.2)
	bb.hp_frac = 0.2
	bb.target_hp_frac = 0.1
	assert_int(_pick(bb)).is_equal(K.FIGHT)


func test_a_retreat_that_ended_hurt_is_not_restarted_during_its_cooldown() -> void:
	var bb := _bb()
	_see_enemy(bb, 15.0, 0.2)
	bb.hp_frac = 0.2
	bb.retreat_block_until_tick = bb.tick + 10 * HZ
	assert_int(_pick(bb)).is_equal(K.FIGHT)
	bb.retreat_block_until_tick = bb.tick - 1
	assert_int(_pick(bb)).is_equal(K.RETREAT)
