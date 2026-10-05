class_name AimAssist
extends RefCounted
## Light gamepad aim assist (W11-C1): slows the right-stick turn rate while the
## crosshair is near an enemy hero's hitbox. Purely client-side view input: it
## scales how fast the stick turns the camera and never touches the server's hit
## logic. Mouse look does not use it. Pure functions (unit-testable).


## Turn-rate multiplier for a crosshair `angle_rad` away from the hitbox edge:
## 1 at or beyond `radius_rad`, falling smoothly to `min_scale` on the hitbox.
static func scale_for_angle(angle_rad: float, radius_rad: float, min_scale: float) -> float:
	if radius_rad <= 0.0 or angle_rad >= radius_rad:
		return 1.0
	var t := clampf(angle_rad / radius_rad, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)  # smoothstep: no pop at the radius edge
	return lerpf(clampf(min_scale, 0.0, 1.0), 1.0, t)


## Strongest slowdown over `targets` (hitbox centres relative to the eye).
## `forward` is the unit view direction; `hit_radius_m` the hitbox radius, so the
## angle is measured to the hitbox edge; targets beyond `max_range_m` or behind
## the view are ignored. Returns 1.0 when nothing is near.
static func scale_for_targets(forward: Vector3, targets: Array, radius_deg: float,
		min_scale: float, hit_radius_m: float, max_range_m: float) -> float:
	var best := 1.0
	var radius := deg_to_rad(radius_deg)
	for t in targets:
		var rel: Vector3 = t
		var dist := rel.length()
		if dist < 0.01 or dist > max_range_m:
			continue
		var ang := forward.angle_to(rel / dist)
		ang = maxf(0.0, ang - atan2(hit_radius_m, dist))
		best = minf(best, scale_for_angle(ang, radius, min_scale))
	return best
