class_name SnapBackEffectDef
extends EffectDef
## W11-M1 recast effect (Sable Phase Shift Fork A, Echo): the caster snaps back to
## where the skill was cast from (SkillInstance.recast_point).


func apply(ctx: EffectContext) -> void:
	if ctx.caster == null or ctx.skill == null or ctx.caster.combat.dead:
		return
	ctx.world.teleport(ctx.caster, ctx.skill.recast_point)
