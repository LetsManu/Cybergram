class_name PushGoal
extends BotGoal
## Go to the lane front (LaneFrontResolver) and work its task: stand in the
## zone of the hardpoint to attack, or hold the front-most own one. A bot near
## an attack its team has under way (Cell planted, Generator damaged, Hold
## progress) commits to it (E14 push commitment).


func _init() -> void:
	kind = Kind.PUSH


func score(bb: BotBlackboard, p: BotProfile) -> float:
	if bb.front_index < 0:
		return 0.0
	var commit := 0.0
	if not bb.front_is_own and bb.front_task_progress > 0.0 \
			and BotBlackboard.flat_dist(bb.pos, bb.front_pos) <= p.push_commit_range_m:
		commit = p.w_push_commit  # E14: finish a task under way instead of running home
	return p.w_push * (0.8 if bb.front_is_own else 1.0) + commit


func destination(bb: BotBlackboard) -> Vector3:
	return bb.front_pos


func arrive_radius(bb: BotBlackboard) -> float:
	return bb.front_radius * 0.55
