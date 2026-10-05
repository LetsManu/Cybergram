class_name RevealEffectDef
extends EffectDef
## W11-M1: reveals the effect target (an enemy hero) to the caster's team through
## walls for `duration_param` seconds (heroes.md §4 Reveal). Wardlings are not
## revealed (they have no fog of war).

@export var duration_param: StringName = &"reveal"


func apply(ctx: EffectContext) -> void:
	var h := ctx.target as HeroBody
	if h == null or h.combat == null or h.combat.dead or h.combat.team == ctx.team:
		return
	ctx.world.reveals.reveal(h.net_id, ctx.team, ctx.ticks(duration_param), ctx.world.server.tick)
