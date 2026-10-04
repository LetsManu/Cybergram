class_name SabotageEffectDef
extends EffectDef
## Sabotage Charge (heroes.md §4.2 S3): plants a charge at ctx.point. It arms after
## `arm_s`, triggers on an enemy hero within `trigger_radius_m` (heroes only), or
## on the recast. At most `max_param` live charges per skill (the oldest is
## removed). Blast: `damage_param` in `radius_param`; `structure_frac` of max
## integrity vs a Ward Generator.

@export var max_param: StringName = &"max_placed"
@export var radius_param: StringName = &"radius"
@export var damage_param: StringName = &"damage"
@export_range(0.0, 10.0, 0.1) var arm_s: float = 1.5
@export_range(0.5, 10.0, 0.1) var trigger_radius_m: float = 3.0
@export_range(0.0, 1.0, 0.01) var structure_frac: float = 0.25


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.plant_charge(ctx, self)
