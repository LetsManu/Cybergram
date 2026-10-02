class_name GoalSelector
extends RefCounted
## Utility selection over the bot goals (architecture.md §9): the highest
## score wins, the current goal gets BotProfile.stickiness on top. Pure: same
## blackboard and profile give the same answer.

var goals: Array[BotGoal] = [PushGoal.new(), DefendGoal.new(), FightGoal.new(), RetreatGoal.new(), SiegeGoal.new(),
	CellGoal.new()]
## Scores of the last pick, indexed by BotGoal.Kind (debug / tests).
var last_scores: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])


func pick(bb: BotBlackboard, p: BotProfile) -> BotGoal:
	var best: BotGoal = null
	var best_s := 0.0
	for g in goals:
		var s := g.score(bb, p)
		last_scores[g.kind] = s
		if s > 0.0 and g.kind == bb.current_goal:
			s += p.stickiness
		if s > best_s:
			best_s = s
			best = g
	return best


func goal(kind: int) -> BotGoal:
	return goals[kind]
