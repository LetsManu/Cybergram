class_name VanguardSpawner
extends RefCounted
## Vanguard cadence and gate (Canon C15, wardlings-and-economy.md §10). Pure
## rules; WardlingWorld mints the bodies.
##   Every wave_interval_s from wave_first_s, per team and lane, a wave spawns
##   only if the previous wave has <= wave_gate_alive members alive; survivors
##   merge into the new wave and only wave_size - survivors are minted.
## `clock_scale` > 1 compresses the cadence (debug clock, --wave-clock).


static func first_tick(rules: WardlingRulesDef, tick_hz: int, clock_scale: float = 1.0) -> int:
	return maxi(roundi(rules.wave_first_s * tick_hz / maxf(clock_scale, 0.001)), 1)


static func interval_ticks(rules: WardlingRulesDef, tick_hz: int, clock_scale: float = 1.0) -> int:
	return maxi(roundi(rules.wave_interval_s * tick_hz / maxf(clock_scale, 0.001)), 1)


## True on a global wave tick (1:00, 2:00, ... scaled).
static func is_wave_tick(tick: int, rules: WardlingRulesDef, tick_hz: int, clock_scale: float = 1.0) -> bool:
	var first := first_tick(rules, tick_hz, clock_scale)
	return tick >= first and (tick - first) % interval_ticks(rules, tick_hz, clock_scale) == 0


## Wardlings to mint for a lane on a wave tick; 0 = the lane skips this tick.
static func mint_count(alive_prev: int, rules: WardlingRulesDef) -> int:
	if alive_prev > rules.wave_gate_alive:
		return 0
	return maxi(rules.wave_size - alive_prev, 0)
