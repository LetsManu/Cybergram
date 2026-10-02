class_name DamageNumberModel
extends RefCounted
## Damage numbers (design/ux/hud.md §13.2). OFF: nothing. COMPACT (default):
## one number per target that merges hits landing within `merge_s` of the
## previous one (headshot / kill flags accumulate; the number restarts its
## life). FULL: one number per hit. World positions are carried for the view.

enum Mode { OFF, COMPACT, FULL }


class Num:
	extends RefCounted
	var target_id: int = 0
	var amount: float = 0.0
	var headshot: bool = false
	var kill: bool = false
	var world_pos: Vector3 = Vector3.ZERO
	## Seconds since the number (re)started.
	var age: float = 0.0
	## Seconds since the last merged hit.
	var since_hit: float = 0.0


var mode: int = Mode.COMPACT
var merge_s: float = 0.5
var life_s: float = 0.9
var numbers: Array[Num] = []


func _init(mode_: int = Mode.COMPACT, merge: float = 0.5, life: float = 0.9) -> void:
	mode = mode_
	merge_s = merge
	life_s = maxf(life, 0.05)


## Records a confirmed hit; returns the number that shows it (null when OFF).
func add(target_id: int, amount: float, headshot: bool, kill: bool, pos: Vector3) -> Num:
	if mode == Mode.OFF:
		return null
	if mode == Mode.COMPACT:
		for n in numbers:
			if n.target_id == target_id and n.since_hit <= merge_s:
				n.amount += amount
				n.headshot = n.headshot or headshot
				n.kill = n.kill or kill
				n.world_pos = pos
				n.age = 0.0
				n.since_hit = 0.0
				return n
	var m := Num.new()
	m.target_id = target_id
	m.amount = amount
	m.headshot = headshot
	m.kill = kill
	m.world_pos = pos
	numbers.append(m)
	return m


func advance(dt: float) -> void:
	for i in range(numbers.size() - 1, -1, -1):
		var n := numbers[i]
		n.age += dt
		n.since_hit += dt
		if n.age >= life_s:
			numbers.remove_at(i)


## 0..1 life fraction used (fade-out in the second half).
func alpha(n: Num) -> float:
	return clampf((life_s - n.age) / (life_s * 0.5), 0.0, 1.0)


## Label text: whole HP, "!" suffix for a headshot (hud.md §13.2).
static func text_of(n: Num) -> String:
	return str(roundi(n.amount)) + ("!" if n.headshot else "")
