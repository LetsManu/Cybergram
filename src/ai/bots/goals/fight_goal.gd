class_name FightGoal
extends BotGoal
## Engage a visible enemy hero: close to the hero's preferred range. Enemy
## Wardlings alone do not pull a bot off its objective (it shoots them on the way).


func _init() -> void:
	kind = Kind.FIGHT


func score(bb: BotBlackboard, p: BotProfile) -> float:
	if bb.target_id == 0 or not bb.target_is_hero or bb.target_dist > p.engage_range_m:
		return 0.0
	var close := 1.0 - clampf(bb.target_dist / p.engage_range_m, 0.0, 1.0)
	var hurt := 0.25 if bb.seconds_since(bb.last_damaged_tick) < 1.5 else 0.0
	return p.w_fight * (0.6 + 0.5 * close) + hurt


func destination(bb: BotBlackboard) -> Vector3:
	return bb.target_pos


func arrive_radius(_bb: BotBlackboard) -> float:
	return 10.0
