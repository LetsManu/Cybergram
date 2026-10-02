class_name BotCostMeter
extends RefCounted
## Wall-clock cost of all bots per server tick (µs), for the budget check
## (architecture.md §12: bots 0.4 ms/tick). Measurement only: never feeds
## back into decisions, so determinism is unaffected.

var per_tick: PackedInt32Array = PackedInt32Array()
var _tick: int = -1
var _acc: int = 0


func add(tick: int, usec: int) -> void:
	if tick != _tick:
		flush()
		_tick = tick
	_acc += usec


func flush() -> void:
	if _tick >= 0:
		per_tick.append(_acc)
	_acc = 0


## {avg_ms, p95_ms, max_ms, ticks} over the recorded ticks.
func summary() -> Dictionary:
	flush()
	_tick = -1
	if per_tick.is_empty():
		return {"avg_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0, "ticks": 0}
	var s := per_tick.duplicate()
	s.sort()
	var total := 0
	for v in s:
		total += v
	return {
		"avg_ms": snappedf(total / 1000.0 / s.size(), 0.001),
		"p95_ms": snappedf(s[mini(s.size() - 1, int(s.size() * 0.95))] / 1000.0, 0.001),
		"max_ms": snappedf(s[s.size() - 1] / 1000.0, 0.001),
		"ticks": s.size(),
	}
