class_name FpViewmodel
extends Node3D
## W19-VM: a hero's first-person viewmodel from the bpy pipeline
## (assets/models/heroes/<key>/<key>_fp.glb, tools/art/build_fp.py): gloved hands
## with fingers, sleeves, the hero's own weapon at FP detail, and FP clips driven
## by an AnimationTree. FirstPersonRig falls back to the procedural box weapon
## (WeaponModelBuilder) when a hero has no FP glb.
##
## The glb root sits at the right grip (sidecar `fp_pos`, Godot eye space), so the
## rig pivots, kicks and FOV-fits the viewmodel there exactly as for the box gun.
## Clips: idle walk sprint (loops), jump land fire reload draw holster cast
## cast_ult inspect (one-shots). Clip timing follows gameplay, never the reverse:
## reload is time-scaled to the WeaponDef's reload time, fire to the fire rate.

const GLB_PATH := "res://assets/models/heroes/%s/%s_fp.glb"
const SIDECAR_PATH := "res://assets/models/heroes/%s/%s_fp.tres"
const MAPS_BASE := "res://assets/models/heroes/%s/%s_fp_"
## Ink outline for first person: thinner than the 3P hull (2.8-3.2 px).
const OUTLINE_PX: float = 1.4
## Mounts on the real-size FP weapon (the box viewmodel runs at 0.6 scale).
const MOUNT_SCALE: float = 0.65
## Locomotion blend points (BlendSpace1D): idle 0, walk 0.5, sprint 1.
const WALK_POINT: float = 0.5
const ONE_SHOTS: Array[StringName] = [&"land", &"jump", &"inspect", &"reload", &"cast", &"fire", &"draw"]
const LOOPS: Array[StringName] = [&"idle", &"walk", &"sprint"]

static var _scenes: Dictionary = {}
static var _materials: Dictionary = {}

var key: StringName = &""
var team: int = 0
var mana: bool = true
## Grip position in eye space (the rig's viewmodel pivot at FOV 90).
var fp_pos: Vector3 = Vector3(0.155, -0.205, -0.34)
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var _sockets: Dictionary = {}
var _markers: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _mount_nodes: Array[Node3D] = []
var _spinners: Array = []
var _grounded: bool = true
var _tris: int = -1


## res:// path of `model_key`'s FP glb.
static func glb_path(model_key: StringName) -> String:
	return GLB_PATH % [model_key, model_key]


## True when `model_key` has an imported FP glb (and box models are not forced).
static func has_fp(model_key: StringName) -> bool:
	if model_key == &"" or HeroModelLoader.box_forced():
		return false
	return ResourceLoader.exists(glb_path(model_key))


## The FP viewmodel for `model_key`, or null when it has none (use the box gun).
static func build(model_key: StringName, team_: int, mana_: bool = true) -> FpViewmodel:
	if not has_fp(model_key):
		return null
	if not _scenes.has(model_key):
		_scenes[model_key] = load(glb_path(model_key)) as PackedScene
	var scene: PackedScene = _scenes[model_key]
	if scene == null:
		return null
	var side_p := SIDECAR_PATH % [model_key, model_key]
	var side: Resource = load(side_p) if ResourceLoader.exists(side_p) else null
	var m := FpViewmodel.new()
	m.mana = mana_
	m.build_from_scene(model_key, scene, side, team_)
	return m


## Time scale that makes a clip of `clip_len` seconds last `target_s` seconds
## (1.0 for a non-positive target or clip).
static func clip_scale(clip_len: float, target_s: float) -> float:
	if clip_len <= 0.0 or target_s <= 0.0:
		return 1.0
	return clip_len / target_s


## Fire clip time scale: the kick never outlasts one shot interval at `fire_rate`
## (shots / s); slower guns play it at its authored speed.
static func fire_scale(clip_len: float, fire_rate: float) -> float:
	if fire_rate <= 0.0:
		return 1.0
	return maxf(1.0, clip_len * fire_rate)


## Seconds the reload clip must fill for `def`: the magazine reload (the empty
## reload when `empty` and the gun has one), or for Mana guns the Burnout lock
## (regen delay x burnout multiplier). Mount modifiers (Quickload) are server-side.
static func reload_duration(def: WeaponDef, empty: bool = false) -> float:
	if def == null:
		return 0.0
	if def.feed_kind == WeaponDef.FeedKind.MANA:
		return def.mana_regen_delay_s * def.burnout_delay_mult
	if empty and def.reload_empty_s > 0.0 and not def.reload_per_round:
		return def.reload_empty_s
	return def.reload_s


## Locomotion blend position: 0 idle .. 0.5 walk .. 1 sprint. `sway` false (weapon
## bob off or reduce motion) holds the idle.
static func loco_point(speed: float, run_speed: float, sprinting: bool, sway: bool) -> float:
	if not sway:
		return 0.0
	if sprinting:
		return 1.0
	return clampf(speed / maxf(run_speed, 0.1), 0.0, 1.0) * WALK_POINT


func build_from_scene(model_key: StringName, scene: PackedScene, sidecar: Resource, team_: int) -> void:
	key = model_key
	name = "FpViewmodel_%s" % key
	var inst := scene.instantiate()
	inst.name = "Glb"
	add_child(inst)
	skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 0.5  # skinned clips swing the arms outside the rest AABB
		_meshes.append(mi)
	if sidecar != null:
		fp_pos = sidecar.get_meta(&"fp_pos", fp_pos)
		_sockets = sidecar.get_meta(&"sockets", {})
	_make_markers()
	_setup_loops()
	_build_tree()
	set_team(team_)


func _make_markers() -> void:
	if skeleton == null:
		return
	var wi := skeleton.find_bone(&"Weapon")
	if wi < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "Att_Weapon"
	att.bone_name = &"Weapon"
	skeleton.add_child(att)
	var inv := skeleton.get_bone_global_rest(wi).affine_inverse()
	for s in _sockets:
		var m := Marker3D.new()
		m.name = String(s)
		m.position = inv * (_sockets[s] as Vector3)
		att.add_child(m)
		_markers[StringName(s)] = m


func _setup_loops() -> void:
	if anim_player == null:
		return
	for n in LOOPS:
		if anim_player.has_animation(n):
			anim_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR


func _clip(n: StringName) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	return a


func _build_tree() -> void:
	if anim_player == null:
		return
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_clip(&"idle"), 0.0)
	loco.add_blend_point(_clip(&"walk"), WALK_POINT)
	loco.add_blend_point(_clip(&"sprint"), 1.0)
	bt.add_node(&"loco_bs", loco)
	bt.add_node(&"loco", AnimationNodeTimeScale.new())
	bt.connect_node(&"loco", 0, &"loco_bs")
	var prev := &"loco"
	for os in ONE_SHOTS:
		var one := AnimationNodeOneShot.new()
		one.fadein_time = 0.03 if os == &"fire" else 0.1
		one.fadeout_time = 0.06 if os == &"fire" else 0.15
		bt.add_node(os, one)
		var clip_name := StringName(String(os) + "_clip")
		bt.add_node(clip_name, _clip(os))
		var ts := StringName(String(os) + "_ts")
		bt.add_node(ts, AnimationNodeTimeScale.new())
		bt.connect_node(ts, 0, clip_name)
		bt.connect_node(os, 0, prev)
		bt.connect_node(os, 1, ts)
		prev = os
	bt.connect_node(&"output", 0, prev)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.root_node = tree.get_path_to(anim_player.get_node(anim_player.root_node))
	tree.anim_player = tree.get_path_to(anim_player)
	tree.tree_root = bt
	tree.set("parameters/loco/scale", 1.0)
	for os in ONE_SHOTS:
		tree.set("parameters/%s_ts/scale" % os, 1.0)
	tree.active = true


## Seconds of clip `n` (0 when missing).
func clip_length(n: StringName) -> float:
	if anim_player == null or not anim_player.has_animation(n):
		return 0.0
	return anim_player.get_animation(n).length


func has_clip(n: StringName) -> bool:
	return anim_player != null and anim_player.has_animation(n)


## Fires one-shot `os` with its clip time-scaled by `scale`.
func _fire(os: StringName, scale: float = 1.0, clip: StringName = &"") -> void:
	if tree == null:
		return
	if clip != &"":
		var bt := tree.tree_root as AnimationNodeBlendTree
		(bt.get_node(StringName(String(os) + "_clip")) as AnimationNodeAnimation).animation = clip
	tree.set("parameters/%s_ts/scale" % os, scale)
	tree.set("parameters/%s/request" % os, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Visual fire kick, at most one shot interval long (the aim kick stays RecoilKick's).
func play_fire(fire_rate: float) -> void:
	_fire(&"fire", fire_scale(clip_length(&"fire"), fire_rate))


## Reload choreography stretched to `duration_s` (FpViewmodel.reload_duration).
func play_reload(duration_s: float) -> void:
	_fire(&"reload", clip_scale(clip_length(&"reload"), duration_s))


## Skill-cast gesture: one shared gesture for Q/E/C (slots 0-2), the stronger
## cast_ult for the ultimate (slot 3).
func play_cast(slot: int) -> void:
	var clip := &"cast_ult" if slot >= 3 and has_clip(&"cast_ult") else &"cast"
	_fire(&"cast", 1.0, clip)


func play_inspect() -> void:
	_fire(&"inspect")


func play_draw() -> void:
	_fire(&"draw", 1.0, &"draw")


func play_holster() -> void:
	_fire(&"draw", 1.0, &"holster")


## True while one-shot `os` is playing (tests / diagnostics).
func is_playing(os: StringName) -> bool:
	return tree != null and bool(tree.get("parameters/%s/active" % os))


## Locomotion: blend position (loco_point) and clip rate. `rate` 0 freezes the
## loops (reduce motion).
func set_motion(point: float, rate: float) -> void:
	if tree == null:
		return
	tree.set("parameters/loco_bs/blend_position", clampf(point, 0.0, 1.0))
	tree.set("parameters/loco/scale", maxf(rate, 0.0))


## Jump on leaving the ground, land on touching it (`sway` false = neither).
func set_grounded(grounded: bool, sway: bool = true) -> void:
	if grounded == _grounded:
		return
	_grounded = grounded
	if sway:
		_fire(&"land" if grounded else &"jump")


func socket(socket_name: StringName) -> Marker3D:
	return _markers.get(socket_name)


func marker_names() -> Array:
	return _markers.keys()


func set_team(team_: int) -> void:
	team = team_
	var m := material(key, team)
	for mi in _meshes:
		mi.material_override = m


## Toon material with the hero's FP painted maps (falls back to flat colours
## without them), the hero's own shader overrides and a thin ink hull.
static func material(model_key: StringName, team_: int) -> ShaderMaterial:
	var k := "%s|%d" % [model_key, team_]
	if _materials.has(k):
		return _materials[k]
	var tc := ModelPalette.team_color(team_)
	var m := ShaderMaterial.new()
	m.shader = load(RiggedHeroModel.TOON_SHADER)
	m.set_shader_parameter("team_color", tc)
	RiggedHeroModel.bind_maps_from(m, MAPS_BASE % [model_key, model_key])
	RiggedHeroModel.apply_shader_overrides(m, RiggedHeroModel.shader_overrides(model_key))
	var o := ShaderMaterial.new()
	o.shader = load(RiggedHeroModel.OUTLINE_SHADER)
	o.set_shader_parameter("outline_color", Color("#090A0E"))
	o.set_shader_parameter("width_px", OUTLINE_PX)
	m.next_pass = o
	_materials[k] = m
	return m


## E13 mount visuals at the weapon's socket markers (same rules as WeaponModel).
func set_mounts(items: Array, tiers: PackedInt32Array) -> int:
	for n in _mount_nodes:
		n.queue_free()
	_mount_nodes.clear()
	_spinners.clear()
	for i in items.size():
		var item := items[i] as ArmoryItemDef
		if item == null:
			continue
		var tier := clampi(tiers[i] if i < tiers.size() else 1, 1, 3)
		var sock := socket(MountVisuals.socket_marker(item.socket))
		if sock == null:
			continue
		var n := MountVisuals.build(item, tier, mana, MOUNT_SCALE)
		sock.add_child(n)
		_mount_nodes.append(n)
		for sp in n.get_meta(&"spinners", []):
			_spinners.append(sp)
	return _mount_nodes.size()


func mount_count() -> int:
	return _mount_nodes.size()


## Triangles of the FP meshes (perf budget: ~15k for weapon and arms).
func triangle_count() -> int:
	if _tris >= 0:
		return _tris
	_tris = 0
	for mi in _meshes:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			_tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return _tris


func mesh_instance_count() -> int:
	return _meshes.size()


func _process(delta: float) -> void:
	for sp in _spinners:
		var n: Node3D = sp[0]
		if is_instance_valid(n):
			n.rotate(sp[1], sp[2] * delta)
