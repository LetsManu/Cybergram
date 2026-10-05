class_name SpreadModel
extends RefCounted
## Client-side mirror of WeaponSim's deterministic spread cone (W16-COMFORT,
## dynamic crosshair). WeaponSim is server-only; its spread is a pure function of
## the shot sequence, so the client reproduces it from the shots RecoilKick
## already predicts: starts at spread_base_deg; each shot adds spread_bloom_deg x
## recoil multiplier up to spread_max_deg; recovers at spread_recovery_deg_s once
## more than spread_recovery_delay_s has passed since the last shot (same order
## as WeaponSim.step: recovery first, then the shot). Presentation only.
##
## Reset on respawn and weapon swap. A reload does NOT reset it (WeaponSim does
## not either; parity with the server wins). If predicted shots never show up in
## the replicated ammo (blocked / dropped), reconcile() resets to the base cone.

## Current cone half-angle (degrees).
var spread_deg: float = 0.0
var def: WeaponDef
var recoil_mult: float = 1.0
## How long (s) predicted shots may go without an ammo drop before the model
## trusts the server and falls back to the base cone.
const UNCONFIRMED_S: float = 0.5

var _tick: int = 0
var _last_shot_tick: int = -1000000
var _recovery_delay_ticks: int = 0
var _recovery_per_tick: float = 0.0
var tick_rate_hz: int = 60
var _unconfirmed_s: float = 0.0
var _ammo_at_shot: float = -1.0
var _pending_shots: int = 0


func _init(weapon: WeaponDef = null, hz: int = 60) -> void:
	tick_rate_hz = maxi(hz, 1)
	set_weapon(weapon, true)


## Switches weapon (null clears). A different weapon resets the cone.
func set_weapon(weapon: WeaponDef, force: bool = false) -> void:
	if weapon == def and not force:
		return
	def = weapon
	if def != null:
		_recovery_delay_ticks = roundi(def.spread_recovery_delay_s * tick_rate_hz)
		_recovery_per_tick = def.spread_recovery_deg_s / tick_rate_hz
	reset()


## Respawn / weapon swap: base cone, no recent shot.
func reset() -> void:
	spread_deg = def.spread_base_deg if def != null else 0.0
	_last_shot_tick = -1000000
	_pending_shots = 0
	_unconfirmed_s = 0.0
	_ammo_at_shot = -1.0


## One tick (mirror of WeaponSim.step). `fired` = a shot was predicted this tick.
func step(fired: bool) -> void:
	if def == null:
		return
	if _tick - _last_shot_tick > _recovery_delay_ticks:
		spread_deg = maxf(def.spread_base_deg, spread_deg - _recovery_per_tick)
	if fired:
		_last_shot_tick = _tick
		spread_deg = minf(def.spread_max_deg, spread_deg + def.spread_bloom_deg * recoil_mult)
		_pending_shots += 1
	_tick += 1


## Called with the replicated ammo each snapshot (`dt` since the last call).
## Predicted shots without any ammo drop for UNCONFIRMED_S: they did not happen.
func reconcile(ammo: float, dt: float) -> void:
	if _pending_shots <= 0:
		_ammo_at_shot = ammo
		_unconfirmed_s = 0.0
		return
	if _ammo_at_shot < 0.0:
		_ammo_at_shot = ammo
	if ammo < _ammo_at_shot:  # the server spent ammo: shots are real
		_pending_shots = 0
		_ammo_at_shot = ammo
		_unconfirmed_s = 0.0
		return
	_unconfirmed_s += dt
	if _unconfirmed_s >= UNCONFIRMED_S:
		reset()


## Screen radius (pixels) of the cone for a camera with vertical `fov_deg` in a
## viewport `viewport_h` px tall: tan(spread) / tan(fov / 2) x half the height.
static func screen_radius_px(spread_deg_: float, fov_deg: float, viewport_h: float) -> float:
	var tan_v := tan(deg_to_rad(clampf(fov_deg, 30.0, 170.0)) * 0.5)
	return tan(deg_to_rad(spread_deg_)) / tan_v * viewport_h * 0.5
