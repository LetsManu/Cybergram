class_name RiggedHeroModel
extends HeroModel
## A rigged toon hero from a glb built by tools/art/build_hero.py
## (design/art/hero-art-bible.md). Drop-in for the procedural HeroModel: same
## API (set_team, set_motion, flinch, markers) plus the animation hooks
## (set_grounded, play_shoot, play_reload, play_cast, set_dead, set_fade).
## An AnimationTree is driven from those hooks; the mapping from replicated
## state to tree parameters is the pure static map_state() (unit-tested).
## Presentation only. Faces -Z like HeroView.

const TOON_SHADER := "res://assets/shaders/spatial_char_toon_rigged.gdshader"
const OUTLINE_SHADER := "res://assets/shaders/spatial_char_outline_hull.gdshader"
## Clip names (the contract with tools/art/hero_anims.py).
const LOOPS: Array[StringName] = [&"idle", &"walk", &"run", &"run_back", &"strafe_l", &"strafe_r",
	&"crouch_idle", &"crouch_walk", &"aim_up", &"aim_mid", &"aim_down"]
const UPPER_BONES: Array[StringName] = [&"UpperChest", &"Neck", &"Head", &"Clavicle_L", &"Clavicle_R",
	&"UpperArm_L", &"UpperArm_R", &"LowerArm_L", &"LowerArm_R", &"Hand_L", &"Hand_R", &"Weapon"]
const RECOIL_BONES: Array[StringName] = [&"Chest"]
## Locomotion: full-speed run (m/s) = blend position 1; crouch walk speed.
const RUN_SPEED: float = 6.0
const CROUCH_SPEED: float = 3.0
## Fallback in-place clip speeds (m/s) when <id>_anim.tres is missing.
const DEFAULT_CLIP_SPEED := {&"walk": 1.3, &"run": 3.0, &"run_back": 1.3}
## Locomotion playback rate clamp (above the run clip speed the run speeds up).
const LOCO_RATE_MAX: float = 2.2
## Max look pitch mapped to aim_up / aim_down (rad, the clips are +-70 deg).
const AIM_PITCH_MAX: float = 1.22
const SKILL_SLOTS: int = 4
## Seconds the death clip plays before HeroView hides the body.
const DEATH_HOLD_S: float = 2.0
## Outline widths per team (match ModelMaterials: Concord thin, Syndicate thick).
const OUTLINE_PX := {ModelPalette.TEAM_CONCORD: 2.8, ModelPalette.TEAM_SYNDICATE: 3.2}

## Beyond this camera distance (m) the inverted hull is dropped (outline LOD):
## the hull pass is the largest per-hero cost (pilot perf note in the art bible).
const OUTLINE_LOD_M: float = 30.0

static var _materials: Dictionary = {}
static var _tris: Dictionary = {}

var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var _meshes: Array[MeshInstance3D] = []
var _grounded: bool = true
var _dead: bool = false
var _flash: float = 0.0
var _fade: float = 1.0
var _state: Dictionary = {}
var _enemy_outline: bool = false
var _far: bool = false
var _clip_speed: Dictionary = DEFAULT_CLIP_SPEED.duplicate()


## Builds from an imported glb scene (instantiated here). `hero_height` = HeroDef
## art height (m) for the nameplate marker.
func build_from_scene(model_key: StringName, scene: PackedScene, team_: int) -> void:
	key = model_key
	name = "RiggedHeroModel_%s" % key
	var inst := scene.instantiate()
	inst.name = "Glb"
	add_child(inst)
	skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(n as MeshInstance3D)
	_measure_height()
	_make_markers()
	_setup_loops()
	_load_clip_speeds()
	_build_tree()
	set_team(team_)
	_apply_pose(0.0)


func _measure_height() -> void:
	var top := 0.0
	for mi in _meshes:
		var aabb := mi.get_aabb()
		top = maxf(top, aabb.position.y + aabb.size.y)
	height_m = top if top > 0.5 else 1.8


func _make_markers() -> void:
	if skeleton == null:
		return
	var spec := {
		&"HAND_R_weapon": [&"Hand_R", Vector3.ZERO],
		&"HEAD_nameplate": [&"Head", Vector3(0.0, 0.32, 0.0)],
		&"BACK_attach": [&"UpperChest", Vector3(0.0, 0.05, 0.18)],
	}
	for mk in spec:
		var bone: StringName = spec[mk][0]
		if skeleton.find_bone(bone) < 0:
			continue
		var att := BoneAttachment3D.new()
		att.name = "Att_" + String(bone)
		att.bone_name = bone
		skeleton.add_child(att)
		var m := Marker3D.new()
		m.name = String(mk)
		m.position = spec[mk][1]
		att.add_child(m)
		_markers[mk] = m
		_pivots[StringName(String(bone).to_lower())] = att


func _load_clip_speeds() -> void:
	var p := HeroModelLoader.glb_path(key).replace(".glb", "_anim.tres")
	if ResourceLoader.exists(p):
		var r := load(p)
		var d: Dictionary = r.get_meta(&"clip_speed", {})
		for k in d:
			if float(d[k]) > 0.05:
				_clip_speed[StringName(k)] = float(d[k])


func _setup_loops() -> void:
	if anim_player == null:
		return
	for n in LOOPS:
		if anim_player.has_animation(n):
			anim_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR


## Track paths of `bones` as used by the clips (for blend filters).
func _bone_paths(bones: Array[StringName]) -> Array[NodePath]:
	var out: Array[NodePath] = []
	if anim_player == null or not anim_player.has_animation(&"aim_mid"):
		return out
	var a := anim_player.get_animation(&"aim_mid")
	for i in a.get_track_count():
		var p := a.track_get_path(i)
		if p.get_subname_count() > 0 and bones.has(StringName(p.get_concatenated_subnames())):
			out.append(p)
	return out


func _clip_node(clip: StringName) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


func _build_tree() -> void:
	if anim_player == null:
		return
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	var rv := run_point(_clip_speed)
	for p in [[&"idle", Vector2.ZERO], [&"walk", Vector2(0, _clip_speed[&"walk"] / RUN_SPEED)], [&"run", Vector2(0, rv)],
			[&"run_back", Vector2(0, -_clip_speed[&"run_back"] / RUN_SPEED)], [&"strafe_l", Vector2(-rv, 0)],
			[&"strafe_r", Vector2(rv, 0)]]:
		loco.add_blend_point(_clip_node(p[0]), p[1])
	bt.add_node(&"loco_bs", loco)
	bt.add_node(&"loco", AnimationNodeTimeScale.new())
	bt.connect_node(&"loco", 0, &"loco_bs")
	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.add_blend_point(_clip_node(&"crouch_idle"), 0.0)
	crouch.add_blend_point(_clip_node(&"crouch_walk"), 1.0)
	bt.add_node(&"crouch", crouch)
	var cmix := AnimationNodeBlend2.new()
	bt.add_node(&"crouch_mix", cmix)
	bt.connect_node(&"crouch_mix", 0, &"loco")
	bt.connect_node(&"crouch_mix", 1, &"crouch")
	var air := AnimationNodeTransition.new()
	air.add_input("ground")
	air.add_input("air")
	air.xfade_time = 0.12
	bt.add_node(&"air", air)
	bt.add_node(&"jump", _clip_node(&"jump"))
	bt.connect_node(&"air", 0, &"crouch_mix")
	bt.connect_node(&"air", 1, &"jump")
	var aim := AnimationNodeBlendSpace1D.new()
	aim.add_blend_point(_clip_node(&"aim_down"), -1.0)
	aim.add_blend_point(_clip_node(&"aim_mid"), 0.0)
	aim.add_blend_point(_clip_node(&"aim_up"), 1.0)
	bt.add_node(&"aim", aim)
	var upper := AnimationNodeBlend2.new()
	_filter(upper, UPPER_BONES)
	bt.add_node(&"upper", upper)
	bt.connect_node(&"upper", 0, &"air")
	bt.connect_node(&"upper", 1, &"aim")
	var prev := &"upper"
	for os in [[&"reload", &"reload", UPPER_BONES, 0.1], [&"cast", &"cast_0", UPPER_BONES, 0.1],
			[&"shoot", &"shoot", RECOIL_BONES, 0.02], [&"hit", &"hit", RECOIL_BONES, 0.03]]:
		var one := AnimationNodeOneShot.new()
		one.fadein_time = os[3]
		one.fadeout_time = os[3] * 1.5
		_filter(one, os[2])
		bt.add_node(os[0], one)
		var clip_name := StringName(String(os[0]) + "_clip")
		bt.add_node(clip_name, _clip_node(os[1]))
		bt.connect_node(os[0], 0, prev)
		bt.connect_node(os[0], 1, clip_name)
		prev = os[0]
	var life := AnimationNodeTransition.new()
	life.add_input("alive")
	life.add_input("dead")
	life.xfade_time = 0.15
	bt.add_node(&"life", life)
	bt.add_node(&"death", _clip_node(&"death"))
	bt.connect_node(&"life", 0, prev)
	bt.connect_node(&"life", 1, &"death")
	bt.connect_node(&"output", 0, &"life")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.root_node = tree.get_path_to(anim_player.get_node(anim_player.root_node))
	tree.anim_player = tree.get_path_to(anim_player)
	tree.tree_root = bt
	tree.set("parameters/upper/blend_amount", 1.0)
	tree.active = true


func _filter(node: AnimationNode, bones: Array[StringName]) -> void:
	node.filter_enabled = true
	for p in _bone_paths(bones):
		node.set_filter_path(p, true)


## Blend-space radius of the run clip (its in-place speed / RUN_SPEED).
static func run_point(clip_speed: Dictionary) -> float:
	return clampf(float(clip_speed.get(&"run", 3.0)) / RUN_SPEED, 0.1, 1.0)


## Pure mapping from replicated state to AnimationTree parameters.
## vel_local: velocity in model space (m/s, forward = -Z); pitch in rad.
## clip_speed: in-place mocap clip speeds (m/s) from <id>_anim.tres.
static func map_state(vel_local: Vector3, crouching: bool, grounded: bool, pitch: float, dead: bool,
		clip_speed: Dictionary = DEFAULT_CLIP_SPEED) -> Dictionary:
	var planar := Vector2(vel_local.x, -vel_local.z)
	var speed := planar.length()
	var rv := run_point(clip_speed)
	var loco := planar / RUN_SPEED
	if loco.length() > rv:
		loco = loco.normalized() * rv
	var run_speed := rv * RUN_SPEED
	return {
		"parameters/loco_bs/blend_position": loco,
		"parameters/loco/scale": clampf(speed / run_speed, 1.0, LOCO_RATE_MAX),
		"parameters/crouch/blend_position": clampf(speed / CROUCH_SPEED, 0.0, 1.0),
		"parameters/crouch_mix/blend_amount": 1.0 if crouching else 0.0,
		"parameters/air/transition_request": "ground" if grounded else "air",
		"parameters/aim/blend_position": clampf(pitch / AIM_PITCH_MAX, -1.0, 1.0),
		"parameters/life/transition_request": "dead" if dead else "alive",
	}


## Clip played by play_cast(slot) (cast_0..cast_3; out of range -> clamped).
static func cast_clip(slot: int) -> StringName:
	return StringName("cast_%d" % clampi(slot, 0, SKILL_SLOTS - 1))


func set_team(team_: int, enemy_outline: bool = false) -> void:
	team = team_
	_enemy_outline = enemy_outline
	var m := material(team_, enemy_outline, _far, key)
	for mi in _meshes:
		mi.material_override = m
	set_meta(&"team_tint", ModelPalette.team_color(team))


## One shared toon + hull material per (hero, team, enemy_outline); `far` = no hull.
## `model_key` binds the hero's baked W14 texture set when it exists
## (assets/models/heroes/<key>/<key>_albedo|_normal|_mask.png), else flat colours.
static func material(team_: int, enemy_outline: bool = false, far: bool = false,
		model_key: StringName = &"") -> ShaderMaterial:
	var k := "%s|%d|%s|%s" % [model_key, team_, enemy_outline, far]
	if _materials.has(k):
		return _materials[k]
	var tc := ModelPalette.team_color(team_)
	var m := ShaderMaterial.new()
	m.shader = load(TOON_SHADER)
	m.set_shader_parameter("team_color", tc)
	_bind_maps(m, model_key)
	var o := ShaderMaterial.new()
	o.shader = load(OUTLINE_SHADER)
	o.set_shader_parameter("outline_color", tc if enemy_outline else Color("#090A0E"))
	o.set_shader_parameter("width_px", OUTLINE_PX.get(team_, 2.0))
	if not far:
		m.next_pass = o
	_materials[k] = m
	return m


## Binds the baked albedo / normal / mask maps of `model_key` (W14), if present.
static func _bind_maps(m: ShaderMaterial, model_key: StringName) -> void:
	if model_key == &"":
		return
	var base := "res://assets/models/heroes/%s/%s_" % [model_key, model_key]
	if not ResourceLoader.exists(base + "albedo.png"):
		return
	m.set_shader_parameter("use_maps", 1.0)
	m.set_shader_parameter("albedo_map", load(base + "albedo.png"))
	m.set_shader_parameter("normal_map", load(base + "normal.png"))
	m.set_shader_parameter("mask_map", load(base + "mask.png"))


func set_motion(velocity_world: Vector3, crouching: bool, pitch: float) -> void:
	var gb := global_transform.basis if is_inside_tree() else transform.basis
	_vel_local = gb.inverse() * Vector3(velocity_world.x, 0.0, velocity_world.z)
	_crouch_target = 1.0 if crouching else 0.0
	_pitch = clampf(pitch, -1.3, 1.3)


func set_grounded(grounded: bool) -> void:
	_grounded = grounded


func flinch(strength: float = 1.0) -> void:
	_flinch = clampf(maxf(_flinch, strength), 0.0, 1.0)
	_flash = maxf(_flash, 0.6 * strength)
	_fire(&"hit")


func play_shoot() -> void:
	_fire(&"shoot")


func play_reload() -> void:
	_fire(&"reload")


func play_cast(slot: int) -> void:
	if tree == null:
		return
	var bt := tree.tree_root as AnimationNodeBlendTree
	(bt.get_node(&"cast_clip") as AnimationNodeAnimation).animation = cast_clip(slot)
	_fire(&"cast")


func set_dead(dead: bool) -> void:
	_dead = dead


func is_dead() -> bool:
	return _dead


## 1 = fully visible, 0 = invisible (screen-door dither, outline drops below 1).
func set_fade(alpha: float) -> void:
	_fade = clampf(alpha, 0.0, 1.0)
	for mi in _meshes:
		mi.set_instance_shader_parameter(&"fade", _fade)


func _fire(shot: StringName) -> void:
	if tree != null and not _dead:
		tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _update_outline_lod() -> void:
	var vp := get_viewport() if is_inside_tree() else null
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var far := cam.global_position.distance_to(global_position) > OUTLINE_LOD_M
	if far != _far:
		_far = far
		set_team(team, _enemy_outline)


## Last parameters written to the tree (tests / debugging).
func state() -> Dictionary:
	return _state


func triangle_count() -> int:
	if _tris.has(key):
		return _tris[key]
	var n := 0
	for mi in _meshes:
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			n += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_tris[key] = n
	return n


func mesh_instance_count() -> int:
	return _meshes.size()


func _apply_pose(delta: float) -> void:
	_time += delta
	_flinch = maxf(0.0, _flinch - delta * 3.5)
	if _flash > 0.0 or delta == 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		for mi in _meshes:
			mi.set_instance_shader_parameter(&"flash", _flash)
	_update_outline_lod()
	_state = map_state(_vel_local, _crouch_target > 0.5, _grounded, _pitch, _dead, _clip_speed)
	if tree == null:
		return
	for p in _state:
		if String(p).ends_with("transition_request"):
			var cur := String(tree.get(String(p).replace("transition_request", "current_state")))
			if cur == _state[p]:
				continue
		tree.set(p, _state[p])
	var speed := Vector2(_vel_local.x, _vel_local.z).length()
	tree.set("parameters/crouch_mix/blend_amount", move_toward(
		float(tree.get("parameters/crouch_mix/blend_amount")), _state["parameters/crouch_mix/blend_amount"], delta * 6.0))
	_speed_s = speed
