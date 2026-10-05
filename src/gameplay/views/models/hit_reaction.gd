class_name HitReaction
extends SkeletonModifier3D
## Procedural additive hit reaction (W14-P2). Runs as a SkeletonModifier3D, so
## it is layered on top of the AnimationTree result every frame: a damped lean
## of Chest/Neck/Head away from the attacker, and a bigger, longer stagger
## (plus a Spine dip) on big hits. Presentation only; costs nothing while idle
## (the modifier deactivates itself when the reaction has decayed).

## Hits at or above this strength (0..1) stagger.
const STAGGER_AT: float = 0.85
const LEAN_RAD: float = 0.32
const STAGGER_MULT: float = 2.0
const DURATION_S: float = 0.35
const STAGGER_DURATION_S: float = 0.7
## Fraction of the lean taken by each bone.
const BONE_SHARE := {&"Spine": 0.0, &"Chest": 0.5, &"Neck": 0.25, &"Head": 0.5}
const STAGGER_SPINE_SHARE: float = 0.5

var _axis := Vector3.ZERO  # model-space rotation axis (unit)
var _amp: float = 0.0
var _t: float = 99.0
var _dur: float = DURATION_S
var _stagger: bool = false


## Pure mapping: attacker direction in model space (from the hero towards the
## attacker, forward = -Z) and strength 0..1 to the lean axis / angle.
## The body is pushed away from the attacker; `stagger` flags a big hit.
static func map_hit(dir_local: Vector3, strength: float) -> Dictionary:
	var d := Vector3(dir_local.x, 0.0, dir_local.z)
	if d.length() < 0.001:
		d = Vector3(0.0, 0.0, -1.0)  # unknown attacker: treat as frontal
	d = d.normalized()
	var push := -d
	var s := clampf(strength, 0.0, 1.0)
	var stagger := s >= STAGGER_AT
	return {
		"axis": Vector3(push.z, 0.0, -push.x),  # up x push: tips the torso towards `push`
		"angle": LEAN_RAD * s * (STAGGER_MULT if stagger else 1.0),
		"stagger": stagger,
		"duration": STAGGER_DURATION_S if stagger else DURATION_S,
	}


## Damped reaction envelope at time t (0 = impact): quick peak, small rebound.
static func envelope(t: float, duration: float) -> float:
	if t < 0.0 or t >= duration:
		return 0.0
	var u := t / duration
	return exp(-3.0 * u) * cos(u * 5.0)


func _ready() -> void:
	active = false


## Triggers a reaction. `dir_local` points from this hero to the attacker.
func hit(dir_local: Vector3, strength: float) -> void:
	var m := map_hit(dir_local, strength)
	if _t < _dur and _amp > m.angle:
		return  # a stronger reaction is still playing
	_axis = m.axis
	_amp = m.angle
	_dur = m.duration
	_stagger = m.stagger
	_t = 0.0
	active = true


func is_playing() -> bool:
	return _t < _dur


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_t += get_process_delta_time()
	var e := envelope(_t, _dur)
	if _t >= _dur:
		active = false
		return
	if _axis.length() < 0.001:
		return
	var ang := _amp * e
	var rot := Basis(_axis.normalized(), ang)
	for b in BONE_SHARE:
		var share: float = BONE_SHARE[b]
		if b == &"Spine" and _stagger:
			share = STAGGER_SPINE_SHARE
		var i := sk.find_bone(b)
		if i < 0 or share <= 0.0:
			continue
		var r := Basis(_axis.normalized(), ang * share)
		var p := sk.get_bone_parent(i)
		var pg := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
		var local := pg.inverse() * r * pg  # model-space rotation expressed in the parent frame
		sk.set_bone_pose_rotation(i, local.get_rotation_quaternion() * sk.get_bone_pose_rotation(i))
	var _unused := rot
