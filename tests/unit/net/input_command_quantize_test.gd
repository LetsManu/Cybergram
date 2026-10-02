extends GdUnitTestSuite
## E14 (bot cost): InputCommand.quantize() is computed arithmetically instead of
## through a byte buffer. It must stay bit-identical to the wire round trip
## (write_to + read_from) and idempotent, for in-range and out-of-range fields.


func _wire(c: InputCommand) -> InputCommand:
	var buf := PackedByteArray()
	buf.resize(InputCommand.WIRE_SIZE)
	c.write_to(buf, 0)
	var out := InputCommand.new()
	InputCommand.read_from(buf, 0, out)
	return out


func _random(rng: RandomNumberGenerator) -> InputCommand:
	var c := InputCommand.new()
	c.seq = rng.randi_range(-5, 1 << 31)
	c.move = Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
	if rng.randf() < 0.3:
		c.move = c.move.normalized()  # unit vectors exercise the length fix-up
	c.yaw = rng.randf_range(-20.0, 20.0)
	c.pitch = rng.randf_range(-2.0, 2.0)
	c.buttons = rng.randi_range(0, 0xFFFF)
	c.view_tick = rng.randi_range(0, 1 << 31)
	c.view_alpha = rng.randf_range(-0.2, 1.2)
	c.squad_cmd = rng.randi_range(-1, 9)
	c.squad_target = rng.randi_range(0, 70000)
	c.squad_point = Vector3(rng.randf_range(-5000.0, 5000.0), rng.randf_range(-50.0, 50.0), rng.randf_range(-500.0, 500.0))
	c.action = rng.randi_range(-1, 8)
	c.action_arg = rng.randi_range(0, 70000)
	return c


func test_quantize_equals_the_wire_round_trip_and_is_idempotent() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1414
	var bad := 0
	for i in 5000:
		var c := _random(rng)
		var smart := c.squad_cmd == InputCommand.SQUAD_SMART
		var expect := _wire(c)
		if smart:
			expect.squad_cmd = InputCommand.SQUAD_SMART
		var q := c.duplicate_command()
		q.quantize()
		var again := q.duplicate_command()
		again.quantize()
		if not q.equals(expect) or not again.equals(q):
			bad += 1
	assert_int(bad).is_equal(0)
