extends GdUnitTestSuite
## W17-MM: lockout escalation and decay, ranked-only leaver locks.

const T0 := 1000.0


func _rules() -> MatchmakingRulesDef:
	var r := MatchmakingRulesDef.new()
	r.decline_lockout_steps_s = PackedFloat32Array([30.0, 120.0, 300.0])
	r.decline_strike_decay_s = 3600.0
	r.leaver_lockout_steps_s = PackedFloat32Array([600.0, 3600.0])
	r.leaver_strike_decay_s = 86400.0
	return r


func test_escalates_then_repeats_last_step() -> void:
	var lt := LockoutTracker.new(_rules())
	assert_float(lt.record("a", LockoutTracker.Kind.DECLINE, T0)).is_equal(30.0)
	assert_float(lt.record("a", LockoutTracker.Kind.DECLINE, T0 + 40)).is_equal(120.0)
	assert_float(lt.record("a", LockoutTracker.Kind.DECLINE, T0 + 200)).is_equal(300.0)
	assert_float(lt.record("a", LockoutTracker.Kind.DECLINE, T0 + 600)).is_equal(300.0)
	assert_int(lt.strikes("a", LockoutTracker.Kind.DECLINE, T0 + 600)).is_equal(4)


func test_lock_runs_out() -> void:
	var lt := LockoutTracker.new(_rules())
	lt.record("a", LockoutTracker.Kind.DECLINE, T0)
	assert_bool(lt.is_locked("a", T0 + 29)).is_true()
	assert_float(lt.locked_until("a", T0 + 29)).is_equal(T0 + 30)
	assert_bool(lt.is_locked("a", T0 + 30)).is_false()


func test_strikes_decay_one_per_period() -> void:
	var lt := LockoutTracker.new(_rules())
	lt.record("a", LockoutTracker.Kind.DECLINE, T0)
	lt.record("a", LockoutTracker.Kind.DECLINE, T0 + 100)
	lt.record("a", LockoutTracker.Kind.DECLINE, T0 + 200)
	assert_int(lt.strikes("a", LockoutTracker.Kind.DECLINE, T0 + 200 + 3599)).is_equal(3)
	assert_int(lt.strikes("a", LockoutTracker.Kind.DECLINE, T0 + 200 + 3600)).is_equal(2)
	assert_int(lt.strikes("a", LockoutTracker.Kind.DECLINE, T0 + 200 + 7300)).is_equal(1)
	# The next decline after decay escalates from the decayed count.
	assert_float(lt.record("a", LockoutTracker.Kind.DECLINE, T0 + 200 + 7300)).is_equal(120.0)
	assert_int(lt.strikes("a", LockoutTracker.Kind.DECLINE, T0 + 200 + 7300 + 3600 * 5)).is_equal(0)


func test_leaver_lock_only_blocks_ranked() -> void:
	var lt := LockoutTracker.new(_rules())
	assert_float(lt.record("a", LockoutTracker.Kind.LEAVE, T0)).is_equal(600.0)
	assert_bool(lt.is_locked("a", T0 + 10, false)).is_false()
	assert_bool(lt.is_locked("a", T0 + 10, true)).is_true()
	assert_float(lt.record("a", LockoutTracker.Kind.LEAVE, T0 + 700)).is_equal(3600.0)


func test_sweep_and_round_trip() -> void:
	var lt := LockoutTracker.new(_rules())
	lt.record("a", LockoutTracker.Kind.DECLINE, T0)
	lt.strikes("b", LockoutTracker.Kind.DECLINE, T0)
	lt.sweep(T0 + 1)
	assert_int(lt.to_dict().size()).is_equal(1)
	var copy := LockoutTracker.new(_rules())
	copy.from_dict(lt.to_dict())
	assert_bool(copy.is_locked("a", T0 + 5)).is_true()
	lt.sweep(T0 + 3600 * 2)
	assert_int(lt.to_dict().size()).is_equal(0)


func test_dodge_has_its_own_ladder_and_locks_every_queue() -> void:
	var r := _rules()
	r.dodge_lockout_steps_s = PackedFloat32Array([360.0, 1800.0])
	r.dodge_strike_decay_s = 86400.0
	var lt := LockoutTracker.new(r)
	assert_float(lt.record("a", LockoutTracker.Kind.DODGE, T0)).is_equal(360.0)
	assert_int(lt.strikes("a", LockoutTracker.Kind.DECLINE, T0)).is_equal(0)
	assert_bool(lt.is_locked("a", T0 + 359)).is_true()  # normal queues too
	assert_float(lt.record("a", LockoutTracker.Kind.DODGE, T0 + 400)).is_equal(1800.0)
	assert_int(lt.strikes("a", LockoutTracker.Kind.DODGE, T0 + 400 + 86400)).is_equal(1)  # one tier per day
