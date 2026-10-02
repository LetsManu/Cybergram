class_name ProjectileSystem
extends RefCounted
## Server projectiles for Wardling mana bolts (wardlings-and-economy.md §4:
## 55 m/s, dodgeable, no hitscan). Static-world occlusion is resolved once at
## spawn (one ray: the bolt dies at the wall); each tick a bolt sweeps its
## segment against the capsules of nearby enemies supplied by `query`.
##
## Example:
##   ps.spawn(origin, dir, 55.0, max_dist, 7.0, team, source_id)
##   ps.step(dt, func(p, r): return candidates, func(target, bolt): ...)

class Bolt:
	var pos: Vector3
	var dir: Vector3
	var speed: float
	var left: float
	var damage: float
	var team: int
	var source_id: int

## Capsule of a candidate target: [object, feet, radius, top_y_offset].
var bolts: Array[Bolt] = []
## Bolts fired this tick as [from, to] for the snapshot tracer block.
var fired: Array = []
var hits_total: int = 0


func spawn(origin: Vector3, dir: Vector3, speed: float, max_dist: float, damage: float, team: int,
		source_id: int, visual_end: Vector3) -> void:
	var b := Bolt.new()
	b.pos = origin
	b.dir = dir.normalized()
	b.speed = speed
	b.left = max_dist
	b.damage = damage
	b.team = team
	b.source_id = source_id
	bolts.append(b)
	fired.append([origin, visual_end])


## Advances every bolt. `candidates.call(pos: Vector3, team: int) -> Array` returns
## [target, feet: Vector3, radius: float, height: float] entries of enemies near
## `pos`; `on_hit.call(target, bolt)` applies the damage.
func step(dt: float, candidates: Callable, on_hit: Callable) -> void:
	var i := 0
	while i < bolts.size():
		var b := bolts[i]
		var seg := minf(b.speed * dt, b.left)
		var end := b.pos + b.dir * seg
		var best_t := INF
		var best: Variant = null
		for c in candidates.call(end, b.team):
			var feet: Vector3 = c[1]
			var r: float = c[2]
			var t := HitscanTracer.ray_vertical_capsule(b.pos, b.dir, feet.y + r,
				feet.y + maxf(float(c[3]) - r, r), Vector2(feet.x, feet.z), r)
			if t >= 0.0 and t <= seg and t < best_t:
				best_t = t
				best = c[0]
		if best != null:
			hits_total += 1
			on_hit.call(best, b)
			bolts.remove_at(i)
			continue
		b.pos = end
		b.left -= seg
		if b.left <= 0.001:
			bolts.remove_at(i)
			continue
		i += 1


func clear() -> void:
	bolts.clear()
	fired.clear()
