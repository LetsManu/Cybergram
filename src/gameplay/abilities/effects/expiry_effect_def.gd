class_name ExpiryEffectDef
extends EffectDef
## W11-M1 expiry hook: registers `effects` to run when the skill's live deployable
## (Aegis Wall...) ends, by expiry OR destruction (Aegis Mastery heal). Put it after
## the spawning effect in the skill's list / a node's added_effects. The effects run
## with the caster, skill and team of this cast and `point` = where the entity stood.

@export var effects: Array[Resource] = []


func apply(ctx: EffectContext) -> void:
	var d := ctx.world.deployable_of(ctx.skill)
	if d != null:
		d.on_end.append([ctx.with_target(null, d.pos), effects])
