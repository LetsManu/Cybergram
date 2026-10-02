class_name MotorState
extends RefCounted
## Complete locomotion state of one hero (architecture.md §5.1). Everything
## HeroMotor needs to continue a simulation lives here, so a snapshot of it is
## enough to reconcile. Timers are integer ticks (architecture.md §1.6).

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var grounded: bool = false
var crouching: bool = false
## Jump button was down last tick (jumps trigger on the press edge).
var jump_held: bool = false
var coyote_ticks: int = 0
var jump_buffer_ticks: int = 0
## E10: move-speed multiplier from the hero StatBlock (slows, roots, stances);
## 0 also blocks jumping. Set by the server each tick; replicated to the owner.
var speed_scale: float = 1.0
## E10: forced motion (Ram Charge, Earthbreaker leap; ADR-0004 MotionEffect).
## While dash_ticks > 0 the horizontal velocity is dash_velocity.xz; on the
## first such tick (dash_launch) the vertical velocity becomes dash_velocity.y.
var dash_ticks: int = 0
var dash_velocity: Vector3 = Vector3.ZERO
var dash_launch: bool = false


func copy_from(o: MotorState) -> void:
	position = o.position
	velocity = o.velocity
	grounded = o.grounded
	crouching = o.crouching
	jump_held = o.jump_held
	coyote_ticks = o.coyote_ticks
	jump_buffer_ticks = o.jump_buffer_ticks
	speed_scale = o.speed_scale
	dash_ticks = o.dash_ticks
	dash_velocity = o.dash_velocity
	dash_launch = o.dash_launch


func duplicate_state() -> MotorState:
	var s := MotorState.new()
	s.copy_from(self)
	return s


func equals(o: MotorState) -> bool:
	return position == o.position and velocity == o.velocity and grounded == o.grounded \
		and crouching == o.crouching and jump_held == o.jump_held \
		and coyote_ticks == o.coyote_ticks and jump_buffer_ticks == o.jump_buffer_ticks \
		and speed_scale == o.speed_scale and dash_ticks == o.dash_ticks and dash_velocity == o.dash_velocity \
		and dash_launch == o.dash_launch
