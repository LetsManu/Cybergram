class_name OverdriveEffectDef
extends EffectDef
## Overdrive Protocol (heroes.md §4.4 Ult): for `duration_param` s the magazine
## is bottomless and weapon damage is +`bonus_param`. Rank 3 rider: each kill extends
## it by `extend_param` s (a node raises it from 0), up to `max_extension_s` in total.

@export var duration_param: StringName = &"duration"
@export var bonus_param: StringName = &"bonus_damage"
@export var extend_param: StringName = &"secondary_duration"
@export_range(0.0, 60.0, 0.5) var max_extension_s: float = 6.0
## Weapon recoil (spread bloom per shot) multiplier while active; heroes.md: -50 % recoil.
@export_range(0.0, 1.0, 0.05) var recoil_mult: float = 0.5


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.overdrive(ctx, self)
