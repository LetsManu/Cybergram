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
## Scales the per-shot spread bloom (Ryker Overdrive: 0.5 = -50 % recoil).
var recoil_mult: float = 1.0
## Armory v2 item stats (items-and-armory.md §3.5, §4.3), combined with the
## skill buffs above, never overwriting them: interval / (rate_mult × item_rate_mult);
## cone (base, bloom, max) × spread_mult. Written by apply_item_stats().
var item_rate_mult: float = 1.0
var spread_mult: float = 1.0
## Signature passives (items-and-armory.md §3.5.3), written each tick by
## SignaturePassives: Overdrive Loop bloom (-40%) and pellet cone (-10%).
var passive_bloom_mult: float = 1.0
var passive_cone_mult: float = 1.0
## Tick of the latest shot and its index in the current burst (0 = first).
var shot_tick: int = 0
var burst_index: int = 0

var _interval: float
var _next_fire_tick: float = 0.0
var _last_shot_tick: int = -1000000
var _trigger_released: bool = true
var _recovery_delay_ticks: int
var _recovery_per_tick: float
var _seed: int
var _burst_left: int = 0
var _next_burst_tick: float = 0.0
var _burst_interval: float = 0.0


func _init(weapon: WeaponDef, tick_rate_hz: int, rng_seed: int) -> void:
	def = weapon
	feed = AmmoFeed.create(weapon, tick_rate_hz)
	_interval = weapon.fire_interval_ticks(tick_rate_hz)
	_recovery_delay_ticks = roundi(weapon.spread_recovery_delay_s * tick_rate_hz)
	_seed = rng_seed
	if weapon.burst_size > 1:
		_burst_interval = tick_rate_hz / weapon.burst_rate
		_interval = tick_rate_hz * weapon.burst_cycle_s
	spread_deg = weapon.spread_base_deg
	_recovery_per_tick = weapon.spread_recovery_deg_s / tick_rate_hz


## Reads the hero's item stats: M_rate (capped, §3.7; beams convert it to tick
## damage so their interval is unchanged) and SPREAD_MULT. Null = v1 defaults.
func apply_item_stats(stats: StatBlock) -> void:
	if stats == null:
		item_rate_mult = 1.0
		spread_mult = 1.0
		return
	item_rate_mult = item_rate_mult_for(def, stats.get_value(StatCatalog.FIRE_RATE_BONUS))
	spread_mult = stats.get_value(StatCatalog.SPREAD_MULT)


## 1 + min(cap, M_rate) for `weapon`, 1.0 for beams (DamageMath.weapon_hit_mult
## puts their M_rate on the tick damage). Shared with client prediction.
static func item_rate_mult_for(weapon: WeaponDef, m_rate: float) -> float:
	var r := DamageMath.rules()
	if r.is_beam(weapon):
		return 1.0
	return 1.0 + clampf(m_rate, 0.0, r.fire_rate_cap)


## Effective fire-rate multiplier (skill buff × items).
func total_rate_mult() -> float:
	return maxf(rate_mult * item_rate_mult, 0.01)


func _spread_base() -> float:
	return def.spread_base_deg * spread_mult * passive_cone_mult


func _spread_max() -> float:
	return def.spread_max_deg * spread_mult * passive_cone_mult


## One tick with `cmd`. `allowed` is false while sprinting, stunned, etc.
## Returns true if a shot was fired this tick.
func step(cmd: InputCommand, tick: int, allowed: bool) -> bool:
	feed.step(tick)
	if tick - _last_shot_tick > _recovery_delay_ticks:
		spread_deg = maxf(_spread_base(), spread_deg - _recovery_per_tick)
	spread_deg = clampf(spread_deg, _spread_base(), _spread_max())
	if cmd.has(InputCommand.BTN_RELOAD):
		feed.request_reload(tick)
	var held := cmd.has(InputCommand.BTN_FIRE)
	var fired := false
	var in_burst := _burst_left > 0
	if in_burst:
		# A started burst completes without the trigger; it breaks when the gun cannot fire.
		if not allowed or not feed.can_fire():
			_burst_left = 0
		elif tick + 1e-4 >= _next_burst_tick:
			_burst_left -= 1
			_next_burst_tick += _burst_interval / total_rate_mult()
			_shoot(tick, def.burst_size - 1 - _burst_left)
			fired = true
	elif held and allowed and (_trigger_released or not def.semi_auto) \
			and tick + 1e-4 >= _next_fire_tick and feed.can_fire():
		if tick > _next_fire_tick + 1.0:
			_next_fire_tick = tick  # idle: no banked shots
		_next_fire_tick += _interval / total_rate_mult()
		if def.burst_size > 1:
			_burst_left = def.burst_size - 1
			_next_burst_tick = tick + _burst_interval / total_rate_mult()
		_shoot(tick, 0)
		_trigger_released = false
		fired = true
	if not held:
		_trigger_released = true
	return fired


func _shoot(tick: int, index: int) -> void:
	feed.consume(tick)
	_last_shot_tick = tick
	shot_tick = tick
	burst_index = index
	shot_spread_deg = spread_deg
	spread_deg = minf(_spread_max(), spread_deg + def.spread_bloom_deg * recoil_mult * spread_mult * passive_bloom_mult)
	shots_fired += 1


## Deterministic uniform float in [0, 1): integer hash of (seed, shot tick, salt).
## Stateless, so server, prediction and replays agree for the same inputs.
func _hash01(salt: int) -> float:
	var x: int = (_seed * 0x9E3779B1 + shot_tick * 0x85EBCA6B + salt * 0xC2B2AE35 + 0x165667B1) & 0xFFFFFFFF
	x = ((x ^ (x >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	x = ((x ^ (x >> 12)) * 0x297A2D39) & 0xFFFFFFFF
	x = x ^ (x >> 15)
	return float(x & 0xFFFFFF) / 16777216.0


## Pellet directions for the latest shot: uniform inside a cone of
## shot_spread_deg around `forward` (unit vector). Deterministic per (seed, shot tick, pellet).
func pellet_directions(forward: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cos_max := cos(deg_to_rad(shot_spread_deg))
	var side := forward.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = forward.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(forward).normalized()
	for i in def.pellets:
		var cos_t := lerpf(1.0, cos_max, _hash01(i * 2))
		var sin_t := sqrt(maxf(0.0, 1.0 - cos_t * cos_t))
		var phi := _hash01(i * 2 + 1) * TAU
		out.append((forward * cos_t + (side * cos(phi) + up * sin(phi)) * sin_t).normalized())
	return out


## Respawn: full feed, base spread, trigger reset.
func reset() -> void:
	feed.refill()
	spread_deg = _spread_base()
	_trigger_released = true
	_burst_left = 0
