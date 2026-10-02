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
