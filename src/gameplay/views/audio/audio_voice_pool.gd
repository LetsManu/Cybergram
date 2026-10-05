class_name AudioVoicePool
extends RefCounted
## W21-A1: voice allocation for a fixed set of players (pure logic, no nodes).
## Rules (audio direction spec §2):
##  * an event already at its `max_voices` steals its own oldest voice;
##  * otherwise a free slot is used;
##  * otherwise the least important (highest priority number), oldest voice is
##    stolen, but only when it is not more important than the new sound;
##    else the new sound is dropped (-1).

var _event: Array[StringName] = []
var _priority: PackedInt32Array = PackedInt32Array()
var _start: PackedInt64Array = PackedInt64Array()
var _busy: Array[bool] = []
var _seq: int = 0  # tie-break for equal start times


func _init(slots: int) -> void:
	for i in slots:
		_event.append(&"")
		_priority.append(3)
		_start.append(0)
		_busy.append(false)


func size() -> int:
	return _busy.size()


func is_busy(slot: int) -> bool:
	return _busy[slot]


func event_at(slot: int) -> StringName:
	return _event[slot]


## Marks a slot free (its player finished or was stopped).
func release(slot: int) -> void:
	_busy[slot] = false


## Number of busy voices playing `event_id`.
func count(event_id: StringName) -> int:
	var n := 0
	for i in _busy.size():
		if _busy[i] and _event[i] == event_id:
			n += 1
	return n


## Slot for a new voice of `event_id` at `priority` (0 = most important), or -1.
## `now` is any monotonic counter (msec); equal times fall back to call order.
func claim(event_id: StringName, priority: int, max_voices: int, now: int) -> int:
	var slot := -1
	if count(event_id) >= maxi(max_voices, 1):
		slot = _oldest(func(i: int) -> bool: return _event[i] == event_id)
	if slot < 0:
		for i in _busy.size():
			if not _busy[i]:
				slot = i
				break
	if slot < 0:
		var worst := -1
		for i in _busy.size():
			worst = maxi(worst, _priority[i])
		if worst < priority:
			return -1  # every voice is more important than the new sound
		slot = _oldest(func(i: int) -> bool: return _priority[i] == worst)
	_seq += 1
	_event[slot] = event_id
	_priority[slot] = priority
	_start[slot] = now * 1024 + (_seq % 1024)
	_busy[slot] = true
	return slot


func _oldest(match_fn: Callable) -> int:
	var best := -1
	for i in _busy.size():
		if _busy[i] and match_fn.call(i) and (best < 0 or _start[i] < _start[best]):
			best = i
	return best
