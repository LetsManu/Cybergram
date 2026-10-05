extends SceneTree
## Extra W16 hero evidence (W16-HERO-B), beside render_turntable.gd:
##   --close   mask/helmet close-up: front, 3/4 and side of the head, tiled into <hero>_mask.png
##   --lane    heroes in a lane line-up next to Vesper, seen from a player's eye height
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##   -s res://tools/art/render_hero_extra.gd -- --close --hero vesper --out production/qa/evidence/x [--tag after]
##   -s res://tools/art/render_hero_extra.gd -- --lane --heroes liora,vesper --out ... \
##      --map res://assets/maps/slice/shardline_causeway.tscn --at 0,-118

const BG := Color("#0B1015")

var _root3d: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _arg(flag: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def


func _has(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


func _run() -> void:
	var out := _arg("--out", "production/qa/evidence/w16-heroB")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	if _has("--lane"):
		await _lane(out)
	else:
		await _close(StringName(_arg("--hero", "vesper")), out, _arg("--tag", ""))
	quit()


## Head close-ups: the camera frames the Head bone at 0.75 m, three yaws tiled side by side.
func _close(key: StringName, out: String, tag: String) -> void:
	_stage()
	var m := HeroModelLoader.build(key, int(_arg("--team", "0")))
	_root3d.add_child(m)
	await _frames(20)
	var head := Vector3(0, m.height_m * 0.9, 0)
	if m is RiggedHeroModel:
		var sk: Skeleton3D = (m as RiggedHeroModel).skeleton
		var bi := sk.find_bone("Head")
		if bi >= 0:
			head = sk.global_transform * sk.get_bone_global_pose(bi).origin
			head.y += 0.08
	var tiles: Array[Image] = []
	for yaw in [0.0, 35.0, 90.0]:
		var dir := Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw)))
		# The model faces -Z after the 180 deg turn: rotate the camera around the head instead.
		m.rotation_degrees.y = 180.0
		await _frames(2)
		var hp := head
		if m is RiggedHeroModel:
			var sk2: Skeleton3D = (m as RiggedHeroModel).skeleton
			hp = sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("Head")).origin + Vector3(0, 0.08, 0)
		_cam.fov = 30.0
		_cam.position = hp + dir.rotated(Vector3.UP, PI) * -0.85 + Vector3(0, 0.05, 0)
		_cam.look_at(hp)
		await _frames(4)
		await RenderingServer.frame_post_draw
		tiles.append(root.get_texture().get_image().get_region(Rect2i(340, 0, 600, 720)))
	var sheet := Image.create(600 * tiles.size(), 720, false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 600, 720), Vector2i(600 * i, 0))
	var name := "%s_mask%s.png" % [key, ("_" + tag) if tag != "" else ""]
	sheet.save_png(ProjectSettings.globalize_path("res://%s/%s" % [out, name]))
	print("saved ", out, "/", name)


## Lane line-up: the listed heroes side by side on the lane (team 0 then team 1 for the last).
func _lane(out: String) -> void:
	_root3d = Node3D.new()
	root.add_child(_root3d)
	_root3d.add_child((load(_arg("--map", "res://assets/maps/slice/shardline_causeway.tscn")) as PackedScene).instantiate())
	_cam = Camera3D.new()
	_root3d.add_child(_cam)
	_cam.current = true
	await _frames(5)
	var at := _arg("--at", "0,-118").split(",")
	var c := Vector3(float(at[0]), 0.0, float(at[1]))
	var keys := _arg("--heroes", "vesper").split(",")
	var space := _root3d.get_world_3d().direct_space_state
	var gy := 0.0
	for i in keys.size():
		var p := c + Vector3((i - (keys.size() - 1) * 0.5) * 1.3, 0, 0.3 * (i % 2))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 40, 0), p - Vector3(0, 40, 0)))
		var m := HeroModelLoader.build(StringName(keys[i]), 0)
		_root3d.add_child(m)
		m.position = hit.position if not hit.is_empty() else p
		gy = m.position.y
		m.rotation_degrees.y = 180.0 + 20.0
	_cam.fov = 70.0
	_cam.position = c + Vector3(0.3, gy + 1.7, 4.8)
	_cam.look_at(c + Vector3(0, gy + 1.0, 0))
	await _frames(20)
	await _save("%s/%s" % [out, _arg("--name", "lane_%s.png" % "_".join(keys))])


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


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://" + path))
	print("saved ", path)
