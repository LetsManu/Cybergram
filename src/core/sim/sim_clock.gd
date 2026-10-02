class_name SimClock
extends RefCounted
## Fixed-step simulation clock (architecture.md §5, ADR-0002).
##
## Turns variable frame deltas into a whole number of fixed simulation ticks.
## The tick rate is injected (it comes from net_config.tres), never hard-coded.
## Time is accumulated in integer microseconds so repeated small deltas never
## drift through float rounding.

const _USEC_PER_SEC: int = 1_000_000

## Upper bound on ticks returned by one advance() call. Excess time is dropped
## so a long hitch cannot snowball into ever-longer catch-up frames.
var max_ticks_per_advance: int

var tick_rate_hz: int
## Total ticks issued since construction.
var tick: int = 0

var _accumulated_usec: int = 0
var _tick_usec: int


func _init(rate_hz: int, max_catch_up_ticks: int = 8) -> void:
	assert(rate_hz > 0, "SimClock: tick rate must be positive")
	assert(max_catch_up_ticks > 0, "SimClock: catch-up cap must be positive")
	tick_rate_hz = rate_hz
	max_ticks_per_advance = max_catch_up_ticks
	_tick_usec = _USEC_PER_SEC / rate_hz


## Seconds per tick.
func get_tick_interval() -> float:
	return float(_tick_usec) / _USEC_PER_SEC


## Adds frame time and returns how many fixed ticks should run now.
func advance(delta_sec: float) -> int:
	if delta_sec > 0.0:
		_accumulated_usec += roundi(delta_sec * _USEC_PER_SEC)
	var ticks: int = _accumulated_usec / _tick_usec
	if ticks > max_ticks_per_advance:
		ticks = max_ticks_per_advance
		_accumulated_usec = 0
	else:
		_accumulated_usec -= ticks * _tick_usec
	tick += ticks
	return ticks


## Fraction (0..1) of the way to the next tick, for render interpolation.
func get_interpolation_alpha() -> float:
	return float(_accumulated_usec) / _tick_usec
