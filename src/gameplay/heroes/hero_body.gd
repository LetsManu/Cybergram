class_name HeroBody
extends CharacterBody3D
## CharacterBody3D wrapper for a hero: owns the capsule, the MotorState and a
## HeroMotor. Used as the authoritative body on the server (architecture.md
## HeroSim) and as PredictedHero on the client. It has no _physics_process: the
## TickRunner/Predictor call step() explicitly so ticks happen in a fixed order.

const LAYER_WORLD: int = 1
const LAYER_HEROES: int = 2
## Invisible walls above edge rails: block hero movement only, never shots.
const LAYER_EDGE_BLOCK: int = 4

var net_id: int = 0
var state := MotorState.new()
var motor: HeroMotor
## Last applied command's look direction (replicated for views).
var look_yaw: float = 0.0
var look_pitch: float = 0.0
## Server-side combat state (null on the client's predicted body).
var combat: HeroCombat

var _def: MovementDef
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D


## Builds the capsule and motor, and places the hero at `spawn`.
## `collide_with_heroes` is false for the client's predicted body (remote heroes
## are views there, not bodies).
func setup(movement: MovementDef, spawn: Vector3, collide_with_heroes: bool) -> void:
	_def = movement
	collision_layer = LAYER_HEROES
	collision_mask = LAYER_WORLD | LAYER_EDGE_BLOCK | (LAYER_HEROES if collide_with_heroes else 0)
	floor_max_angle = deg_to_rad(movement.max_floor_angle_deg)
	floor_snap_length = movement.floor_snap_length
	_capsule = CapsuleShape3D.new()
	_capsule.radius = movement.capsule_radius
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	add_child(_shape)
	_apply_height(movement.stand_height)
	motor = HeroMotor.new(movement, self)
	state.position = spawn
	position = spawn


## Must be called once the body is inside the tree (after setup()).
func place() -> void:
	motor.restore(state)


## One tick of movement.
func step(cmd: InputCommand, dt: float) -> void:
	motor.step(state, cmd, dt)
	look_yaw = cmd.yaw
	look_pitch = clampf(cmd.pitch, -deg_to_rad(_def.max_pitch_deg), deg_to_rad(_def.max_pitch_deg))


func movement_def() -> MovementDef:
	return _def


## Eye height above the feet for the current stance.
func eye_height() -> float:
	return _def.crouch_eye_height if state.crouching else _def.stand_eye_height


func set_crouched(crouched: bool) -> void:
	_apply_height(_def.crouch_height if crouched else _def.stand_height)


## True if there is headroom to stand up from a crouch.
func can_stand() -> bool:
	var rise := _def.stand_height - _def.crouch_height
	return not test_move(global_transform, Vector3(0.0, rise, 0.0))


func _apply_height(h: float) -> void:
	_capsule.height = h
	_shape.position = Vector3(0.0, h / 2.0, 0.0)
