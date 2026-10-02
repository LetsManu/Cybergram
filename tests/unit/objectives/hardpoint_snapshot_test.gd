extends GdUnitTestSuite
## E7 replication: the snapshot objectives block round-trips owner, progress,
## capturing team, flags and lane fronts.


func test_hardpoint_block_round_trips() -> void:
	var s := SnapshotData.new()
	s.tick = 99
	for i in 5:
		var h := SnapshotData.HardpointState.new()
		h.owner = [0, 0, -1, 1, 1][i]
		h.capturing_team = 0 if i == 2 else -1
		h.progress = 0.4567 if i == 2 else 0.0
		h.contested = i == 2
		h.overtime = i == 1
		h.severed = i == 3
		h.locked = [i == 4, i == 0]
		s.hardpoints.append(h)
	s.fronts = PackedInt32Array([2, -1])
	var d := SnapshotCodec.decode(SnapshotCodec.encode(s))
	assert_object(d).is_not_null()
	assert_int(d.hardpoints.size()).is_equal(5)
	for i in 5:
		var a := s.hardpoints[i]
		var b := d.hardpoints[i]
		assert_int(b.owner).is_equal(a.owner)
		assert_int(b.capturing_team).is_equal(a.capturing_team)
		assert_float(b.progress).is_equal_approx(a.progress, 1.0 / 65535.0)
		assert_bool(b.contested).is_equal(a.contested)
		assert_bool(b.overtime).is_equal(a.overtime)
		assert_bool(b.severed).is_equal(a.severed)
		assert_array(b.locked).is_equal(a.locked)
	assert_array(Array(d.fronts)).is_equal([2, -1])


func test_snapshot_without_objectives_and_truncated_block() -> void:
	var s := SnapshotData.new()
	var b := SnapshotCodec.encode(s)
	var d := SnapshotCodec.decode(b)
	assert_object(d).is_not_null()
	assert_int(d.hardpoints.size()).is_equal(0)
	assert_object(SnapshotCodec.decode(b.slice(0, b.size() - 1))).is_null()
