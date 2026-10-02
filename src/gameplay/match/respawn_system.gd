class_name RespawnSystem
extends RefCounted
## Respawn timer (design/gdd/match-flow-and-map.md F7, Canon C11):
## R(m) = min(R_max, R_0 + k * m), m = match minutes at the time of death.
## Coefficients come from MatchRulesDef.


static func respawn_seconds(rules: MatchRulesDef, match_minutes: float) -> float:
	return minf(rules.respawn_cap_s, rules.respawn_base_s + rules.respawn_per_min_s * maxf(match_minutes, 0.0))


## Whole ticks until respawn for a death at server tick `death_tick`.
static func respawn_ticks(rules: MatchRulesDef, death_tick: int, tick_rate_hz: int) -> int:
	var minutes := float(death_tick) / tick_rate_hz / 60.0
	return ceili(respawn_seconds(rules, minutes) * tick_rate_hz - 1e-6)
