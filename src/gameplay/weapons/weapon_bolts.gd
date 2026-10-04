class_name WeaponBolts
extends RefCounted
## In-flight hero weapon bolts (weapons-and-mods.md 3.1: projectiles only for
## Liora's Halo Repeater; speed from WeaponDef.projectile_speed).
##
## Lag compensation (architecture.md 8.7), the choice made for projectiles:
## the shooter's view time (view_tick + view_alpha) is captured at fire, and the
## bolt is swept forward one tick at a time. The segment flown during the k-th tick
## after the shot is tested against target poses rewound to (view_tick + k):
## the shooter's perceived timeline advances with the bolt. Once view_tick + k
## reaches the server tick the poses are current. A bolt therefore hits what the
## shooter saw it pass through, within NetConfig.max_rewind_ms, the same window
## and the same pose history as hitscan.
##
## Example:
##   bolts.spawn(owner_id, def, origin, dir, view_tick, view_alpha)
##   bolts.step(dt, func(b, seg) -> bool: ...)  # true = the bolt stopped

class Bolt:
	var owner_id: int
	var def: WeaponDef
	var pos: Vector3
	var dir: Vector3
	var traveled: float = 0.0
	var view_tick: int
	var view_alpha: float
	var age: int = 0

var bolts: Array[Bolt] = []
## [from, to] segments of bolts launched this tick, for the snapshot bolt block.
var launched: Array = []


func spawn(owner_id: int, def: WeaponDef, origin: Vector3, dir: Vector3, view_tick: int,
		view_alpha: float) -> Bolt:
	var b := Bolt.new()
	b.owner_id = owner_id
	b.def = def
	b.pos = origin
	b.dir = dir.normalized()
	b.view_tick = view_tick
	b.view_alpha = view_alpha
	bolts.append(b)
	return b


## Advances every bolt one tick. `resolve.call(bolt, seg_len) -> bool` sweeps the
## segment from bolt.pos along bolt.dir and returns true when the bolt stopped
## (hit, wall or shield). Bolts also die at def.range_m or when `alive` says the
## owner is gone.
func step(dt: float, resolve: Callable, alive: Callable) -> void:
	var i := 0
	while i < bolts.size():
		var b := bolts[i]
		if not alive.call(b.owner_id):
			bolts.remove_at(i)
			continue
		var seg := minf(b.def.projectile_speed * dt, b.def.range_m - b.traveled)
		var stopped: bool = resolve.call(b, seg)
		b.pos += b.dir * seg
		b.traveled += seg
		b.age += 1
		if stopped or b.traveled >= b.def.range_m - 1e-3:
			bolts.remove_at(i)
			continue
		i += 1


func clear() -> void:
	bolts.clear()
	launched.clear()
