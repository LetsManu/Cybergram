class_name InputBindings
extends RefCounted
## Rebindable controls: one keyboard/mouse binding and one gamepad binding per
## action, stored as spec strings. Keyboard/mouse: "k:<physical keycode>" or
## "m:<mouse button>" ([bindings] section). Gamepad (W11-C1): "j:<JoyButton>" or
## "a:<JoyAxis>:<sign>" with sign +1 / -1 ([bindings_pad] section). Both are
## persisted in user://settings.cfg and applied to the InputMap at boot
## (GameSettings.shared()). Game code reads InputMap actions (is_down()), so
## rebinding takes effect everywhere at once. Pure data + InputMap writes: no
## UI or gameplay types.

const GROUP_MOVE := "move"
const GROUP_COMBAT := "combat"
const GROUP_SKILLS := "skills"
const GROUP_SQUAD := "squad"
const GROUP_INTERFACE := "interface"

## [action, group, default key/mouse spec, default gamepad spec ("" = unbound)]
## in menu order. Pad layout: LS move, RS look (fixed, not an action), RT fire,
## LT alt-fire, A jump, B crouch, L3 sprint, X reload, Y interact, LB/RB skills
## 1/2, D-pad left/up skills 3/ult, D-pad down med-pack, D-pad right = quick
## spend modifier (hold + a skill button learns it), R3 squad smart (hold =
## wheel), Back scoreboard, Start pause. Fork A/B on a pad default to unbound:
## while the HUD offers a Fork the skill-1 / skill-2 pad buttons (LB / RB) pick it. Names and defaults follow
## PlayerInputSource (hud.md §13) and the HUD (Tab scoreboard, F3 net graph).
## Keycodes: W 87, S 83, A 65, D 68, Space 32, Ctrl 4194326, Shift 4194325,
## R 82, F 70, 4 52, T 84, Q 81, E 69, C 67, G 71, Alt 4194328, Z 90, X 88, V 86,
## B 66, Tab 4194306, F3 4194334, Esc 4194305.
const ACTIONS: Array = [
	["move_forward", GROUP_MOVE, "k:87", "a:1:-1"],
	["move_back", GROUP_MOVE, "k:83", "a:1:1"],
	["move_left", GROUP_MOVE, "k:65", "a:0:-1"],
	["move_right", GROUP_MOVE, "k:68", "a:0:1"],
	["jump", GROUP_MOVE, "k:32", "j:0"],
	["crouch", GROUP_MOVE, "k:4194326", "j:1"],
	["sprint", GROUP_MOVE, "k:4194325", "j:7"],
	["fire", GROUP_COMBAT, "m:1", "a:5:1"],
	["alt_fire", GROUP_COMBAT, "m:2", "a:4:1"],
	["reload", GROUP_COMBAT, "k:82", "j:2"],
	["interact", GROUP_COMBAT, "k:70", "j:3"],
	["use_medpack", GROUP_COMBAT, "k:52", "j:12"],
	# W19-VM: weapon inspect (first-person presentation only; T, pad unbound).
	["inspect", GROUP_COMBAT, "k:84", ""],
	["skill_1", GROUP_SKILLS, "k:81", "j:9"],
	["skill_2", GROUP_SKILLS, "k:69", "j:10"],
	["skill_3", GROUP_SKILLS, "k:67", "j:13"],
	["skill_4", GROUP_SKILLS, "k:71", "j:11"],
	["quick_spend", GROUP_SKILLS, "k:4194328", "j:14"],
	# W10-T1: pick Fork A / B when the HUD offers the choice (1 / 2; gamepad L1 / R1).
	["fork_a", GROUP_SKILLS, "k:49", ""],
	["fork_b", GROUP_SKILLS, "k:50", ""],
	["squad_smart", GROUP_SQUAD, "k:90", "j:8"],
	["squad_follow", GROUP_SQUAD, "k:88", ""],
	["squad_wheel", GROUP_SQUAD, "k:86", ""],
	["open_shop", GROUP_INTERFACE, "k:66", ""],
	["scoreboard", GROUP_INTERFACE, "k:4194306", "j:4"],
	["net_graph", GROUP_INTERFACE, "k:4194334", ""],
	["pause", GROUP_INTERFACE, "k:4194305", "j:6"],
]
const GROUPS: Array[String] = [GROUP_MOVE, GROUP_COMBAT, GROUP_SKILLS, GROUP_SQUAD, GROUP_INTERFACE]
const SECTION := "bindings"
const SECTION_PAD := "bindings_pad"
const UNBOUND := ""
## Axis value past which a stick / trigger counts as a press when capturing.
const CAPTURE_AXIS_THRESHOLD := 0.6
const JOY_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad Up", JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left", JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}

## action -> key / mouse spec string.
var _map: Dictionary = {}
## action -> gamepad spec string ("" = unbound).
var _pad: Dictionary = {}


func _init() -> void:
	reset_all()


## All action ids (menu order).
static func action_ids() -> Array[String]:
	var out: Array[String] = []
	for a in ACTIONS:
		out.append(a[0])
	return out


## Group of `action` ("" if unknown).
static func group_of(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return ""


## Default spec of `action` ("" if unknown).
static func default_spec(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return UNBOUND


## Current spec of `action`.
func get_spec(action: String) -> String:
	return str(_map.get(action, UNBOUND))


## True when every action has its default binding.
func is_default() -> bool:
	for a in ACTIONS:
		if get_spec(a[0]) != a[2]:
			return false
	return true


## Restores every default key / mouse binding (the gamepad map is untouched).
func reset_all() -> void:
	_map.clear()
	for a in ACTIONS:
		_map[a[0]] = a[2]
	if _pad.is_empty():
		reset_pad()


## Default gamepad spec of `action` ("" = unbound / unknown).
static func default_pad_spec(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[3]
	return UNBOUND


## Current gamepad spec of `action`.
func get_pad_spec(action: String) -> String:
	return str(_pad.get(action, UNBOUND))


## True when every action has its default gamepad binding.
func is_pad_default() -> bool:
	for a in ACTIONS:
		if get_pad_spec(a[0]) != a[3]:
			return false
	return true


## Restores every default gamepad binding.
func reset_pad() -> void:
	_pad.clear()
	for a in ACTIONS:
		_pad[a[0]] = a[3]


## Binds the gamepad `spec` to `action`; same swap-on-conflict rule as assign().
## Returns the swapped action id or "". Malformed specs change nothing; "" unbinds.
func assign_pad(action: String, spec: String) -> String:
	if not _pad.has(action) or (spec != UNBOUND and joy_event_from_spec(spec) == null):
		return ""
	var old := get_pad_spec(action)
	if old == spec:
		return ""
	var other := pad_action_using(spec, action) if spec != UNBOUND else ""
	_pad[action] = spec
	if other != "":
		_pad[other] = old
	return other


## The action (other than `except`) with the gamepad `spec`, or "".
func pad_action_using(spec: String, except: String = "") -> String:
	if spec == UNBOUND:
		return ""
	for a in ACTIONS:
		if a[0] != except and get_pad_spec(a[0]) == spec:
			return a[0]
	return ""


## Binds `spec` to `action`. When another action already uses it the two swap
## (that action takes `action`'s old spec). Returns the swapped action id, or ""
## when there was no conflict. Unknown actions or malformed specs change nothing.
func assign(action: String, spec: String) -> String:
	if not _map.has(action) or event_from_spec(spec) == null:
		return ""
	var old := get_spec(action)
	if old == spec:
		return ""
	var other := action_using(spec, action)
	_map[action] = spec
	if other != "":
		_map[other] = old
	return other


## The action (other than `except`) bound to `spec`, or "".
func action_using(spec: String, except: String = "") -> String:
	for a in ACTIONS:
		if a[0] != except and get_spec(a[0]) == spec:
			return a[0]
	return ""


## Writes the [bindings] section.
func write_config(cfg: ConfigFile) -> void:
	for a in ACTIONS:
		cfg.set_value(SECTION, a[0], get_spec(a[0]))
		cfg.set_value(SECTION_PAD, a[0], get_pad_spec(a[0]))


## Reads the [bindings] section. Unknown / malformed values keep the default;
## a file that binds one spec twice is repaired (the later action falls back to
## its default, or stays unbound when that is taken too).
func read_config(cfg: ConfigFile) -> void:
	reset_all()
	var seen := {}
	for a in ACTIONS:
		var spec := str(cfg.get_value(SECTION, a[0], a[2]))
		if event_from_spec(spec) == null or seen.has(spec):
			spec = a[2]
		if seen.has(spec):
			spec = UNBOUND
		_map[a[0]] = spec
		if spec != UNBOUND:
			seen[spec] = true
	# Gamepad section: same repair (invalid / duplicate -> default, else unbound).
	_pad.clear()
	var seen_pad := {}
	for a in ACTIONS:
		var pspec := str(cfg.get_value(SECTION_PAD, a[0], a[3]))
		if pspec != UNBOUND and (joy_event_from_spec(pspec) == null or seen_pad.has(pspec)):
			pspec = a[3]
		if pspec != UNBOUND and seen_pad.has(pspec):
			pspec = UNBOUND
		_pad[a[0]] = pspec
		if pspec != UNBOUND:
			seen_pad[pspec] = true


## Replaces each action's InputMap events with its binding. "pause" also feeds
## ui_cancel (Esc stays there too) so the pause menu follows the rebind.
func apply_to_input_map() -> void:
	for a in ACTIONS:
		var action := StringName(a[0])
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var ev := event_from_spec(get_spec(a[0]))
		if ev != null:
			InputMap.action_add_event(action, ev)
		var jev := joy_event_from_spec(get_pad_spec(a[0]))
		if jev != null:
			InputMap.action_add_event(action, jev)
	if InputMap.has_action(&"ui_cancel"):
		var esc_spec := "k:%d" % KEY_ESCAPE
		InputMap.action_erase_events(&"ui_cancel")
		InputMap.action_add_event(&"ui_cancel", event_from_spec(esc_spec))
		var pause_spec := get_spec("pause")
		if pause_spec != esc_spec and event_from_spec(pause_spec) != null:
			InputMap.action_add_event(&"ui_cancel", event_from_spec(pause_spec))
		var pad_pause := joy_event_from_spec(get_pad_spec("pause"))
		if pad_pause != null:
			InputMap.action_add_event(&"ui_cancel", pad_pause)


## InputEvent for a spec (null when malformed).
static func event_from_spec(spec: String) -> InputEvent:
	var parts := spec.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var n := parts[1].to_int()
	if parts[0] == "k" and n > 0:
		var k := InputEventKey.new()
		k.physical_keycode = n as Key
		return k
	if parts[0] == "m" and n > 0 and n <= MOUSE_BUTTON_XBUTTON2:
		var m := InputEventMouseButton.new()
		m.button_index = n as MouseButton
		return m
	return null


## InputEvent for a gamepad spec ("j:<button>" / "a:<axis>:<sign>"); null when
## malformed. Events match every device (device -1).
static func joy_event_from_spec(spec: String) -> InputEvent:
	var parts := spec.split(":")
	if parts.size() == 2 and parts[0] == "j" and parts[1].is_valid_int():
		var n := parts[1].to_int()
		if n < 0 or n >= JOY_BUTTON_SDL_MAX:
			return null
		var b := InputEventJoypadButton.new()
		b.device = -1
		b.button_index = n as JoyButton
		return b
	if parts.size() == 3 and parts[0] == "a" and parts[1].is_valid_int() and parts[2].is_valid_int():
		var axis := parts[1].to_int()
		var sign_v := parts[2].to_int()
		if axis < 0 or axis >= JOY_AXIS_SDL_MAX or (sign_v != 1 and sign_v != -1):
			return null
		var m := InputEventJoypadMotion.new()
		m.device = -1
		m.axis = axis as JoyAxis
		m.axis_value = float(sign_v)
		return m
	return null


## Gamepad spec for a captured event ("" = not a bindable press): a button press,
## or an axis pushed past CAPTURE_AXIS_THRESHOLD.
static func joy_spec_from_event(event: InputEvent) -> String:
	if event is InputEventJoypadButton and event.pressed:
		return "j:%d" % event.button_index
	if event is InputEventJoypadMotion and absf(event.axis_value) >= CAPTURE_AXIS_THRESHOLD:
		return "a:%d:%d" % [event.axis, 1 if event.axis_value > 0.0 else -1]
	return UNBOUND


## Display text of a gamepad spec ("A", "RT", "Left Stick Up", ...); "-" = unbound.
static func joy_spec_text(spec: String) -> String:
	var ev := joy_event_from_spec(spec)
	if ev is InputEventJoypadButton:
		var b: int = (ev as InputEventJoypadButton).button_index
		return str(JOY_BUTTON_NAMES.get(b, "Button %d" % b))
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		var up := m.axis_value < 0.0
		match m.axis:
			JOY_AXIS_LEFT_X:
				return "Left Stick " + ("Left" if up else "Right")
			JOY_AXIS_LEFT_Y:
				return "Left Stick " + ("Up" if up else "Down")
			JOY_AXIS_RIGHT_X:
				return "Right Stick " + ("Left" if up else "Right")
			JOY_AXIS_RIGHT_Y:
				return "Right Stick " + ("Up" if up else "Down")
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			_:
				return "Axis %d%s" % [m.axis, "-" if up else "+"]
	return "-"


## Spec for a captured event ("" when it is not a bindable key / mouse press).
static func spec_from_event(event: InputEvent) -> String:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return "k:%d" % code if code > 0 else UNBOUND
	if event is InputEventMouseButton and event.pressed:
		return "m:%d" % event.button_index
	return UNBOUND


## Display text of a spec ("Space", "LMB", ...). Not localised: key names come
## from the OS.
static func spec_text(spec: String) -> String:
	var ev := event_from_spec(spec)
	if ev is InputEventKey:
		var code: Key = (ev as InputEventKey).physical_keycode
		if DisplayServer.get_name() != "headless":
			var label := DisplayServer.keyboard_get_label_from_physical(code)
			if label != KEY_NONE:
				return OS.get_keycode_string(label)
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		var b: int = (ev as InputEventMouseButton).button_index
		match b:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel Down"
			_:
				return "Mouse %d" % b
	return "-"


## True while `action` is held. Uses the InputMap action (rebindable); if the
## action is not in the map yet (unit tests, before GameSettings loaded) it
## falls back to `fallback_key` as a physical key.
static func is_down(action: StringName, fallback_key: Key = KEY_NONE) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return fallback_key != KEY_NONE and Input.is_physical_key_pressed(fallback_key)
