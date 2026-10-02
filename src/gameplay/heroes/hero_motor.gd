class_name HeroMotor
extends RefCounted
## The ONLY hero movement code (architecture.md §5.1, ADR-0002 §5). Runs on the
## server (HeroBody under ServerWorld) and in client prediction (Predictor), so
## the same (state, command, dt) sequence gives the same state on both.
## Implements design/gdd/heroes.md §2: walk, Sprint x1.35, Crouch x0.5, jump.
##
## Two layers:
## - compute_intent(): pure, no engine calls; velocity, jump and crouch intent.
## - step(): compute_intent + collision via CharacterBody3D.move_and_slide().
##
## Example:
##   var motor := HeroMotor.new(def, hero_body)
##   motor.step(state, cmd, 1.0 / 30.0)

const _PRIME_SPEED: float = 0.01  # see restore(); docs/architecture/verification-4.7.md

var def: MovementDef
var body: HeroBody


func _init(movement: MovementDef, hero_body: HeroBody) -> void:
	def = movement
	body = hero_body


## Pure part of a step: updates velocity, jump/coyote timers and crouch intent
## in `state`. Position is untouched (collision resolves it). Returns true if
## the hero wants to crouch this tick.
static func compute_intent(state: MotorState, cmd: InputCommand, d: MovementDef, dt: float) -> bool:
	var wants_crouch := cmd.has(InputCommand.BTN_CROUCH)
	var crouched := state.crouching or wants_crouch
	var speed := d.base_move_speed * maxf(state.speed_scale, 0.0)
	if crouched:
		speed *= d.crouch_multiplier
	elif cmd.has(InputCommand.BTN_SPRINT) and cmd.move.y > 0.0:
		speed *= d.sprint_multiplier
	var basis := Basis(Vector3.UP, cmd.yaw)
	var wish := basis * Vector3(cmd.move.x, 0.0, -cmd.move.y)
	var target := Vector2(wish.x, wish.z) * speed
	var accel := d.ground_acceleration if state.grounded else d.air_acceleration
	var hv := Vector2(state.velocity.x, state.velocity.z)
	if state.dash_ticks == 0 and state.dash_velocity != Vector3.ZERO:
		hv = hv.limit_length(speed)  # E10: a dash just ended; back to walk speed
		state.dash_velocity = Vector3.ZERO
	var h := hv.move_toward(target, accel * dt)
	var vy := state.velocity.y
	if state.grounded:
		vy = minf(vy, 0.0)
	vy -= d.gravity * dt
	# E10 forced motion (dash / leap) replaces the walk velocity.
	if state.dash_ticks > 0:
		state.dash_ticks -= 1
		h = Vector2(state.dash_velocity.x, state.dash_velocity.z)
		if state.dash_launch:
			vy = state.dash_velocity.y
			state.dash_launch = false
			state.grounded = false
	# Jump: press edge fills the buffer; take-off needs ground or coyote time.
	var jump_down := cmd.has(InputCommand.BTN_JUMP) and state.speed_scale > 0.0
	if jump_down and not state.jump_held:
		state.jump_buffer_ticks = roundi(d.jump_buffer_s / dt) + 1
	state.jump_held = jump_down
	if state.jump_buffer_ticks > 0:
		state.jump_buffer_ticks -= 1
		if state.grounded or state.coyote_ticks > 0:
			vy = d.jump_velocity
			state.jump_buffer_ticks = 0
			state.coyote_ticks = 0
			state.grounded = false
	state.velocity = Vector3(h.x, vy, h.y)
	return wants_crouch


## Advances `state` by one tick of `dt` seconds using `cmd`.
## The body must already be at state.position (true unless restore() is needed).
func step(state: MotorState, cmd: InputCommand, dt: float) -> void:
	var wants_crouch := compute_intent(state, cmd, def, dt)
	if wants_crouch != state.crouching:
		if wants_crouch or body.can_stand():
			state.crouching = wants_crouch
			body.set_crouched(wants_crouch)
	# move_and_slide() integrates over the engine physics step, not dt; scale so
	# the motor honours dt (exactly 1.0 at runtime, where physics rate = tick rate).
	var scale := dt / body.get_physics_process_delta_time()
	body.velocity = state.velocity * scale
	body.move_and_slide()
	var was_grounded := state.grounded
	state.position = body.global_position
	state.velocity = body.velocity / scale
	state.grounded = body.is_on_floor()
	if state.grounded:
		state.coyote_ticks = 0
	elif was_grounded and state.velocity.y <= 0.0:
		state.coyote_ticks = roundi(def.coyote_time_s / dt)
	elif state.coyote_ticks > 0:
		state.coyote_ticks -= 1


## Puts the body into `state` (teleport, spawn, reconciliation). CharacterBody3D
## keeps hidden contact state that position/velocity do not restore; one tiny
## move toward the recorded contact rebuilds it so replay matches live stepping
## (verification-4.7.md item 3).
func restore(state: MotorState) -> void:
	body.set_crouched(state.crouching)
	body.global_position = state.position
	body.velocity = Vector3(0.0, -_PRIME_SPEED if state.grounded else _PRIME_SPEED, 0.0)
	body.move_and_slide()
	body.global_position = state.position
	body.velocity = state.velocity
