class_name WardlingPrioritiser
extends RefCounted
## W16-NET relevance / priority for ONE client's Wardling updates (heroes,
## hardpoints, objectives and skill FX are never deferred: they are few, and
## enemy heroes in weapon range must never lag; see SnapshotCodec).
##
## Priority accumulator: every tick each Wardling's accumulator grows by its
## weight - 1.0 when relevant (the client's own squad, within `near_m`, or
## inside the view cone up to `view_m`), 1 / far_interval_ticks otherwise
## (10 Hz at 30 Hz with 3). A Wardling is eligible once its accumulator reaches
## 1.0; eligible ones go oldest-first (highest accumulator), so when the byte
## budget is short the longest-waiting updates win and nothing starves: an
## entity's accumulator only grows until it is sent. It resets when the client's
## view of it is current (sent, or unchanged against the baseline).
##
## Example:
##   encoder.prioritiser = WardlingPrioritiser.new(net)

var near_m: float = 40.0
var view_m: float = 90.0
var view_cos: float = cos(deg_to_rad(55.0))
var far_interval_ticks: int = 3
var _acc: Dictionary = {}  # key -> float
## Diagnostics of the last order(): relevant / far counts.
var last_relevant: int = 0
var last_far: int = 0


func _init(net: NetConfig = null) -> void:
	if net != null:
		near_m = net.relevance_near_m
		view_m = net.relevance_view_m
		view_cos = cos(deg_to_rad(net.relevance_view_half_angle_deg))
		far_interval_ticks = maxi(net.far_send_interval_ticks, 1)


## True when Wardling `w` must be fresh every tick for the client at `eye`
## looking along `fwd` (flat, normalised; zero = no view cone) owning `own_id`.
func is_relevant(w: SnapshotData.WardlingState, eye: Vector3, fwd: Vector3, own_id: int) -> bool:
	if own_id != 0 and w.owner_net_id == own_id:
		return true
	var d := w.position - eye
	var dist2 := d.x * d.x + d.z * d.z
	if dist2 <= near_m * near_m:
		return true
	if fwd == Vector3.ZERO or dist2 > view_m * view_m:
		return false
	var flat := Vector3(d.x, 0.0, d.z) / sqrt(dist2)
	return flat.dot(fwd) >= view_cos


## Wardling keys eligible this tick, highest accumulator first (SnapshotEncoder hook).
func order(s: SnapshotData, _base: Variant, _tick: int) -> Array:
	var eye := Vector3.ZERO
	var fwd := Vector3.ZERO
	var has_eye := s.own_state != null
	if has_eye:
		eye = s.own_state.position
		for e in s.entities:
			if e.net_id == s.own_net_id:
				fwd = Vector3(-sin(e.yaw), 0.0, -cos(e.yaw))  # Godot forward is -Z at yaw 0
				break
	var far_w := 1.0 / far_interval_ticks
	var live := {}
	var eligible: Array = []
	last_relevant = 0
	last_far = 0
	for w in s.wardlings:
		var k := w.net_id & 0xFFFF
		live[k] = true
		var rel := not has_eye or is_relevant(w, eye, fwd, s.own_net_id)
		if rel:
			last_relevant += 1
		else:
			last_far += 1
		var a: float = _acc.get(k, 0.0) + (1.0 if rel else far_w)
		_acc[k] = a
		if a >= 1.0 - 1e-6:
			eligible.append(k)
	for k in _acc.keys():
		if not live.has(k):
			_acc.erase(k)
	eligible.sort_custom(func(x: int, y: int) -> bool:
		var ax: float = _acc[x]
		var ay: float = _acc[y]
		return ax > ay if not is_equal_approx(ax, ay) else x < y)
	return eligible


## The client's view of `keys` is current at this tick (SnapshotEncoder hook).
func sent(keys: Array, _tick: int) -> void:
	for k in keys:
		if _acc.has(k):
			_acc[k] = 0.0


## Accumulator of `key` (tests).
func accumulator(key: int) -> float:
	return _acc.get(key, 0.0)
