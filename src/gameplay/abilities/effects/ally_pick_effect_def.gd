class_name AllyPickEffectDef
extends EffectDef
## Soft-targets the allied hero nearest the crosshair (cone `cone_deg`, within
## `range_param`, line of sight) and runs `effects` on it; falls back to the caster
## when none is aimed at (Prism Ward, heroes.md §4.6 S2).

@export var range_param: StringName = &"range"
@export_range(1.0, 45.0, 0.5) var cone_deg: float = 12.0
@export var effects: Array[Resource] = []


func apply(ctx: EffectContext) -> void:
	var t: HeroBody = ctx.world.extras.pick_ally_hero(ctx.caster, ctx.origin, ctx.dir, ctx.param(range_param), cone_deg)
	if t == null:
		t = ctx.caster
	ctx.with_target(t, t.state.position).run(effects)
