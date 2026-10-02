class_name StatusEffectDef
extends EffectDef
## Applies a StatusComponent status (heroes.md §3.6) to ctx.target, or to the
## caster when `on_caster`. Wardlings only take STUN (as a stall).

@export var kind: StatusComponent.Kind = StatusComponent.Kind.SLOW
@export var duration_param: StringName = &"duration"
## Param for the magnitude (slow fraction, DR fraction, shield HP); empty = `magnitude`.
@export var magnitude_param: StringName = &""
@export var magnitude: float = 0.0
@export var on_caster: bool = false


func apply(ctx: EffectContext) -> void:
	var t: Node3D = ctx.caster if on_caster else ctx.target
	if t == null:
		return
	var mag := magnitude if magnitude_param == &"" else ctx.param(magnitude_param)
	if kind == StatusComponent.Kind.SHIELD and magnitude_param != &"":
		mag = ctx.power_param(magnitude_param)
	ctx.world.apply_status(ctx, t, kind, ctx.ticks(duration_param), mag)
