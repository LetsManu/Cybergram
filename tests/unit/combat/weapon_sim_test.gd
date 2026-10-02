extends GdUnitTestSuite
## WeaponSim: fire-rate gating, trigger discipline, spread (weapons-and-mods.md §3.2).

const HZ: int = 30


func _run(w: WeaponSim, ticks: int, fire: Callable, allowed: bool = true) -> int:
	var cmd := InputCommand.new()
	var shots := 0
	for t in ticks:
		cmd.buttons = InputCommand.BTN_FIRE if fire.call(t) else 0
		if w.step(cmd, t, allowed):
			shots += 1
	return shots


func test_full_auto_is_gated_by_fire_rate() -> void:
	# 4 shots/s = one per 7.5 ticks: 40 shots in 300 ticks (10 s), never more.
	var w := WeaponSim.new(CombatFixtures.auto_gun(4.0), HZ, 1)
	assert_int(_run(w, 300, func(_t: int) -> bool: return true)).is_equal(40)
	var w2 := WeaponSim.new(CombatFixtures.auto_gun(10.0), HZ, 1)
	assert_int(_run(w2, 300, func(_t: int) -> bool: return true)).is_equal(100)


func test_fire_interval_holds_between_shots() -> void:
	var w := WeaponSim.new(CombatFixtures.auto_gun(1.25), HZ, 1)  # Ironmaw rate: 24 ticks
	var cmd := InputCommand.new()
	cmd.buttons = InputCommand.BTN_FIRE
	var shot_ticks: Array[int] = []
	for t in 100:
		if w.step(cmd, t, true):
			shot_ticks.append(t)
	assert_array(shot_ticks).is_equal([0, 24, 48, 72, 96])


func test_idle_time_does_not_bank_shots() -> void:
	var w := WeaponSim.new(CombatFixtures.auto_gun(4.0), HZ, 1)
	var shots := _run(w, 400, func(t: int) -> bool: return t >= 300)
	assert_int(shots).is_equal(14)  # 100 ticks of fire from a cold start: ceil(100 / 7.5)


func test_semi_auto_needs_a_trigger_release() -> void:
	var def := CombatFixtures.auto_gun(4.0)
	def.semi_auto = true
	var held := WeaponSim.new(def, HZ, 1)
	assert_int(_run(held, 300, func(_t: int) -> bool: return true)).is_equal(1)
	var mash := WeaponSim.new(def, HZ, 1)
	var shots := _run(mash, 300, func(t: int) -> bool: return t % 2 == 0)
	assert_int(shots).is_less_equal(40)  # still capped at 4/s
	assert_int(shots).is_greater_equal(37)


func test_no_fire_when_not_allowed() -> void:
	var w := WeaponSim.new(CombatFixtures.auto_gun(10.0), HZ, 1)
	assert_int(_run(w, 60, func(_t: int) -> bool: return true, false)).is_equal(0)


func test_fire_stops_when_feed_is_empty() -> void:
	var w := WeaponSim.new(CombatFixtures.vesper().weapon, HZ, 1)  # Threadcaster: 17 shots to empty
	var shots := _run(w, 140, func(t: int) -> bool: return t % 2 == 0)
	assert_int(shots).is_equal(17)
	assert_bool((w.feed as ManaPoolFeed).burnout).is_true()


func test_spread_blooms_and_recovers() -> void:
	# Breakline AR-7 spread (0.4 / +0.12 / 2.2) at 10/s; recovers 6 deg/s after 0.15 s.
	var def := CombatFixtures.auto_gun(10.0)
	def.spread_base_deg = 0.4
	def.spread_bloom_deg = 0.12
	def.spread_max_deg = 2.2
	var w := WeaponSim.new(def, HZ, 1)
	assert_int(_run(w, 60, func(t: int) -> bool: return t < 60)).is_equal(20)
	assert_float(w.spread_deg).is_equal_approx(2.2, 1e-5)  # 0.4 + 20 x 0.12 capped
	var cmd := InputCommand.new()
	var tk := 60
	while tk < 63:  # inside the 0.15 s recovery delay: no recovery yet
		w.step(cmd, tk, true)
		tk += 1
	assert_float(w.spread_deg).is_equal_approx(2.2, 1e-5)
	while tk < 120:
		w.step(cmd, tk, true)
		tk += 1
	assert_float(w.spread_deg).is_equal_approx(0.4, 1e-5)


func test_pellets_stay_inside_the_cone() -> void:
	var w := WeaponSim.new(CombatFixtures.brannoc().weapon, HZ, 3)
	var cmd := InputCommand.new()
	cmd.buttons = InputCommand.BTN_FIRE
	assert_bool(w.step(cmd, 0, true)).is_true()
	var fwd := Vector3(0.3, -0.1, -1.0).normalized()
	var dirs := w.pellet_directions(fwd)
	assert_int(dirs.size()).is_equal(10)
	for d in dirs:
		assert_float(rad_to_deg(d.angle_to(fwd))).is_less_equal(5.5 + 1e-3)


func test_reset_refills_and_resets_spread() -> void:
	var w := WeaponSim.new(CombatFixtures.vesper().weapon, HZ, 1)
	_run(w, 100, func(t: int) -> bool: return t % 2 == 0)
	w.reset()
	assert_float(w.feed.current()).is_equal(100.0)
	assert_float(w.spread_deg).is_equal_approx(0.2, 1e-6)
