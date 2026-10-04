class_name DelayedEffectDef
extends EffectDef
## Runs `effects` at ctx.point after `delay_s` s (Flash Bloom fuse). A small
## orb marks the spot while it waits.

@export_range(0.0, 5.0, 0.05) var delay_s: float = 0.3
@export var effects: Array[Resource] = []


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.schedule(ctx, roundi(delay_s * ctx.world.tick_hz), effects)
