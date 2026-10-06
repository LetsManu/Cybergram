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


func _init(weapon: WeaponDef, tick_rate: int) -> void:
	super(weapon, tick_rate)
	rounds = def.magazine
	reserve = def.reserve


func is_reloading() -> bool:
	return reload_end_tick >= 0


func step(tick: int) -> void:
	if is_reloading() and tick >= reload_end_tick:
		if def.reload_per_round:
			rounds += 1
			reserve -= 1
			reload_end_tick = tick + ticks(reload_time(def.reload_s)) if rounds < def.magazine and reserve > 0 else -1
		else:
			var n := mini(def.magazine - rounds, reserve)
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
	if is_reloading() or rounds >= def.magazine or reserve <= 0:
		return
	var t := def.reload_s
	if rounds == 0 and not def.reload_per_round and def.reload_empty_s > 0.0:
		t = def.reload_empty_s
	reload_end_tick = tick + ticks(reload_time(t))


func refill() -> void:
	rounds = def.magazine
	reserve = def.reserve
	reload_end_tick = -1


## Adds up to `n` rounds to the reserve (Supply Cache, C5); returns how many fit.
func add_reserve(n: int) -> int:
	var add := clampi(n, 0, def.reserve - reserve)
	reserve += add
	return add


func current() -> float:
	return rounds


func capacity() -> int:
	return def.magazine


func reserve_count() -> int:
	return reserve


func flags() -> int:
	var f := 0
	if is_reloading():
		f |= AmmoFeed.FLAG_RELOADING
	if rounds == 0 and reserve == 0:
		f |= AmmoFeed.FLAG_DRY
	return f
