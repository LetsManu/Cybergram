class_name SquadFocusEffectDef
extends EffectDef
## Marionette Thread (heroes.md §4.1 S1): the caster's squad and any Vanguard
## wave she conducts focus ctx.target for `duration_param` s (an instant
## Attack Target through the wardlings §13 issue_command / command_vanguard hooks).

@export var duration_param: StringName = &"secondary_duration"


func apply(ctx: EffectContext) -> void:
	if ctx.target != null:
		ctx.world.wardling_focus(ctx, ctx.target, ctx.ticks(duration_param))
