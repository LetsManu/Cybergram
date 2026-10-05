class_name ComfortVignetteModel
extends RefCounted
## Comfort vignette level (W16-COMFORT): soft edge darkening that fades in only
## during fast or forced moves (speed above a threshold, slides and dashes,
## knockback, big vertical speed from jump pads or falls) and fades back out.
## Pure logic: feed it the local hero's motion each frame, read `alpha`.

var rules: ComfortRulesDef
## Current smoothed level 0..1 (before the player's strength).
var level: float = 0.0


func _init(r: ComfortRulesDef = null) -> void:
	rules = r if r != null else ComfortRulesDef.new()


## Instant target level 0..1 for the motion this frame.
func target(velocity: Vector3, forced: bool) -> float:
	if forced:
		return rules.vignette_forced_level
	var horiz := Vector2(velocity.x, velocity.z).length()
	return maxf(ComfortMath.ramp(horiz, rules.vignette_speed_start_mps, rules.vignette_speed_full_mps),
		ComfortMath.ramp(absf(velocity.y), rules.vignette_vertical_start_mps, rules.vignette_vertical_full_mps))


## Advances the level toward the target (fast in, slow out); returns it.
## `forced` = dashing / sliding or knockback.
func step(dt: float, velocity: Vector3, forced: bool) -> float:
	var t := target(velocity, forced)
	var time_s := rules.vignette_fade_in_s if t > level else rules.vignette_fade_out_s
	level = move_toward(level, t, dt / maxf(time_s, 0.001))
	return level


## Final edge alpha for the player's `strength` (0..1; 0 = always fully off).
func alpha(strength: float) -> float:
	return clampf(strength, 0.0, 1.0) * level * rules.vignette_max_alpha
