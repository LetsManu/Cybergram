class_name StimEffectDef
extends EffectDef
## Combat Stim (heroes.md §4.4 S2): self buff of +`fire_rate_bonus` fire rate and
## +`speed_bonus` move speed for `duration_param` s; costs `hp_cost` HP (never
## below 1 HP).

@export var duration_param: StringName = &"duration"
@export_range(0.0, 2.0, 0.01) var fire_rate_bonus: float = 0.25
@export_range(0.0, 2.0, 0.01) var speed_bonus: float = 0.15
@export_range(0.0, 500.0, 1.0) var hp_cost: float = 20.0


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.stim(ctx, self)
