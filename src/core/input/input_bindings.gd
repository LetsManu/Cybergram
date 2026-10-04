class_name InputBindings
extends RefCounted
## Rebindable controls: one primary binding per action, stored as a spec string
## ("k:<physical keycode>" or "m:<mouse button>"), persisted in the [bindings]
## section of user://settings.cfg and applied to the InputMap at boot
## (GameSettings.shared()). Game code reads InputMap actions (is_down()), so
## rebinding takes effect everywhere at once. Pure data + InputMap writes: no
## UI or gameplay types.

const GROUP_MOVE := "move"
const GROUP_COMBAT := "combat"
const GROUP_SKILLS := "skills"
const GROUP_SQUAD := "squad"
const GROUP_INTERFACE := "interface"

## [action, group, default spec] in menu order. Names and defaults follow
## PlayerInputSource (hud.md §13) and the HUD (Tab scoreboard, F3 net graph).
## Keycodes: W 87, S 83, A 65, D 68, Space 32, Ctrl 4194326, Shift 4194325,
## R 82, F 70, 4 52, Q 81, E 69, C 67, G 71, Alt 4194328, Z 90, X 88, V 86,
## B 66, Tab 4194306, F3 4194334, Esc 4194305.
const ACTIONS: Array = [
	["move_forward", GROUP_MOVE, "k:87"],
	["move_back", GROUP_MOVE, "k:83"],
	["move_left", GROUP_MOVE, "k:65"],
	["move_right", GROUP_MOVE, "k:68"],
	["jump", GROUP_MOVE, "k:32"],
	["crouch", GROUP_MOVE, "k:4194326"],
	["sprint", GROUP_MOVE, "k:4194325"],
	["fire", GROUP_COMBAT, "m:1"],
	["reload", GROUP_COMBAT, "k:82"],
	["interact", GROUP_COMBAT, "k:70"],
	["use_medpack", GROUP_COMBAT, "k:52"],
	["skill_1", GROUP_SKILLS, "k:81"],
	["skill_2", GROUP_SKILLS, "k:69"],
	["skill_3", GROUP_SKILLS, "k:67"],
	["skill_4", GROUP_SKILLS, "k:71"],
	["quick_spend", GROUP_SKILLS, "k:4194328"],
	["squad_smart", GROUP_SQUAD, "k:90"],
	["squad_follow", GROUP_SQUAD, "k:88"],
	["squad_wheel", GROUP_SQUAD, "k:86"],
	["open_shop", GROUP_INTERFACE, "k:66"],
	["scoreboard", GROUP_INTERFACE, "k:4194306"],
	["net_graph", GROUP_INTERFACE, "k:4194334"],
	["pause", GROUP_INTERFACE, "k:4194305"],
]
const GROUPS: Array[String] = [GROUP_MOVE, GROUP_COMBAT, GROUP_SKILLS, GROUP_SQUAD, GROUP_INTERFACE]
const SECTION := "bindings"
const UNBOUND := ""

## action -> spec string.
var _map: Dictionary = {}


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


## Restores every default binding.
func reset_all() -> void:
	_map.clear()
	for a in ACTIONS:
		_map[a[0]] = a[2]


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
	if InputMap.has_action(&"ui_cancel"):
		var esc_spec := "k:%d" % KEY_ESCAPE
		InputMap.action_erase_events(&"ui_cancel")
		InputMap.action_add_event(&"ui_cancel", event_from_spec(esc_spec))
		var pause_spec := get_spec("pause")
		if pause_spec != esc_spec and event_from_spec(pause_spec) != null:
			InputMap.action_add_event(&"ui_cancel", event_from_spec(pause_spec))


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
