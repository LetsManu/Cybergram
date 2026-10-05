class_name PlayerInputSource
extends Node
## Keyboard + mouse + gamepad input for the local player (architecture.md §8.4).
## Mouse look and the right stick (W11-C1: dead zone + response curve + optional
## aim assist, all from LookSettings / GameSettings) are applied every rendered
## frame (live_yaw/live_pitch, read by the camera); sample() snapshots them into
## an InputCommand once per tick. Gamepad buttons / axes come from the InputMap
## (InputBindings pad specs), so they rebind like keys.
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
## Gamepad (W11-C1). True while the last input device used was the pad (fire
## then works without mouse capture). aim_targets_fn() -> Array[Vector3]: enemy
## hitbox centres relative to the eye (ClientWorld sets it; empty = no assist).
## W11-C1 view punch (client-side only; see RecoilKick).
var recoil := RecoilKick.new()
## W16-COMFORT camera recoil (GameSettings.comfort_camera_recoil, set by ClientWorld).
## FAIR for everyone: the aim sent in the InputCommand ALWAYS includes the full
## kick (aim_yaw / aim_pitch). The slider only scales how much of the kick the
## CAMERA shows (view_yaw / view_pitch); the remainder (hidden_kick) is shown by
## moving the crosshair to where the shot will land (CenterFeedback). The server
## spread is separate and untouched.
var camera_recoil_scale: float = 1.0
## Debug (evidence, `--debug-recoil-demo`): hold fire without mouse capture.
var debug_fire: bool = false
## Weapon whose recovery values apply while no shot is kicking (ClientWorld sets it).
var recoil_def: WeaponDef
var pad_active: bool = false
var aim_targets_fn: Callable
## Last aim-assist multiplier applied to the stick turn (diagnostics / tests).
var last_aim_scale: float = 1.0
const WHEEL_STICK_PX: float = 100.0
const PAD_ACTIVITY_AXIS: float = 0.4
var _z_held_s: float = -1.0
var _x_was_down: bool = false
var _wheel_by_key: bool = false


func setup(look_settings: LookSettings, movement: MovementDef) -> void:
	look = look_settings
	GameSettings.shared()  # first use applies the saved key bindings to the InputMap
	max_pitch_rad = deg_to_rad(movement.max_pitch_deg)
	debug_fire = OS.get_cmdline_user_args().has("--debug-recoil-demo")


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		pad_active = true
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) >= PAD_ACTIVITY_AXIS:
			pad_active = true  # below this is stick drift, not intent
	elif event is InputEventMouseButton or event is InputEventKey \
			or (event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		pad_active = false


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


## W10-T1: returns the basic-skill slot with a Fork choice on offer (-1 = none);
## ClientWorld sets it to its own fork_pending_slot().
var fork_slot_fn: Callable
var _fork_a_was_down: bool = false
var _fork_b_was_down: bool = false


## Queues an InputCommand.ACTION_* (sent on the next ticks, one per tick).
func request_action(action: int, arg: int = 0) -> void:
	_actions.append([action, arg])


## Aim sent to the server: player look + the FULL recoil kick (same for everyone,
## independent of the comfort slider).
func aim_yaw() -> float:
	return fposmod(live_yaw + recoil.kick.x, TAU)


func aim_pitch() -> float:
	return clampf(live_pitch + recoil.kick.y, -max_pitch_rad, max_pitch_rad)


## Camera yaw / pitch: player look + the kick scaled by the comfort option.
func view_yaw() -> float:
	return fposmod(live_yaw + recoil.kick.x * camera_recoil_scale, TAU)


func view_pitch() -> float:
	return clampf(live_pitch + recoil.kick.y * camera_recoil_scale, -max_pitch_rad, max_pitch_rad)


## The kick the camera does not show (full - scaled): the crosshair (and the
## viewmodel) show it, so the crosshair marks where the shot lands.
func hidden_kick() -> Vector2:
	return ComfortMath.hidden_kick(recoil.kick, camera_recoil_scale)


func _process(delta: float) -> void:
	recoil.recover(delta, recoil_def)
	_apply_stick_look(delta)
	quick_spend = _pressed("quick_spend", KEY_ALT)
	var keys := [KEY_Q, KEY_E, KEY_C, KEY_G]
	for i in 4:
		var down := quick_spend and not ui_captured and _pressed(StringName("skill_%d" % (i + 1)), keys[i])
		if down and not _learn_was_down[i]:
			request_action(InputCommand.ACTION_LEARN, i)
		_learn_was_down[i] = down
	# W10-T1: Fork choice (keys 1 / 2 or L1 / R1) for the slot the HUD offers it on.
	var fa := not ui_captured and (_pressed("fork_a", KEY_1) or _pad_down("fork_a") or _pad_down("skill_1"))
	var fb := not ui_captured and (_pressed("fork_b", KEY_2) or _pad_down("fork_b") or _pad_down("skill_2"))
	if fork_slot_fn.is_valid():
		var fs: int = fork_slot_fn.call()
		if fs >= 0 and fa and not _fork_a_was_down:
			request_action(InputCommand.ACTION_LEARN, ProgressionSystem.learn_arg(fs, 1))
		if fs >= 0 and fb and not _fork_b_was_down:
			request_action(InputCommand.ACTION_LEARN, ProgressionSystem.learn_arg(fs, 2))
	_fork_a_was_down = fa
	_fork_b_was_down = fb
	var med := not ui_captured and _pressed("use_medpack", KEY_4)
	if med and not _medpack_was_down:
		request_action(InputCommand.ACTION_USE_MEDPACK)
	_medpack_was_down = med
	var z := _pressed("squad_smart", KEY_Z) and not ui_captured
	var wheel_key := _pressed("squad_wheel", KEY_V) and not ui_captured
	if wheel_key:
		# Dedicated wheel key: opens at once, flick + release picks the slice.
		if not wheel_open:
			wheel_open = true
			wheel_vec = Vector2.ZERO
			wheel_capture = true
		_wheel_by_key = true
	elif _wheel_by_key:
		_wheel_by_key = false
		if wheel_open:
			_squad_request = wheel_selection()
			wheel_open = false
	elif z:
		_z_held_s = 0.0 if _z_held_s < 0.0 else _z_held_s + delta
		if _z_held_s >= WHEEL_HOLD_S and not wheel_open:
			wheel_open = true
			wheel_vec = Vector2.ZERO
			wheel_capture = true
	if not wheel_key and not _wheel_by_key and not z and _z_held_s >= 0.0:
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


## Raw right stick (device 0).
func _right_stick() -> Vector2:
	return Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))


## Right-stick look for this frame (and the radial wheel pick while it is open).
func _apply_stick_look(delta: float) -> void:
	if paused or look == null:
		return
	var raw := _right_stick()
	if wheel_open:
		if raw.length() > PAD_ACTIVITY_AXIS:
			wheel_vec = raw.normalized() * WHEEL_STICK_PX
		return
	var targets: Array = aim_targets_fn.call() if aim_targets_fn.is_valid() else []
	var step := stick_look_step(raw, delta, targets)
	if step != Vector2.ZERO:
		live_yaw = fposmod(live_yaw + step.x, TAU)
		live_pitch = clampf(live_pitch + step.y, -max_pitch_rad, max_pitch_rad)


## (yaw, pitch) change in radians for a raw stick vector over `delta`: dead zone
## + response curve + (gamepad only) aim-assist slowdown near `targets` (hitbox
## centres relative to the eye). The mouse path never calls this.
func stick_look_step(raw: Vector2, delta: float, targets: Array = []) -> Vector2:
	var shaped := StickMath.shape(raw, look.pad_deadzone, look.pad_curve)
	last_aim_scale = 1.0
	if shaped == Vector2.ZERO:
		return Vector2.ZERO
	if look.aim_assist and not targets.is_empty():
		var fwd := Basis.from_euler(Vector3(live_pitch, live_yaw, 0.0)) * Vector3.FORWARD
		last_aim_scale = AimAssist.scale_for_targets(fwd, targets, look.aim_assist_radius_deg,
			look.aim_assist_min_scale, look.aim_assist_hit_radius_m, look.aim_assist_max_range_m)
	var rate := deg_to_rad(look.pad_sensitivity_deg_s) * delta * last_aim_scale
	var dy := -shaped.y if not look.pad_invert_y else shaped.y
	return Vector2(-shaped.x * rate, dy * rate)


## Fire / alt-fire need the mouse captured, except while the pad is in use.
func _can_shoot() -> bool:
	return debug_fire or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or pad_active


## True while the gamepad spec bound to `action` is held (device 0). Used for
## context buttons the InputMap action must not own (Fork picks on skill buttons).
func _pad_down(action: String) -> bool:
	var spec := GameSettings.shared().bindings.get_pad_spec(action)
	var parts := spec.split(":")
	if parts.size() == 2 and parts[0] == "j" and parts[1].is_valid_int():
		return Input.is_joy_button_pressed(0, parts[1].to_int() as JoyButton)
	if parts.size() == 3 and parts[0] == "a" and parts[1].is_valid_int() and parts[2].is_valid_int():
		return Input.get_joy_axis(0, parts[1].to_int() as JoyAxis) * parts[2].to_int() > 0.5
	return false


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
	out.move = _move_vector()
	out.yaw = aim_yaw()
	out.pitch = aim_pitch()
	out.buttons = 0
	if _pressed("jump", KEY_SPACE):
		out.buttons |= InputCommand.BTN_JUMP
	if _pressed("crouch", KEY_CTRL):
		out.buttons |= InputCommand.BTN_CROUCH
	if _pressed("sprint", KEY_SHIFT):
		out.buttons |= InputCommand.BTN_SPRINT
	# Fire only while the mouse is captured (the capturing click never shoots).
	if _can_shoot() and _fire_down():
		out.buttons |= InputCommand.BTN_FIRE
	# Alt-fire (RMB, rebindable): Liora's heal beam (weapons-and-mods.md §3.3.1).
	if _can_shoot() and _alt_fire_down():
		out.buttons |= InputCommand.BTN_ALT
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


## Held-state of the fire action (InputMap, rebindable; default left mouse).
func _alt_fire_down() -> bool:
	if InputMap.has_action(&"alt_fire"):
		return Input.is_action_pressed(&"alt_fire")
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func _fire_down() -> bool:
	if debug_fire:  # pulse: semi-auto weapons need a press edge per shot
		return Engine.get_physics_frames() % 6 < 3
	if InputMap.has_action(&"fire"):
		return Input.is_action_pressed(&"fire")
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## WASD (or rebound) movement vector; physical-key fallback without the map.
func _move_vector() -> Vector2:
	if InputMap.has_action(&"move_forward"):
		return Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	return Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))).limit_length(1.0)


## Input-map action if defined, else the physical key (unit tests / before
## GameSettings applied the bindings).
func _pressed(action: StringName, fallback: Key) -> bool:
	return InputBindings.is_down(action, fallback)
