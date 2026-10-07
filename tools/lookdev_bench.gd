extends SceneTree
## Look-dev render benchmark (docs/lookdev.md): loads the Shardline Front map
## with its client visuals, puts the camera on fixed shot.gd presets and measures
## per view: wall frame time, the viewport's measured CPU / GPU render time, draw
## calls and primitives; then the same with every shadow off (shadow cost =
## the difference). One JSON line per run.
##
## Needs a display (xvfb + Mesa). On lavapipe (software Vulkan) the GPU numbers
## are CPU rasterisation: compare variants and tiers with each other, never with
## a real GPU budget.
##   xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --resolution 1920x1080 \
##     -s res://tools/lookdev_bench.gd -- --look a --quality 1 [--frames 20] [--out file.json]

const MAP_DEF := "res://assets/data/match/map_front.tres"
const VIEWS := ["fp-lane-center", "fp-spawn-a", "base-a"]
const SHOT := preload("res://tools/shot.gd")

var _frames := 20
var _out := ""
var _quality := 2


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--frames":
				_frames = int(args[i + 1])
			"--out":
				_out = args[i + 1]
			"--quality":
				_quality = clampi(int(args[i + 1]), 0, 3)
	GameSettings.shared().graphics_quality = _quality
	_run.call_deferred()


func _run() -> void:
	var md := load(MAP_DEF) as MapDef
	var map: Node3D = md.scene.instantiate()
	root.add_child(map)
	map.add_child(WorldDecals.create(md))  # floor tiles + decals, props, cover kit: as shot.gd / ClientWorld
	WorldProps.spawn(map, md)
	CoverDressing.spawn(map)
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 2000.0
	map.add_child(cam)
	cam.current = true
	var vp_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	await _wait(30)
	var shots := {}
	for s in SHOT.presets(md):
		shots[s[0]] = s
	var res := {"look": LookProfile.id_from_args(OS.get_cmdline_user_args()), "quality": _quality, "views": {}}
	var tot_on := 0.0
	var tot_off := 0.0
	for v: String in VIEWS:
		var s: Array = shots[v]
		cam.global_position = s[1]
		cam.look_at(s[2])
		var on := await _measure(vp_rid)
		var saved := _shadows_off(map)
		var off := await _measure(vp_rid)
		_shadows_restore(saved)
		on["shadow_ms"] = snappedf(on.frame_ms - off.frame_ms, 0.1)
		res.views[v] = on
		tot_on += on.frame_ms
		tot_off += off.frame_ms
	res["mean_frame_ms"] = snappedf(tot_on / VIEWS.size(), 0.1)
	res["mean_shadow_ms"] = snappedf((tot_on - tot_off) / VIEWS.size(), 0.1)
	var line := JSON.stringify(res)
	print("[lookdev-bench] ", line)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_line(line)
	quit()


func _measure(vp_rid: RID) -> Dictionary:
	await _wait(8)
	var wall := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var t0 := Time.get_ticks_usec()
	for k in _frames:
		await process_frame
		var t1 := Time.get_ticks_usec()
		wall += (t1 - t0) / 1000.0
		t0 = t1
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var n := float(_frames)
	return {
		"frame_ms": snappedf(wall / n, 0.1), "render_cpu_ms": snappedf(cpu / n, 0.01),
		"render_gpu_ms": snappedf(gpu / n, 0.1),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}


func _shadows_off(map: Node) -> Array:
	var saved := []
	for n in map.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l.shadow_enabled:
			saved.append(l)
			l.shadow_enabled = false
	return saved


func _shadows_restore(saved: Array) -> void:
	for l: Light3D in saved:
		l.shadow_enabled = true


func _wait(n: int) -> void:
	for k in n:
		await process_frame
