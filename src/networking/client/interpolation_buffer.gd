class_name InterpolationBuffer
extends RefCounted
## Snapshot interpolation for one remote entity (ADR-0002 §6). Holds the newest
## samples by server tick; sample() interpolates at a fractional render tick and
## extrapolates at most `extrapolation_cap_ticks` past the newest sample.

const CAPACITY: int = 16

var extrapolation_cap_ticks: int
var _ticks: PackedInt64Array = PackedInt64Array()
var _pos: PackedVector3Array = PackedVector3Array()
var _yaw: PackedFloat32Array = PackedFloat32Array()
var _crouch: Array[bool] = []

## Results of the last sample().
var position: Vector3
var yaw: float
var crouching: bool


func _init(extrapolation_cap: int) -> void:
	extrapolation_cap_ticks = extrapolation_cap


## Adds a sample; out-of-order or duplicate ticks are ignored.
func push(tick: int, pos: Vector3, yaw_rad: float, is_crouching: bool) -> void:
	if not _ticks.is_empty() and tick <= _ticks[_ticks.size() - 1]:
		return
	_ticks.append(tick)
	_pos.append(pos)
	_yaw.append(yaw_rad)
	_crouch.append(is_crouching)
	if _ticks.size() > CAPACITY:
		_ticks.remove_at(0)
		_pos.remove_at(0)
		_yaw.remove_at(0)
		_crouch.remove_at(0)


func newest_tick() -> int:
	return -1 if _ticks.is_empty() else _ticks[_ticks.size() - 1]


## Interpolates at `render_tick`. Returns false if there is no sample yet.
func sample(render_tick: float) -> bool:
	var n := _ticks.size()
	if n == 0:
		return false
	if n == 1 or render_tick <= _ticks[0]:
		var j := 0 if render_tick <= _ticks[0] else n - 1
		position = _pos[j]
		yaw = _yaw[j]
		crouching = _crouch[j]
		return true
	var hi := n - 1
	if render_tick >= _ticks[hi]:
		# Extrapolate from the last two samples, capped.
		var t := minf(render_tick, _ticks[hi] + extrapolation_cap_ticks)
		var lo := hi - 1
		var a := (t - _ticks[lo]) / float(_ticks[hi] - _ticks[lo])
		position = _pos[lo].lerp(_pos[hi], a)
		yaw = lerp_angle(_yaw[lo], _yaw[hi], a)
		crouching = _crouch[hi]
		return true
	while _ticks[hi - 1] > render_tick:
		hi -= 1
	var lo2 := hi - 1
	var alpha := (render_tick - _ticks[lo2]) / float(_ticks[hi] - _ticks[lo2])
	position = _pos[lo2].lerp(_pos[hi], alpha)
	yaw = lerp_angle(_yaw[lo2], _yaw[hi], alpha)
	crouching = _crouch[lo2] if alpha < 0.5 else _crouch[hi]
	return true
