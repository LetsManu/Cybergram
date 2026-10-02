class_name SiegeGoal
extends BotGoal
## The enemy Uplink is Exposed (F6): stand where it can be shot from, which is
## inside the enemy HQ gate (BotBrain._siege_point). E14 regroup: bots first gather
## at the staging point outside the HQ and go in once enough allies are there
## (BotProfile.siege_group_min), or straight in when already inside.


func _init() -> void:
	kind = Kind.SIEGE


func score(bb: BotBlackboard, p: BotProfile) -> float:
	if not bb.enemy_uplink_exposed:
		return 0.0
	return p.w_siege + (0.2 if bb.target_id == bb.enemy_uplink_id else 0.0)


func destination(bb: BotBlackboard) -> Vector3:
	return bb.siege_pos if bb.siege_committed else bb.siege_stage_pos


func arrive_radius(_bb: BotBlackboard) -> float:
	return 3.0
