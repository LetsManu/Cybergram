class_name PracticeRangeDef
extends Resource
## Practice Range tuning (assets/data/match/practice_range.tres, W10-W4): the
## offline session on the movement test course with training dummies, free
## Lumen, a level-up key and a reset key. All values are data.

## Lumen is topped up to this every tick ("infinite gold").
@export var lumen_floor: int = 99999
## Static dummies: offsets from the player's spawn (metres; -Z is forward).
@export var static_dummy_offsets: PackedVector3Array = PackedVector3Array([
	Vector3(-4.0, 0.0, -10.0), Vector3(0.0, 0.0, -14.0), Vector3(4.0, 0.0, -18.0)])
@export_file("*.tres") var static_dummy_input: String = "res://assets/data/debug/scripted_input_dummy_idle.tres"
@export_file("*.tres") var dummy_hero: String = "res://assets/data/heroes/hero_brannoc.tres"
## Keyboard / gamepad keys (fixed, not part of the rebindable gameplay actions).
@export var key_level_up: Key = KEY_F5
@export var key_reset: Key = KEY_F10  # F6-F9 are HUD settings keys (hud_root.gd)
@export var key_tutorial: Key = KEY_F1
@export var key_skip_step: Key = KEY_F2
@export var key_skip_all: Key = KEY_F4
@export var joy_skip_step: JoyButton = JOY_BUTTON_DPAD_RIGHT
@export var joy_skip_all: JoyButton = JOY_BUTTON_DPAD_DOWN
@export var joy_level_up: JoyButton = JOY_BUTTON_DPAD_UP
@export var joy_reset: JoyButton = JOY_BUTTON_BACK
@export var joy_tutorial: JoyButton = JOY_BUTTON_DPAD_LEFT
## Seconds before the keys repeat / the level-up key can fire again.
@export_range(0.05, 2.0, 0.05) var key_cooldown_s: float = 0.25
