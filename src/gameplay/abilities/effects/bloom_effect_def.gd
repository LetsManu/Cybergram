class_name BloomEffectDef
extends EffectDef
## Flash Bloom burst (heroes.md §4.6 S3) at ctx.point: enemy heroes within
## `radius_param` whose facing is within `facing_deg` of it are Blinded for
## `blind_param` s and knocked back `knock_param` m.

@export var radius_param: StringName = &"radius"
@export var blind_param: StringName = &"duration"
@export var knock_param: StringName = &"distance"
@export_range(10.0, 180.0, 1.0) var facing_deg: float = 100.0
@export_range(0.05, 1.0, 0.01) var knock_s: float = 0.2


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.bloom(ctx, self)
