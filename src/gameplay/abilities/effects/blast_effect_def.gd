class_name BlastEffectDef
extends EffectDef
## Radial explosion at ctx.point (grenade, heroes.md §4.4 S1): skill damage
## to enemy heroes and Wardlings in `radius_param`, linear falloff to
## `min_falloff` at the edge, `wardling_mult` vs Wardlings, blocked by level geometry.

@export var radius_param: StringName = &"radius"
@export var damage_param: StringName = &"damage"
@export_range(0.0, 1.0, 0.01) var min_falloff: float = 0.4
@export_range(0.0, 5.0, 0.05) var wardling_mult: float = 1.5


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.blast(ctx, self)
