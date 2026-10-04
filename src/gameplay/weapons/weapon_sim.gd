class_name WeaponSim
extends RefCounted
## Server-side weapon state for one hero (architecture.md §5.2): fire-rate
## gating, trigger discipline (semi-auto), spread bloom/recovery and the AmmoFeed.
## Hit resolution is done by the caller (ServerWorld via HitscanTracer) with the
## directions from pellet_directions().
##
## The clock is the owner's applied-command count (one tick per InputCommand),
## so queued inputs after a stall cannot fire faster than the weapon allows.
##
## Example:
##   if weapon.step(cmd, tick, true):
##       for dir in weapon.pellet_directions(forward): trace(dir)

var def: WeaponDef
var feed: AmmoFeed
## Current cone half-angle (degrees).
var spread_deg: float
## Cone used by the shot fired in the latest step().
var shot_spread_deg: float = 0.0
var shots_fired: int = 0
## Fire-rate multiplier of timed buffs (Combat Stim +25% = 1.25).
var rate_mult: float = 1.0

var _interval: float
var _next_fire_tick: float = 0.0
var _last_shot_tick: int = -1000000
var _trigger_released: bool = true
var _recovery_delay_ticks: int
var _recovery_per_tick: float
var _rng := RandomNumberGenerator.new()


func _init(weapon: WeaponDef, tick_rate_hz: int, rng_seed: int) -> void:
	def = weapon
	feed = AmmoFeed.create(weapon, tick_rate_hz)
	_interval = weapon.fire_interval_ticks(tick_rate_hz)
	_recovery_delay_ticks = roundi(weapon.spread_recovery_delay_s * tick_rate_hz)
	_rng.seed = rng_seed
	spread_deg = weapon.spread_base_deg
	_recovery_per_tick = weapon.spread_recovery_deg_s / tick_rate_hz


## One tick with `cmd`. `allowed` is false while sprinting, stunned, etc.
## Returns true if a shot was fired this tick.
func step(cmd: InputCommand, tick: int, allowed: bool) -> bool:
	feed.step(tick)
	if tick - _last_shot_tick > _recovery_delay_ticks:
		spread_deg = maxf(def.spread_base_deg, spread_deg - _recovery_per_tick)
	if cmd.has(InputCommand.BTN_RELOAD):
		feed.request_reload(tick)
	var held := cmd.has(InputCommand.BTN_FIRE)
	var fired := false
	if held and allowed and (_trigger_released or not def.semi_auto) \
			and tick + 1e-4 >= _next_fire_tick and feed.can_fire():
		feed.consume(tick)
		if tick > _next_fire_tick + 1.0:
			_next_fire_tick = tick  # idle: no banked shots
		_next_fire_tick += _interval / rate_mult
		_last_shot_tick = tick
		shot_spread_deg = spread_deg
		spread_deg = minf(def.spread_max_deg, spread_deg + def.spread_bloom_deg)
		shots_fired += 1
		_trigger_released = false
		fired = true
	if not held:
		_trigger_released = true
	return fired


## Pellet directions for the latest shot: uniform inside a cone of
## shot_spread_deg around `forward` (unit vector). Deterministic per seed.
func pellet_directions(forward: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cos_max := cos(deg_to_rad(shot_spread_deg))
	var side := forward.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = forward.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(forward).normalized()
	for i in def.pellets:
		var cos_t := lerpf(1.0, cos_max, _rng.randf())
		var sin_t := sqrt(maxf(0.0, 1.0 - cos_t * cos_t))
		var phi := _rng.randf() * TAU
		out.append((forward * cos_t + (side * cos(phi) + up * sin(phi)) * sin_t).normalized())
	return out


## Respawn: full feed, base spread, trigger reset.
func reset() -> void:
	feed.refill()
	spread_deg = def.spread_base_deg
	_trigger_released = true
