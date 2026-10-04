class_name SabotageDetonateEffectDef
extends EffectDef
## Remote detonation of every live Sabotage Charge of the caster (recast of the
## skill, heroes.md §4.2 S3).


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.detonate_charges(ctx.caster)
