class_name HeroModel
extends Node3D
## A stylised stand-in hero built in code (HeroModelBuilder): an articulated
## node tree of pivots (hips, spine, head, arms, legs + hook extras), each
## with one merged mesh. No skeleton: a procedural layer rotates the pivots —
## idle breathing, a walk cycle from velocity, crouch, look pitch, a hit
## flinch — and a 2-bone IK keeps both hands on the held weapon.
## Faces -Z like HeroView. Presentation only; replaceable by a real glb that
## exposes the same markers (HAND_R_weapon, HEAD_nameplate, BACK_attach).

## Model key (ModelCatalog.HERO_KEYS).
var key: StringName = &""
var team: int = ModelPalette.TEAM_NEUTRAL
## Standing height (m).
var height_m: float = 1.8
## Held third-person weapon (null if none).
var weapon: WeaponModel

var _bp: Dictionary = {}
var _pivots: Dictionary = {}  # name -> Node3D
var _markers: Dictionary = {}  # name -> Marker3D
var _mats: Array = []  # [MeshInstance3D, descriptor String]
var _anim: Array = []  # extras: [Node3D, kind, speed, amount, base_rot, phase]
var _vel_local := Vector3.ZERO
var _crouch: float = 0.0
var _crouch_target: float = 0.0
var _pitch: float = 0.0
var _phase: float = 0.0
var _time: float = 0.0
var _flinch: float = 0.0
var _flinch_side: float = 1.0
var _speed_s: float = 0.0
var _hips_y: float = 0.0
var _lean: float = 0.0


## Instantiates the blueprint (shared meshes) for `team_`.
func build_from(bp: Dictionary, team_: int) -> void:
	_bp = bp
	key = bp.key
	height_m = bp.height
	_hips_y = bp.hips_y
	_lean = bp.get("lean", 0.0)
	name = "HeroModel_%s" % key
	_pivots[&"root"] = self
	for p in bp.pivots:
		var n := Node3D.new()
		n.name = String(p.name)
		n.position = p.pos
		n.rotation = p.get("rot", Vector3.ZERO)
		(_pivots[p.parent] as Node3D).add_child(n)
		_pivots[p.name] = n
		if p.has("anim"):
			var a: Array = p.anim
			_anim.append([n, a[0], a[1], a[2], n.rotation, n.position, randf() * TAU])
	for k in bp.meshes:
		var parts := (k as String).split("|")
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + parts[1].replace(":", "_").replace("#", "")
		mi.mesh = bp.meshes[k]
		(_pivots[StringName(parts[0])] as Node3D).add_child(mi)
		if parts[1] != "toon":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mats.append([mi, parts[1]])
	for mk in bp.markers:
		var d: Array = bp.markers[mk]
		var m := Marker3D.new()
		m.name = String(mk)
		m.position = d[1]
		(_pivots[d[0]] as Node3D).add_child(m)
		_markers[mk] = m
	if bp.weapon_key != &"":
		weapon = WeaponModelBuilder.build(bp.weapon_key, false, team_)
		weapon.scale = Vector3.ONE * bp.get("weapon_scale", 1.0)
		weapon.rotation = bp.get("weapon_rot", Vector3.ZERO)
		(_markers[&"HAND_R_weapon"] as Node3D).add_child(weapon)
	set_team(team_)
	_apply_pose(0.0)


func pivot(pivot_name: StringName) -> Node3D:
	return _pivots.get(pivot_name)


func marker(marker_name: StringName) -> Marker3D:
	return _markers.get(marker_name)


func marker_names() -> Array:
	return _markers.keys()


## Re-materials every part for `team_` (shared per-team materials).
func set_team(team_: int, enemy_outline: bool = false) -> void:
	team = team_
	var tc := ModelPalette.team_color(team)
	for e in _mats:
		var mi: MeshInstance3D = e[0]
		var d: String = e[1]
		mi.material_override = material_for(d, team, enemy_outline)
	if weapon != null:
		weapon.set_team(team, enemy_outline)
	set_meta(&"team_tint", tc)


## Material for a blueprint descriptor: "toon", "holo", "holo_panel",
## "mana_team", "mana:<hex>:<energy>", "holo:<hex>".
static func material_for(d: String, team_: int, enemy_outline: bool = false) -> Material:
	var tc := ModelPalette.team_color(team_)
	if d == "toon":
		return ModelMaterials.toon(team_, false, enemy_outline)
	if d == "holo":
		return ModelMaterials.holo(tc, 0.9)
	if d == "holo_panel":
		return ModelMaterials.holo(tc, 0.95, true)
	if d == "mana_team":
		return ModelMaterials.crystal(tc, 1.6, 4.0, 0.6)
	if d.begins_with("mana:"):
		var p := d.split(":")
		return ModelMaterials.crystal(Color(p[1]), float(p[2]), 4.0, 0.4)
	if d.begins_with("holo:"):
		return ModelMaterials.holo(Color(d.split(":")[1]), 0.85)
	return ModelMaterials.toon(team_)


## Velocity in WORLD space (m/s), crouch state and look pitch (rad, + = up).
func set_motion(velocity_world: Vector3, crouching: bool, pitch: float) -> void:
	var gb := global_transform.basis if is_inside_tree() else transform.basis
	_vel_local = gb.inverse() * Vector3(velocity_world.x, 0.0, velocity_world.z)
	_crouch_target = 1.0 if crouching else 0.0
	_pitch = clampf(pitch, -1.3, 1.3)


## Hit flinch impulse (0..1), decays over ~0.3 s.
func flinch(strength: float = 1.0) -> void:
	_flinch = clampf(maxf(_flinch, strength), 0.0, 1.0)
	_flinch_side = -_flinch_side


func triangle_count() -> int:
	var n: int = _bp.get("tris", 0)
	if weapon != null:
		n += weapon.triangle_count()
	return n


func mesh_instance_count() -> int:
	return _mats.size() + (weapon.mesh_instance_count() if weapon != null else 0)


func _process(delta: float) -> void:
	_apply_pose(delta)


## One animation step (public for tests / the showcase's fixed poses).
func _apply_pose(delta: float) -> void:
	_time += delta
	_crouch = move_toward(_crouch, _crouch_target, delta * 6.0)
	_flinch = maxf(0.0, _flinch - delta * 3.5)
	var speed := Vector2(_vel_local.x, _vel_local.z).length()
	_speed_s = lerpf(_speed_s, speed, clampf(delta * 10.0, 0.0, 1.0))
	var stride: float = _bp.get("stride", 1.0)
	var walk := clampf(_speed_s / 6.0, 0.0, 1.0)
	_phase = fmod(_phase + delta * (_speed_s / maxf(stride, 0.1)) * PI, TAU)
	var fwd := -_vel_local.z / maxf(speed, 0.001) if speed > 0.2 else 1.0
	var side := _vel_local.x / maxf(speed, 0.001) if speed > 0.2 else 0.0
	var s := sin(_phase)
	var hips: Node3D = _pivots[&"hips"]
	var spine: Node3D = _pivots[&"spine"]
	var head: Node3D = _pivots[&"head"]
	var c := _crouch
	var crouch_base: float = _bp.get("crouch_base", 0.0)
	var ck := maxf(c, crouch_base)
	# Legs: swing forward/back along the travel direction, knees bend on the lift.
	var swing := 0.55 * walk
	var thigh_crouch := 1.05 * ck
	var shin_crouch := -1.7 * ck
	for i in 2:
		var sg := 1.0 if i == 0 else -1.0
		var leg: Node3D = _pivots[&"leg_l" if i == 0 else &"leg_r"]
		var shin: Node3D = _pivots[&"shin_l" if i == 0 else &"shin_r"]
		var ph := s * sg
		leg.rotation = Vector3(thigh_crouch + ph * swing * fwd, 0.0, ph * swing * side * 0.6)
		var lift := maxf(0.0, cos(_phase + (0.0 if i == 0 else PI))) * 0.9 * walk
		shin.rotation = Vector3(shin_crouch - lift, 0.0, 0.0)
	var l1: float = _bp.thigh
	var l2: float = _bp.shin
	var drop := (l1 + l2) - (l1 * cos(thigh_crouch) + l2 * cos(thigh_crouch + shin_crouch))
	var bob := absf(cos(_phase)) * 0.035 * walk + sin(_time * 1.8) * 0.006
	hips.position.y = _hips_y - drop + bob
	hips.rotation = Vector3(0.0, s * 0.12 * walk * fwd, 0.0)
	# Torso: lean, breathing, pitch share, flinch.
	var breathe := sin(_time * 1.8) * 0.015
	spine.rotation = Vector3(_lean - 0.25 * ck - 0.08 * walk + _pitch * 0.3 + breathe - _flinch * 0.32,
		-hips.rotation.y, _flinch * 0.18 * _flinch_side)
	head.rotation = Vector3(_pitch * 0.45 - (_lean - 0.25 * ck) * 0.6 + _flinch * 0.35, 0.0, -_flinch * 0.2 * _flinch_side)
	var aim: Node3D = _pivots.get(&"aim")
	if aim != null:
		aim.rotation = Vector3(_pitch * 0.7 - (_lean - 0.25 * ck) * 0.8 + 0.08 * walk, 0.0, 0.0)
		aim.position = _bp.aim_pos + Vector3(0.0, sin(_phase * 2.0) * 0.012 * walk, 0.0)
	# Extras (halo spindles, scarf tails, rings, panels).
	for a in _anim:
		var n: Node3D = a[0]
		var r0: Vector3 = a[4]
		var p0: Vector3 = a[5]
		match a[1]:
			&"spin_y":
				n.rotation = Vector3(r0.x, r0.y + _time * a[2], r0.z)
			&"spin_z":
				n.rotation = Vector3(r0.x, r0.y, r0.z + _time * a[2])
			&"bob":
				n.position = p0 + Vector3(0.0, sin(_time * a[2] + a[6]) * a[3], 0.0)
			&"sway":
				# Cloth: trails back with speed, ripples.
				n.rotation = r0 + Vector3(-walk * a[3] * fwd - sin(_time * a[2] + a[6]) * 0.06 * (1.0 + walk),
					0.0, sin(_time * a[2] * 0.7 + a[6]) * 0.05 - side * walk * a[3] * 0.5)
			&"orbit":
				n.rotation = Vector3(r0.x, r0.y + _time * a[2], r0.z)
				n.position = p0 + Vector3(0.0, sin(_time * 2.0 + a[6]) * a[3], 0.0)
	_solve_arms()


## Places both arms with a 2-bone IK onto the weapon grips (spine space).
func _solve_arms() -> void:
	var spine: Node3D = _pivots[&"spine"]
	var targets := {}
	if weapon != null:
		var inv := spine.global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
		if is_inside_tree():
			targets[&"r"] = inv * weapon.grip_r_global()
			targets[&"l"] = inv * weapon.grip_l_global()
		else:
			return
	for side in [&"l", &"r"]:
		var arm: Node3D = _pivots[StringName("arm_" + side)]
		var fore: Node3D = _pivots[StringName("fore_" + side)]
		if not targets.has(side):
			continue
		var sg := -1.0 if side == &"l" else 1.0
		_ik(arm, fore, targets[side], Vector3(sg * 0.8, -1.0, 0.35).normalized())


func _ik(arm: Node3D, fore: Node3D, target: Vector3, pole: Vector3) -> void:
	var l1: float = _bp.upper_arm
	var l2: float = _bp.forearm
	var sp := arm.position
	var to := target - sp
	var d := clampf(to.length(), 0.05, (l1 + l2) * 0.999)
	var dir := to.normalized()
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var bend := (pole - dir * pole.dot(dir))
	if bend.length() < 1e-4:
		bend = Vector3(0, -1, 0)
	bend = bend.normalized()
	var elbow := sp + dir * ca * l1 + bend * sqrt(1.0 - ca * ca) * l1
	var hand := sp + dir * d
	var b_arm := _bone_basis(elbow - sp, bend)
	var b_fore := _bone_basis(hand - elbow, bend)
	arm.basis = b_arm
	fore.basis = b_arm.inverse() * b_fore


## Basis whose -Y points along `d` (limbs hang along -Y).
static func _bone_basis(d: Vector3, hint: Vector3) -> Basis:
	var y := -d.normalized()
	var z := hint - y * hint.dot(y)
	if z.length() < 1e-4:
		z = Vector3(0, 0, 1) - y * y.z
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)
