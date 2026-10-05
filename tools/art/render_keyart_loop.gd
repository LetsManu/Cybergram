extends SceneTree
## Renders one hero's `showcase` idle loop for the launcher key art (W15-UX).
## The loop is exactly one clip length, on a pure black background (the
## launcher blends the video additively over its own backdrop).
## xvfb-run -a -s "-screen 0 540x760x24" godot --path . --resolution 540x760 \
##   --fixed-fps 24 --write-movie <dir>/f.png --quit-after <frames> \
##   -s res://tools/art/render_keyart_loop.gd -- --hero vesper_loom
## Prints "KEYART_LENGTH <seconds>" so the caller knows how many frames to take.

var _model: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _arg(flag: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def


func _run() -> void:
	var stem := _arg("--hero", "vesper_loom")
	var root3d := Node3D.new()
	root.add_child(root3d)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.48, 0.55)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	root3d.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-28, 40, 0)
	root3d.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.25, 0.85, 0.8)
	rim.light_energy = 4.0
	rim.omni_range = 6.0
	rim.position = Vector3(1.6, 2.2, -1.8)
	root3d.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 26.0
	root3d.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0.4, 1.2, 4.9), Vector3(0, 1.0, 0))
	_model = HeroModelLoader.build(ModelCatalog.hero_key_from_id(stem), ModelPalette.TEAM_NEUTRAL)
	root3d.add_child(_model)
	_model.rotation.y = deg_to_rad(205.0)
	if _model.has_method(&"play_showcase"):
		_model.call(&"play_showcase")
	var ap := _model.get(&"anim_player") as AnimationPlayer
	var len_s := ap.get_animation(&"showcase").length if ap != null and ap.has_animation(&"showcase") else 0.0
	print("KEYART_LENGTH ", len_s)
