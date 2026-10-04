class_name HpCostEffectDef
extends EffectDef
## W10-T1: the caster pays HP (never below 1), e.g. Stim's Overdrive Fork
## (heroes.md §4.4: HP cost rises to 40). Amount from a skill param.

@export var amount_param: StringName = &"extra_b"


func apply(ctx: EffectContext) -> void:
	var c := ctx.caster.combat if ctx.caster != null else null
	if c != null and not c.dead:
		c.health.hp = maxf(SkillEntities.MIN_HP, c.health.hp - ctx.param(amount_param))
