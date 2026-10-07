class_name AmmoTargetState
extends RefCounted
## Ammo effect state on one target (weapons-and-mods.md §3.7.1, §4.5): one Burn
## pool and one Shock Charge meter per shooter, one shared Chill meter, Brittle.
## Heroes keep it in StatusComponent.ammo (cleared on respawn); Wardlings in
## AmmoEffects. Written only by AmmoEffects; server-side only.


## Burn pool of one shooter (Incendiary): deals itself out over `ticks_left`.
class BurnPool:
	var shooter_id: int = 0
	var team: int = -1
	var pool: float = 0.0
	var ticks_left: int = 0


## Shock Charge of one shooter.
class Charge:
	var value: float = 0.0
	var last_hit_tick: int = -1000000
	## No Overload from this shooter before this tick (3 s ICD).
	var icd_until: int = -1


var burns: Dictionary = {}    # shooter net id -> BurnPool
var charges: Dictionary = {}  # shooter net id -> Charge
## Shared Chill meter (0..chill_max) and its decay clock.
var chill: float = 0.0
var chill_last_hit: int = -1000000
var chill_delay_ticks: int = 0
## Brittle window and re-trigger lock (ticks; -1 = none).
var brittle_until: int = -1
var brittle_lock_until: int = -1
## Brittle ended and the meter was reset for this window.
var brittle_reset_done: bool = true


## True while Brittle is active at `tick`.
func is_brittle(tick: int) -> bool:
	return tick < brittle_until


## True while any Burn pool is live (Scorched).
func is_burning() -> bool:
	for b: BurnPool in burns.values():
		if b.pool > 0.0 and b.ticks_left > 0:
			return true
	return false


## Remaining Burn pool of `shooter` (Volatile passes 40% of it on).
func burn_left(shooter: int) -> float:
	var b: BurnPool = burns.get(shooter)
	return b.pool if b != null else 0.0


## Charge of `shooter` (0 when none).
func charge_of(shooter: int) -> float:
	var c: Charge = charges.get(shooter)
	return c.value if c != null else 0.0


func clear() -> void:
	burns.clear()
	charges.clear()
	chill = 0.0
	chill_last_hit = -1000000
	brittle_until = -1
	brittle_lock_until = -1
	brittle_reset_done = true
