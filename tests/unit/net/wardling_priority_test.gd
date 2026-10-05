extends GdUnitTestSuite
## W16-NET relevance / priority accumulator: near, in-view and own-squad
## Wardlings every tick, far ones at 1 / far_interval_ticks, and no starvation
## when the byte budget is short.


func _snap(tick: int, wards: Array) -> SnapshotData:
	var s := SnapshotData.new()
	s.tick = tick
	s.own_net_id = 1
	var m := MotorState.new()
	m.position = Vector3.ZERO
	s.own_state = m
	var me := SnapshotFixtures.hero(1, Vector3.ZERO)
	me.yaw = 0.0  # looking down -Z
	s.entities.append(me)
	for w in wards:
		s.wardlings.append(w)
	return s


func _prio() -> WardlingPrioritiser:
	return WardlingPrioritiser.new(NetFixtures.net_config())


func test_relevance_rules() -> void:
	var p := _prio()
	var fwd := Vector3(0, 0, -1)
	assert_bool(p.is_relevant(SnapshotFixtures.wardling(1, Vector3(30, 0, 20)), Vector3.ZERO, fwd, 1)).is_true()  # near
	assert_bool(p.is_relevant(SnapshotFixtures.wardling(2, Vector3(0, 0, -80)), Vector3.ZERO, fwd, 1)).is_true()  # in view
	assert_bool(p.is_relevant(SnapshotFixtures.wardling(3, Vector3(0, 0, 80)), Vector3.ZERO, fwd, 1)).is_false()  # behind
	assert_bool(p.is_relevant(SnapshotFixtures.wardling(4, Vector3(0, 0, -200)), Vector3.ZERO, fwd, 1)).is_false()  # too far
	assert_bool(p.is_relevant(SnapshotFixtures.wardling(5, Vector3(0, 0, 300), 1), Vector3.ZERO, fwd, 1)).is_true()  # own squad


func test_near_every_tick_far_at_one_in_three() -> void:
	var p := _prio()
	var near := SnapshotFixtures.wardling(10, Vector3(5, 0, 5))
	var far := SnapshotFixtures.wardling(11, Vector3(0, 0, 300))
	var near_sent := 0
	var far_sent := 0
	for t in 30:
		var order := p.order(_snap(t, [near, far]), null, t)
		near_sent += 1 if 10 in order else 0
		far_sent += 1 if 11 in order else 0
		p.sent(order, t)
	assert_int(near_sent).is_equal(30)
	assert_int(far_sent).is_equal(10)


func test_oldest_eligible_goes_first() -> void:
	var p := _prio()
	var far := SnapshotFixtures.wardling(20, Vector3(0, 0, 300))
	var near := SnapshotFixtures.wardling(21, Vector3(1, 0, 1))
	for t in 6:  # far one waits 6 ticks (budget never reached it)
		var order := p.order(_snap(t, [far, near]), null, t)
		p.sent([21], t)
	var o := p.order(_snap(6, [far, near]), null, 6)
	assert_int(o[0]).is_equal(20)


## Budget-limited end to end: 120 moving Wardlings, budget for far fewer per
## tick. Every one must be refreshed within the bound and none starves.
func test_no_starvation_under_a_tight_budget() -> void:
	var net := NetFixtures.net_config()
	var enc := SnapshotEncoder.new(32, 700)
	enc.prioritiser = WardlingPrioritiser.new(net)
	var dec := SnapshotDecoder.new(64)
	var n := 120
	var last_fresh := {}
	var worst_gap := 0
	var ack := 0
	for t in range(1, 181):
		var wards := []
		for i in n:
			# Half near the player, half in another lane; all move every tick.
			var base := Vector3(i % 10, 0, 10 + i) if i < n / 2 else Vector3(200 + i, 0, 300)
			wards.append(SnapshotFixtures.wardling(100 + i, base + Vector3(0.05 * t, 0, 0)))
		var s := _snap(t, wards)
		var b := enc.encode(s, ack)
		assert_int(b.size()).is_less_equal(700)
		var d := dec.decode(b)
		assert_object(d).is_not_null()
		ack = t
		for w in d.wardlings:
			if not w.stale:
				if last_fresh.has(w.net_id):
					worst_gap = maxi(worst_gap, t - last_fresh[w.net_id])
				last_fresh[w.net_id] = t
	assert_int(last_fresh.size()).is_equal(n)
	# 120 x 9 B updates against ~560 B of room per tick: ~60 per tick, so a full
	# rotation takes ~2 ticks; the bound allows the far interval on top of it.
	assert_int(worst_gap).is_less_equal(net.far_send_interval_ticks + ceili(n / 50.0))


func test_heroes_are_never_deferred() -> void:
	var enc := SnapshotEncoder.new(32, 300)
	enc.prioritiser = _prio()
	var s := _snap(5, [])
	for i in 9:
		s.entities.append(SnapshotFixtures.hero(10 + i, Vector3(0, 0, -400.0)))
	for i in 60:
		s.wardlings.append(SnapshotFixtures.wardling(100 + i, Vector3(0, 0, -5)))
	var d := SnapshotCodec.decode(enc.encode(s, 0))
	assert_int(d.entities.size()).is_equal(10)
	assert_int(enc.last.deferred).is_greater(0)
