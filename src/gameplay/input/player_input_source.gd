class_name PlayerInputSource
extends Node
## Keyboard + mouse input for the local player (architecture.md §8.4).
## Mouse look is applied every rendered frame (live_yaw/live_pitch, read by the
## camera); sample() snapshots it into an InputCommand once per tick.
## Mouse capture: left click captures, ui_cancel (Esc) releases. Capture is never
## forced at boot, so headless/Xvfb runs are unaffected.
##
## Deviation: architecture.md §3 places input sources in src/ai/input, but
## ClientWorld (gameplay) needs this and gameplay may not reference src/ai.

var look: LookSettings
var max_pitch_rad: float = deg_to_rad(89.0)
var live_yaw: float = 0.0
var live_pitch: float = 0.0

## E8 squad orders (wardlings-and-economy.md §8, hud.md §7): Z tap = Smart
## Command, hold Z >= 0.2 s = radial wheel (flick + release), X = Follow.
const WHEEL_HOLD_S: float = 0.2
const WHEEL_DEADZONE_PX: float = 30.0
## Radial slices: Follow top, Hold right, Attack bottom, Capture left.
const WHEEL_SLICES: Array[int] = [InputCommand.SQUAD_FOLLOW, InputCommand.SQUAD_HOLD,
	InputCommand.SQUAD_ATTACK, InputCommand.SQUAD_CAPTURE]
var wheel_open: bool = false
## Accumulated mouse flick while the wheel is open (screen px, +y down).
var wheel_vec: Vector2 = Vector2.ZERO
## Set when the wheel opens: ClientWorld captures the crosshair targets then.
var wheel_capture: bool = false
var _squad_request: int = InputCommand.SQUAD_NONE
## E13/E15 actions (hud.md §11 quick spend: hold Alt + Q/E/C/G; Med-Pack [4];
## Armory panel and death screen push requests): [action, arg], one per tick.
var _actions: Array = []
var _learn_was_down: Array[bool] = [false, false, false, false]
var _medpack_was_down: bool = false
## True while Alt is held (the HUD shows the quick-spend flyout).
var quick_spend: bool = false
## UI panels (Armory) take the keyboard: skills and squad keys are ignored.
var ui_captured: bool = false
## Set by the pause menu: the hero gets neutral commands (no move, no buttons).
var paused: bool = false
## True when a pause menu handles Esc (it releases the mouse itself).
var has_pause_menu: bool = false
var _z_held_s: float = -1.0
var _x_was_down: bool = false


func setup(look_settings: LookSettings, movement: MovementDef) -> void:
	look = look_settings
	max_pitch_rad = deg_to_rad(movement.max_pitch_deg)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and wheel_open:
		wheel_vec += event.relative  # the wheel takes the flick; aim holds still
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := deg_to_rad(look.mouse_sensitivity_deg)
		var dy: float = -event.relative.y if not look.invert_y else event.relative.y
		live_yaw = fposmod(live_yaw - event.relative.x * sens, TAU)
		live_pitch = clampf(live_pitch + dy * sens, -max_pitch_rad, max_pitch_rad)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel") and not has_pause_menu:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Queues an InputCommand.ACTION_* (sent on the next ticks, one per tick).
func request_action(action: int, arg: int = 0) -> void:
	_actions.append([action, arg])


func _process(delta: float) -> void:
	quick_spend = _pressed("quick_spend", KEY_ALT)
	var keys := [KEY_Q, KEY_E, KEY_C, KEY_G]
	for i in 4:
		var down := quick_spend and not ui_captured and _pressed(StringName("skill_%d" % (i + 1)), keys[i])
		if down and not _learn_was_down[i]:
			request_action(InputCommand.ACTION_LEARN, i)
		_learn_was_down[i] = down
	var med := not ui_captured and _pressed("use_medpack", KEY_4)
	if med and not _medpack_was_down:
		request_action(InputCommand.ACTION_USE_MEDPACK)
	_medpack_was_down = med
	var z := _pressed("squad_smart", KEY_Z) and not ui_captured
	if z:
		_z_held_s = 0.0 if _z_held_s < 0.0 else _z_held_s + delta
		if _z_held_s >= WHEEL_HOLD_S and not wheel_open:
			wheel_open = true
			wheel_vec = Vector2.ZERO
			wheel_capture = true
	elif _z_held_s >= 0.0:
		if wheel_open:
			_squad_request = wheel_selection()
			wheel_open = false
		else:
			_squad_request = InputCommand.SQUAD_SMART
		_z_held_s = -1.0
	var x := _pressed("squad_follow", KEY_X) and not ui_captured
	if x and not _x_was_down:
		_squad_request = InputCommand.SQUAD_FOLLOW
	_x_was_down = x


## Radial slice under the flick (SQUAD_NONE inside the dead zone = cancel).
func wheel_selection() -> int:
	if wheel_vec.length() < WHEEL_DEADZONE_PX:
		return InputCommand.SQUAD_NONE
	var a := fposmod(atan2(wheel_vec.x, -wheel_vec.y) + PI / 4.0, TAU)  # 0 = up, clockwise
	return WHEEL_SLICES[int(a / (PI / 2.0)) % 4]


## Fills `out` for tick `seq` (quantized, ready for prediction and sending).
func sample(seq: int, out: InputCommand) -> void:
	out.seq = seq
	if paused:
		_sample_neutral(out)
		return
	out.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	out.yaw = live_yaw
	out.pitch = live_pitch
	out.buttons = 0
	if Input.is_action_pressed("jump"):
		out.buttons |= InputCommand.BTN_JUMP
	if Input.is_action_pressed("crouch"):
		out.buttons |= InputCommand.BTN_CROUCH
	if Input.is_action_pressed("sprint"):
		out.buttons |= InputCommand.BTN_SPRINT
	# Fire only while the mouse is captured (the capturing click never shoots).
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		out.buttons |= InputCommand.BTN_FIRE
	if _pressed("reload", KEY_R):
		out.buttons |= InputCommand.BTN_RELOAD
	# E14 (hud.md §13 binds: Interact F, hold): Cell pickup, plant, defuse.
	if not ui_captured and _pressed("interact", KEY_F):
		out.buttons |= InputCommand.BTN_INTERACT
	# E10 skills (hud.md §4.4 / §13 binds: S1 Q, S2 E, S3 C, Ult G). Alt held =
	# quick spend (E15): the keys learn instead of cast.
	var cast := not quick_spend and not ui_captured
	if cast and _pressed("skill_1", KEY_Q):
		out.buttons |= InputCommand.BTN_SKILL1
	if cast and _pressed("skill_2", KEY_E):
		out.buttons |= InputCommand.BTN_SKILL2
	if cast and _pressed("skill_3", KEY_C):
		out.buttons |= InputCommand.BTN_SKILL3
	if cast and _pressed("skill_4", KEY_G):
		out.buttons |= InputCommand.BTN_SKILL4
	out.squad_cmd = _squad_request
	out.squad_target = 0
	out.squad_point = Vector3.ZERO
	_squad_request = InputCommand.SQUAD_NONE
	out.action = InputCommand.ACTION_NONE
	out.action_arg = 0
	if not _actions.is_empty():
		var a: Array = _actions.pop_front()
		out.action = a[0]
		out.action_arg = a[1]
	out.quantize()


## Paused: keep the view where it was, no movement, no buttons, no actions.
func _sample_neutral(out: InputCommand) -> void:
	out.move = Vector2.ZERO
	out.yaw = live_yaw
	out.pitch = live_pitch
	out.buttons = 0
	out.squad_cmd = InputCommand.SQUAD_NONE
	out.squad_target = 0
	out.squad_point = Vector3.ZERO
	out.action = InputCommand.ACTION_NONE
	out.action_arg = 0
	out.quantize()


## Input-map action if defined, else the physical key (no project.godot edit needed).
func _pressed(action: StringName, fallback: Key) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_physical_key_pressed(fallback)
