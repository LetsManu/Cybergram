extends GdUnitTestSuite
## E8 wire additions: squad order fields in InputCommand, the compact Wardling
## and bolt blocks in snapshots.


func test_squad_order_fields_round_trip() -> void:
	var c := InputCommand.new()
	c.seq = 9
	c.squad_cmd = InputCommand.SQUAD_HOLD
	c.squad_target = 4321
	c.squad_point = Vector3(-12.3, 0.5, -87.6)
	c.quantize()
	var buf := PackedByteArray()
	buf.resize(InputCommand.WIRE_SIZE)
	c.write_to(buf, 0)
	var back := InputCommand.new()
	assert_bool(InputCommand.read_from(buf, 0, back)).is_true()
	assert_bool(back.equals(c)).is_true()
	assert_vector(back.squad_point).is_equal_approx(Vector3(-12.3, 0.5, -87.6), Vector3.ONE * 0.07)


func test_smart_command_is_client_local_and_never_on_the_wire() -> void:
	var c := InputCommand.new()
	c.squad_cmd = InputCommand.SQUAD_SMART
	c.quantize()
	assert_int(c.squad_cmd).is_equal(InputCommand.SQUAD_SMART)
	var buf := PackedByteArray()
	buf.resize(InputCommand.WIRE_SIZE)
	c.write_to(buf, 0)
	buf.encode_u8(17, 200)  # garbage from a hostile client
	var back := InputCommand.new()
	InputCommand.read_from(buf, 0, back)
	assert_int(back.squad_cmd).is_equal(InputCommand.SQUAD_NONE)


func test_wardling_and_bolt_blocks_round_trip() -> void:
	var s := SnapshotData.new()
	s.tick = 5
	var w := SnapshotData.WardlingState.new()
	w.net_id = 300
	w.position = Vector3(-3.25, 0.5, -412.75)
	w.yaw = 1.0
	w.hp_frac = 0.5
	w.team = 1
	w.vanguard = true
	w.owner_net_id = 0
	w.state = 5 | (1 << 3)
	s.wardlings.append(w)
	var o := SnapshotData.WardlingState.new()
	o.net_id = 301
	o.owner_net_id = 7
	o.state = Squad.CMD_ATTACK
	s.wardlings.append(o)
	s.bolts.append([Vector3(1, 1, -2), Vector3(4, 1.5, -20)])
	var bytes := SnapshotCodec.encode(s)
	var d := SnapshotCodec.decode(bytes)
	assert_object(d).is_not_null()
	assert_int(d.wardlings.size()).is_equal(2)
	var a := d.wardlings[0]
	assert_int(a.net_id).is_equal(300)
	assert_vector(a.position).is_equal_approx(w.position, Vector3.ONE * 0.02)
	assert_float(a.yaw).is_equal_approx(1.0, 0.03)
	assert_float(a.hp_frac).is_equal_approx(0.5, 0.005)
	assert_int(a.team).is_equal(1)
	assert_bool(a.vanguard).is_true()
	assert_int(a.state).is_equal(w.state)
	assert_int(d.wardlings[1].owner_net_id).is_equal(7)
	assert_bool(d.wardlings[1].vanguard).is_false()
	assert_int(d.bolts.size()).is_equal(1)
	assert_vector(d.bolts[0][1]).is_equal_approx(Vector3(4, 1.5, -20), Vector3.ONE * 0.02)
	# Compact: 15 B per Wardling (v8: + u8 tier), 12 B per bolt.
	var empty := SnapshotCodec.encode(SnapshotData.new())
	assert_int(bytes.size() - empty.size()).is_equal(2 * 15 + 12)
	bytes.resize(bytes.size() - 1)
	assert_object(SnapshotCodec.decode(bytes)).is_null()
