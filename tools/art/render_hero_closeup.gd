extends SceneTree
## Mask / helmet close-up evidence for the rigged heroes (W16): the head from the
## front, 3/4, side and back, tiled 2 x 2 into <hero>_mask_closeup.png (1280 x 720 each
## tile cropped to 640 x 360). Same stage and lights as render_turntable.gd.
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##   -s res://tools/art/render_hero_closeup.gd -- --hero ryker --out production/qa/evidence/w16-heroA

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
	var out := _arg("--out", "production/qa/evidence")
	var head := float(_arg("--head", "0.91"))  # head centre as a share of the height
	var dist := float(_arg("--dist", "1.15"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	_stage()
	var m := HeroModelLoader.build(key, int(_arg("--team", "0")))
	_root3d.add_child(m)
	await _frames(20)
	var y := m.height_m * head
	var tiles: Array[Image] = []
	for yaw in [0.0, 35.0, 90.0, 180.0]:
		m.rotation_degrees.y = 180.0 + yaw
		_cam.fov = 30.0
		_cam.position = Vector3(0.0, y + 0.08, dist)
		_cam.look_at(Vector3(0.0, y, 0.0))
		await _frames(4)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		tiles.append(img.get_region(Rect2i(320, 0, 640, 720)))
	var sheet := Image.create(1280, 1440, false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 640, 720), Vector2i(640 * (i % 2), 720 * (i / 2)))
	sheet.resize(1280, 1440)
	var path := "%s/%s_mask_closeup.png" % [out, key]
	sheet.save_png(ProjectSettings.globalize_path("res://" + path))
	print("saved ", path)
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
	e.ambient_light_energy = 0.7
	e.tonemap_white = 2.2
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	_root3d.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("#9FB4FF")
	_root3d.add_child(fill)
	_cam = Camera3D.new()
	_root3d.add_child(_cam)
	_cam.current = true


func _frames(n: int) -> void:
	for i in n:
		await process_frame
