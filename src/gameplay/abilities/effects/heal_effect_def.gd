class_name HealEffectDef
extends EffectDef
## W10-T1: instant heal (or, when the amount is negative, an HP cost that
## never kills) of the effect target, or of the caster. Used by Fork / Mastery
## nodes (Adrenal, Lifeblood, Sanctuary...). The amount is a skill param so the
## numbers stay in the node's modifiers.

@export var amount_param: StringName = &"count"
@export var on_caster: bool = false
## Scales the amount with SkillPower (heals do, HP costs do not).
@export var use_skill_power: bool = true


func apply(ctx: EffectContext) -> void:
	var t: Node3D = ctx.caster if on_caster else ctx.target
	if t == null:
		return
	var amount := ctx.power_param(amount_param) if use_skill_power else ctx.param(amount_param)
	if t is HeroBody:
		var c := (t as HeroBody).combat
		if c.dead or c.team != ctx.team:
			return
		c.health.heal(amount)
	elif t is WardlingSim:
		var w := t as WardlingSim
		if w.dead or w.team != ctx.team:
			return
		w.health.heal(amount)
