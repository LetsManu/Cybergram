class_name DefendGoal
extends BotGoal
## An own hardpoint is being taken (enemy progress > 0): get into its zone.
## Urgency grows with the enemy's progress and with nearness.


func _init() -> void:
	kind = Kind.DEFEND


func score(bb: BotBlackboard, p: BotProfile) -> float:
	if bb.defend_index < 0:
		return 0.0
	var d := BotBlackboard.flat_dist(bb.pos, bb.defend_pos)
	var near := clampf(1.0 - d / 200.0, 0.3, 1.0)
	return p.w_defend * (0.7 + 0.6 * bb.defend_progress) * near + 0.15


func destination(bb: BotBlackboard) -> Vector3:
	return bb.defend_pos


func arrive_radius(bb: BotBlackboard) -> float:
	return bb.defend_radius * 0.55
