extends GdUnitTestSuite
## W11-V1 protocol v14: per-hero Fork/Mastery state in the snapshot entity and the
## SKILL_CAST game event round-trip through their codecs.


func _entity(id: int, bits: int) -> SnapshotData.EntityState:
	var e := SnapshotData.EntityState.new()
	e.net_id = id
	e.kind = EntityRegistry.KIND_HERO
	e.hero_index = 3
	e.status = 0x0102
	e.fork_bits = bits
	return e


func test_all_fork_states_round_trip_in_one_byte() -> void:
	for a in 6:
		for b in 6:
			for c in 6:
				var bits := 0
				bits = SnapshotData.EntityState.with_slot(bits, 0, a >> 1, (a & 1) == 1)
				bits = SnapshotData.EntityState.with_slot(bits, 1, b >> 1, (b & 1) == 1)
				bits = SnapshotData.EntityState.with_slot(bits, 2, c >> 1, (c & 1) == 1)
				var packed := SnapshotCodec.pack_fork(bits)
				assert_int(packed).is_less(216)
				assert_int(SnapshotCodec.unpack_fork(packed)).is_equal(bits)


func test_entity_fork_state_survives_snapshot_and_keeps_neighbours() -> void:
	var s := SnapshotData.new()
	var bits := SnapshotData.EntityState.with_slot(0, 0, 1, true)
	bits = SnapshotData.EntityState.with_slot(bits, 2, 2, false)
	s.entities.append(_entity(5, bits))
	s.entities.append(_entity(6, 0))
	var d := SnapshotCodec.decode(SnapshotCodec.encode(s))
	assert_object(d).is_not_null()
	assert_int(d.entities.size()).is_equal(2)
	var e: SnapshotData.EntityState = d.entities[0]
	assert_int(e.fork_of(0)).is_equal(1)
	assert_bool(e.mastery_of(0)).is_true()
	assert_int(e.fork_of(1)).is_equal(0)
	assert_int(e.fork_of(2)).is_equal(2)
	assert_bool(e.mastery_of(2)).is_false()
	assert_int(e.hero_index).is_equal(3)
	assert_int(e.status).is_equal(0x0102)
	assert_int(d.entities[1].fork_bits).is_equal(0)


## v16 (W16-NET): a new hero is u16 key + u8 group mask + the quantised record
## (v22: 39 B, the 11-byte public build included; items-and-armory.md §3.8).
func test_new_entity_costs_42_bytes() -> void:
	var a := SnapshotData.new()
	var b := SnapshotData.new()
	b.entities.append(_entity(1, 0))
	assert_int(SnapshotCodec.encode(b).size() - SnapshotCodec.encode(a).size()).is_equal(42)


func test_skill_cast_event_round_trip() -> void:
	var evs: Array[GameEvent] = [GameEvent.skill_cast(42, 2, 2, true, Vector3(1.5, 2.0, -3.0)),
		GameEvent.skill_cast(7, 3, 0, false, Vector3.ZERO)]
	var out: Array[GameEvent] = []
	var tick := EventCodec.decode(EventCodec.encode(77, evs), out)
	assert_int(tick).is_equal(77)
	assert_int(out.size()).is_equal(2)
	assert_int(out[0].kind).is_equal(GameEvent.SKILL_CAST)
	assert_int(out[0].source_net_id).is_equal(42)
	assert_int(out[0].cast_slot()).is_equal(2)
	assert_int(out[0].cast_fork()).is_equal(2)
	assert_bool(out[0].cast_mastery()).is_true()
	assert_vector(out[0].position).is_equal(Vector3(1.5, 2.0, -3.0))
	assert_int(out[1].cast_slot()).is_equal(3)
	assert_int(out[1].cast_fork()).is_equal(0)
	assert_bool(out[1].cast_mastery()).is_false()
