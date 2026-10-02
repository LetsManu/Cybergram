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
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var z := _pressed("squad_smart", KEY_Z)
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
	var x := _pressed("squad_follow", KEY_X)
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
	out.squad_cmd = _squad_request
	out.squad_target = 0
	out.squad_point = Vector3.ZERO
	_squad_request = InputCommand.SQUAD_NONE
	out.quantize()


## Input-map action if defined, else the physical key (no project.godot edit needed).
func _pressed(action: StringName, fallback: Key) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_physical_key_pressed(fallback)
