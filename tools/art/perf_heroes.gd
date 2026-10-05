extends SceneTree
## Frame-time A/B for 6 heroes (W13): 6 models in motion (3 rigged pilots x2
## when available), camera at lane distance. Run twice:
##   xvfb-run ... godot --path . -s res://tools/art/perf_heroes.gd             (rigged)
##   xvfb-run ... godot --path . -s res://tools/art/perf_heroes.gd -- --box-heroes
## Prints mean / p95 frame ms over 300 frames after a 60-frame warm-up.

const KEYS: Array[StringName] = [&"ryker", &"vesper", &"ryker", &"vesper", &"ryker", &"vesper"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.has("--tier"):  # W14-P2: GfxQuality tier 0..3 (hit reaction / foot IK / spring bones follow it)
		GameSettings.shared().set("graphics_quality", int(ua[ua.find("--tier") + 1]))
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.position = Vector3(0, 2.0, 9.0)
	cam.look_at(Vector3(0, 1.0, 0))
	var models: Array[HeroModel] = []
	for i in KEYS.size():
		var m := HeroModelLoader.build(KEYS[i], i % 2)
		stage.add_child(m)
		m.position = Vector3((i - 2.5) * 1.6, 0, -float(i % 3))
		models.append(m)
		if OS.get_cmdline_user_args().has("--no-anim") and m is RiggedHeroModel:
			(m as RiggedHeroModel).tree.active = false
		if OS.get_cmdline_user_args().has("--no-outline"):
			for mi in m.find_children("*", "MeshInstance3D", true, false):
				var mat := (mi as MeshInstance3D).material_override
				if mat is ShaderMaterial:
					mat = mat.duplicate()
					mat.next_pass = null
					(mi as MeshInstance3D).material_override = mat
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for f in 360:
		for i in models.size():
			var t := f / 60.0 + i
			models[i].set_motion(models[i].global_basis * Vector3(sin(t) * 3.0, 0, -4.0 - cos(t) * 2.0),
				fmod(t, 6.0) > 5.0, sin(t) * 0.5)
			if f % 20 == i:
				models[i].play_shoot()
		await process_frame
		var now := Time.get_ticks_usec()
		if f >= 60:
			times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var mean := 0.0
	for t in times:
		mean += t
	mean /= times.size()
	print("PERF heroes=6 rigged=%s mean_ms=%.2f p95_ms=%.2f tris_each=%d" % [
		not HeroModelLoader.box_forced(), mean, times[int(times.size() * 0.95)], models[0].triangle_count()])
	quit()
