class_name FootIK
extends SkeletonModifier3D
## Foot IK with a pelvis offset (W14-P2). After the animation pose, ray-casts
## under each foot, lowers the Hips by the larger drop and plants both feet on
## the ground through two TwoBoneIK3D modifiers (4.6+, verified in 4.7).
## Tiers: High and Ultra only; heroes beyond NEAR_M skip the casts.

const NEAR_M: float = 22.0
const MAX_STEP_M: float = 0.35
const CAST_UP: float = 0.5
const CAST_DOWN: float = 0.9
const PLANT_H: float = 0.22  # a foot higher than this in the clip is mid-stride: not planted
const PELVIS_SMOOTH: float = 14.0
const LEGS := [
	[&"UpperLeg_L", &"LowerLeg_L", &"Foot_L"],
	[&"UpperLeg_R", &"LowerLeg_R", &"Foot_R"],
]

var _ik: Node  # TwoBoneIK3D
var _targets: Array[Node3D] = []
var _pelvis: float = 0.0
var _origin_y: float = 0.0


static func enabled_for(lvl: int) -> bool:
	return lvl >= GfxQuality.HIGH


## Pure planner. `drop` = ground height under the foot minus the model floor
## (+ up / - down); `foot_h` = animated foot height above the floor.
## Returns the pelvis shift (<= 0, only lowers) and per-foot target lift.
static func plan(drop_l: float, drop_r: float, foot_h_l: float, foot_h_r: float) -> Dictionary:
	var dl := clampf(drop_l, -MAX_STEP_M, MAX_STEP_M)
	var dr := clampf(drop_r, -MAX_STEP_M, MAX_STEP_M)
	var wl := clampf(1.0 - foot_h_l / PLANT_H, 0.0, 1.0)
	var wr := clampf(1.0 - foot_h_r / PLANT_H, 0.0, 1.0)
	# The pelvis drops to the lowest planted foot so the leg can reach it.
	var pelvis := minf(minf(dl * wl, dr * wr), 0.0)
	return {"pelvis": pelvis, "lift": [dl * wl, dr * wr]}


## Creates and wires the modifier under `skeleton` (returns null if bones are missing).
static func attach(skeleton: Skeleton3D, lvl: int) -> FootIK:
	if skeleton == null or not enabled_for(lvl) or not ClassDB.class_exists("TwoBoneIK3D"):
		return null
	for leg in LEGS:
		for b in leg:
			if skeleton.find_bone(b) < 0:
				return null
	if skeleton.find_bone(&"Hips") < 0:
		return null
	var f := FootIK.new()
	f.name = "FootIK"
	skeleton.add_child(f)
	var ik := ClassDB.instantiate("TwoBoneIK3D") as SkeletonModifier3D
	ik.name = "LegIK"
	skeleton.add_child(ik)  # after FootIK: runs after it
	ik.set("setting_count", 2)
	for i in 2:
		var t := Node3D.new()
		t.name = "FootTarget%d" % i
		t.top_level = true
		skeleton.add_child(t)
		f._targets.append(t)
		ik.call("set_target_node", i, ik.get_path_to(t))
		ik.call("set_root_bone_name", i, LEGS[i][0])
		ik.call("set_middle_bone_name", i, LEGS[i][1])
		ik.call("set_end_bone_name", i, LEGS[i][2])
		ik.call("set_pole_direction_vector", i, Vector3(0.0, 0.0, -1.0))
	f._ik = ik
	ik.active = false
	return f


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _targets.size() < 2 or not sk.is_inside_tree():
		return
	var model := sk.get_parent().get_parent() as Node3D  # Skeleton -> Glb -> RiggedHeroModel
	var cam := get_viewport().get_camera_3d()
	if cam == null or model == null or cam.global_position.distance_to(model.global_position) > NEAR_M:
		_ik.active = false
		_pelvis = lerpf(_pelvis, 0.0, 0.2)
		return
	var space := sk.get_world_3d().direct_space_state
	var floor_y := model.global_position.y
	var drops: Array[float] = []
	var hs: Array[float] = []
	var feet: Array[Transform3D] = []
	for i in 2:
		var fi := sk.find_bone(LEGS[i][2])
		var gt := sk.global_transform * sk.get_bone_global_pose(fi)
		feet.append(gt)
		var q := PhysicsRayQueryParameters3D.create(gt.origin + Vector3.UP * CAST_UP,
			gt.origin + Vector3.DOWN * CAST_DOWN, HeroBody.LAYER_WORLD)
		var hit := space.intersect_ray(q)
		drops.append((hit.position.y - floor_y) if not hit.is_empty() else 0.0)
		hs.append(maxf(gt.origin.y - floor_y, 0.0))
	var p := plan(drops[0], drops[1], hs[0], hs[1])
	_pelvis = lerpf(_pelvis, p.pelvis, clampf(get_process_delta_time() * PELVIS_SMOOTH, 0.0, 1.0))
	var hips := sk.find_bone(&"Hips")
	sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) + sk.global_transform.basis.inverse() * Vector3(0.0, _pelvis, 0.0))
	for i in 2:
		_targets[i].global_transform = Transform3D(feet[i].basis, feet[i].origin + Vector3(0.0, p.lift[i], 0.0))
	_ik.active = absf(_pelvis) > 0.005 or absf(p.lift[0]) > 0.005 or absf(p.lift[1]) > 0.005


func _exit_tree() -> void:
	if is_instance_valid(_ik):
		_ik.queue_free()
	for t in _targets:
		if is_instance_valid(t):
			t.queue_free()
