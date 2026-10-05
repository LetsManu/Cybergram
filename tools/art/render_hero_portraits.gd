extends SceneTree
## Renders every hero's model (HeroModelLoader: rigged toon glb, else HeroModelBuilder; team-neutral palette) to a
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
## It also writes assets/ui/portraits/portraits.json: per hero the head
## centre and head size in image px ({"brannoc": {"head": [x, y], "size": s}}),
## which UiPortrait uses to crop circles on the face. The head comes from a
## Skeleton3D bone named like "head" (rigged models), else a "head" pivot /
## node, else the top of the model bounds.
## Optional: `-- --only=brannoc,hex` renders a subset (merged into the json). Heroes come from
## HeroCatalog (every hero_*.tres), so a new hero needs no change here.
## Adapted from design/ux/mockups/v0.9/render_heroes.gd.

const OUT_DIR := "res://assets/ui/portraits"
const SIZE := Vector2i(720, 1000)
## Largest head size as a share of the model's projected height.
const HEAD_SHARE := 0.16
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
	var meta_path := OUT_DIR + "/portraits.json"
	var meta: Dictionary = {}
	if FileAccess.file_exists(meta_path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if old is Dictionary:
			meta = old
	var done := 0
	for h: Dictionary in HeroCatalog.entries():
		var stem := String(h.stem)
		if not only.is_empty() and not only.has(stem):
			continue
		var model := HeroModelLoader.build(ModelCatalog.hero_key_from_id(stem), ModelPalette.TEAM_NEUTRAL)
		turn.add_child(model)
		for i in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/hero_%s.png" % [OUT_DIR, stem]
		var err := vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		meta[stem] = head_box(model, cam)
		print("rendered ", path, " err=", err, " head=", meta[stem])
		done += 1
		model.free()
	var f := FileAccess.open(ProjectSettings.globalize_path(meta_path), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t", true) + "\n")
	f.close()
	print("portraits rendered: ", done)
	quit(0 if done > 0 else 1)


## {"head": [x, y], "size": s} in image px: the head's projected box.
static func head_box(model: Node3D, cam: Camera3D) -> Dictionary:
	var whole := _bounds(model)
	var box := AABB()
	var found := false
	var neck := Vector3(INF, INF, INF)  # head base (bone / pivot origin) when known
	# 1. Rigged model: a skeleton bone named like "head".
	for sk: Skeleton3D in model.find_children("*", "Skeleton3D", true, false):
		for b in sk.get_bone_count():
			if sk.get_bone_name(b).to_lower().contains("head"):
				var c := sk.global_transform * sk.get_bone_global_pose(b).origin
				neck = c
				var r := whole.size.y * 0.075
				box = AABB(c - Vector3(r, r * 0.4, r), Vector3(r, r, r) * 2.0)
				found = true
				break
		if found:
			break
	# 2. A "head" pivot (HeroModel) or any node named head: its meshes' bounds.
	if not found:
		var head: Node3D = model.call("pivot", &"head") if model.has_method("pivot") else null
		if head == null:
			var hits := model.find_children("*head*", "Node3D", true, false)
			head = hits[0] as Node3D if not hits.is_empty() else null
		if head != null:
			neck = head.global_position
			box = _bounds(head)
			found = box.size != Vector3.ZERO
	# 3. Fallback: the top of the model bounds.
	if not found:
		var hh := whole.size.y * 0.15
		box = AABB(Vector3(whole.get_center().x - hh * 0.5, whole.end.y - hh, whole.get_center().z - hh * 0.5),
			Vector3(hh, hh, hh))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := cam.unproject_position(box.get_endpoint(i))
		lo = lo.min(p)
		hi = hi.max(p)
	# Accessories on the head (halo, hood, antennae) inflate the box: cap the
	# size at a head's share of the body and keep the bottom (the face end).
	var body_px := absf(cam.unproject_position(Vector3(0, whole.position.y, 0)).y
		- cam.unproject_position(Vector3(0, whole.end.y, 0)).y)
	var size := minf(maxf(hi.x - lo.x, hi.y - lo.y), body_px * HEAD_SHARE)
	# Bottom of the head: the bone / pivot origin (the neck) when known, so
	# collars and capes hanging from the head do not pull the crop down.
	var bottom := hi.y
	if neck.x != INF:
		bottom = minf(hi.y, cam.unproject_position(neck).y)
	var c2 := Vector2((lo.x + hi.x) * 0.5, bottom - size * 0.5)
	return {"head": [roundf(c2.x), roundf(c2.y)], "size": roundf(size)}


## World-space bounds of every mesh under `n` (empty AABB when none).
static func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
