extends SceneTree
## Full-match benchmark (owner plan Part 5, docs/performance.md): boots the real
## game (app_root.tscn, user args as given, e.g. `--bots`) and samples every
## frame: main-thread process and physics time, then prints one JSON line with
## mean / p95 / max per phase, the Wardling and hero counts, and the server's
## own Wardling step + AI think cost. Headless measures simulation, animation
## and scripts (no GPU); under a display it includes rendering submission.
##   $GODOT --headless --path . -s res://tools/bench_match.gd -- --bots --bench-s 90 [--bench-warmup-s 20] [--bench-out file.json]

var _proc: PackedFloat32Array = []
var _phys: PackedFloat32Array = []
var _wardlings_max := 0
var _wardlings_sum := 0
var _samples := 0
var _t0 := 0.0
var _warm := 20.0
var _dur := 90.0
var _out := ""
var _app: Node


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		match a[i]:
			"--bench-s":
				_dur = float(a[i + 1])
			"--bench-warmup-s":
				_warm = float(a[i + 1])
			"--bench-out":
				_out = a[i + 1]
	_app = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	root.add_child.call_deferred(_app)
	_t0 = Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> bool:
	var t := Time.get_ticks_msec() / 1000.0 - _t0
	if t < _warm:
		return false
	_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if _samples % 30 == 0:
		var n := root.find_children("*", "WardlingModel", true, false).size()
		_wardlings_max = maxi(_wardlings_max, n)
		_wardlings_sum += n
	_samples += 1
	if t >= _warm + _dur:
		_finish()
		return true
	return false


func _stats(a: PackedFloat32Array) -> Dictionary:
	var s := Array(a)
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	return {"mean": snappedf(sum / maxi(s.size(), 1), 0.01), "p95": snappedf(s[int(s.size() * 0.95)] if not s.is_empty() else 0.0, 0.01),
		"max": snappedf(s[-1] if not s.is_empty() else 0.0, 0.01)}


func _finish() -> void:
	var r := {"frames": _proc.size(), "seconds": _dur, "headless": DisplayServer.get_name() == "headless",
		"process_ms": _stats(_proc), "physics_ms": _stats(_phys),
		"wardlings_max": _wardlings_max, "wardlings_avg": int(_wardlings_sum / maxf(ceilf(_samples / 30.0), 1.0)),
		"heroes": root.find_children("*", "HeroView", true, false).size()}
	var servers := root.find_children("*", "ServerWorld", true, false)
	if not servers.is_empty():
		var w: Variant = servers[0].get("wardlings")
		if w != null and int(w.steps) > 0:
			r["server_wardling_step_ms"] = snappedf(float(w.step_usec_total) / 1000.0 / float(w.steps), 0.001)
			r["server_wardling_think_ms"] = snappedf(float(w.think_usec_total) / 1000.0 / float(w.steps), 0.001)
			r["server_wardlings"] = (w.wardlings as Array).size() if w.get("wardlings") is Array else -1
	var line := JSON.stringify(r)
	print("[bench] " + line)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string(line + "\n")
