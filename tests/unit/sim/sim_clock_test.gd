extends GdUnitTestSuite
## Unit tests for SimClock (src/core/sim/sim_clock.gd).

const RATE_HZ: int = 30


func test_sim_clock_one_interval_yields_one_tick() -> void:
	var clock := SimClock.new(RATE_HZ)
	assert_int(clock.advance(1.0 / RATE_HZ)).is_equal(1)
	assert_int(clock.tick).is_equal(1)


func test_sim_clock_partial_intervals_accumulate() -> void:
	var clock := SimClock.new(RATE_HZ)
	var half := 0.5 / RATE_HZ
	assert_int(clock.advance(half)).is_equal(0)
	assert_int(clock.advance(half)).is_equal(1)


func test_sim_clock_many_small_frames_do_not_drift() -> void:
	var clock := SimClock.new(RATE_HZ)
	var total := 0
	for i in 144 * 10:  # ten seconds of 144 fps frames
		total += clock.advance(1.0 / 144.0)
	assert_int(total).is_between(RATE_HZ * 10 - 1, RATE_HZ * 10)


func test_sim_clock_long_hitch_is_capped_and_dropped() -> void:
	var clock := SimClock.new(RATE_HZ, 4)
	assert_int(clock.advance(2.0)).is_equal(4)
	assert_int(clock.advance(0.0)).is_equal(0)


func test_sim_clock_negative_delta_is_ignored() -> void:
	var clock := SimClock.new(RATE_HZ)
	assert_int(clock.advance(-1.0)).is_equal(0)
	assert_int(clock.tick).is_equal(0)


func test_sim_clock_interpolation_alpha_tracks_remainder() -> void:
	var clock := SimClock.new(RATE_HZ)
	clock.advance(0.25 / RATE_HZ)
	assert_float(clock.get_interpolation_alpha()).is_equal_approx(0.25, 0.01)
