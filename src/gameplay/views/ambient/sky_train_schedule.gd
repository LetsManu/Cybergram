class_name SkyTrainSchedule
extends RefCounted
## W18-LIFE: when the sky-train passes. Gaps between passes are 60..120 s,
## drawn from the match seed, measured on the shared match clock (server tick /
## tick rate), so every client sees the same train at the same moment.

const MIN_GAP_S: float = 60.0
const MAX_GAP_S: float = 120.0
## Time from entering to leaving the track (s).
const PASS_S: float = 22.0

var seed_value: int = 0
## Cache: start time of pass `_k` (keeps per-frame queries O(1)).
var _k: int = 0
var _start: float = 0.0


func _init(seed: int = 0) -> void:
	seed_value = seed
	_k = 0
	_start = gap(seed, 0)


## Gap (s) before pass `k` (pass 0: after match start).
static func gap(seed: int, k: int) -> float:
	var h := AmbientMood._mix(seed ^ 0x7472, k * 7919 + 13)
	return MIN_GAP_S + float(h % 1000) / 999.0 * (MAX_GAP_S - MIN_GAP_S)


## Progress 0..1 along the track at match time `t`, or -1 when no train is on it.
func progress(t: float) -> float:
	if t < _start and _k > 0:  # clock went backwards (rejoin): restart the walk
		_k = 0
		_start = gap(seed_value, 0)
	while t >= _start + gap(seed_value, _k + 1):
		_start += gap(seed_value, _k + 1)
		_k += 1
	if t >= _start and t < _start + PASS_S:
		return (t - _start) / PASS_S
	return -1.0


## Start time of the pass index the schedule is on (tests / debug).
func current_start() -> float:
	return _start
