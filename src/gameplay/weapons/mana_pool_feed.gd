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


## Pool size after capacity items (Wellframe, Reservoir Frame, Anchor Frame).
func max_pool() -> float:
	return float(scaled_capacity(def.mana_pool, false))


func step(tick: int) -> void:
	var cap := max_pool()
	if mana > cap:
		mana = cap  # weapons-and-mods.md §5: selling capacity clamps
	if tick < regen_resume_tick:
		return
	burnout = false
	mana = minf(cap, mana + regen_rate() / tick_rate_hz)


func can_fire() -> bool:
	return mana > 1e-4


func consume(tick: int) -> void:
	mana = maxf(0.0, mana - def.mana_cost * cost_mult)
	var delay := regen_delay_s()
	if mana <= 1e-4:
		mana = 0.0
		burnout = true
		delay *= def.burnout_delay_mult
	regen_resume_tick = tick + ticks(delay)


func refill() -> void:
	mana = max_pool()
	burnout = false
	regen_resume_tick = 0


func current() -> float:
	return mana


func capacity() -> int:
	return int(max_pool())


## Siphon (weapons-and-mods.md §3.7.1): restores mana up to the pool; returns the gain.
func add_mana(amount: float) -> float:
	var add := clampf(amount, 0.0, max_pool() - mana)
	mana += add
	return add


func disrupt(tick: int, duration_ticks: int, _penalty_ticks: int) -> void:
	regen_resume_tick = maxi(regen_resume_tick, tick + maxi(duration_ticks, ticks(regen_delay_s())))


func flags() -> int:
	return AmmoFeed.FLAG_BURNOUT if burnout else 0
