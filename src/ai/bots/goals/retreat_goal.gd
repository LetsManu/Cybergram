class_name RetreatGoal
extends BotGoal
## Low HP under threat: fall back toward the own HQ until calm (no threat for
## retreat_calm_s) or healed above return_hp_frac (Rally Beacon). The slice
## has no passive HP regen, so a retreat mostly breaks contact.


func _init() -> void:
	kind = Kind.RETREAT


func score(bb: BotBlackboard, p: BotProfile) -> float:
	var retreating := bb.current_goal == Kind.RETREAT
	if not retreating and bb.tick < bb.retreat_block_until_tick:
		return 0.0
	var limit := p.return_hp_frac if retreating else p.retreat_hp_frac
	if bb.hp_frac >= limit or not bb.threatened(p.retreat_calm_s if retreating else 1.5):
		return 0.0
	# Finishing a visibly weaker hero beats turning one's back on it.
	if not retreating and bb.target_is_hero and bb.target_dist < p.engage_range_m and bb.target_hp_frac < bb.hp_frac:
		return 0.0
	return p.w_retreat * (1.0 + 0.5 * (1.0 - bb.hp_frac / maxf(limit, 0.01)))


func destination(bb: BotBlackboard) -> Vector3:
	return bb.home_pos
