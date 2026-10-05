extends GdUnitTestSuite
## W16-NET adaptive interpolation: delay from p95 jitter within 2..5 ticks,
## hysteresis against oscillation, loss allowance, and end to end over a
## jittery simulated link.

const DT := 1.0 / 60.0  # render frames


func _ctl() -> InterpDelayController:
	return InterpDelayController.from_config(NetFixtures.net_config())


func _run(c: InterpDelayController, jitter_ms: float, loss: float, seconds: float) -> int:
	var changes := 0
	var last := c.target
	for i in roundi(seconds / DT):
		c.update(jitter_ms, loss, DT)
		if c.target != last:
			changes += 1
			last = c.target
	return changes


func test_clean_link_settles_at_the_minimum() -> void:
	var c := _ctl()
	assert_int(c.target).is_equal(3)  # starts at the configured fixed delay
	_run(c, 0.0, 0.0, 5.0)
	assert_int(c.target).is_equal(2)
	assert_float(c.delay).is_equal_approx(2.0, 1e-6)
	assert_float(c.delay_ms()).is_equal_approx(66.67, 0.01)


func test_target_covers_p95_jitter_within_bounds() -> void:
	var c := _ctl()
	_run(c, 40.0, 0.0, 1.0)  # 1.5 + 1.2 = 2.7 ticks
	assert_int(c.target).is_equal(3)
	_run(c, 70.0, 0.0, 1.0)  # 1.5 + 2.1 = 3.6
	assert_int(c.target).is_equal(4)
	_run(c, 400.0, 0.0, 1.0)
	assert_int(c.target).is_equal(5)  # capped at ~166 ms


func test_rise_is_immediate_fall_waits_for_the_hold() -> void:
	var c := _ctl()
	_run(c, 0.0, 0.0, 5.0)
	c.update(70.0, 0.0, DT)
	assert_int(c.target).is_equal(4)
	_run(c, 0.0, 0.0, 1.9)
	assert_int(c.target).is_equal(4)  # still held
	_run(c, 0.0, 0.0, 0.2)
	assert_int(c.target).is_equal(3)  # one step at a time
	_run(c, 0.0, 0.0, 2.1)
	assert_int(c.target).is_equal(2)


func test_jitter_hovering_at_a_boundary_does_not_oscillate() -> void:
	var c := _ctl()
	var changes := 0
	for k in 40:  # 20 s of p95 alternating 48 / 52 ms around the 3/4 boundary
		changes += _run(c, 48.0 if k % 2 == 0 else 52.0, 0.0, 0.5)
	assert_int(changes).is_less_equal(1)


func test_slew_moves_the_applied_delay_gradually() -> void:
	var c := _ctl()
	_run(c, 0.0, 0.0, 5.0)
	c.update(400.0, 0.0, DT)
	assert_int(c.target).is_equal(5)
	assert_float(c.delay).is_less(2.1)
	_run(c, 400.0, 0.0, 0.5)
	assert_float(c.delay).is_equal_approx(3.0, 0.05)  # 2 ticks/s
	_run(c, 400.0, 0.0, 2.0)
	assert_float(c.delay).is_equal(5.0)


func test_heavy_loss_adds_a_tick() -> void:
	var c := _ctl()
	_run(c, 0.0, 8.0, 1.0)
	assert_int(c.target).is_equal(3)


func test_disabled_keeps_the_fixed_delay() -> void:
	var net := NetFixtures.net_config()
	net.adaptive_interp = false
	var c := InterpDelayController.from_config(net)
	_run(c, 400.0, 20.0, 3.0)
	assert_int(c.target).is_equal(net.interp_delay_ticks)
	assert_float(c.delay).is_equal(float(net.interp_delay_ticks))


## Real snapshots over a conditioned loopback link, client polling at 30 Hz.
func _link_target(jitter_ms: int) -> int:
	var net := NetFixtures.net_config()
	var link := LoopbackLink.new(NetFixtures.profile(30, jitter_ms, 0.0, 5))
	var server := link.create_endpoint(1)
	var cs := ClientSession.new(link.create_endpoint(2), net)
	var c := InterpDelayController.from_config(net)
	for t in range(1, 300):
		var s := SnapshotData.new()
		s.tick = t
		server.send(2, Transport.CH_SNAPSHOT, SnapshotCodec.encode(s))
		link.advance(net.tick_dt())
		cs.poll()
		c.update(cs.stats.jitter_p95_ms(), cs.stats.loss_pct(), net.tick_dt())
	return c.target


func test_simulated_link_jitter_drives_the_delay() -> void:
	assert_int(_link_target(0)).is_equal(2)
	var jittery := _link_target(60)
	assert_int(jittery).is_greater_equal(3)
	assert_int(jittery).is_less_equal(5)
