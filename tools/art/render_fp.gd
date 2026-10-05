extends SceneTree
## W19-VM evidence renders of a hero's first-person viewmodel, through the real
## FirstPersonRig (FOV fitting, kick, hooks):
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##   -s res://tools/art/render_fp.gd -- --hero vesper --out production/qa/evidence/w19-vm
## Writes <hero>_fp_idle_fov90 / _idle_fov120 / _reload / _fire / _cast / _cast_ult /
## _inspect / _box_fallback .png, <hero>_fp_strip_<clip>.png (6 frames each) and prints
## a rough draw-cost line (draw calls, primitives, tris, frame CPU time with and without
## the viewmodel).

const HERO_DEFS := "res://assets/data/heroes/"
const BG := Color("#0B1015")

var _root3d: Node3D
var _rig: FirstPersonRig
var _feet := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _arg(flag: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def


func _hero_def(key: StringName) -> HeroDef:
	for f in DirAccess.get_files_at(HERO_DEFS):
		if f.ends_with(".tres") and f.contains(String(key)):
			return load(HERO_DEFS + f) as HeroDef
	return null


func _run() -> void:
	var key := StringName(_arg("--hero", "vesper"))
	var out := _arg("--out", "production/qa/evidence/w19-vm")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	_stage()
	await _frames(3)
	var hit := _root3d.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(0, 60, 0), Vector3(0, -60, 0)))
	if not hit.is_empty():
		_feet = hit.position
	var hd := _hero_def(key)
	var look := LookSettings.new()
	look.fov_deg = 90.0
	_rig = FirstPersonRig.new()
	_rig.setup(look)
	_root3d.add_child(_rig)
	_rig.set_weapon(hd.weapon, key, ModelPalette.TEAM_CONCORD)
	_rig.follow(_feet, 1.65, 0.0, -0.05)
	var fp := _rig.fp_model
	if fp == null:
		push_error("no FP glb for %s" % key)
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--flat"):  # look-dev after a --notex build (stale maps)
		var flat := (FpViewmodel.material(key, ModelPalette.TEAM_CONCORD).duplicate()) as ShaderMaterial
		flat.set_shader_parameter("use_maps", 0.0)
		flat.next_pass = FpViewmodel.material(key, ModelPalette.TEAM_CONCORD).next_pass
		for mi in fp.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = flat
	fp.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	await _settle(fp, 1.0)
	await _save("%s/%s_fp_idle_fov90.png" % [out, key])
	_rig.set_fov(120.0)
	await _settle(fp, 0.1)
	await _save("%s/%s_fp_idle_fov120.png" % [out, key])
	_rig.set_fov(90.0)
	var rl := FpViewmodel.reload_duration(hd.weapon)
	fp.play_reload(rl)
	await _settle(fp, rl * 0.45)
	await _save("%s/%s_fp_reload.png" % [out, key])
	await _settle(fp, rl)
	_rig.play_shot()
	_rig.follow(_feet, 1.65, 0.0, -0.05, Vector2(0.0, 0.02))
	await _settle(fp, 0.035)
	await _save("%s/%s_fp_fire.png" % [out, key])
	_rig.follow(_feet, 1.65, 0.0, -0.05)
	await _settle(fp, 0.5)
	fp.play_cast(0)
	await _settle(fp, 0.22)
	await _save("%s/%s_fp_cast.png" % [out, key])
	await _settle(fp, 0.8)
	fp.play_cast(3)
	await _settle(fp, 0.5)
	await _save("%s/%s_fp_cast_ult.png" % [out, key])
	await _settle(fp, 1.2)
	fp.play_inspect()
	await _settle(fp, 1.0)
	await _save("%s/%s_fp_inspect.png" % [out, key])
	await _settle(fp, 1.0)
	await _save("%s/%s_fp_inspect2.png" % [out, key])
	await _settle(fp, 2.0)
	for clip in [&"reload", &"inspect", &"cast_ult", &"sprint", &"draw"]:
		await _strip(fp, clip, "%s/%s_fp_strip_%s.png" % [out, key, clip])
	await _perf(fp, key)
	# The fallback (no FP glb / --box-heroes): the old box gun.
	HeroModelLoader.set_box_forced(1)
	_rig.set_weapon(hd.weapon, key, ModelPalette.TEAM_CONCORD)
	HeroModelLoader.set_box_forced(0)
	_rig.follow(_feet, 1.65, 0.0, -0.05)
	await _frames(4)
	await _save("%s/%s_fp_box_fallback.png" % [out, key])
	quit()


## Advances the FP tree by `s` seconds in 1/60 steps and redraws.
func _settle(fp: FpViewmodel, s: float) -> void:
	var n := maxi(1, int(round(s * 60.0)))
	for i in n:
		fp.tree.advance(1.0 / 60.0)
	_rig.follow(_feet, 1.65, 0.0, -0.05)
	await _frames(2)


func _strip(fp: FpViewmodel, clip: StringName, path: String) -> void:
	var length := fp.clip_length(clip)
	var tiles: Array[Image] = []
	fp.tree.active = false
	var ap := fp.anim_player
	for i in 6:
		ap.play(clip)
		ap.seek(length * i / 6.0, true)
		ap.pause()
		await _frames(3)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(426, 240, Image.INTERPOLATE_BILINEAR)
		tiles.append(img)
	ap.stop()
	fp.tree.active = true
	var strip := Image.create(426 * 3, 240 * 2, false, tiles[0].get_format())
	for i in 6:
		strip.blit_rect(tiles[i], Rect2i(0, 0, 426, 240), Vector2i(426 * (i % 3), 240 * (i / 3)))
	strip.save_png(ProjectSettings.globalize_path("res://" + path))
	print("saved ", path)


func _perf(fp: FpViewmodel, key: StringName) -> void:
	var rows := []
	for on in [true, false]:
		_rig.camera.get_child(_rig.camera.get_child_count() - 1).visible = on
		await _frames(10)
		var dc := 0.0
		var prim := 0.0
		var t0 := Time.get_ticks_usec()
		for i in 30:
			await process_frame
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var ms := (Time.get_ticks_usec() - t0) / 30000.0
		rows.append([dc / 30.0, prim / 30.0, ms])
	_rig.camera.get_child(_rig.camera.get_child_count() - 1).visible = true
	print("fp perf %s: tris %d, meshes %d, draw calls %.0f vs %.0f without (+%.0f), primitives +%.0f, frame %.2f ms vs %.2f ms" % [
		key, fp.triangle_count(), fp.mesh_instance_count(), rows[0][0], rows[1][0], rows[0][0] - rows[1][0],
		rows[0][1] - rows[1][1], rows[0][2], rows[1][2]])


func _stage() -> void:
	_root3d = Node3D.new()
	root.add_child(_root3d)
	var map_path := _arg("--map", "res://assets/maps/slice/shardline_causeway.tscn")
	if map_path != "" and ResourceLoader.exists(map_path):
		var map := (load(map_path) as PackedScene).instantiate() as Node3D
		_root3d.add_child(map)
		var at := _arg("--at", "0,-85").split(",")
		map.position = -Vector3(float(at[0]), 0.0, float(at[1]))
		return
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#3A4250")
	e.ambient_light_energy = 0.7
	env.environment = e
	_root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	_root3d.add_child(sun)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://" + path))
	print("saved ", path)
