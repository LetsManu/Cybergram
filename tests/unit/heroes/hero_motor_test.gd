extends GdUnitTestSuite
## HeroMotor (design/gdd/heroes.md §2): determinism and movement rules.

const DT: float = 1.0 / 30.0
const TICKS: int = 150


func _world() -> Node3D:
	var vp := SubViewport.new()  # isolated world per run: runs cannot see each other
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	var root: Node3D = NetFixtures.course_scene().instantiate()
	vp.add_child(root)
	return root


func _hero(root: Node3D, def: MovementDef) -> HeroBody:
	var h := HeroBody.new()
	h.setup(def, Vector3(0.0, 0.05, 0.0), true)
	root.add_child(h)
	h.place()
	return h


func _run(def: MovementDef, src: ScriptedInputSource) -> Array[MotorState]:
	var h := _hero(_world(), def)
	var cmd := InputCommand.new()
	var out: Array[MotorState] = []
	for t in TICKS:
		src.sample(t, cmd)
		h.step(cmd, DT)
		out.append(h.state.duplicate_state())
	return out


func _flat_speed(buttons: int) -> float:
	var def := MovementDef.new()
	var h := _hero(_world(), def)
	var cmd := InputCommand.new()
	cmd.move = Vector2(0.0, 1.0)
	cmd.yaw = PI / 2.0  # face -X, away from the ramp and block
	cmd.buttons = buttons
	for t in 30:
		h.step(cmd, DT)
	return Vector2(h.state.velocity.x, h.state.velocity.z).length()


func test_same_inputs_give_identical_state_sequence() -> void:
	await get_tree().physics_frame
	var def := MovementDef.new()
	var a := _run(def, ScriptedInputSource.new(NetFixtures.walk_pattern()))
	var b := _run(def, ScriptedInputSource.new(NetFixtures.walk_pattern()))
	for t in TICKS:
		assert_bool(a[t].equals(b[t])).override_failure_message("diverged at tick %d" % t).is_true()
	assert_float(a[TICKS - 1].position.length()).is_greater(1.0)


func test_walk_reaches_base_speed() -> void:
	assert_float(_flat_speed(0)).is_equal_approx(MovementDef.new().base_move_speed, 0.01)


func test_sprint_multiplies_speed() -> void:
	var d := MovementDef.new()
	assert_float(_flat_speed(InputCommand.BTN_SPRINT)).is_equal_approx(d.base_move_speed * d.sprint_multiplier, 0.01)


func test_crouch_halves_speed_and_overrides_sprint() -> void:
	var d := MovementDef.new()
	var v := _flat_speed(InputCommand.BTN_CROUCH | InputCommand.BTN_SPRINT)
	assert_float(v).is_equal_approx(d.base_move_speed * d.crouch_multiplier, 0.01)


func test_jump_triggers_on_press_edge_only() -> void:
	var def := MovementDef.new()
	var h := _hero(_world(), def)
	var cmd := InputCommand.new()
	for t in 5:
		h.step(cmd, DT)  # settle on the floor
	assert_bool(h.state.grounded).is_true()
	cmd.buttons = InputCommand.BTN_JUMP
	h.step(cmd, DT)
	assert_float(h.state.velocity.y).is_greater(0.0)
	var max_y := 0.0
	for t in 60:  # keep holding jump: one jump, then stays down
		h.step(cmd, DT)
		max_y = maxf(max_y, h.state.position.y)
	# Per-tick (explicit Euler) integration: apex = v^2/2g + v*dt/2.
	var apex := def.jump_velocity * def.jump_velocity / (2.0 * def.gravity) + def.jump_velocity * DT / 2.0
	assert_float(max_y).is_equal_approx(apex, apex * 0.05)
	assert_bool(h.state.grounded).is_true()
	assert_float(h.state.position.y).is_less(0.05)


func test_crouch_is_kept_under_low_ceiling() -> void:
	var def := MovementDef.new()
	var h := _hero(_world(), def)
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.2, 4.0)
	shape.shape = box
	roof.add_child(shape)
	roof.position = Vector3(0.0, (def.crouch_height + def.stand_height) / 2.0 + 0.1, 0.0)
	h.get_parent().add_child(roof)
	var cmd := InputCommand.new()
	cmd.buttons = InputCommand.BTN_CROUCH
	h.step(cmd, DT)
	assert_bool(h.state.crouching).is_true()
	cmd.buttons = 0
	h.step(cmd, DT)
	assert_bool(h.state.crouching).override_failure_message("stood up into the roof").is_true()
