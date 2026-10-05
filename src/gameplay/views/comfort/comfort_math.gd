class_name ComfortMath
extends RefCounted
## Pure helpers for the Comfort options (W16-COMFORT). No nodes, so unit-testable.


## Viewmodel offset / scale factor for `fov_deg`: tan(fov/2) / tan(ref/2). A
## fixed-position gun drifts to the centre and shrinks as the FOV widens; this
## keeps its screen footprint. 1.0 at the reference FOV (90).
static func viewmodel_fov_factor(fov_deg: float, ref_fov_deg: float = 90.0) -> float:
	var half := deg_to_rad(clampf(fov_deg, 30.0, 170.0)) * 0.5
	var ref_half := deg_to_rad(clampf(ref_fov_deg, 30.0, 170.0)) * 0.5
	return tan(half) / tan(ref_half)


## The part of the full view punch the camera does NOT show (full - scaled):
## the viewmodel spends it, so the gun kicks even at camera recoil 0.
static func hidden_kick(kick: Vector2, camera_scale: float) -> Vector2:
	return kick * (1.0 - clampf(camera_scale, 0.0, 1.0))


## Linear 0..1 ramp between `start` and `full` (0 below start, 1 at/above full).
static func ramp(v: float, start: float, full: float) -> float:
	if full <= start:
		return 1.0 if v >= start else 0.0
	return clampf((v - start) / (full - start), 0.0, 1.0)


## Screen offset (pixels, +x right, +y down) of where a shot lands relative to the
## screen centre when the camera does not show `kick` (x yaw, + left; y pitch, +
## up; radians). Perspective projection with the camera's vertical `fov_deg`:
## offset = tan(angle) / tan(half_fov) * half_extent. Zero kick = zero offset.
static func kick_to_screen_px(kick: Vector2, fov_deg: float, viewport: Vector2) -> Vector2:
	var tan_v := tan(deg_to_rad(clampf(fov_deg, 30.0, 170.0)) * 0.5)
	var aspect := viewport.x / maxf(viewport.y, 1.0)
	var tan_h := tan_v * aspect
	return Vector2(-tan(kick.x) / tan_h * viewport.x * 0.5, -tan(kick.y) / tan_v * viewport.y * 0.5)
