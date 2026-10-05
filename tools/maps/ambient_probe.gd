extends SceneTree
## W18-LIFE perf probe (presentation only): loads Shardline Front, looks down
## three lanes and reports draw calls, objects and the mean / worst frame time
## per view. Needs a display (xvfb). Pass ambient debug args after "--":
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##     -s res://tools/maps/ambient_probe.gd -- --ambient-off
## llvmpipe numbers are rough: compare runs on the same machine only.

const MAP := "res://assets/maps/front/shardline_front.tscn"
## [label, eye, look-at] in world space (z = -L).
const VIEWS := [
	["north", Vector3(-80, 2.0, -104), Vector3(-80, 1.0, -200)],
	["center", Vector3(-3, 2.0, -112), Vector3(0, 1.0, -160)],
	["south", Vector3(83, 2.0, -108), Vector3(80, 1.0, -160)],
	["skyline", Vector3(-90, 6.0, -150), Vector3(-260, 40.0, -210)],
]
const WARM := 8
const MEASURE := 24


func _initialize() -> void:
	var map: Node3D = (load(MAP) as PackedScene).instantiate()
	root.add_child(map)
	await process_frame
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 1500.0
	map.add_child(cam)
	cam.current = true
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var tot_dc := 0
	var tot_ms := 0.0
	for v in VIEWS:
		cam.global_position = v[1]
		cam.look_at(v[2])
		for i in WARM:
			await process_frame
		var dc := 0
		var obj := 0
		var sum_us := 0
		var worst_us := 0
		var gpu := 0.0
		var cpu := 0.0
		var last := Time.get_ticks_usec()
		for i in MEASURE:
			await process_frame
			var now := Time.get_ticks_usec()
			sum_us += now - last
			worst_us = maxi(worst_us, now - last)
			last = now
			dc = maxi(dc, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			obj = maxi(obj, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		var ms := sum_us / 1000.0 / MEASURE
		tot_dc += dc
		tot_ms += ms
		print("PROBE %-8s draw_calls=%d objects=%d frame_ms=%.2f worst_ms=%.2f render_cpu_ms=%.2f render_gpu_ms=%.2f" % [
			v[0], dc, obj, ms, worst_us / 1000.0, cpu / MEASURE, gpu / MEASURE])
	print("PROBE mean draw_calls=%.1f frame_ms=%.2f" % [tot_dc / float(VIEWS.size()), tot_ms / VIEWS.size()])
	quit()
