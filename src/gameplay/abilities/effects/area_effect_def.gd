class_name AreaEffectDef
extends EffectDef
## Runs child effects on every matching entity within `radius_param` of
## ctx.point (flat distance): heroes and/or Wardlings, enemies and/or allies.

@export var radius_param: StringName = &"radius"
@export var enemies: bool = true
@export var allies: bool = false
@export var heroes: bool = true
@export var wardlings: bool = true
@export var include_caster: bool = false
@export var effects: Array[Resource] = []


func apply(ctx: EffectContext) -> void:
	var r := ctx.param(radius_param)
	for t in ctx.world.entities_in_radius(ctx.point, r, ctx.team, enemies, allies, heroes, wardlings):
		if t == ctx.caster and not include_caster:
			continue
		ctx.with_target(t, ctx.point).run(effects)
