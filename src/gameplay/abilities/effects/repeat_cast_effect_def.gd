class_name RepeatCastEffectDef
extends EffectDef
## W11-M1 recast effect (Ryker Tactical Slide Fork B, Rebound): the second press
## inside the recast window runs the skill's whole effect list again.


func apply(ctx: EffectContext) -> void:
	if ctx.skill != null:
		ctx.run(ctx.skill.effects())
