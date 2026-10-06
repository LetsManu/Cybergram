extends SceneTree
## Wardling v2 CPU cost (docs/assets/wardling.md): N rigged Wardlings walking in
## a circle, mean main-thread frame time over the measured frames. Headless
## measures the animation / script cost only (no rendering).
##   $GODOT --headless --path . -s res://tools/perf_wardlings.gd -- [--n 100]

func _initialize() -> void:
	var n := 100
	var args := OS.get_cmdline_user_args()
	var near := args.has("--near")
	for i in args.size():
		if args[i] == "--n":
			n = int(args[i + 1])
	var holder := Node3D.new()
	root.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.current = true
	var ws: Array[WardlingModel] = []
	for i in n:
		var w := WardlingModelBuilder.build(&"picket", 1 + i % 3, i % 2)
		w.set_owner_kind(i % 3)
		holder.add_child(w)
		ws.append(w)
	for f in 30:
		await process_frame
	var frames := 120
	var proc := 0.0
	for f in frames:
		for i in ws.size():
			var a := TAU * i / ws.size() + f * 0.05
			# spread over 5..100 m (a Mid team fight seen from one side), or all at 12 m with --near
			var r := 12.0 if near else 5.0 + 95.0 * float(i) / ws.size()
			ws[i].position = Vector3(cos(a), 0, sin(a)) * r
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
	var ms := proc * 1000.0 / frames
	print("[perf] %d Wardlings %s (rig %s): %.2f ms process time per frame (animation + scripts, headless)" % [
		n, "all at 12 m" if near else "spread 5-100 m", ws[0].rig != null, ms])
	quit(0)
