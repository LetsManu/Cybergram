extends SceneTree
## Turntable + side-by-side evidence renders for the rigged heroes (W13).
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##   -s res://tools/art/render_turntable.gd -- --hero ryker --out production/qa/evidence/w13-heroes
## Writes <hero>_front / _34 / _side / _back / _far30m / _vs_old .png and an
## animation contact sheet (<hero>_poses.png: idle, run, aim up, shoot, cast, death).

const BG := Color("#0B1015")

var _root3d: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _arg(flag: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def


func _run() -> void:
	var key := StringName(_arg("--hero", "ryker"))
	var out := _arg("--out", "production/qa/evidence/w13-heroes")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	_stage()
	var team := int(_arg("--team", "0"))
	var m := HeroModelLoader.build(key, team)
	_root3d.add_child(m)
	await _frames(20)
	var h := m.height_m
	for shot in [["front", 0.0], ["34", 35.0], ["side", 90.0], ["back", 180.0]]:
		m.rotation_degrees.y = 180.0 + shot[1]
		_frame_cam(h, 3.4, h * 0.52, 30.0)
		await _frames(4)
		await _save("%s/%s_%s.png" % [out, key, shot[0]])
	m.rotation_degrees.y = 180.0 + 35.0
	_frame_cam(h, 30.0, h * 0.5, 70.0)
	await _frames(3)
	await _save("%s/%s_far30m.png" % [out, key])
	# Side by side with the old procedural model.
	HeroModelLoader.set_box_forced(1)
	var old := HeroModelLoader.build(key, team)
	HeroModelLoader.set_box_forced(0)
	_root3d.add_child(old)
	old.position.x = 0.75
	m.position.x = -0.75
	old.rotation_degrees.y = 180.0 + 25.0
	m.rotation_degrees.y = 180.0 + 25.0
	_frame_cam(h, 4.6, h * 0.5, 30.0)
	await _frames(6)
	await _save("%s/%s_vs_old.png" % [out, key])
	old.queue_free()
	m.position.x = 0.0
	# Pose sheet.
	m.rotation_degrees.y = 180.0 + 30.0
	_frame_cam(h, 3.4, h * 0.5, 30.0)
	var poses := [["idle", func(): pass], ["run", func(): m.set_motion(m.global_basis * Vector3(0, 0, -6), false, 0.0)],
		["aim_up", func(): m.set_motion(Vector3.ZERO, false, 1.0)], ["crouch", func(): m.set_motion(Vector3.ZERO, true, 0.0)],
		["shoot", func(): m.set_motion(Vector3.ZERO, false, 0.0); m.play_shoot()], ["reload", func(): m.play_reload()],
		["cast", func(): m.play_cast(0)], ["cast_ult", func(): m.play_cast(3)], ["jump", func(): m.set_grounded(false)],
		["death", func(): m.set_grounded(true); m.set_dead(true)]]
	for p in poses:
		(p[1] as Callable).call()
		await _frames(28 if p[0] in ["death"] else 12)
		await _save("%s/%s_pose_%s.png" % [out, key, p[0]])
	quit()


func _stage() -> void:
	_root3d = Node3D.new()
	root.add_child(_root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#3A4250")
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	_root3d.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("#9FB4FF")
	_root3d.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#1E272D")
	floor_mi.material_override = fm
	_root3d.add_child(floor_mi)
	_cam = Camera3D.new()
	_root3d.add_child(_cam)
	_cam.current = true


func _frame_cam(h: float, dist: float, look_y: float, fov: float) -> void:
	_cam.fov = fov
	_cam.position = Vector3(0.0, look_y + dist * 0.06, dist)
	_cam.look_at(Vector3(0.0, look_y, 0.0))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://" + path))
	print("saved ", path)
