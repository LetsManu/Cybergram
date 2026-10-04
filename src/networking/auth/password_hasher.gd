class_name PasswordHasher
extends RefCounted
## Runs PBKDF2 jobs on the WorkerThreadPool so a login never stalls the 30 Hz
## tick (design/ux/lobby-and-social.md §6). submit() queues a job; poll()
## (main thread, every step) returns finished jobs. `threaded = false` runs
## jobs inline (deterministic unit tests).
##
## Example:
##   var id := hasher.submit(pw_bytes, salt, iters, {"peer": 2, "op": OP_LOGIN})
##   for job in hasher.poll(): handle(job.context, job.hash)

## A finished job.
class Job:
	extends RefCounted
	var id: int = 0
	var password: PackedByteArray
	var salt: PackedByteArray
	var iterations: int = 1
	var context: Dictionary = {}
	var hash: PackedByteArray
	var task: int = -1

var threaded: bool = true
var _next: int = 1
var _running: Array[Job] = []
var _done: Array[Job] = []


## Queues a hash of `password` with `salt`; `context` comes back with it.
func submit(password: PackedByteArray, salt: PackedByteArray, iterations: int, context: Dictionary) -> int:
	var j := Job.new()
	j.id = _next
	_next += 1
	j.password = password
	j.salt = salt
	j.iterations = iterations
	j.context = context
	if threaded:
		j.task = WorkerThreadPool.add_task(_run.bind(j), false, "pbkdf2")
		_running.append(j)
	else:
		_run(j)
		_done.append(j)
	return j.id


## Finished jobs since the last poll (main thread).
func poll() -> Array[Job]:
	for i in range(_running.size() - 1, -1, -1):
		var j := _running[i]
		if WorkerThreadPool.is_task_completed(j.task):
			WorkerThreadPool.wait_for_task_completion(j.task)
			_running.remove_at(i)
			_done.append(j)
	var out := _done
	_done = []
	return out


## Jobs still running (tests / shutdown).
func pending() -> int:
	return _running.size()


## Blocks until every job finished (shutdown / tests only, never per tick).
func drain() -> void:
	for j in _running:
		WorkerThreadPool.wait_for_task_completion(j.task)


static func _run(j: Job) -> void:
	j.hash = Pbkdf2.derive(j.password, j.salt, j.iterations, Pbkdf2.HLEN)
	j.password = PackedByteArray()  # do not keep the password longer than needed
