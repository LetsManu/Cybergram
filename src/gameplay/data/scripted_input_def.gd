class_name ScriptedInputDef
extends Resource
## A repeating, deterministic input pattern for dummy entities and tests.
## Bots (ADR-0005) will replace this with brains that emit the same InputCommand.

## Move vectors (x = strafe right, y = forward), each held for ticks_per_segment.
@export var segments: PackedVector2Array = PackedVector2Array([Vector2(0.0, 1.0)])
@export_range(1, 600) var ticks_per_segment: int = 30
## Initial facing (degrees, 0 = -Z) and turn rate per tick.
@export_range(-360.0, 360.0, 0.5) var start_yaw_deg: float = 0.0
@export_range(-45.0, 45.0, 0.1) var yaw_deg_per_tick: float = 0.0
## Fixed look pitch (degrees, positive looks up).
@export_range(-89.0, 89.0, 0.1) var pitch_deg: float = 0.0
## Hold sprint the whole time.
@export var sprint: bool = false
## Press jump once every N ticks (0 = never).
@export_range(0, 600) var jump_interval_ticks: int = 0
## Hold crouch during these segment indices.
@export var crouch_segments: PackedInt32Array = PackedInt32Array()
## Fire held for fire_hold_ticks out of every fire_period_ticks (0 = never fire).
@export_range(0, 600) var fire_period_ticks: int = 0
@export_range(0, 600) var fire_hold_ticks: int = 1
