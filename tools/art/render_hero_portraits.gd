extends SceneTree
## Renders every hero's model (HeroModelBuilder, team-neutral palette) to a
## transparent PNG portrait: assets/ui/portraits/hero_<stem>.png, 720x1000,
## three-quarter view, warm key light + teal rim (design/ux/mockups/v0.9).
## The menus crop these (UiPortrait / UiKit.portrait_texture), so keep the
## camera framing below unchanged unless the crop in UiPortrait.FACE changes too.
##
## Re-run it whenever a hero model changes (the hero models are being
## redesigned), from the repo root, with a real renderer (not --headless):
##
##   xvfb-run -a -s "-screen 0 1280x1024x24" ~/godot/Godot_v4.7-stable_linux.x86_64 \
##       --path . --rendering-driver opengl3 -s res://tools/art/render_hero_portraits.gd
##   ~/godot/Godot_v4.7-stable_linux.x86_64 --headless --path . --import
##   bash launcher/tools/sync_shared.sh    # the launcher shows the same portraits
##
## Optional: `-- --only=brannoc,hex` renders a subset. Heroes come from
## HeroCatalog (every hero_*.tres), so a new hero needs no change here.
## Adapted from design/ux/mockups/v0.9/render_heroes.gd.

const OUT_DIR := "res://assets/ui/portraits"
const SIZE := Vector2i(720, 1000)
## Settle frames before grabbing (shader compile, first light pass).
const SETTLE_FRAMES := 6


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var vp := SubViewport.new()
	vp.size = SIZE
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
	turn.rotation.y = deg_to_rad(205.0)
	vp.add_child(turn)
	var done := 0
	for h: Dictionary in HeroCatalog.entries():
		var stem := String(h.stem)
		if not only.is_empty() and not only.has(stem):
			continue
		var model := HeroModelBuilder.build(ModelCatalog.hero_key_from_id(stem), ModelPalette.TEAM_NEUTRAL)
		turn.add_child(model)
		for i in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/hero_%s.png" % [OUT_DIR, stem]
		var err := vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("rendered ", path, " err=", err)
		done += 1
		model.free()
	print("portraits rendered: ", done)
	quit(0 if done > 0 else 1)
