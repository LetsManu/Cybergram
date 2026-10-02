class_name RewriteEffectDef
extends EffectDef
## Rewrite (heroes.md §4.1 Ult): every Wardling within `radius` of the caster:
## allied -> Elite for `duration` s (rewrite_to_elite); enemy squad / Vanguard
## -> Turned to the caster for `secondary_duration` s (subvert).

@export var radius_param: StringName = &"radius"
@export var elite_param: StringName = &"duration"
@export var turned_param: StringName = &"secondary_duration"


func apply(ctx: EffectContext) -> void:
	ctx.world.rewrite(ctx, ctx.param(radius_param), ctx.ticks(elite_param), ctx.ticks(turned_param))
