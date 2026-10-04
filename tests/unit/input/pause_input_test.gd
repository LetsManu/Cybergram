extends GdUnitTestSuite
## The pause menu sets PlayerInputSource.paused: the hero must then get a
## neutral command (no move, no buttons, no actions) that keeps the view.


func test_paused_input_sends_a_neutral_command_with_the_same_view() -> void:
	var src: PlayerInputSource = auto_free(PlayerInputSource.new())
	src.setup(LookSettings.new(), MovementDef.new())
	src.live_yaw = 1.25
	src.live_pitch = -0.3
	src.request_action(InputCommand.ACTION_NONE + 1, 2)
	src.paused = true
	var cmd := InputCommand.new()
	src.sample(7, cmd)
	assert_int(cmd.seq).is_equal(7)
	assert_vector(cmd.move).is_equal(Vector2.ZERO)
	assert_int(cmd.buttons).is_equal(0)
	assert_int(cmd.action).is_equal(InputCommand.ACTION_NONE)
	assert_float(cmd.yaw).is_equal_approx(1.25, 0.01)
	assert_float(cmd.pitch).is_equal_approx(-0.3, 0.01)
