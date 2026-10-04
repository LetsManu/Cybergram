class_name AuraEffectDef
extends EffectDef
## Aurora dome (heroes.md §4.6 Ult) centred on the caster: for `duration_param` s
## allied heroes inside heal `heal_param` HP/s (Wardlings x`wardling_mult`) and gain
## `dr_param` damage reduction; for the first `floor_s` s they cannot drop below 1 HP.

@export var radius_param: StringName = &"radius"
@export var heal_param: StringName = &"heal_per_s"
@export var duration_param: StringName = &"duration"
@export var dr_param: StringName = &"dr"
@export_range(0.0, 10.0, 0.1) var floor_s: float = 2.0
@export_range(0.0, 1.0, 0.01) var wardling_mult: float = 0.5


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.spawn_aura(ctx, self)
