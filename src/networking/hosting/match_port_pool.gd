class_name MatchPortPool
extends RefCounted
## The UDP ports match processes may bind (W17). acquire() hands out the
## lowest free port, so a freed port is reused first and the open range stays
## compact. Memory only.

var first: int
var last: int
var _used: Dictionary = {}  # port -> true


func _init(first_: int, last_: int) -> void:
	first = first_
	last = last_


## The lowest free port, or 0 when every port is taken.
func acquire() -> int:
	for p in range(first, last + 1):
		if not _used.has(p):
			_used[p] = true
			return p
	return 0


func release(port: int) -> void:
	_used.erase(port)


func in_use(port: int) -> bool:
	return _used.has(port)


func used_count() -> int:
	return _used.size()


func free_count() -> int:
	return (last - first + 1) - _used.size()
