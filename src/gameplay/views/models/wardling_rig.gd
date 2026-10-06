class_name WardlingRig
extends Node3D
## Wardling v2 (owner redesign 2026-10-06, docs/assets/wardling.md): a rigged
## mini-soldier built on the hero pipeline (tools/art/hero_defs_wardling.py) and
## animated like a hero by a RiggedHeroModel: mocap walk / run blended by speed,
## shoot, hit reaction, death. Tier, class and Elite pieces are baked props
## (tools/art/world/wardling_props.py) attached to the skeleton's bones.
## WardlingModel uses this when the glbs are built (procedural Picket otherwise).
## Presentation only. Faces -Z.

## Faction skins (art bible §5.3): Concord porcelain + gold, Syndicate iron + brass.
const KEYS := {ModelPalette.TEAM_SYNDICATE: &"wardling_s"}
const KEY_DEFAULT: StringName = &"wardling_c"
const PROPS_KEY: StringName = &"wardling_props"
## Locomotion playback clamp: short legs at hero speeds (Wardlings run 6.5 m/s).
const LOCO_RATE_MAX: float = 5.5
## Hit reaction strength for a Wardling hit (a full flinch reads as a stagger).
const HIT_STRENGTH: float = 0.7
## Prop attachment: piece -> [bone, offset from the bone's rest origin, model space
## (Y up, -Z forward)]. "top" = the offset is from the helmet top (mesh height).
const PROPS := {
	&"crest": [&"Head", Vector3(0.0, -0.035, 0.01), true],
	&"crown": [&"Head", Vector3(0.0, -0.03, 0.01), true],
	&"elite": [&"Head", Vector3(0.0, 0.07, 0.0), true],
	&"sash": [&"Chest", Vector3(0.0, 0.0, 0.0), false],
	&"sash_own": [&"Chest", Vector3(0.0, 0.0, 0.0), false],
	&"pennant": [&"UpperChest", Vector3(0.0, 0.08, 0.13), false],
}
const PLATE_LIFT := Vector3(0.0, 0.035, 0.0)
## Animation LOD: camera distance (m) -> tree update stride (frames).
const ANIM_LOD := [[15.0, 1], [30.0, 2], [60.0, 4]]
const ANIM_LOD_FAR: int = 8
const OWN_RING_M: float = 0.55

var key: StringName = &""
var team: int = ModelPalette.TEAM_NEUTRAL
var body: RiggedHeroModel
var _props: Dictionary = {}
var _atts: Dictionary = {}  # bone name -> BoneAttachment3D
var _ring_own: MeshInstance3D

static var _ring_mats: Dictionary = {}


## The rigged skin for `team_`, or &"" when it is not built (or the props are missing).
static func key_for(team_: int) -> StringName:
	var k: StringName = KEYS.get(team_, KEY_DEFAULT)
	return k if HeroModelLoader.has_rigged(k) and WorldModel.exists(PROPS_KEY) else &""


## True when a rigged Wardling can be built for `team_`.
static func available(team_: int) -> bool:
	return key_for(team_) != &""


func setup(team_: int) -> void:
	name = "WardlingRig"
	_build(team_)


## Rebuilds the body when the faction skin changes; otherwise only re-tints.
func set_team(team_: int) -> void:
	if key_for(team_) != key:
		_build(team_)
		return
	team = team_
	body.set_team(team_)
	_tint_props()


## Tier II adds the shoulder plates and the crest; tier III the crystal crown.
func set_tier(tier_: int) -> void:
	for n in [&"plate_l", &"plate_r", &"crest"]:
		_show(n, tier_ >= 2)
	_show(&"crown", tier_ >= 3)
	_refresh_attachments()


## 0 = Vanguard (pennant), 1 = someone's squad (sash), 2 = own squad (knot + ring).
func set_marks(kind: int, turned: bool, elite: bool) -> void:
	_show(&"pennant", kind == 0 and not turned)
	_show(&"sash", kind == 1 or (turned and kind == 0))
	_show(&"sash_own", kind == 2)
	if _ring_own != null:
		_ring_own.visible = kind == 2
	_show(&"elite", elite)
	_refresh_attachments()


## Animation LOD stride for a camera `dist_m` away (pure; see ANIM_LOD).
static func anim_stride_for(dist_m: float) -> int:
	for e in ANIM_LOD:
		if dist_m < float(e[0]):
			return int(e[1])
	return ANIM_LOD_FAR


func update_lod(dist_m: float) -> void:
	body.set_anim_stride(anim_stride_for(dist_m))


## World-space velocity (m/s) drives walk / run (RiggedHeroModel blend space).
func set_velocity(v: Vector3) -> void:
	body.set_motion(v, false, 0.0)


func shoot() -> void:
	body.play_shoot()


## `from_world` = attacker position (Vector3.INF = unknown).
func hit(from_world: Vector3 = Vector3.INF) -> void:
	body.flinch(HIT_STRENGTH, from_world)


func die(from_world: Vector3 = Vector3.INF) -> void:
	body.set_death_dir(from_world)
	body.set_dead(true)


func set_fade(alpha: float) -> void:
	body.set_fade(alpha)
	for n in _props:
		(_props[n] as MeshInstance3D).transparency = 1.0 - alpha
	if _ring_own != null:
		_ring_own.transparency = 1.0 - alpha


func triangle_count() -> int:
	var n := body.triangle_count()
	for p in _props.values() + ([_ring_own] if _ring_own != null else []):
		var mi := p as MeshInstance3D
		if mi.visible and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				n += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func mesh_instance_count() -> int:
	return body.mesh_instance_count() + _props.size() + (1 if _ring_own != null else 0)


func prop(name_: StringName) -> MeshInstance3D:
	return _props.get(name_)


func _show(n: StringName, on: bool) -> void:
	if _props.has(n):
		(_props[n] as MeshInstance3D).visible = on


func _build(team_: int) -> void:
	for c in get_children():
		c.queue_free()
	_props.clear()
	_atts.clear()
	team = team_
	key = key_for(team_)
	body = HeroModelLoader.build(key, team_) as RiggedHeroModel
	body.loco_rate_max = LOCO_RATE_MAX
	add_child(body)
	var src := WorldModel.instantiate(PROPS_KEY, team_)
	var sk := body.skeleton
	var top := body.height_m
	for n: StringName in PROPS:
		var spec: Array = PROPS[n]
		var mi := WorldModel.piece(src, n)
		var idx := sk.find_bone(spec[0])
		if mi == null or idx < 0:
			continue
		var rest := sk.get_bone_global_rest(idx)
		var at: Vector3 = rest.origin + (spec[1] as Vector3)
		if spec[2]:
			at.y = top + (spec[1] as Vector3).y
		_attach(n, mi, idx, rest, at)
	# The shoulder plates go on whichever upper arm is on that side of the body.
	for b in [&"UpperArm_L", &"UpperArm_R"]:
		var idx := sk.find_bone(b)
		if idx < 0:
			continue
		var rest := sk.get_bone_global_rest(idx)
		var n: StringName = &"plate_r" if rest.origin.x > 0.0 else &"plate_l"
		var mi := WorldModel.piece(src, n)
		if mi != null:
			_attach(n, mi, sk.find_bone(&"Clavicle_" + String(b).right(1)), sk.get_bone_global_rest(
				sk.find_bone(&"Clavicle_" + String(b).right(1))), rest.origin + PLATE_LIFT)
	src.free()
	# Own squad ground ring: a flat team-neon torus (art bible §5.4, 0.55 m).
	_ring_own = MeshInstance3D.new()
	_ring_own.name = "RingOwn"
	var tm := TorusMesh.new()
	tm.inner_radius = OWN_RING_M - 0.04
	tm.outer_radius = OWN_RING_M
	tm.rings = 40
	tm.ring_segments = 3
	_ring_own.mesh = tm
	_ring_own.scale = Vector3(1.0, 0.25, 1.0)
	_ring_own.position.y = 0.02
	_ring_own.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_own.layers = GfxQuality.character_layers()
	_ring_own.material_override = _ring_mat(team_)
	add_child(_ring_own)
	set_tier(1)
	set_marks(1, false, false)


func _attach(n: StringName, mi: MeshInstance3D, bone: int, rest: Transform3D, at: Vector3) -> void:
	mi.get_parent().remove_child(mi)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = GfxQuality.character_layers()
	# Perf (docs/performance.md): one BoneAttachment3D per bone, shared by its
	# props; an attachment whose props are all hidden stops updating.
	var bone_name := body.skeleton.get_bone_name(bone)
	var att: BoneAttachment3D = _atts.get(bone_name)
	if att == null:
		att = BoneAttachment3D.new()
		att.name = "Props_" + bone_name
		att.bone_name = bone_name
		body.skeleton.add_child(att)
		_atts[bone_name] = att
	# Keep the prop upright and placed in model space at rest; it follows the bone from there.
	mi.transform = rest.affine_inverse() * Transform3D(Basis(), at)
	att.add_child(mi)
	_props[n] = mi


## Attachments with no visible prop stop updating (and hide), the rest run.
func _refresh_attachments() -> void:
	for att: BoneAttachment3D in _atts.values():
		var any := false
		for c in att.get_children():
			if (c as Node3D).visible:
				any = true
				break
		att.visible = any
		att.process_mode = Node.PROCESS_MODE_INHERIT if any else Node.PROCESS_MODE_DISABLED


## Number of attachments still updating (tests, perf log).
func active_attachments() -> int:
	return _atts.values().filter(func(a: BoneAttachment3D) -> bool:
		return a.process_mode != Node.PROCESS_MODE_DISABLED).size()


func _tint_props() -> void:
	var m := WorldModel.material(PROPS_KEY, team)
	for n in _props:
		(_props[n] as MeshInstance3D).material_override = m
	if _ring_own != null:
		_ring_own.material_override = _ring_mat(team)


## One unshaded team-colour material per team for the own-squad ring.
static func _ring_mat(team_: int) -> StandardMaterial3D:
	if not _ring_mats.has(team_):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = ModelPalette.team_color(team_)
		_ring_mats[team_] = m
	return _ring_mats[team_]
