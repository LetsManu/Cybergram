class_name WardlingModel
extends Node3D
## Wardling model. Wardling v2 (owner redesign 2026-10-06): when the rigged
## mini-soldier is built, a WardlingRig (hero rig: walk / run / shoot / hit /
## death, bone-attached tier and class props) is used; the Picket below is the
## fallback. Picket: Phase 6, the hero-pipeline bake (tools/art/world/picket.py,
## picket_c = Concord porcelain, picket_s = Syndicate iron) with the heroes' toon
## material; the procedural WardlingModelBuilder meshes are the fallback when the
## glb is missing. Shared meshes, one material per (faction, team). States: tier
## I-III (silhouette + scale), class marking (owner sash / Vanguard pennant),
## Elite (gold threads + spindle, x1.3) and Turned (violet ring). Hover-skip legs
## while moving. Faces -Z.

## Baked faction skins (art bible §5.3: Concord porcelain + gold, Syndicate iron + brass).
const BAKED_KEYS := {ModelPalette.TEAM_SYNDICATE: &"picket_s"}
const BAKED_DEFAULT: StringName = &"picket_c"

var key: StringName = &"picket"
var tier: int = 1
var team: int = ModelPalette.TEAM_NEUTRAL
## 0 = Vanguard (pennant), 1 = someone's squad (sash), 2 = own squad (bright sash + ring).
var owner_kind: int = 1
var elite: bool = false
var turned: bool = false
## False when the owner (WardlingView) already applies the Elite x1.3 scale.
var apply_elite_scale: bool = true

var _hover: Node3D
var _body: MeshInstance3D
var _legs: Array[Node3D] = []
var _sash: MeshInstance3D
var _pennant: MeshInstance3D
var _elite_mi: MeshInstance3D
var _ring: MeshInstance3D
var _moving: bool = false
var _t: float = 0.0
var _last_pos := Vector3.INF
var _tier_mi: MeshInstance3D
## The baked skin in use (&"" = procedural fallback).
var baked_key: StringName = &""

## Wardling v2 rig (null = the Picket fallback is in use).
var rig: WardlingRig
## Smoothed world velocity from the interpolated position (drives walk / run).
var velocity: Vector3 = Vector3.ZERO
## Seconds between animation-LOD distance checks (WardlingRig.update_lod).
const LOD_CHECK_S: float = 0.25
var _lod_t: float = 0.0

## key -> {piece name -> Mesh}, read once from the glb.
static var _baked: Dictionary = {}


func setup(model_key: StringName, tier_: int, team_: int) -> void:
	key = model_key
	name = "WardlingModel_%s" % key
	_t = randf() * TAU
	if WardlingRig.available(team_):
		rig = WardlingRig.new()
		add_child(rig)
		rig.setup(team_)
		team = team_
		set_tier(tier_)
		set_owner_kind(1)
		return
	_hover = Node3D.new()
	add_child(_hover)
	_body = _mi(_hover, null)
	_tier_mi = _mi(_hover, null)
	_tier_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in [1.0, -1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.11 * s, 0.25, 0.0)
		_hover.add_child(leg)
		_mi(leg, WardlingModelBuilder.mesh("leg"))
		_legs.append(leg)
	_sash = _mi(_hover, WardlingModelBuilder.mesh("sash"))
	_pennant = _mi(_hover, WardlingModelBuilder.mesh("pennant"))
	_elite_mi = _mi(_hover, WardlingModelBuilder.mesh("elite"))
	_ring = _mi(self, WardlingModelBuilder.mesh("ring"))
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_tier(tier_)
	set_team(team_)
	set_owner_kind(1)
	set_elite(false)
	set_turned(false)


## The baked skin for `team`, or &"" when its glb is not built.
static func baked_key_for(team_: int) -> StringName:
	var k: StringName = BAKED_KEYS.get(team_, BAKED_DEFAULT)
	return k if WorldModel.exists(k) else &""


## Piece `name` of the baked skin `k` (meshes shared by every Wardling).
static func baked_mesh(k: StringName, name_: String) -> Mesh:
	if not _baked.has(k):
		var pieces := {}
		var inst := (load(WorldModel.glb_path(k)) as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			pieces[String(mi.name)] = (mi as MeshInstance3D).mesh
		inst.free()
		_baked[k] = pieces
	return (_baked[k] as Dictionary).get(name_)


func set_team(team_: int) -> void:
	team = team_
	if rig != null:
		rig.set_team(team_)
		set_tier(tier)
		set_owner_kind(owner_kind)
		return
	baked_key = baked_key_for(team)
	var m: Material = WorldModel.material(baked_key, team) if baked_key != &"" else ModelMaterials.toon(team)
	for mi in [_body, _tier_mi, _sash, _pennant, _elite_mi]:
		(mi as MeshInstance3D).material_override = m
	for leg in _legs:
		var lm := leg.get_child(0) as MeshInstance3D
		lm.material_override = m
		lm.mesh = baked_mesh(baked_key, "leg_r" if leg.position.x > 0.0 else "leg_l") if baked_key != &"" else WardlingModelBuilder.mesh("leg")
	_ring.material_override = ModelMaterials.toon(team)
	_pennant.mesh = _part("pennant")
	_elite_mi.mesh = _part("elite")
	set_tier(tier)
	set_owner_kind(owner_kind)


func _part(name_: String) -> Mesh:
	return baked_mesh(baked_key, name_) if baked_key != &"" else WardlingModelBuilder.mesh(name_)


func set_tier(tier_: int) -> void:
	tier = clampi(tier_, 1, 3)
	if rig != null:
		rig.set_tier(tier)
		_apply_scale()
		return
	if baked_key != &"":
		_body.mesh = baked_mesh(baked_key, "body")
		_tier_mi.mesh = baked_mesh(baked_key, "tier%d" % tier) if tier > 1 else null
	else:
		_body.mesh = WardlingModelBuilder.mesh("body%d" % tier)
		_tier_mi.mesh = null
	_tier_mi.visible = _tier_mi.mesh != null
	_apply_scale()


func set_owner_kind(kind: int) -> void:
	owner_kind = kind
	if rig != null:
		rig.set_marks(kind, turned, elite)
		return
	_pennant.visible = kind == 0 and not turned
	_sash.visible = kind != 0 or turned
	_sash.mesh = _part("sash_own" if kind == 2 else "sash")


func set_elite(on: bool) -> void:
	elite = on
	if rig != null:
		set_owner_kind(owner_kind)
	else:
		_elite_mi.visible = on
	_apply_scale()


func set_turned(on: bool) -> void:
	turned = on
	if _ring == null and on:  # the rig has no violet ring of its own: the shared procedural one
		_ring = _mi(self, WardlingModelBuilder.mesh("ring"))
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.material_override = ModelMaterials.toon(team)
	if _ring != null:
		_ring.visible = on
	set_owner_kind(owner_kind)


## What is shown (tests, debugging): pennant / sash / own sash / Elite / tier pieces.
func marks() -> Dictionary:
	if rig != null:
		return {"pennant": rig.prop(&"pennant").visible, "sash": rig.prop(&"sash").visible or rig.prop(&"sash_own").visible,
			"elite": rig.prop(&"elite").visible, "tier2": rig.prop(&"crest").visible, "tier3": rig.prop(&"crown").visible}
	return {"pennant": _pennant.visible, "sash": _sash.visible, "elite": _elite_mi.visible,
		"tier2": tier >= 2, "tier3": tier >= 3}


## Combat hooks (WardlingView): a shot, a hit (attacker position, INF = unknown),
## death (plays the fall; the view frees the model after it), fade 1..0.
func shoot() -> void:
	if rig != null:
		rig.shoot()


func hit(from_world: Vector3 = Vector3.INF) -> void:
	if rig != null:
		rig.hit(from_world)


func die(from_world: Vector3 = Vector3.INF) -> void:
	if rig != null:
		rig.die(from_world)


func set_fade(alpha: float) -> void:
	if rig != null:
		rig.set_fade(alpha)
	else:
		visible = alpha > 0.05


func set_moving(on: bool) -> void:
	_moving = on


func _apply_scale() -> void:
	scale = Vector3.ONE * WardlingModelBuilder.SCALE_BY_TIER[tier - 1] * (WardlingModelBuilder.ELITE_SCALE if elite and apply_elite_scale else 1.0)


func triangle_count() -> int:
	if rig != null:
		return rig.triangle_count()
	var n := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).visible and (mi as MeshInstance3D).mesh != null:
			n += _tris((mi as MeshInstance3D).mesh)
	return n


func mesh_instance_count() -> int:
	if rig != null:
		return rig.mesh_instance_count()
	return find_children("*", "MeshInstance3D", true, false).size()


static func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _process(delta: float) -> void:
	_t += delta
	if rig != null:
		if is_inside_tree():
			if _last_pos != Vector3.INF and delta > 0.0:
				var v := (global_position - _last_pos) / delta
				velocity = velocity.lerp(Vector3(v.x, 0.0, v.z), 1.0 - exp(-12.0 * delta))
			_last_pos = global_position
		rig.set_velocity(velocity)
		_lod_t -= delta
		if _lod_t <= 0.0 and is_inside_tree():
			_lod_t = LOD_CHECK_S
			var cam := get_viewport().get_camera_3d()
			if cam != null:
				rig.update_lod(cam.global_position.distance_to(global_position))
		return
	if is_inside_tree() and _last_pos != Vector3.INF:
		var v := (global_position - _last_pos) / maxf(delta, 1e-4)
		if v.length() > 0.4:
			_moving = true
	if is_inside_tree():
		_last_pos = global_position
	var hop := absf(sin(_t * 7.0)) * 0.06 if _moving else 0.0
	_hover.position.y = 0.03 + sin(_t * 2.2) * 0.015 + hop
	var sw := sin(_t * 7.0) * 0.6 if _moving else 0.0
	_legs[0].rotation.x = sw
	_legs[1].rotation.x = -sw
	_hover.rotation.x = -0.12 if _moving else 0.0
	_moving = false


func _mi(parent: Node3D, mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mesh != null:  # only the body shell casts a shadow (cheap at ~100 on screen)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
