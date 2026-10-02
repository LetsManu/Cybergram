class_name AimHumanizer
extends RefCounted
## Human-like aim for bots (architecture.md §9, ADR-0005 §2): a reaction delay
## after a new target appears, a flick overshoot that settles, a bounded
## random-walk tracking error and a turn-rate limit, all from BotProfile.
## Bots never aim better than a player could: no lead beyond what they see,
## no rewind (view_tick = current tick).
##
## Angles follow InputCommand: yaw in [0, TAU) with 0 facing -Z, pitch
## positive up, clamped to +-PITCH_LIMIT.

const PITCH_LIMIT: float = deg_to_rad(85.0)
## Steady error is re-sampled this often (seconds) and eased toward.
const ERROR_RESAMPLE_S: float = 0.25
const HEAD_REROLL_S: float = 1.0

var profile: BotProfile
var rng: RandomNumberGenerator
var tick_hz: int = 30
var yaw: float = 0.0
var pitch: float = 0.0
var target_id: int = 0
var ready_tick: int = 0
var aim_head: bool = false

var _acquire_tick: int = 0
var _err: Vector2 = Vector2.ZERO  # degrees (yaw, pitch)
var _err_goal: Vector2 = Vector2.ZERO
var _flick: Vector2 = Vector2.ZERO
var _next_resample: int = 0
var _next_head_roll: int = 0


func _init(p: BotProfile, r: RandomNumberGenerator, hz: int) -> void:
	profile = p
	rng = r
	tick_hz = hz


## Switches target (0 = none). A new target restarts the reaction delay and flick.
func set_target(id: int, tick: int) -> void:
	if id == target_id:
		return
	target_id = id
	if id == 0:
		return
	_acquire_tick = tick
	var jitter := 1.0 + rng.randf_range(-profile.reaction_jitter, profile.reaction_jitter)
	ready_tick = tick + roundi(profile.reaction_s * jitter * tick_hz)
	var a := rng.randf() * TAU
	_flick = Vector2(cos(a), sin(a)) * profile.flick_error_deg
	aim_head = rng.randf() < profile.headshot_rate
	_next_head_roll = tick + roundi(HEAD_REROLL_S * tick_hz)


## True once the reaction delay for the current target has passed.
func can_fire(tick: int) -> bool:
	return target_id != 0 and tick >= ready_tick


## Current total error in degrees (steady + flick), bounded by
## max_error_deg + flick_error_deg.
func error_deg(tick: int) -> Vector2:
	var settle := maxf(profile.flick_settle_s * tick_hz, 1.0)
	var f := clampf(1.0 - float(tick - _acquire_tick) / settle, 0.0, 1.0)
	return _err + _flick * f


## One tick of tracking `point` from `eye`: turns toward it plus the error.
func track(point: Vector3, eye: Vector3, tick: int) -> void:
	if tick >= _next_resample:
		_next_resample = tick + maxi(roundi(ERROR_RESAMPLE_S * tick_hz), 1)
		_err_goal = Vector2(rng.randfn(0.0, profile.tracking_error_deg), rng.randfn(0.0, profile.tracking_error_deg))
		_err_goal = _err_goal.limit_length(profile.max_error_deg)
	_err = _err.lerp(_err_goal, 0.2).limit_length(profile.max_error_deg)
	if tick >= _next_head_roll and target_id != 0:
		_next_head_roll = tick + roundi(HEAD_REROLL_S * tick_hz)
		aim_head = rng.randf() < profile.headshot_rate
	var want := angles_to(eye, point)
	var e := error_deg(tick)
	_turn_toward(want.x + deg_to_rad(e.x), want.y + deg_to_rad(e.y))


## Turn-rate-limited look at `point` without tracking error (walking, skills).
func look_at(point: Vector3, eye: Vector3) -> void:
	var want := angles_to(eye, point)
	_turn_toward(want.x, want.y)


## Turn-rate-limited look along absolute angles.
func look_angles(y: float, p: float) -> void:
	_turn_toward(y, p)


## Angle (radians) between the current aim and the direction to `point`.
func off_angle(point: Vector3, eye: Vector3) -> float:
	var to := point - eye
	if to.length_squared() < 1e-6:
		return 0.0
	return forward().angle_to(to.normalized())


## True if the current aim is within the target's angular radius (scaled by
## fire_tolerance_mult) of `point`.
func on_target(point: Vector3, eye: Vector3, radius_m: float) -> bool:
	var d := maxf(eye.distance_to(point), 0.5)
	return off_angle(point, eye) <= atan(radius_m / d) * profile.fire_tolerance_mult


func forward() -> Vector3:
	# = Basis(UP, yaw) * Basis(RIGHT, pitch) * FORWARD, without building two Basis (E14 bot cost).
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


## (yaw, pitch) looking from `from` at `to`.
static func angles_to(from: Vector3, to: Vector3) -> Vector2:
	var d := to - from
	return Vector2(fposmod(atan2(-d.x, -d.z), TAU), clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PITCH_LIMIT, PITCH_LIMIT))


func _turn_toward(y: float, p: float) -> void:
	var step := deg_to_rad(profile.turn_rate_deg_s) / tick_hz
	var dy := angle_difference(yaw, y)
	yaw = fposmod(yaw + clampf(dy, -step, step), TAU)
	pitch = clampf(pitch + clampf(p - pitch, -step, step), -PITCH_LIMIT, PITCH_LIMIT)
