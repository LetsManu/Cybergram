extends GdUnitTestSuite
## W16-NET protocol v16: quantised snapshot records, delta against an acked
## baseline, lost-baseline fallback, budget / deferral, malformed input.

const POS_ERR := 0.5 / 32.0 + 1e-4
const VEL_ERR := 0.5 / 128.0 + 1e-4


func _same_state(a: SnapshotData, b: SnapshotData) -> void:
	assert_int(a.entities.size()).is_equal(b.entities.size())
	for i in a.entities.size():
		assert_int(a.entities[i].net_id).is_equal(b.entities[i].net_id)
		assert_vector(a.entities[i].position).is_equal(b.entities[i].position)
		assert_int(a.entities[i].hp).is_equal(b.entities[i].hp)
		assert_int(a.entities[i].fork_bits).is_equal(b.entities[i].fork_bits)
	assert_int(a.wardlings.size()).is_equal(b.wardlings.size())
	for i in a.wardlings.size():
		assert_vector(a.wardlings[i].position).is_equal(b.wardlings[i].position)
		assert_int(a.wardlings[i].owner_net_id).is_equal(b.wardlings[i].owner_net_id)
	assert_int(a.hardpoints.size()).is_equal(b.hardpoints.size())
	for i in a.hardpoints.size():
		assert_float(a.hardpoints[i].progress).is_equal(b.hardpoints[i].progress)
	assert_int(a.fx.size()).is_equal(b.fx.size())
	if not a.fx.is_empty():
		assert_int(a.fx[0].ticks_left).is_equal(b.fx[0].ticks_left)
	assert_array(Array(a.fronts)).is_equal(Array(b.fronts))
	assert_int(a.progress.lumen).is_equal(b.progress.lumen)
	assert_float(a.match_state.time_s).is_equal(b.match_state.time_s)
	assert_int(a.own_combat.hp).is_equal(b.own_combat.hp)
	assert_vector(a.own_state.position).is_equal(b.own_state.position)


func test_full_snapshot_round_trips_within_quantisation() -> void:
	var s := SnapshotFixtures.rich(40)
	var d := SnapshotCodec.decode(SnapshotCodec.encode(s))
	assert_object(d).is_not_null()
	assert_bool(d.is_delta).is_false()
	assert_int(d.tick).is_equal(40)
	assert_int(d.last_processed_seq).is_equal(80)
	assert_vector(d.own_state.position).is_equal(s.own_state.position)  # own motor stays f32
	assert_float(d.own_state.speed_scale).is_equal_approx(0.85, 1e-6)
	assert_int(d.own_combat.skill_cd_left[3]).is_equal(600)
	assert_int(d.entities.size()).is_equal(10)
	for i in 10:
		var a := s.entities[i]
		var b := d.entities[i]
		assert_int(b.net_id).is_equal(a.net_id)
		assert_vector(b.position).is_equal_approx(a.position, Vector3.ONE * POS_ERR)
		assert_vector(b.velocity).is_equal_approx(a.velocity, Vector3.ONE * VEL_ERR)
		assert_int(b.hp).is_equal(640)
		assert_int(b.max_hp).is_equal(800)
		assert_int(b.status).is_equal(0x0012)
		assert_int(b.hero_index).is_equal(4)
		assert_int(b.fork_bits).is_equal(a.fork_bits)
		assert_int(b.team).is_equal(a.team)
		assert_bool(b.grounded).is_true()
	assert_int(d.wardlings.size()).is_equal(20)
	assert_int(d.hardpoints.size()).is_equal(15)
	assert_float(d.hardpoints[7].progress).is_equal_approx(7 / 15.0, 1.0 / 65535.0)
	assert_int(d.fx[0].ticks_left).is_equal(90)
	assert_array(Array(d.fronts)).is_equal([1, 2, 0, 4, -1, 3])
	assert_int(d.progress.motes.size()).is_equal(2)
	assert_float(d.match_state.time_s).is_equal_approx(40 / 30.0, 1e-6)
	assert_float(d.match_state.uplinks[0].integrity).is_equal(900.0)
	assert_int(d.bolts.size()).is_equal(1)


func test_quantisation_error_is_bounded_across_map_extents() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	var worst := Vector4.ZERO
	for i in 400:
		var e := SnapshotData.EntityState.new()
		e.position = Vector3(rng.randf_range(-120, 120), rng.randf_range(-10, 60), rng.randf_range(-480, 40))
		e.velocity = Vector3(rng.randf_range(-40, 40), rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		e.yaw = rng.randf_range(-10.0, 10.0)
		e.pitch = rng.randf_range(-PI / 2.0, PI / 2.0)
		var d := SnapshotCodec.hero_from(1, SnapshotCodec.hero_record(e))
		var dp := (d.position - e.position).abs()
		var dv := (d.velocity - e.velocity).abs()
		worst.x = maxf(worst.x, maxf(dp.x, maxf(dp.y, dp.z)))
		worst.y = maxf(worst.y, maxf(dv.x, maxf(dv.y, dv.z)))
		worst.z = maxf(worst.z, absf(angle_difference(d.yaw, e.yaw)))
		worst.w = maxf(worst.w, absf(d.pitch - e.pitch))
	assert_float(worst.x).is_less_equal(1.0 / 64.0 + 1e-5)
	assert_float(worst.y).is_less_equal(1.0 / 256.0 + 1e-5)
	assert_float(worst.z).is_less_equal(PI / 65536.0 + 1e-6)
	assert_float(worst.w).is_less_equal(PI / 65536.0 + 1e-6)


func test_delta_rebuilds_the_same_state_as_full_and_is_smaller() -> void:
	var enc := SnapshotEncoder.new(32, 0)
	var dec := SnapshotDecoder.new(64)
	var s1 := SnapshotFixtures.rich(10)
	assert_object(dec.decode(enc.encode(s1, 0))).is_not_null()
	var s2 := SnapshotFixtures.advance(s1, 5)
	s2.hardpoints[3].progress = 0.9
	s2.progress.lumen = 2000
	var bytes := enc.encode(s2, 10)
	assert_bool(enc.last.is_delta).is_true()
	var d := dec.decode(bytes)
	assert_object(d).is_not_null()
	assert_bool(d.is_delta).is_true()
	assert_int(d.base_tick).is_equal(10)
	_same_state(d, SnapshotCodec.decode(SnapshotCodec.encode(s2)))
	assert_int(bytes.size()).is_less(SnapshotCodec.encode(s2).size() / 2)


func test_unchanged_world_costs_only_the_fixed_part() -> void:
	var enc := SnapshotEncoder.new(32, 0)
	var dec := SnapshotDecoder.new(64)
	var s1 := SnapshotFixtures.rich(10)
	dec.decode(enc.encode(s1, 0))
	var s2 := SnapshotFixtures.rich(11)  # same world, clock one tick on
	s2.fx[0].ticks_left = 89  # same expiry tick
	var bytes := enc.encode(s2, 10)
	# header 16 + own motor 44 + 4 same-blob tags + 3 empty keyed sections x 5
	# + match clock 4 + bolt count 2 + one bolt 12 + empty Wardling section 5.
	assert_int(bytes.size()).is_equal(16 + 44 + 4 + 15 + 4 + 2 + 12 + 5)
	_same_state(dec.decode(bytes), SnapshotCodec.decode(SnapshotCodec.encode(s2)))


func test_delta_against_an_older_ack_still_converges() -> void:
	var enc := SnapshotEncoder.new(32, 0)
	var dec := SnapshotDecoder.new(64)
	var s := SnapshotFixtures.rich(10)
	dec.decode(enc.encode(s, 0))
	for t in 5:
		s = SnapshotFixtures.advance(s, 20)
		enc.encode(s, 10)  # lost in transit: the client never sees ticks 11..15
	s = SnapshotFixtures.advance(s, 20)
	var d := dec.decode(enc.encode(s, 10))
	assert_object(d).is_not_null()
	_same_state(d, SnapshotCodec.decode(SnapshotCodec.encode(s)))


func test_removed_and_new_entities_are_applied() -> void:
	var enc := SnapshotEncoder.new(32, 0)
	var dec := SnapshotDecoder.new(64)
	var s1 := SnapshotFixtures.rich(10)
	dec.decode(enc.encode(s1, 0))
	var s2 := SnapshotFixtures.rich(11)
	s2.entities.remove_at(3)
	s2.wardlings.remove_at(0)
	s2.wardlings.append(SnapshotFixtures.wardling(900, Vector3(1, 0, -1)))
	s2.fx.clear()
	var d := dec.decode(enc.encode(s2, 10))
	assert_int(d.entities.size()).is_equal(9)
	assert_bool(d.entities.any(func(e: SnapshotData.EntityState) -> bool: return e.net_id == 4)).is_false()
	assert_int(d.wardlings.size()).is_equal(20)
	assert_int(d.wardlings[d.wardlings.size() - 1].net_id).is_equal(900)
	assert_int(d.fx.size()).is_equal(0)


func test_missing_or_too_old_baseline_falls_back_to_full() -> void:
	var enc := SnapshotEncoder.new(8, 0)
	var s := SnapshotFixtures.rich(10)
	enc.encode(s, 0)
	enc.encode(SnapshotFixtures.rich(11), 999)  # unknown ack
	assert_bool(enc.last.is_delta).is_false()
	enc.encode(SnapshotFixtures.rich(30), 10)  # 20 ticks old, ring 8
	assert_bool(enc.last.is_delta).is_false()
	assert_bool(10 in enc.held_ticks()).is_false()
	var fresh := SnapshotDecoder.new(64)
	assert_object(fresh.decode(enc.encode(SnapshotFixtures.rich(31), 30))).is_null()  # delta vs 30
	assert_int(fresh.last_error).is_equal(ERR_DOES_NOT_EXIST)
	var d := fresh.decode(enc.encode(SnapshotFixtures.rich(32), 0))  # full again
	assert_object(d).is_not_null()
	assert_int(fresh.last_error).is_equal(OK)


func test_budget_defers_wardlings_and_marks_them_stale() -> void:
	var enc := SnapshotEncoder.new(32, 1100)
	var dec := SnapshotDecoder.new(64)
	var s := SnapshotFixtures.rich(10, 1, 150)  # far too many for one packet
	var b := enc.encode(s, 0)
	assert_int(b.size()).is_less_equal(1100)
	assert_int(enc.last.deferred).is_greater(0)
	var d := dec.decode(b)
	assert_int(d.wardlings.size()).is_equal(enc.last.sent.size())  # deferred new ones are not known yet
	var ack := 10
	var guard := 0
	while enc.last.deferred > 0 and guard < 20:
		s = SnapshotFixtures.advance(s, 0)
		b = enc.encode(s, ack)
		assert_int(b.size()).is_less_equal(1100)
		d = dec.decode(b)
		ack = s.tick
		guard += 1
	assert_int(d.wardlings.size()).is_equal(150)
	# Now every Wardling moves: the budget defers some, which keep their old value as stale.
	var prev := d
	s = SnapshotFixtures.advance(s, 150)
	b = enc.encode(s, ack)
	d = dec.decode(b)
	assert_int(enc.last.deferred).is_greater(0)
	var stale := 0
	for i in d.wardlings.size():
		if d.wardlings[i].stale:
			stale += 1
			assert_vector(d.wardlings[i].position).is_equal(prev.wardlings[i].position)
		else:
			assert_vector(d.wardlings[i].position).is_not_equal(prev.wardlings[i].position)
	assert_int(stale).is_equal(enc.last.deferred)


func test_running_fx_and_clock_do_not_resend_their_blocks() -> void:
	var enc := SnapshotEncoder.new(32, 0)
	var s1 := SnapshotFixtures.rich(10)
	enc.encode(s1, 0)
	var s2 := SnapshotFixtures.rich(11)
	s2.fx[0].ticks_left = 89  # same expiry tick
	s2.bolts.clear()
	var dec_full := SnapshotCodec.encode(s2).size()
	var b := enc.encode(s2, 10)
	assert_int(b.size()).is_equal(16 + 44 + 4 + 15 + 4 + 2 + 5)
	assert_int(b.size()).is_less(dec_full / 10)


func test_malformed_snapshots_are_rejected() -> void:
	var s := SnapshotFixtures.rich(10)
	var good := SnapshotCodec.encode(s)
	assert_object(SnapshotCodec.decode(good)).is_not_null()
	var truncated := good.slice(0, good.size() - 1)
	assert_object(SnapshotCodec.decode(truncated)).is_null()
	var trailing := good.duplicate()
	trailing.append(0)
	assert_object(SnapshotCodec.decode(trailing)).is_null()
	var bad_flags := good.duplicate()
	bad_flags[15] = 0x80 | SnapshotCodec.FLAG_HAS_OWN
	assert_object(SnapshotCodec.decode(bad_flags)).is_null()
	var wrong_type := good.duplicate()
	wrong_type[0] = MsgType.EVENT
	assert_object(SnapshotCodec.decode(wrong_type)).is_null()
	assert_object(SnapshotCodec.decode(PackedByteArray())).is_null()
	# A "same as baseline" blob in a full snapshot (no baseline) is invalid.
	var same := good.duplicate()
	same[SnapshotCodec.HEADER_SIZE + SnapshotCodec.OWN_MOTOR_SIZE] = SnapshotCodec.BLOB_SAME
	assert_object(SnapshotCodec.decode(same)).is_null()


func test_hostile_bytes_never_crash_the_decoder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1600
	var good := SnapshotCodec.encode(SnapshotFixtures.rich(10))
	var dec := SnapshotDecoder.new(8)
	for i in 300:
		var b := good.duplicate()
		for k in 1 + i % 6:
			b[rng.randi_range(SnapshotCodec.HEADER_SIZE, b.size() - 1)] = rng.randi() & 0xFF
		if i % 3 == 0:
			b.resize(rng.randi_range(SnapshotCodec.HEADER_SIZE, b.size()))
		var d := dec.decode(b)
		if d == null:
			assert_int(dec.last_error).is_not_equal(OK)


func test_delta_rejects_partial_new_key_and_unknown_removal() -> void:
	var enc := SnapshotEncoder.new(32, 0)
	var dec := SnapshotDecoder.new(64)
	var s1 := SnapshotData.new()
	s1.tick = 10
	s1.entities.append(SnapshotFixtures.hero(1, Vector3.ZERO))
	dec.decode(enc.encode(s1, 0))
	var s2 := SnapshotData.new()
	s2.tick = 11
	s2.entities.append(SnapshotFixtures.hero(1, Vector3(1, 0, 0)))
	var b := enc.encode(s2, 10)
	assert_object(SnapshotDecoder.new(64).decode(b)).is_null()  # no baseline held
	# Heroes section starts after header + own-combat tag (no own hero).
	var off := SnapshotCodec.HEADER_SIZE + 1
	var unknown := b.duplicate()
	unknown.encode_u16(off, 1)  # one removal ...
	var forged := unknown.slice(0, off + 2)
	forged.append_array(PackedByteArray([0x39, 0x05]))  # ... of key 1337, unknown to the baseline
	forged.append_array(b.slice(off + 2))
	assert_object(dec.decode(forged)).is_null()
	assert_int(dec.last_error).is_equal(ERR_INVALID_DATA)
	# Update of hero 1 rewritten as a new key 2 with only the position group.
	var partial := b.duplicate()
	partial.encode_u16(off + 4, 2)
	assert_object(dec.decode(partial)).is_null()
	assert_object(dec.decode(b)).is_not_null()
