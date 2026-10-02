extends GdUnitTestSuite
## E11 AimHumanizer: reaction delay, bounded tracking error, turn-rate limit,
## and convergence on a target (BotProfile difficulty tiers).

const HZ: int = 30


func _aim(path: String, seed_: int = 7) -> AimHumanizer:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	return AimHumanizer.new(load(path) as BotProfile, rng, HZ)


func test_error_stays_within_profile_bounds_for_every_tier() -> void:
	for tier in ["easy", "normal", "hard"]:
		var a := _aim("res://assets/data/ai/bot_profile_%s.tres" % tier)
		var p := a.profile
		var eye := Vector3(0.0, 1.6, 0.0)
		var limit := p.max_error_deg + p.flick_error_deg + 1e-3
		var max_seen := 0.0
		for t in 3000:
			if t % 45 == 0:
				a.set_target(1 + floori(t / 45.0) % 3, t)
			var target := Vector3(20.0 * sin(t * 0.01), 1.1, -25.0 + 5.0 * cos(t * 0.013))
			a.track(target, eye, t)
			var e := a.error_deg(t)
			max_seen = maxf(max_seen, e.length())
			assert_float(e.length()).is_less_equal(limit)
			assert_float(a.yaw).is_between(0.0, TAU)
			assert_float(absf(a.pitch)).is_less_equal(AimHumanizer.PITCH_LIMIT + 1e-6)
		assert_float(max_seen).is_greater(0.0)  # the error is real, not zero


func test_reaction_delay_gates_firing() -> void:
	var a := _aim("res://assets/data/ai/bot_profile_normal.tres")
	var p := a.profile
	a.set_target(5, 100)
	var earliest := 100 + floori(p.reaction_s * (1.0 - p.reaction_jitter) * HZ)
	var latest := 100 + ceili(p.reaction_s * (1.0 + p.reaction_jitter) * HZ)
	assert_bool(a.can_fire(100)).is_false()
	assert_bool(a.can_fire(earliest - 1)).is_false()
	assert_bool(a.can_fire(latest)).is_true()
	a.set_target(0, latest)
	assert_bool(a.can_fire(latest + 1)).is_false()


func test_harder_tiers_react_faster_and_err_less() -> void:
	var e := load("res://assets/data/ai/bot_profile_easy.tres") as BotProfile
	var n := load("res://assets/data/ai/bot_profile_normal.tres") as BotProfile
	var h := load("res://assets/data/ai/bot_profile_hard.tres") as BotProfile
	assert_float(h.reaction_s).is_less(n.reaction_s)
	assert_float(n.reaction_s).is_less(e.reaction_s)
	assert_float(h.max_error_deg).is_less(n.max_error_deg)
	assert_float(n.max_error_deg).is_less(e.max_error_deg)
	assert_float(h.headshot_rate).is_greater(n.headshot_rate)
	assert_float(n.headshot_rate).is_greater(e.headshot_rate)


func test_turn_rate_is_limited_per_tick() -> void:
	var a := _aim("res://assets/data/ai/bot_profile_normal.tres")
	var step := deg_to_rad(a.profile.turn_rate_deg_s) / HZ
	a.yaw = 0.0
	var eye := Vector3.ZERO
	var behind := Vector3(0.0, 0.0, 10.0)  # yaw PI
	var prev := a.yaw
	for t in 20:
		a.look_at(behind, eye)
		assert_float(absf(angle_difference(prev, a.yaw))).is_less_equal(step + 1e-5)
		prev = a.yaw
	for t in 60:
		a.look_at(behind, eye)
	assert_float(absf(angle_difference(a.yaw, PI))).is_less(0.01)


func test_tracking_converges_within_error_bound() -> void:
	var a := _aim("res://assets/data/ai/bot_profile_hard.tres")
	var eye := Vector3(0.0, 1.6, 0.0)
	var target := Vector3(10.0, 1.1, -20.0)
	a.set_target(3, 0)
	for t in 90:
		a.track(target, eye, t)
	var bound := deg_to_rad(a.profile.max_error_deg) * 1.5 + 1e-3
	assert_float(a.off_angle(target, eye)).is_less_equal(bound)
