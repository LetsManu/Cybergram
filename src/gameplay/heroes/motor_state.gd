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


func copy_from(o: MotorState) -> void:
	position = o.position
	velocity = o.velocity
	grounded = o.grounded
	crouching = o.crouching
	jump_held = o.jump_held
	coyote_ticks = o.coyote_ticks
	jump_buffer_ticks = o.jump_buffer_ticks


func duplicate_state() -> MotorState:
	var s := MotorState.new()
	s.copy_from(self)
	return s


func equals(o: MotorState) -> bool:
	return position == o.position and velocity == o.velocity and grounded == o.grounded \
		and crouching == o.crouching and jump_held == o.jump_held \
		and coyote_ticks == o.coyote_ticks and jump_buffer_ticks == o.jump_buffer_ticks
