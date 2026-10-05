class_name StickMath
extends RefCounted
## Gamepad stick shaping (W11-C1): radial dead zone with rescale, then a power
## response curve. Pure functions, no Input access (unit-testable).


## Shapes a raw stick vector (|v| <= 1). Inside `deadzone` -> zero; outside, the
## magnitude is rescaled so the output rises smoothly from 0 at the dead-zone
## edge to 1 at full deflection, then raised to `curve` (1 = linear, >1 = finer
## control near the centre). Direction is preserved (radial, not per-axis).
static func shape(raw: Vector2, deadzone: float, curve: float) -> Vector2:
	var len := raw.length()
	var dz := clampf(deadzone, 0.0, 0.95)
	if len <= dz or len <= 0.0:
		return Vector2.ZERO
	var t := clampf((len - dz) / (1.0 - dz), 0.0, 1.0)
	return raw / len * pow(t, maxf(curve, 0.1))
