class_name SlideEffectDef
extends EffectDef
## A short ground dash along ctx.dir (Tactical Slide heroes.md §4.4 S3, Phase
## Shift §4.2 S2): `distance_param` m in `time_s` s. `reload_frac` of the magazine
## capacity is reloaded from reserve; `intangible_s` > 0 makes the hero take no
## damage and pass through other bodies for that long; `locks_actions` blocks
## skills and firing during the dash (like a charge).

@export var distance_param: StringName = &"distance"
@export_range(0.05, 3.0, 0.01) var time_s: float = 0.45
@export_range(0.0, 1.0, 0.01) var reload_frac: float = 0.0
@export_range(0.0, 3.0, 0.01) var intangible_s: float = 0.0
@export var locks_actions: bool = false


func apply(ctx: EffectContext) -> void:
	ctx.world.extras.slide(ctx, self)
