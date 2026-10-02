extends GdUnitTestSuite
## LaneFrontResolver (Canon C15 / §3.8 "front"; ADR-0005): contested first,
## then the next C3-attackable hardpoint, then the own front-most held one.

const MAP_PATH := "res://assets/data/match/map_slice_lane.tres"
const C := MapDef.TEAM_CONCORD
const S := MapDef.TEAM_SYNDICATE


func _system() -> ObjectiveSystem:
	return ObjectiveSystem.new(load(MAP_PATH) as MapDef, MatchRulesDef.new())


func _owners(sys: ObjectiveSystem, owners: Array) -> void:
	for i in owners.size():
		(sys.lanes[0][i] as HardpointSim).owner = owners[i]


func test_start_of_match_both_fronts_are_the_neutral_mid() -> void:
	var sys := _system()
	assert_int(sys.front.front_for(C, 0)).is_equal(2)
	assert_int(sys.front.front_for(S, 0)).is_equal(2)


func test_after_a_mid_capture_the_front_moves_to_the_enemy_outer() -> void:
	var sys := _system()
	_owners(sys, [C, C, C, S, S])
	assert_int(sys.front.front_for(C, 0)).is_equal(3)
	assert_int(sys.front.front_for(S, 0)).is_equal(2)  # Mid needs no prerequisite


func test_contested_hardpoint_wins_over_attackable() -> void:
	var sys := _system()
	_owners(sys, [C, C, C, S, S])
	var ao: HardpointSim = sys.lanes[0][1]
	ao.capturing_team = S  # enemy progress on an own node (not attackable by S yet: test data only)
	ao.progress = 0.2
	assert_int(sys.front.front_for(C, 0)).is_equal(1)
	assert_int(sys.front.front_for(S, 0)).is_equal(1)


func test_nearest_contested_is_measured_from_own_hq() -> void:
	var sys := _system()
	_owners(sys, [C, C, C, S, S])
	(sys.lanes[0][1] as HardpointSim).capturing_team = S
	(sys.lanes[0][1] as HardpointSim).progress = 0.2
	(sys.lanes[0][3] as HardpointSim).capturing_team = C
	(sys.lanes[0][3] as HardpointSim).progress = 0.4
	assert_int(sys.front.front_for(C, 0)).is_equal(1)
	assert_int(sys.front.front_for(S, 0)).is_equal(3)


func test_attackable_respects_c3_deep_push() -> void:
	var sys := _system()
	_owners(sys, [C, C, C, C, S])
	assert_int(sys.front.front_for(C, 0)).is_equal(4)
	assert_int(sys.front.front_for(S, 0)).is_equal(3)
	_owners(sys, [C, S, S, S, S])
	assert_int(sys.front.front_for(S, 0)).is_equal(0)
	assert_int(sys.front.front_for(C, 0)).is_equal(1)


func test_falls_back_to_own_front_most_held_when_nothing_attackable() -> void:
	var sys := _system()
	_owners(sys, [C, C, C, C, C])
	assert_int(sys.front.front_for(C, 0)).is_equal(4)
	assert_int(sys.held_front(C, 0)).is_equal(4)
	assert_int(sys.held_front(S, 0)).is_equal(-1)
	# Its own Inner is adjacent to its HQ, so always attackable for Syndicate.
	assert_int(sys.front.front_for(S, 0)).is_equal(4)
