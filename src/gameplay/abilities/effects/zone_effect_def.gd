class_name ZoneEffectDef
extends EffectDef
## Killbox (Juniper ult, heroes.md §4.3) and Static Field (Hex S2, §4.7): a
## timed zone at ctx.point. Radius, duration and (Killbox) emitter HP come from
## the skill's params. Behaviour lives in TrapWorld.

enum Kind { KILLBOX, FIELD }

@export var kind: Kind = Kind.KILLBOX
@export var duration_param: StringName = &"duration"
@export var hp_param: StringName = &"hp"
@export var radius_param: StringName = &"radius"


func apply(ctx: EffectContext) -> void:
	var t := ctx.world.traps
	if kind == Kind.KILLBOX:
		t.spawn_zone(ctx, TrapWorld.KIND_KILLBOX, ctx.param(duration_param), ctx.param(hp_param), TrapWorld.FX_DOME,
			ctx.param(radius_param))
	else:
		t.spawn_zone(ctx, TrapWorld.KIND_FIELD, ctx.param(duration_param), 0.0, TrapWorld.FX_FIELD, ctx.param(radius_param))
