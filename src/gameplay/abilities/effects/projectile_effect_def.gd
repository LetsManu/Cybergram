class_name ProjectileEffectDef
extends EffectDef
## Launches an aimed skill projectile from the caster's eye along ctx.dir
## (Marionette Thread: 60 m/s, 30 m). On the first enemy hit (hero or
## Wardling) it runs `on_hit` with that target. Walls block it.

@export var speed_param: StringName = &"speed"
@export var range_param: StringName = &"range"
## PLACEHOLDER. Extra hit radius around the projectile (m).
@export var hit_radius_m: float = 0.25
@export var on_hit: Array[Resource] = []


func apply(ctx: EffectContext) -> void:
	ctx.world.launch_projectile(ctx, ctx.param(speed_param), ctx.param(range_param), hit_radius_m, on_hit)
