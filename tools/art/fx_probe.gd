extends SceneTree
## W14-P2 evidence probe (xvfb): a rigged hero on a step with a side camera.
##   godot --path . -s res://tools/art/fx_probe.gd -- --mode ik|hit|run --tier 2 --out /path/prefix
## Saves 4 frames as <out>_0..3.png.

var _frame := 0
var _m: RiggedHeroModel
var _mode := "ik"
var _out := "/tmp/probe"
var _cam: Camera3D


func _arg(k: String, d: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(k)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else d


func _initialize() -> void:
	_mode = _arg("--mode", "ik")
	_out = _arg("--out", "/tmp/probe")
	var tier := int(_arg("--tier", "2"))
	GameSettings.shared().set("graphics_quality", tier)
	var stage := Node3D.new()
	root.add_child(stage)
	var we := WorldEnvironment.new()
	we.environment = GfxQuality.make_environment()
	stage.add_child(we)
	var sun := GfxQuality.make_sun()
	stage.add_child(sun)
	GfxQuality.apply(tier, we.environment, sun, root)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = HeroBody.LAYER_WORLD
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(20, 0.2, 20)
	fm.mesh = bm
	floor_body.add_child(fm)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position.y = -0.1
	stage.add_child(floor_body)
	if _mode == "ik":
		var step := StaticBody3D.new()
		step.collision_layer = HeroBody.LAYER_WORLD
		var sm := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.5, 0.3, 1.0)
		sm.mesh = sb
		step.add_child(sm)
		var sc := CollisionShape3D.new()
		var ss := BoxShape3D.new()
		ss.size = sb.size
		sc.shape = ss
		step.add_child(sc)
		step.position = Vector3(0.2, 0.15, 0)  # under the hero's left foot only
		stage.add_child(step)
	_m = HeroModelLoader.build(&"ryker", 0) as RiggedHeroModel
	stage.add_child(_m)
	_m.rotation.y = -PI / 2.0
	_cam = Camera3D.new()
	stage.add_child(_cam)
	var cp := Vector3(0.0, 1.1, 3.4)  # model faces -Z; for ik/run it faces -X so look from +Z (side view)
	if _mode == "hit":
		cp = Vector3(0.0, 1.3, -3.4)  # hero faces the camera? no: faces -Z, so view from the front
		cp = Vector3(0.0, 1.3, -3.4)
	_cam.look_at_from_position(cp, Vector3(0, 0.9, 0))
	if _mode == "hit":
		_m.rotation.y = 0.0
	root.size = Vector2i(640, 480)


func _process(_d: float) -> bool:
	_frame += 1
	if _mode == "run" and _frame % 4 == 0:
		_m.set_motion(_m.global_transform.basis * Vector3(0, 0, -6.0), false, 0.0)
	var shots := {20: 0, 30: 1, 36: 2, 44: 3}
	if _mode == "hit":
		if _frame == 24:
			_m.flinch(1.0, Vector3(3, 1, 0))  # big hit from the hero right (screen left): stagger
		shots = {23: 0, 27: 1, 33: 2, 44: 3}
	if _mode == "run":
		shots = {40: 0, 46: 1, 52: 2, 58: 3}
	if shots.has(_frame):
		root.get_texture().get_image().save_png("%s_%d.png" % [_out, shots[_frame]])
	if _frame > 64:
		print("PROBE spring=%s foot_ik=%s" % [_m.spring_bones != null, _m.foot_ik != null])
		return true
	return false
