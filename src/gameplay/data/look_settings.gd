class_name LookSettings
extends Resource
## Client-side look preferences (architecture.md §4 UserSettings owns these once
## it exists; until then the default .tres is loaded directly).

## Degrees of yaw/pitch per pixel of mouse motion.
@export_range(0.001, 1.0, 0.001) var mouse_sensitivity_deg: float = 0.12
## Invert vertical mouse look.
@export var invert_y: bool = false
## Camera vertical field of view (degrees).
@export_range(50.0, 120.0, 0.5) var fov_deg: float = 90.0

@export_group("Gamepad")
## Right-stick turn rate at full deflection (deg/s).
@export_range(30.0, 720.0, 1.0) var pad_sensitivity_deg_s: float = 180.0
## Radial dead zone (0..0.5) and response-curve exponent (1 = linear).
@export_range(0.0, 0.5, 0.01) var pad_deadzone: float = 0.15
@export_range(1.0, 3.0, 0.05) var pad_curve: float = 1.6
@export var pad_invert_y: bool = false
## Gamepad aim assist on/off (player option).
@export var aim_assist: bool = true

@export_group("Aim assist tuning")
## Slowdown starts this many degrees outside an enemy hitbox edge.
@export_range(0.5, 15.0, 0.1) var aim_assist_radius_deg: float = 4.0
## Turn-rate multiplier right on the hitbox (1 = no assist).
@export_range(0.1, 1.0, 0.01) var aim_assist_min_scale: float = 0.45
## Assumed hitbox radius and centre height above the feet (metres).
@export_range(0.1, 1.0, 0.01) var aim_assist_hit_radius_m: float = 0.4
@export_range(0.3, 1.8, 0.05) var aim_assist_center_height_m: float = 1.2
## Enemies farther than this do not slow the aim.
@export_range(5.0, 200.0, 1.0) var aim_assist_max_range_m: float = 60.0
