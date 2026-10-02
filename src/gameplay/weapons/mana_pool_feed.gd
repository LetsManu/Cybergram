class_name ManaPoolFeed
extends AmmoFeed
## Mana pool (design/gdd/weapons-and-mods.md §3.2, §3.5, §4.6): each shot costs
## `mana_cost`; regen starts `mana_regen_delay_s` after the last shot. A shot
## may fire with any mana left (the pool clamps at 0), and emptying the pool
## triggers Burnout: the delay is multiplied by burnout_delay_mult (1.5).
## Burnout ends when regen resumes.

var mana: float
var burnout: bool = false
## First tick on which regen runs.
var regen_resume_tick: int = 0


func _init(weapon: WeaponDef, tick_rate: int) -> void:
	super(weapon, tick_rate)
	mana = def.mana_pool


func step(tick: int) -> void:
	if tick < regen_resume_tick:
		return
	burnout = false
	mana = minf(def.mana_pool, mana + def.mana_regen / tick_rate_hz)


func can_fire() -> bool:
	return mana > 1e-4


func consume(tick: int) -> void:
	mana = maxf(0.0, mana - def.mana_cost)
	var delay := def.mana_regen_delay_s
	if mana <= 1e-4:
		mana = 0.0
		burnout = true
		delay *= def.burnout_delay_mult
	regen_resume_tick = tick + ticks(delay)


func refill() -> void:
	mana = def.mana_pool
	burnout = false
	regen_resume_tick = 0


func current() -> float:
	return mana


func capacity() -> int:
	return def.mana_pool


func flags() -> int:
	return AmmoFeed.FLAG_BURNOUT if burnout else 0
