class_name EclipseRiderEffectDef
extends EffectDef
## Eclipse Step rank 3 rider (heroes.md §4.2): a kill inside the mark window
## re-enters Veilwalk for free and refunds `refund_frac` of the ultimate cooldown.
## Appended to the skill by its rank-3 node.

@export_range(0.0, 1.0, 0.01) var refund_frac: float = 0.3


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.arm_rider(ctx.caster, refund_frac)
