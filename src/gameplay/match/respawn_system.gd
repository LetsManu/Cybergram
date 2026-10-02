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


## Whole ticks until respawn for a death at `match_minutes` on the match clock
## (MatchRules.minutes(); E9 wires C11 to the real match time).
## `exposed`: the hero's own Uplink is Exposed (slice tuning, MatchRulesDef.exposed_respawn_mult).
static func respawn_ticks_at_minutes(rules: MatchRulesDef, match_minutes: float, tick_rate_hz: int,
		exposed: bool = false) -> int:
	var s := respawn_seconds(rules, match_minutes) * (rules.exposed_respawn_mult if exposed else 1.0)
	return ceili(s * tick_rate_hz - 1e-6)
