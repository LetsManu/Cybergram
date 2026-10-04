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
	ctx.world.teleport(h, dest + Vector3(0.0, 0.05, 0.0))
	ctx.world.add_fx(AbilityWorld.FX_TRAIL, ctx.team, from, dest, ctx.yaw, roundi(trail_s * ctx.world.tick_hz))
