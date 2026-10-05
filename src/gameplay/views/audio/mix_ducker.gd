class_name MixDucker
extends RefCounted
## W21-A1: code-driven ducks (pure logic). The Voice duck is the side-chain
## compressor on Music / Ambient (GameSettings.ensure_buses); this adds
##  * Ambient ambient_weapon_duck_db while a weapon fired within weapon_duck_radius_m,
##  * Music music_big_moment_db for big_moment_hold_s after a big moment,
## gliding with duck_attack_s / duck_release_s (dB per second derived from them).

var def: AudioMixDef
var music_db: float = 0.0
var ambient_db: float = 0.0
var _weapon_left: float = 0.0
var _big_left: float = 0.0


func _init(mix_def: AudioMixDef = null) -> void:
	def = mix_def if mix_def != null else AudioMixDef.new()


## A weapon fired `distance_m` from the listener.
func note_weapon(distance_m: float) -> void:
	if distance_m <= def.weapon_duck_radius_m:
		_weapon_left = def.weapon_duck_hold_s


func note_big_moment() -> void:
	_big_left = def.big_moment_hold_s


func step(dt: float) -> void:
	_weapon_left = maxf(_weapon_left - dt, 0.0)
	_big_left = maxf(_big_left - dt, 0.0)
	ambient_db = _glide(ambient_db, def.ambient_weapon_duck_db if _weapon_left > 0.0 else 0.0, dt)
	music_db = _glide(music_db, def.music_big_moment_db if _big_left > 0.0 else 0.0, dt)


func _glide(cur: float, target: float, dt: float) -> float:
	var span := maxf(absf(def.ambient_weapon_duck_db), absf(def.music_big_moment_db))
	var t := def.duck_attack_s if target < cur else def.duck_release_s
	return move_toward(cur, target, span * dt / maxf(t, 0.001))
