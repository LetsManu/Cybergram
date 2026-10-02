class_name SwapEffectDef
extends EffectDef
## Threadstep (heroes.md §4.1 S3): the caster and ctx.target (an own or
## conducted Wardling) swap positions; a thread trail shows where she went.

## heroes.md: "the swap leaves a 1 s thread trail".
@export var trail_s: float = 1.0


func apply(ctx: EffectContext) -> void:
	if ctx.target != null:
		ctx.world.swap_with(ctx, ctx.target, trail_s)
