class_name PushGoal
extends BotGoal
## Go to the lane front (LaneFrontResolver) and work its task: stand in the
## zone of the hardpoint to attack, or hold the front-most own one.


func _init() -> void:
	kind = Kind.PUSH


func score(bb: BotBlackboard, p: BotProfile) -> float:
	if bb.front_index < 0:
		return 0.0
	return p.w_push * (0.8 if bb.front_is_own else 1.0)


func destination(bb: BotBlackboard) -> Vector3:
	return bb.front_pos


func arrive_radius(bb: BotBlackboard) -> float:
	return bb.front_radius * 0.55
