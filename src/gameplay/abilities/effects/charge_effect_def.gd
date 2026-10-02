class_name ChargeEffectDef
extends EffectDef
## Ram Charge (heroes.md §4.5 S2): a forced dash of `distance` m in `duration`
## s along ctx.dir. The first enemy hero met is carried and takes `damage`;
## carried into a wall it takes `bonus_damage` more and is stunned `stun` s.
## Other enemies in the path are knocked aside.

@export var distance_param: StringName = &"distance"
@export var duration_param: StringName = &"duration"
@export var damage_param: StringName = &"damage"
@export var bonus_param: StringName = &"bonus_damage"
@export var stun_param: StringName = &"stun"
## PLACEHOLDER. Knock-aside impulse (m/s, 0.3 s) and lateral hit width (m).
@export var knock_speed: float = 8.0
@export var knock_s: float = 0.3
@export var path_half_width_m: float = 1.1


func apply(ctx: EffectContext) -> void:
	ctx.world.start_charge(ctx, self)
