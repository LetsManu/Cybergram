extends GdUnitTestSuite
## Squad rules (Canon C15, wardlings-and-economy.md §3, §9.5, §9.8): Attack
## Target lifetime, owner-death hold then dissolve, and the squad-of-3 pickup.

const HZ: int = 30

var _rules: WardlingRulesDef


func before_test() -> void:
	_rules = load("res://assets/data/wardlings/wardling_rules_slice.tres") as WardlingRulesDef


func test_attack_target_times_out_after_12_s_and_reverts_to_the_previous_command() -> void:
	var sq := Squad.new(1, 10, 0, 3)
	sq.issue(Squad.CMD_HOLD, 0, Vector3(1, 0, 2))
	sq.issue(Squad.CMD_ATTACK, 30, Vector3.ZERO, 77)
	assert_int(sq.prev_command).is_equal(Squad.CMD_HOLD)
	var end_tick := 30 + roundi(_rules.attack_timeout_s * HZ)
	for t in range(31, end_tick):
		sq.note_target_seen(t)  # visible the whole time
		assert_int(sq.update_attack(t, HZ, _rules, true, true)).is_equal(Squad.END_NONE)
	assert_int(sq.command).is_equal(Squad.CMD_ATTACK)
	assert_int(sq.update_attack(end_tick, HZ, _rules, true, true)).is_equal(Squad.END_TIMEOUT)
	assert_int(sq.command).is_equal(Squad.CMD_HOLD)
	assert_int(sq.attack_target_id).is_equal(0)
	assert_float(_rules.attack_timeout_s).is_equal(12.0)


func test_attack_ends_on_target_death_los_loss_or_leash() -> void:
	var sq := Squad.new(1, 10, 0, 3)
	sq.issue(Squad.CMD_ATTACK, 0, Vector3.ZERO, 5)
	assert_int(sq.update_attack(1, HZ, _rules, false, true)).is_equal(Squad.END_TARGET_GONE)
	assert_int(sq.command).is_equal(Squad.CMD_FOLLOW)
	sq.issue(Squad.CMD_ATTACK, 100, Vector3.ZERO, 5)
	var los_ticks := roundi(_rules.attack_los_timeout_s * HZ)
	assert_int(sq.update_attack(100 + los_ticks - 1, HZ, _rules, true, true)).is_equal(Squad.END_NONE)
	assert_int(sq.update_attack(100 + los_ticks, HZ, _rules, true, true)).is_equal(Squad.END_LOS_LOST)
	sq.issue(Squad.CMD_ATTACK, 300, Vector3.ZERO, 5)
	assert_int(sq.update_attack(301, HZ, _rules, true, false)).is_equal(Squad.END_LEASH)


func test_owner_death_holds_10_s_then_dissolves() -> void:
	var sq := Squad.new(1, 10, 0, 3)
	sq.issue(Squad.CMD_ATTACK, 0, Vector3.ZERO, 9)
	sq.on_owner_died(50, Vector3(4, 0, -20))
	assert_bool(sq.is_dissolving()).is_true()
	assert_vector(sq.hold_point).is_equal(Vector3(4, 0, -20))
	assert_int(sq.attack_target_id).is_equal(0)
	var hold := roundi(_rules.death_hold_s * HZ)
	assert_bool(sq.dissolve_due(50 + hold - 1, HZ, _rules)).is_false()
	assert_bool(sq.dissolve_due(50 + hold, HZ, _rules)).is_true()
	assert_float(_rules.death_hold_s).is_equal(10.0)


func test_go_capture_keeps_its_zone_during_death_hold() -> void:
	var sq := Squad.new(1, 10, 0, 3)
	sq.issue(Squad.CMD_CAPTURE, 0, Vector3(0, 0, -210), 0, 2)
	sq.on_owner_died(10, Vector3(5, 0, -100))
	assert_int(sq.command).is_equal(Squad.CMD_CAPTURE)
	assert_vector(sq.capture_point).is_equal(Vector3(0, 0, -210))


func test_squad_of_three_pickup_rule() -> void:
	assert_int(_rules.squad_size).is_equal(3)
	# Spawning at the Sanctum mints a full squad.
	assert_int(Squad.mint_count(0, 0, 3, false, true)).is_equal(3)
	# Losses are NOT replaced away from the Foundry...
	assert_int(Squad.mint_count(1, 0, 3, false, false)).is_equal(0)
	# ...the Foundry tops up only the empty slots, counting pending mints.
	assert_int(Squad.mint_count(1, 0, 3, true, false)).is_equal(2)
	assert_int(Squad.mint_count(1, 1, 3, true, false)).is_equal(1)
	assert_int(Squad.mint_count(3, 0, 3, true, false)).is_equal(0)


func test_follow_formation_sits_behind_the_owner() -> void:
	var slots := SquadBrain.formation_slots(Vector3.ZERO, Vector3(0, 0, -1), 3, _rules)
	assert_int(slots.size()).is_equal(3)
	for s in slots:
		assert_float(s.z).is_greater(0.0)  # moving -Z: the wedge trails at +Z
		var d := Vector2(s.x, s.z).length()
		assert_float(d).is_between(_rules.follow_back_min_m - 0.01, _rules.follow_back_max_m + 0.01)
