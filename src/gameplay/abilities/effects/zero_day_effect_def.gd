class_name ZeroDayEffectDef
extends EffectDef
## Zero Day (heroes.md §4.7 Ult): a pulse at ctx.point. Every enemy gadget in
## the radius Malfunctions for `duration` s IGNORING post-hack immunity; enemy
## heroes are Scrambled `scramble` s and their READY basic skills get `lag` s
## of cooldown. Never touches heroes' guns.

@export var radius_param: StringName = &"radius"
@export var duration_param: StringName = &"duration"
@export var scramble_param: StringName = &"scramble"
@export var lag_param: StringName = &"lag"


func apply(ctx: EffectContext) -> void:
	var w := ctx.world
	var r := ctx.param(radius_param)
	w.add_fx(TrapWorld.FX_PULSE, ctx.team, ctx.point, Vector3(r, 0.0, 0.0), 0.0, roundi(AbilityWorld.BURST_S * 2.0 * w.tick_hz))
	for g in w.traps.gadgets_in_radius(ctx.point, r, ctx.team):
		w.traps.hack(g, ctx.ticks(duration_param), 0, true)
	for e in w.entities_in_radius(ctx.point, r, ctx.team, true, false, true, false):
		var h := e as HeroBody
		w.traps.scramble(h, ctx.ticks(scramble_param))
		w.traps.lag(h, ctx.ticks(lag_param))
