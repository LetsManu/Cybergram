extends MatchProcessLauncher
## Fake process launcher for the W17-SUP tests: records spawns, kills and
## lets a test end a "process" (crash) without any real OS process.

var spawned: Array = []  # [{pid, args}]
var running: Dictionary = {}  # pid -> true
var killed: Array = []
var fail_next: bool = false
var _next_pid: int = 1000


func _init() -> void:
	super("fake-binary", PackedStringArray())


func spawn(user_args: PackedStringArray) -> int:
	if fail_next:
		fail_next = false
		return -1
	_next_pid += 1
	spawned.append({"pid": _next_pid, "args": user_args})
	running[_next_pid] = true
	return _next_pid


func is_running(pid: int) -> bool:
	return running.has(pid)


func kill(pid: int) -> void:
	killed.append(pid)
	running.erase(pid)


## The process exits by itself (clean exit or crash).
func end(pid: int) -> void:
	running.erase(pid)
