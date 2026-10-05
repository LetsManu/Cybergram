class_name CorrectionSmoother
extends RefCounted
## Presentation-only blend of prediction corrections (W16-COMFORT, smooth
## corrections). When reconciliation moves the predicted position by a small
## error, the camera and rendered position keep the OLD place (`offset`) and fade
## toward the corrected one over ~`time_s`. A large error (teleport, respawn,
## knockback over `threshold_m`) clears the offset: the view snaps.
## It never touches the simulated or predicted state, nor what is sent.
##
## Usage: smoother.push(predictor.reconcile(...), rules.smooth_threshold_m);
## each frame smoother.step(dt, rules.smooth_time_s); draw at pos + offset.

## Added to the rendered position (old position - new position, decaying to 0).
var offset: Vector3 = Vector3.ZERO
## Offsets shorter than this (metres) are dropped (no endless tail).
const EPSILON_M: float = 0.001
## exp(-DECAY_K) = 5%: "about gone" after time_s.
const DECAY_K: float = 3.0


## Adds a reconciliation error (old predicted - new predicted). Returns true when
## the view snapped (error or the accumulated offset reached `threshold_m`).
func push(error: Vector3, threshold_m: float) -> bool:
	if error == Vector3.ZERO:
		return false
	var total := offset + error
	if error.length() >= threshold_m or total.length() >= threshold_m:
		offset = Vector3.ZERO
		return true
	offset = total
	return false


## Fades the offset over `dt`; time_s <= 0 snaps at once.
func step(dt: float, time_s: float) -> void:
	if offset == Vector3.ZERO:
		return
	if time_s <= 0.0:
		offset = Vector3.ZERO
		return
	offset *= exp(-DECAY_K * maxf(dt, 0.0) / time_s)
	if offset.length() < EPSILON_M:
		offset = Vector3.ZERO


func reset() -> void:
	offset = Vector3.ZERO
