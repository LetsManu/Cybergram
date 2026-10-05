extends SceneTree
## W14-P2 evidence probe (xvfb): a rigged hero on a step with a side camera.
##   godot --path . -s res://tools/art/fx_probe.gd -- --mode ik|hit|run --tier 2 --out /path/prefix
## Saves 4 frames as <out>_0..3.png.

var _frame := 0
var _m: RiggedHeroModel
var _mode := "ik"
var _out := "/tmp/probe"
var _cam: Camera3D
var _fx: FxDirector


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
	if _mode == "fx":
		_m.visible = false
		_fx = FxDirector.new()
		stage.add_child(_fx)
		cp = Vector3(0.0, 1.4, 5.0)
		_cam.look_at_from_position(cp, Vector3(0, 1.2, 0))
	root.size = Vector2i(640, 480)


func _process(_d: float) -> bool:
	_frame += 1
	if _mode == "run" and _frame % 4 == 0:
		_m.set_motion(_m.global_transform.basis * Vector3(0, 0, -6.0), false, 0.0)
	var shots := {20: 0, 30: 1, 36: 2, 44: 3}
	if _mode == "fx":
		if _frame % 10 == 2 and _frame < 50:
			var k := (_frame / 10) % 4
			_fx.flash(Vector3(-2.4, 1.2, 0), Color(1.0, 0.82, 0.35), 0.8, 0.3, false, 2.0, 5.0)  # muzzle
			_fx.flash(Vector3(-0.8, 1.2, 0), Color(1.0, 0.42, 0.2), 1.0, 0.3, false, 1.8, 6.0)  # hit star
			_fx.burst(Vector3(-0.8, 1.2, 0), Vector3.UP, Color(1.0, 0.7, 0.5), 8, 5.0, 0.5, 70.0)
			_fx.flash(Vector3(1.0, 1.2, 0), Color(0.18, 0.525, 1.0), 2.2, 0.5, true, 1.8)  # kill ring
			_fx.flash(Vector3(1.0, 1.2, 0), Color.WHITE, 2.0, 0.5, false, 2.0, 8.0)  # cel explosion
			_fx.flash(Vector3(1.0, 1.2, 0), Color(0.18, 0.525, 1.0), 3.0, 0.5, false, 1.6, 12.0)
			var dome := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			dome.mesh = sm
			dome.material_override = ToonFx.cel(Color(0.3, 0.9, 0.5), 0.3, 1.3)
			dome.position = Vector3(2.8, 1.2, 0)
			root.get_child(root.get_child_count() - 1).add_child(dome) if k == 0 else null
		shots = {4: 0, 7: 1, 12: 2, 17: 3}
	if _mode == "hit":
		if _frame == 23:
			_m.flinch(1.0, Vector3(3, 1, 0))  # big hit from the hero right (screen left): stagger
		shots = {24: 0, 26: 1, 29: 2, 40: 3}
	if _mode == "run":
		shots = {40: 0, 46: 1, 52: 2, 58: 3}
	if shots.has(_frame):
		root.get_texture().get_image().save_png("%s_%d.png" % [_out, shots[_frame]])
	if _frame > 64:
		print("PROBE spring=%s foot_ik=%s" % [_m.spring_bones != null, _m.foot_ik != null])
		return true
	return false
