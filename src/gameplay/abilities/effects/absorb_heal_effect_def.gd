class_name AbsorbHealEffectDef
extends EffectDef
## W11-M1 expiry hook for statuses (Fortify Fork B, Lifeblood): opens a window on
## the caster; when it ends the caster heals `frac_param` of the damage the
## caster's damage reduction absorbed during it.

@export var duration_param: StringName = &"duration"
@export var frac_param: StringName = &"recast_value"


func apply(ctx: EffectContext) -> void:
	ctx.world.open_absorb_window(ctx, ctx.ticks(duration_param), ctx.param(frac_param))
