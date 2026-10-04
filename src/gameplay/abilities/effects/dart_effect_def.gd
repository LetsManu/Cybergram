class_name DartEffectDef
extends EffectDef
## Eclipse Step shadow dart (heroes.md §4.2 Ult): an aimed projectile. On an enemy
## hero: Silence for `silence_param` s and a weapon bonus `mark_param` for
## `window_param` s, and after `delay_s` the caster teleports `behind_m` behind the
## target. On level geometry: the caster teleports to the impact. Walls absorb it.

@export var speed_param: StringName = &"speed"
@export var range_param: StringName = &"range"
@export var silence_param: StringName = &"duration"
@export var mark_param: StringName = &"bonus_damage"
@export var window_param: StringName = &"secondary_duration"
@export_range(0.0, 3.0, 0.05) var delay_s: float = 0.5
@export_range(0.5, 5.0, 0.1) var behind_m: float = 1.5
@export_range(0.05, 1.0, 0.05) var hit_radius_m: float = 0.3


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.launch_dart(ctx, self)
