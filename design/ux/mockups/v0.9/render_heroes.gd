extends SceneTree
## Renders every hero model to a transparent PNG portrait for the UI mockup.

const OUT := "/tmp/claude-0/-home-user-Cybergram/1e3fde17-2a7f-5ddb-a886-a055dec56299/scratchpad/mock/root/hero_%s.png"
const STEMS := ["vesper_loom", "brannoc", "ryker_vance", "liora_vale", "sable", "juniper_quill", "hex"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1000)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.55)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 26.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.4, 1.25, 6.2), Vector3(0, 1.0, 0))
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-28, 40, 0)
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.25, 0.85, 0.8)
	rim.light_energy = 4.0
	rim.omni_range = 6.0
	rim.position = Vector3(1.6, 2.2, -1.8)
	vp.add_child(rim)
	var turn := Node3D.new()
	vp.add_child(turn)
	for stem: String in STEMS:
		var k := ModelCatalog.hero_key_from_id(stem)
		var model := HeroModelBuilder.build(k, ModelPalette.TEAM_NEUTRAL)
		turn.add_child(model)
		turn.rotation.y = deg_to_rad(205.0)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(OUT % stem)
		print("rendered ", stem)
		model.free()
	quit(0)
