class_name MatchProcessLauncher
extends RefCounted
## Starts and watches match processes for the MatchSupervisor (W17). This base
## class uses the real OS; tests inject a fake with the same four methods.
##
## A match process is `executable engine_args -- user_args`:
## - exported server: executable = Cybergram.x86_64, engine_args = ["--headless"];
## - from source:     executable = godot, engine_args = ["--headless", "--path", <project>].
## The supervisor supplies user_args ("--server --port N --host-boot <file>").
## Nothing secret is ever put on a command line (other users can read them).

var executable: String = ""
var engine_args: PackedStringArray = PackedStringArray(["--headless"])
## Pids this launcher killed: OS.kill() already reaped them, so asking the OS
## again would log "not a child" errors.
var _killed: Dictionary = {}


## `executable_` "" = this very binary (the front runs the same build).
func _init(executable_: String = "", engine_args_: PackedStringArray = PackedStringArray(["--headless"])) -> void:
	executable = executable_ if executable_ != "" else OS.get_executable_path()
	engine_args = engine_args_


## Starts a process; its pid, or -1.
func spawn(user_args: PackedStringArray) -> int:
	var args := PackedStringArray(engine_args)
	args.append("--")
	args.append_array(user_args)
	return OS.create_process(executable, args)


## False once the process has ended (this also reaps it).
func is_running(pid: int) -> bool:
	if pid <= 0 or _killed.has(pid):
		return false
	return OS.is_process_running(pid)


## Hard stop (SIGKILL on Linux). Graceful stops go over the channel.
func kill(pid: int) -> void:
	if pid > 0 and not _killed.has(pid):
		_killed[pid] = true
		OS.kill(pid)


## Resident memory of `pid` in KiB from /proc (0 when unknown). Diagnostics.
func rss_kib(pid: int) -> int:
	var f := FileAccess.open("/proc/%d/status" % pid, FileAccess.READ)
	if f == null:
		return 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return line.substr(6).strip_edges().split(" ")[0].to_int()
	return 0
