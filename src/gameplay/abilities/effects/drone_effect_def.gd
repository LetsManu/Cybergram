class_name DroneEffectDef
extends EffectDef
## Med-Pack Drone (heroes.md §4.6 S1): lands at ctx.point, flies to the most
## injured ally (heroes incl. the caster, Wardlings) within `radius_param` and
## heals `heal_param` HP/s (SkillPower-scaled) for `duration_param` s. Waits up
## to `wait_s` s for someone to be hurt.

@export var radius_param: StringName = &"radius"
@export var heal_param: StringName = &"heal_per_s"
@export var duration_param: StringName = &"duration"
@export_range(0.0, 10.0, 0.1) var wait_s: float = 2.0
@export_range(1.0, 40.0, 0.5) var fly_speed: float = 14.0


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.spawn_drone(ctx, self)
