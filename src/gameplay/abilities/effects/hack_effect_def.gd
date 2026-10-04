class_name HackEffectDef
extends EffectDef
## Breach Spike hit (heroes.md §4.7 S1, §3.7, §5.4). On a gadget (Wardling, or
## a Deployable via AbilityWorld's projectile hook): Malfunction for the
## category duration x the skill's `duration` multiplier (base 1, +0.25 Boost).
## On an enemy hero: `damage` and Scramble for `scramble` s. Heroes, Uplinks,
## Ward Generators, Mana Cells and HQ buildings are never gadgets.

## Category base durations (s) and post-hack immunity (s), heroes.md §3.7.
@export var trap_s: float = 6.0
@export var turret_s: float = 4.0
@export var deployable_s: float = 3.0
@export var wardling_s: float = 3.0
@export var barricade_s: float = 4.0
@export var immune_s: float = 4.0
@export var scale_param: StringName = &"duration"
@export var damage_param: StringName = &"damage"
@export var scramble_param: StringName = &"scramble"


func apply(ctx: EffectContext) -> void:
	var t := ctx.target
	if t == null:
		return
	if t is HeroBody:
		var h := t as HeroBody
		if h.combat.team == ctx.team or h.combat.dead:
			return
		ctx.world.skill_damage(ctx, h, ctx.power_param(damage_param))
		ctx.world.traps.scramble(h, ctx.ticks(scramble_param))
	elif t is WardlingSim and (t as WardlingSim).team != ctx.team:
		hack_gadget(ctx, t)


## Malfunctions `gadget` (WardlingSim or AbilityWorld.Deployable).
func hack_gadget(ctx: EffectContext, gadget: Object) -> bool:
	var w := ctx.world
	return w.traps.hack(gadget, w.traps.category_ticks(gadget, self, ctx.param(scale_param)),
		roundi(immune_s * w.tick_hz))
