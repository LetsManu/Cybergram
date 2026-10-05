extends GdUnitTestSuite
## W14-M2 multi-lane hardpoint graph (Canon C3, F8/C9, C7) on Shardline Front:
## prerequisites are per lane (holding North's Mid unlocks nothing in Center),
## Incursion sums the deepest node of each of the 3 lanes (0-9), and any enemy-held
## Inner in any lane exposes the Uplink.

const DEF_PATH := "res://assets/data/match/map_front.tres"
const C := MapDef.TEAM_CONCORD
const S := MapDef.TEAM_SYNDICATE
const N := MapDef.TEAM_NEUTRAL

var _def: MapDef
var _sys: ObjectiveSystem
var _m: MatchRules


func before_test() -> void:
	_def = load(DEF_PATH) as MapDef
	_sys = ObjectiveSystem.new(_def, _def.match_rules)
	_sys.mid_locked = false
	_m = MatchRules.new(_def.match_rules, _sys)
	for u in _m.build_uplinks(_def):
		auto_free(u)


func _owners(lane: int, owners: Array) -> void:
	for i in owners.size():
		(_sys.lanes[lane][i] as HardpointSim).owner = owners[i]


func test_prerequisites_are_per_lane() -> void:
	assert_int(_sys.lanes.size()).is_equal(3)
	for li in 3:
		# Start: Mids open to both, enemy Outers locked (the Mid is not held yet).
		assert_bool(_sys.eligible(li, 2, C)).is_true()
		assert_bool(_sys.eligible(li, 2, S)).is_true()
		assert_bool(_sys.eligible(li, 3, C)).is_false()
		assert_bool(_sys.eligible(li, 1, S)).is_false()
	# Concord takes the North Mid only: North's Syndicate Outer opens, Center's does not.
	(_sys.lanes[0][2] as HardpointSim).owner = C
	assert_bool(_sys.eligible(0, 3, C)).is_true()
	assert_bool(_sys.eligible(1, 3, C)).is_false()
	assert_bool(_sys.eligible(2, 3, C)).is_false()
	# ... and its Inner stays locked until the Outer falls (one step at a time).
	assert_bool(_sys.eligible(0, 4, C)).is_false()
	(_sys.lanes[0][3] as HardpointSim).owner = C
	assert_bool(_sys.eligible(0, 4, C)).is_true()
	# Severed: Syndicate retakes the North Mid; Concord's B-Outer is cut off.
	(_sys.lanes[0][2] as HardpointSim).owner = S
	assert_bool(_sys.is_severed(0, 3)).is_true()
	assert_bool(_sys.is_severed(1, 3)).is_false()


func test_held_front_per_lane() -> void:
	_owners(0, [C, C, C, S, S])
	_owners(1, [C, C, N, S, S])
	_owners(2, [C, S, S, S, S])
	assert_int(_sys.held_front(C, 0)).is_equal(2)
	assert_int(_sys.held_front(C, 1)).is_equal(1)
	assert_int(_sys.held_front(C, 2)).is_equal(0)
	assert_int(_sys.held_front(S, 2)).is_equal(1)


func test_incursion_sums_three_lanes() -> void:
	assert_int(_m.incursion(C)).is_equal(0)
	assert_int(_m.incursion(S)).is_equal(0)
	# GDD F8 example: Concord holds N-MID (1) and C-BO (2), nothing past its own
	# S-AO (0) -> 3; Syndicate holds S-AO (Concord's, 2) and S-MID (1) -> 2.
	_owners(0, [C, C, C, S, S])
	_owners(1, [C, C, C, C, S])
	_owners(2, [C, S, S, S, S])
	assert_int(_m.incursion(C)).is_equal(3)
	assert_int(_m.incursion(S)).is_equal(2)
	# Maximum: every enemy Inner in every lane = 9.
	for li in 3:
		_owners(li, [C, C, C, C, C])
	assert_int(_m.incursion(C)).is_equal(9)
	assert_int(_m.incursion(S)).is_equal(0)


func test_time_out_on_three_lane_incursion() -> void:
	_owners(0, [C, C, C, S, S])
	_owners(2, [C, C, S, S, S])
	_m.resolve_time_out()
	assert_int(_m.winner).is_equal(N)  # 1 - 1: tie, no Uplink damage -> Sudden Death
	assert_int(_m.phase).is_equal(MatchRules.Phase.SUDDEN_DEATH)


func test_any_lane_inner_exposes_the_uplink() -> void:
	_m.step(0.1)  # LOAD -> DEPLOY (live)
	assert_bool(_m.exposed_now(C)).is_false()
	(_sys.lanes[2][0] as HardpointSim).owner = S  # South: Prism Locks falls
	assert_bool(_m.exposed_now(C)).is_true()
	assert_bool(_m.exposed_now(S)).is_false()
	(_sys.lanes[2][0] as HardpointSim).owner = C
	(_sys.lanes[1][4] as HardpointSim).owner = C  # Center: Boiler Hall falls
	assert_bool(_m.exposed_now(S)).is_true()
