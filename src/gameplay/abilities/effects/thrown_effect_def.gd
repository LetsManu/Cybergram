class_name ThrownEffectDef
extends EffectDef
## Throws a bouncing body from the eye along the aim (Frag Grenade, heroes.md
## §4.4 S1): gravity, bounces off level geometry, and after `fuse_param` s (or on
## the first impact when `on_impact`) runs `on_detonate` at its position.

@export var speed_param: StringName = &"speed"
@export var fuse_param: StringName = &"duration"
## PLACEHOLDER. Upward aim lift added to the throw direction.
@export var lift: float = 0.18
## PLACEHOLDER. Gravity (m/s^2) and bounce velocity retention.
@export var gravity: float = 20.0
@export_range(0.0, 1.0, 0.01) var bounce: float = 0.45
@export var on_impact: bool = false
@export var on_detonate: Array[Resource] = []


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.launch_thrown(ctx, self)
