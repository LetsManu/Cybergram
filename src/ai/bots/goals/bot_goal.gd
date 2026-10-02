@abstract
class_name BotGoal
extends RefCounted
## One utility goal (architecture.md §9 GoalSelector, ADR-0005 §2). A goal
## scores a BotBlackboard (0 = not applicable) and names where to stand.
## Goals never write inputs: BotBrain turns the winner into movement, and the
## combat layer shoots whatever target the sensor picked in every goal.

enum Kind { PUSH, DEFEND, FIGHT, RETREAT, SIEGE }
const NAMES: Array[String] = ["push", "defend", "fight", "retreat", "siege"]

var kind: int = Kind.PUSH


@abstract func score(bb: BotBlackboard, p: BotProfile) -> float


## Where the bot moves while this goal runs.
@abstract func destination(bb: BotBlackboard) -> Vector3


## Metres from destination() that count as arrived (the bot then mills about).
func arrive_radius(_bb: BotBlackboard) -> float:
	return 2.0
