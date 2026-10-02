class_name CellGoal
extends BotGoal
## E14 Plant (match-flow-and-map.md §3.4 Plant): the bot has a Cell job from
## BotBrain (the team's designated carrier fetching a Cell from the Cradle or
## picking up a dropped one, the carrier walking to the Socket to plant, or a
## defender defusing / dispersing an enemy Cell). Standing on the spot, BotBrain
## holds Interact. Outranks fighting: the Cell is the objective.


func _init() -> void:
	kind = Kind.CELL


func score(bb: BotBlackboard, p: BotProfile) -> float:
	if bb.cell_job == BotBlackboard.CellJob.NONE:
		return 0.0
	# A carrier or a defuser under fire still goes on; only a near-dead bot retreats.
	return p.w_cell + (0.2 if bb.carrying or bb.cell_job == BotBlackboard.CellJob.DEFUSE else 0.0)


func destination(bb: BotBlackboard) -> Vector3:
	return bb.cell_job_pos


func arrive_radius(bb: BotBlackboard) -> float:
	return bb.cell_job_radius
