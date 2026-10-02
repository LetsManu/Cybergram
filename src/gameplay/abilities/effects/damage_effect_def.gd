class_name DamageEffectDef
extends EffectDef
## Skill damage to ctx.target (enemy hero, Wardling or deployable), scaled by
## SkillPower. Goes through HealthComponent like every damage (ADR-0004 §7).

@export var amount_param: StringName = &"damage"


func apply(ctx: EffectContext) -> void:
	if ctx.target != null:
		ctx.world.skill_damage(ctx, ctx.target, ctx.power_param(amount_param))
