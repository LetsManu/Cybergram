extends GdUnitTestSuite
## ManaPoolFeed and MagazineFeed (weapons-and-mods.md §3.2, §3.5, §4.6).

const HZ: int = 30


func _threadcaster_feed() -> ManaPoolFeed:
	return AmmoFeed.create(CombatFixtures.vesper().weapon, HZ) as ManaPoolFeed


func test_create_picks_feed_by_kind() -> void:
	assert_object(AmmoFeed.create(CombatFixtures.vesper().weapon, HZ)).is_instanceof(ManaPoolFeed)
	assert_object(AmmoFeed.create(CombatFixtures.brannoc().weapon, HZ)).is_instanceof(MagazineFeed)


func test_mana_drains_per_shot_without_burnout_above_zero() -> void:
	var f := _threadcaster_feed()
	for i in 16:
		assert_bool(f.can_fire()).is_true()
		f.consume(i)
	assert_float(f.mana).is_equal_approx(4.0, 1e-4)  # 100 - 16 x 6
	assert_bool(f.burnout).is_false()
	assert_int(f.regen_resume_tick).is_equal(15 + 30)  # 1.0 s delay


func test_emptying_pool_triggers_burnout_with_longer_delay() -> void:
	var f := _threadcaster_feed()
	for i in 17:
		f.consume(0)
	assert_float(f.mana).is_equal(0.0)
	assert_bool(f.burnout).is_true()
	assert_bool(f.can_fire()).is_false()
	assert_int(f.flags() & AmmoFeed.FLAG_BURNOUT).is_not_equal(0)
	assert_int(f.regen_resume_tick).is_equal(45)  # 1.0 s x 1.5
	for t in range(1, 45):
		f.step(t)
	assert_float(f.mana).is_equal(0.0)  # still waiting
	f.step(45)
	assert_bool(f.burnout).is_false()  # Burnout ends when regen resumes
	assert_float(f.mana).is_equal_approx(35.0 / HZ, 1e-4)


func test_mana_regen_rate_and_cap() -> void:
	var f := _threadcaster_feed()
	f.consume(0)
	f.consume(0)  # 88 left, regen from tick 30
	for t in range(0, 30):
		f.step(t)
	assert_float(f.mana).is_equal_approx(88.0, 1e-4)
	for t in range(30, 30 + 6):
		f.step(t)  # 6 ticks x 35/30
	assert_float(f.mana).is_equal_approx(95.0, 1e-3)
	for t in range(36, 200):
		f.step(t)
	assert_float(f.mana).is_equal(100.0)


func test_firing_restarts_regen_delay() -> void:
	var f := _threadcaster_feed()
	f.consume(0)
	f.step(29)
	f.consume(29)
	f.step(30)
	assert_float(f.mana).is_equal_approx(88.0, 1e-4)
	assert_int(f.regen_resume_tick).is_equal(59)


func test_mana_refill() -> void:
	var f := _threadcaster_feed()
	for i in 17:
		f.consume(0)
	f.refill()
	assert_float(f.mana).is_equal(100.0)
	assert_bool(f.burnout).is_false()


func test_magazine_drain_and_empty_reload_time() -> void:
	var f := AmmoFeed.create(CombatFixtures.rifle_mag(), HZ) as MagazineFeed
	for i in 30:
		assert_bool(f.can_fire()).is_true()
		f.consume(10)
	assert_int(f.rounds).is_equal(0)
	assert_bool(f.can_fire()).is_false()
	assert_bool(f.is_reloading()).is_true()  # auto reload on empty
	assert_int(f.reload_end_tick).is_equal(10 + 57)  # 1.9 s empty reload
	f.step(66)
	assert_int(f.rounds).is_equal(0)
	f.step(67)
	assert_int(f.rounds).is_equal(30)
	assert_int(f.reserve).is_equal(120)


func test_tactical_reload_is_committed_and_uses_reload_time() -> void:
	var f := AmmoFeed.create(CombatFixtures.rifle_mag(), HZ) as MagazineFeed
	f.request_reload(0)
	assert_bool(f.is_reloading()).is_false()  # full magazine: ignored
	for i in 10:
		f.consume(0)
	f.request_reload(5)
	assert_int(f.reload_end_tick).is_equal(5 + 48)  # 1.6 s
	assert_bool(f.can_fire()).is_false()  # committed: fire locked
	assert_int(f.flags() & AmmoFeed.FLAG_RELOADING).is_not_equal(0)
	f.step(53)
	assert_int(f.rounds).is_equal(30)
	assert_int(f.reserve).is_equal(140)


func test_reserve_exhaustion_goes_dry() -> void:
	var w := CombatFixtures.rifle_mag()
	w.reserve = 40
	var f := AmmoFeed.create(w, HZ) as MagazineFeed
	var tick := 0
	var shots := 0
	while tick < 2000:
		f.step(tick)
		if f.can_fire():
			f.consume(tick)
			shots += 1
		tick += 1
	assert_int(shots).is_equal(70)  # magazine + reserve
	assert_int(f.rounds).is_equal(0)
	assert_int(f.reserve).is_equal(0)
	assert_bool(f.is_reloading()).is_false()
	assert_int(f.flags() & AmmoFeed.FLAG_DRY).is_not_equal(0)
	f.refill()
	assert_int(f.rounds).is_equal(30)
	assert_int(f.reserve).is_equal(40)


func test_ironmaw_loads_one_shell_per_step() -> void:
	var f := AmmoFeed.create(CombatFixtures.brannoc().weapon, HZ) as MagazineFeed
	for i in 3:
		f.consume(0)
	f.request_reload(0)
	var per := ceili(0.45 * HZ)  # 14 ticks per shell
	assert_int(f.reload_end_tick).is_equal(per)
	for t in range(1, 3 * per + 1):
		f.step(t)
	assert_int(f.rounds).is_equal(6)
	assert_int(f.reserve).is_equal(27)
	assert_bool(f.is_reloading()).is_false()


func test_ironmaw_reload_is_interrupted_by_firing() -> void:
	var f := AmmoFeed.create(CombatFixtures.brannoc().weapon, HZ) as MagazineFeed
	for i in 6:
		f.consume(0)  # empty -> auto reload
	assert_bool(f.is_reloading()).is_true()
	assert_bool(f.can_fire()).is_false()
	for t in range(1, 15):
		f.step(t)  # one shell loaded at tick 14
	assert_int(f.rounds).is_equal(1)
	assert_bool(f.can_fire()).is_true()  # interruptible
	f.consume(15)
	assert_int(f.rounds).is_equal(0)
	assert_int(f.reserve).is_equal(29)  # the loaded shell was kept and fired
	assert_bool(f.is_reloading()).is_true()  # empty again -> reload restarts
