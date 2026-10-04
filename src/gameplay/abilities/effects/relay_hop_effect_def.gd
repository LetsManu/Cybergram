class_name RelayHopEffectDef
extends EffectDef
## Relay Hop (heroes.md §4.7 S3): the caster teleports to the gadget chosen by
## GADGET targeting (an allied gadget or a Malfunctioning enemy one). Wardling
## targets are followed to where they stand when the channel ends.

@export var trail_s: float = 1.0


func apply(ctx: EffectContext) -> void:
	var h := ctx.caster
	if h == null or h.combat.dead:
		return
	var dest := ctx.point
	if ctx.target != null and is_instance_valid(ctx.target):
		dest = WardlingWorld.feet_of(ctx.target)
	var from := h.state.position
	ctx.with_target(null, from).run(origin_effects)  # W10-T1 Firmware Bomb: effects at the departure point
	_extend_malfunction(ctx, dest)
	ctx.world.teleport(h, dest + Vector3(0.0, 0.05, 0.0))
	ctx.world.add_fx(AbilityWorld.FX_TRAIL, ctx.team, from, dest, ctx.yaw, roundi(trail_s * ctx.world.tick_hz))

## W10-T1 Fork / Mastery hooks: effects that run at the origin before the hop.
@export var origin_effects: Array[Resource] = []


## Mastery (`extra` s): hopping to a Malfunctioning enemy gadget extends it.
func _extend_malfunction(ctx: EffectContext, dest: Vector3) -> void:
	var ext := ctx.ticks(&"extra")
	if ext <= 0:
		return
	var tw := ctx.world.traps
	for g in tw.gadgets_in_radius(dest, 1.5, ctx.team):
		if tw.is_down(g):
			var left := maxi(int(tw.hacks[g][0]) - ctx.world.tick(), 0)
			tw.hack(g, left + ext, 0, true)
