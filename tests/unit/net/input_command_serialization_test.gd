extends GdUnitTestSuite
## InputCommand wire format (architecture.md §8.2) and InputBatchCodec.


func _sample() -> InputCommand:
	var c := InputCommand.new()
	c.seq = 123456
	c.move = Vector2(0.6, -0.8)
	c.yaw = 4.2
	c.pitch = -0.7
	c.buttons = InputCommand.BTN_JUMP | InputCommand.BTN_SPRINT | InputCommand.BTN_SKILL4
	c.view_tick = 98765
	c.view_alpha = 0.5
	return c


func test_quantized_command_round_trip_is_exact() -> void:
	var c := _sample()
	c.quantize()
	var buf := PackedByteArray()
	buf.resize(InputCommand.WIRE_SIZE)
	assert_int(c.write_to(buf, 0)).is_equal(InputCommand.WIRE_SIZE)
	var back := InputCommand.new()
	assert_bool(InputCommand.read_from(buf, 0, back)).is_true()
	assert_bool(back.equals(c)).is_true()


func test_quantize_is_idempotent_and_close_to_source() -> void:
	var src := _sample()
	var q := _sample()
	q.quantize()
	var q2 := q.duplicate_command()
	q2.quantize()
	assert_bool(q2.equals(q)).is_true()
	assert_float(q.yaw).is_equal_approx(src.yaw, 0.001)
	assert_float(q.pitch).is_equal_approx(src.pitch, 0.001)
	assert_float(q.move.x).is_equal_approx(src.move.x, 0.01)


func test_read_rejects_short_buffer() -> void:
	var buf := PackedByteArray()
	buf.resize(InputCommand.WIRE_SIZE - 1)
	assert_bool(InputCommand.read_from(buf, 0, InputCommand.new())).is_false()


func test_read_clamps_oversized_move_to_unit_length() -> void:
	var buf := PackedByteArray()
	buf.resize(InputCommand.WIRE_SIZE)
	buf.encode_s8(4, 127)
	buf.encode_s8(5, 127)  # (1, 1): a speed-hack diagonal
	var c := InputCommand.new()
	InputCommand.read_from(buf, 0, c)
	assert_float(c.move.length()).is_equal_approx(1.0, 0.0001)


func test_input_batch_round_trip_keeps_order_and_ack() -> void:
	var cmds: Array[InputCommand] = []
	for i in 3:
		var c := _sample()
		c.seq = 10 + i
		c.quantize()
		cmds.append(c)
	var out: Array[InputCommand] = []
	var ack := InputBatchCodec.decode(InputBatchCodec.encode(77, cmds), 3, out)
	assert_int(ack).is_equal(77)
	assert_int(out.size()).is_equal(3)
	for i in 3:
		assert_bool(out[i].equals(cmds[i])).is_true()


func test_input_batch_with_too_many_commands_is_rejected() -> void:
	var cmds: Array[InputCommand] = [_sample(), _sample(), _sample(), _sample()]
	var out: Array[InputCommand] = []
	assert_int(InputBatchCodec.decode(InputBatchCodec.encode(1, cmds), 3, out)).is_equal(-1)


func test_input_batch_truncated_is_rejected() -> void:
	var cmds: Array[InputCommand] = [_sample()]
	var b := InputBatchCodec.encode(1, cmds)
	b.resize(b.size() - 1)
	var out: Array[InputCommand] = []
	assert_int(InputBatchCodec.decode(b, 3, out)).is_equal(-1)


func test_snapshot_round_trip_preserves_own_state_and_entities() -> void:
	var s := SnapshotData.new()
	s.tick = 500
	s.last_processed_seq = 480
	s.own_net_id = 3
	s.own_state = MotorState.new()
	s.own_state.position = Vector3(1.25, 0.5, -7.75)
	s.own_state.velocity = Vector3(3.0, -1.5, 0.25)
	s.own_state.grounded = true
	s.own_state.jump_held = true
	s.own_state.coyote_ticks = 2
	var e := SnapshotData.EntityState.new()
	e.net_id = 4
	e.kind = EntityRegistry.KIND_HERO
	e.position = Vector3(-2.0, 0.0, 9.5)
	e.yaw = 1.5
	e.crouching = true
	s.entities.append(e)
	var d := SnapshotCodec.decode(SnapshotCodec.encode(s))
	assert_int(d.tick).is_equal(500)
	assert_int(d.last_processed_seq).is_equal(480)
	assert_bool(d.own_state.equals(s.own_state)).is_true()
	assert_int(d.entities.size()).is_equal(1)
	assert_vector(d.entities[0].position).is_equal(e.position)
	assert_bool(d.entities[0].crouching).is_true()


func test_quantize_is_idempotent_for_diagonal_and_near_unit_moves() -> void:
	# E11: bots emit arbitrary unit vectors; rounding must not leave a length > 1
	# that read_from renormalises off the wire grid.
	for i in 720:
		var a := deg_to_rad(i * 0.5)
		var c := InputCommand.new()
		c.move = Vector2(cos(a), sin(a))
		c.yaw = a * 3.0
		c.pitch = sin(a) * 1.4
		c.quantize()
		var once := c.duplicate_command()
		c.quantize()
		assert_bool(c.equals(once)).is_true()
		assert_float(c.move.length()).is_less_equal(1.0)
