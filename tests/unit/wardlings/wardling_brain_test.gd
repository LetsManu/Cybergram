extends GdUnitTestSuite
## WardlingBrain transition table (architecture.md §10.1, wardlings-and-economy.md
## §9): one row per command, plus Vanguard and DeathHold, and the invariant
## that decide() only ever returns a state allowed by TRANSITIONS.

const S := WardlingBrain.State


func _p(cmd: int) -> WardlingBrain.Percept:
	var p := WardlingBrain.Percept.new()
	p.command = cmd
	return p


func test_follow_row() -> void:
	var p := _p(Squad.CMD_FOLLOW)
	assert_int(WardlingBrain.decide(S.FOLLOW, p)).is_equal(S.FOLLOW)
	p.threat = true  # retaliation (owner or self hit, or enemy Wardling in aggro)
	assert_int(WardlingBrain.decide(S.FOLLOW, p)).is_equal(S.ENGAGE)
	p.threat = false
	assert_int(WardlingBrain.decide(S.ENGAGE, p)).is_equal(S.FOLLOW)
	p.out_of_leash = true
	p.returned = false
	assert_int(WardlingBrain.decide(S.FOLLOW, p)).is_equal(S.RETURN)
	# Returning holds fire until back inside the return radius, even under threat.
	p.out_of_leash = false
	p.threat = true
	assert_int(WardlingBrain.decide(S.RETURN, p)).is_equal(S.RETURN)
	p.returned = true
	assert_int(WardlingBrain.decide(S.RETURN, p)).is_equal(S.ENGAGE)
	p.threat = false
	assert_int(WardlingBrain.decide(S.RETURN, p)).is_equal(S.FOLLOW)


func test_hold_row() -> void:
	var p := _p(Squad.CMD_HOLD)
	assert_int(WardlingBrain.decide(S.FOLLOW, p)).is_equal(S.HOLD)
	p.threat = true
	assert_int(WardlingBrain.decide(S.HOLD, p)).is_equal(S.ENGAGE)
	p.threat = false
	assert_int(WardlingBrain.decide(S.ENGAGE, p)).is_equal(S.HOLD)
	p.out_of_leash = true
	p.returned = false
	assert_int(WardlingBrain.decide(S.ENGAGE, p)).is_equal(S.RETURN)
	p.out_of_leash = false
	p.returned = true
	assert_int(WardlingBrain.decide(S.RETURN, p)).is_equal(S.HOLD)
	p.command = Squad.CMD_FOLLOW
	assert_int(WardlingBrain.decide(S.HOLD, p)).is_equal(S.FOLLOW)


func test_attack_target_row() -> void:
	var p := _p(Squad.CMD_ATTACK)
	p.attack_valid = true
	for from in [S.FOLLOW, S.HOLD, S.ENGAGE, S.RETURN, S.CAPTURE]:
		assert_int(WardlingBrain.decide(from, p)).is_equal(S.ATTACK_TARGET)
	# Attack Target is NOT overridden by retaliation (C15, §10.1).
	p.threat = true
	assert_int(WardlingBrain.decide(S.ATTACK_TARGET, p)).is_equal(S.ATTACK_TARGET)
	# Order over (Squad reverted the command): back to the previous command.
	p.threat = false
	p.attack_valid = false
	p.command = Squad.CMD_HOLD
	assert_int(WardlingBrain.decide(S.ATTACK_TARGET, p)).is_equal(S.HOLD)
	p.command = Squad.CMD_FOLLOW
	assert_int(WardlingBrain.decide(S.ATTACK_TARGET, p)).is_equal(S.FOLLOW)


func test_go_capture_row() -> void:
	var p := _p(Squad.CMD_CAPTURE)
	assert_int(WardlingBrain.decide(S.FOLLOW, p)).is_equal(S.CAPTURE)
	p.threat = true  # enemy in the zone
	assert_int(WardlingBrain.decide(S.CAPTURE, p)).is_equal(S.ENGAGE)
	p.threat = false
	assert_int(WardlingBrain.decide(S.ENGAGE, p)).is_equal(S.CAPTURE)
	p.out_of_leash = true
	p.returned = false
	assert_int(WardlingBrain.decide(S.CAPTURE, p)).is_equal(S.RETURN)


func test_owner_death_goes_to_dissolving_from_every_squad_state_and_stays() -> void:
	var p := _p(Squad.CMD_ATTACK)
	p.dissolving = true
	p.attack_valid = true
	for from in [S.FOLLOW, S.HOLD, S.ENGAGE, S.RETURN, S.ATTACK_TARGET, S.CAPTURE]:
		assert_int(WardlingBrain.decide(from, p)).is_equal(S.DISSOLVING)
	p.dissolving = false
	assert_int(WardlingBrain.decide(S.DISSOLVING, p)).is_equal(S.DISSOLVING)


func test_vanguard_row() -> void:
	var p := WardlingBrain.Percept.new()
	p.allegiance = WardlingBrain.Allegiance.VANGUARD
	assert_int(WardlingBrain.decide(S.MARCH, p)).is_equal(S.MARCH)
	p.at_front = true
	assert_int(WardlingBrain.decide(S.MARCH, p)).is_equal(S.CAPTURE)
	p.threat = true
	assert_int(WardlingBrain.decide(S.CAPTURE, p)).is_equal(S.ENGAGE)
	p.threat = false
	p.at_front = false  # the front moved
	assert_int(WardlingBrain.decide(S.ENGAGE, p)).is_equal(S.MARCH)
	assert_int(WardlingBrain.decide(S.CAPTURE, p)).is_equal(S.MARCH)


func test_decide_only_returns_table_transitions() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	for i in 3000:
		var p := WardlingBrain.Percept.new()
		p.allegiance = rng.randi_range(0, 2)
		p.command = rng.randi_range(1, 4)
		p.dissolving = rng.randf() < 0.1
		p.attack_valid = rng.randf() < 0.5
		p.threat = rng.randf() < 0.5
		p.out_of_leash = rng.randf() < 0.3
		p.returned = rng.randf() < 0.5
		p.at_front = rng.randf() < 0.5
		var from := rng.randi_range(0, S.size() - 1)
		var to := WardlingBrain.decide(from, p)
		assert_bool(WardlingBrain.is_allowed(from, to)).is_true()
