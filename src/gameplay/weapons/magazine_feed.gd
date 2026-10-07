class_name MagazineFeed
extends AmmoFeed
## Magazine + reserve (design/gdd/weapons-and-mods.md §3.2, §3.5).
## Reload rules:
## - Reload starts on the reload button (magazine not full, reserve > 0) or
##   automatically when the magazine is empty.
## - Full-magazine reload (reload_per_round = false): one committed reload of
##   reload_s (reload_empty_s from empty); firing is locked until it ends.
## - Per-round reload (Ironmaw, "0.45 s per shell (interruptible)"): each
##   reload_s loads one round; pressing fire with >= 1 round loaded cancels the
##   reload and keeps the rounds already loaded.
## - Dry (magazine and reserve 0): cannot fire until a refill.

var rounds: int
var reserve: int
## Tick the current reload step completes; -1 when not reloading.
var reload_end_tick: int = -1
## Shock Disrupted: ticks added to the next reload started before `_penalty_until`.
var _penalty_ticks: int = 0
var _penalty_until: int = -1


func _init(weapon: WeaponDef, tick_rate: int) -> void:
	super(weapon, tick_rate)
	rounds = def.magazine
	reserve = def.reserve


## Magazine and reserve sizes after capacity items (round down, min +1).
func max_magazine() -> int:
	return scaled_capacity(def.magazine, true)


func max_reserve() -> int:
	return scaled_capacity(def.reserve, true) if def.reserve > 0 else 0


func is_reloading() -> bool:
	return reload_end_tick >= 0


func step(tick: int) -> void:
	var mag := max_magazine()
	if rounds > mag:  # weapons-and-mods.md §5: excess rounds go back to the reserve
		reserve = mini(max_reserve(), reserve + rounds - mag)
		rounds = mag
	if reserve > max_reserve():
		reserve = max_reserve()
	if is_reloading() and tick >= reload_end_tick:
		if def.reload_per_round:
			rounds += 1
			reserve -= 1
			reload_end_tick = tick + ticks(reload_time(def.reload_s)) if rounds < mag and reserve > 0 else -1
		else:
			var n := mini(mag - rounds, reserve)
			rounds += n
			reserve -= n
			reload_end_tick = -1
	if rounds == 0 and not is_reloading():
		request_reload(tick)


func can_fire() -> bool:
	if rounds <= 0:
		return false
	return def.reload_per_round or not is_reloading()


func consume(tick: int) -> void:
	rounds -= 1
	reload_end_tick = -1  # only reachable mid-reload for per-round reloads: cancels it
	if rounds == 0:
		request_reload(tick)


func request_reload(tick: int) -> void:
	if is_reloading() or rounds >= max_magazine() or reserve <= 0:
		return
	var t := def.reload_s
	if rounds == 0 and not def.reload_per_round and def.reload_empty_s > 0.0:
		t = def.reload_empty_s
	reload_end_tick = tick + ticks(reload_time(t))
	if _penalty_until >= tick and _penalty_ticks > 0:
		reload_end_tick += _penalty_ticks
		_penalty_ticks = 0
		_penalty_until = -1


func refill() -> void:
	rounds = max_magazine()
	reserve = max_reserve()
	reload_end_tick = -1
	_penalty_ticks = 0
	_penalty_until = -1


func disrupt(tick: int, duration_ticks: int, penalty_ticks: int) -> void:
	if is_reloading():
		reload_end_tick += penalty_ticks
	else:
		_penalty_ticks = penalty_ticks
		_penalty_until = tick + duration_ticks


## Adds up to `n` rounds to the reserve (Supply Cache, C5); returns how many fit.
func add_reserve(n: int) -> int:
	var add := clampi(n, 0, max_reserve() - reserve)
	reserve += add
	return add


func current() -> float:
	return rounds


func capacity() -> int:
	return max_magazine()


func reserve_count() -> int:
	return reserve


func flags() -> int:
	var f := 0
	if is_reloading():
		f |= AmmoFeed.FLAG_RELOADING
	if rounds == 0 and reserve == 0:
		f |= AmmoFeed.FLAG_DRY
	return f
