class_name DeployableEffectDef
extends EffectDef
## Spawns a deployable at ctx.point facing the caster (ADR-0004 SpawnEntity):
## WALL (Aegis Wall: blocks enemy hitscan, bolts and skill projectiles),
## BEACON (Rally Beacon: heals / shields allied Wardlings in radius),
## BASTION (Earthbreaker zone: allied heroes take less damage).

enum Kind { WALL, BEACON, BASTION }

@export var kind: Kind = Kind.WALL
@export var duration_param: StringName = &"duration"
@export var hp_param: StringName = &"hp"
@export var radius_param: StringName = &"radius"
@export var width_param: StringName = &"width"
@export var height_param: StringName = &"height"
@export var heal_param: StringName = &"heal_per_s"
@export var dr_param: StringName = &"dr"
## The deployable's end (expiry or destruction) ends the skill's active window
## (heroes.md §3.4: the wall's cooldown starts when the wall ends).
@export var ends_active: bool = false
## PLACEHOLDER. Wall thickness (m) for blocking tests.
@export var thickness_m: float = 0.4


func apply(ctx: EffectContext) -> void:
	ctx.world.spawn_deployable(ctx, self)
