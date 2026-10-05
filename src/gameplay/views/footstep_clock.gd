class_name FootstepClock
extends RefCounted
## W11-C1: decides when the own hero's footstep sounds. Cadence follows ground
## speed (one step per `stride_m` walked, so sprinting steps faster); nothing
## while airborne or below `min_speed`. Landing restarts the stride. Pure logic.

var stride_m: float = 2.3
var min_speed: float = 1.2
var _walked_m: float = 0.0
var _was_grounded: bool = true


func _init(stride: float = 2.3, min_speed_mps: float = 1.2) -> void:
	stride_m = stride
	min_speed = min_speed_mps


## Advances by `dt`; true when a step sound is due. `stride_mult` > 1 lengthens
## the stride (crouching).
func advance(ground_speed: float, grounded: bool, dt: float, stride_mult: float = 1.0) -> bool:
	if not grounded or ground_speed < min_speed:
		_was_grounded = grounded
		if not grounded or ground_speed <= 0.0:
			_walked_m = 0.0
		return false
	var landed := not _was_grounded
	_was_grounded = true
	_walked_m += ground_speed * dt
	var stride := maxf(stride_m * stride_mult, 0.1)
	if landed or _walked_m >= stride:
		_walked_m = fmod(_walked_m, stride) if not landed else 0.0
		return true
	return false
