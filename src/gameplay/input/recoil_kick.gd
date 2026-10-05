class_name RecoilKick
extends RefCounted
## Client-side view punch (W11-C1), from WeaponDef.recoil_* fields. The kick is
## added to the view angles (camera + the aim sent in the InputCommand) and
## recovers over time. It never touches server state: hit resolution uses the
## server's own deterministic spread bloom (WeaponSim), so a kick cannot desync.
## Shots are predicted locally from held fire + ammo + the weapon's fire rate
## (a visual approximation; the server decides the real shots).

## Current kick in radians: x = yaw (+ left), y = pitch (+ up).
var kick: Vector2 = Vector2.ZERO
var shots: int = 0
var _cooldown_s: float = 0.0
var _idle_s: float = 0.0
var _was_firing: bool = false
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## One tick step (shots only; call recover() every rendered frame). `mult` is the replicated recoil multiplier (Overdrive 0.5).
## Returns true when a shot kicked the view.
func tick(firing: bool, can_fire: bool, def: WeaponDef, dt: float, mult: float = 1.0) -> bool:
	_cooldown_s = maxf(0.0, _cooldown_s - dt)
	var kicked := false
	var edge := firing and not _was_firing
	_was_firing = firing
	if def != null and firing and can_fire and _cooldown_s <= 0.0 and (edge or not def.semi_auto):
		_cooldown_s = 1.0 / maxf(def.fire_rate, 0.1)
		_idle_s = 0.0
		shots += 1
		kicked = true
		var m := maxf(mult, 0.0)
		kick.y += deg_to_rad(def.recoil_v) * m
		kick.x += deg_to_rad(_rng.randf_range(-1.0, 1.0) * def.recoil_h) * m
		var cap := deg_to_rad(def.recoil_max_deg)
		if kick.length() > cap:
			kick = kick.normalized() * cap
	return kicked


## Pulls the kick back toward zero (after the recovery delay).
func recover(dt: float, def: WeaponDef) -> void:
	if kick == Vector2.ZERO:
		return
	_idle_s += dt
	var delay := def.recoil_recovery_delay_s if def != null else 0.0
	if _idle_s < delay:
		return
	var rate := deg_to_rad(def.recoil_recovery_deg_s if def != null else 14.0) * dt
	kick = Vector2.ZERO if kick.length() <= rate else kick - kick.normalized() * rate


func reset() -> void:
	kick = Vector2.ZERO
	_cooldown_s = 0.0
	_idle_s = 0.0
	_was_firing = false
