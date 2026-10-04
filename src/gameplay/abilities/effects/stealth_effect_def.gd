class_name StealthEffectDef
extends EffectDef
## Veilwalk (heroes.md §4.2 S1): stealth for `duration_param` s, +`speed_bonus`
## move speed. Firing, using another skill or taking damage ends it (the skill
## cooldown then starts). Clients fade the hero by distance (AbilityPresenter).

@export var duration_param: StringName = &"duration"
@export_range(0.0, 1.0, 0.01) var speed_bonus: float = 0.15


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.stealth_start(ctx.caster, ctx.skill, ctx.ticks(duration_param), speed_bonus)
