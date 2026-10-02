class_name SquadOrderEffectDef
extends EffectDef
## Rally Beacon double-tap (heroes.md §4.1 S2): orders the caster's squad (and
## a conducted wave) to Hold Here at the skill's live deployable, or Go Capture
## when the deployable stands in a hardpoint zone.


func apply(ctx: EffectContext) -> void:
	ctx.world.order_squad_to_deployable(ctx)
