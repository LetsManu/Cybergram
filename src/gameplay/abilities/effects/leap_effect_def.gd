class_name LeapEffectDef
extends EffectDef
## Earthbreaker (heroes.md §4.5 Ult): a ballistic leap to ctx.point in
## `leap_time` s with a landing marker visible to everyone; `on_land` runs at
## the landing spot.

@export var time_param: StringName = &"leap_time"
@export var marker_radius_param: StringName = &"radius"
@export var on_land: Array[Resource] = []


func apply(ctx: EffectContext) -> void:
	ctx.world.start_leap(ctx, self)
