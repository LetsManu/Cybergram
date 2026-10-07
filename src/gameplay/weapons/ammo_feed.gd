class_name AmmoFeed
extends RefCounted
## Abstract weapon feed (architecture.md §5.2). ManaPoolFeed and MagazineFeed
## implement it; WeaponDef.feed_kind picks one (create()). All timers are in
## ticks of the owner's weapon clock (architecture.md §1.6).

const FLAG_RELOADING: int = 1
const FLAG_BURNOUT: int = 2
const FLAG_DRY: int = 4

var def: WeaponDef
var tick_rate_hz: int
## E13: the owner's hero StatBlock (Frame mounts: MANA_REGEN, REGEN_DELAY,
## RELOAD_TIME). Null = the WeaponDef values.
var stats: StatBlock
## Armory v2 Overcharged ammo mod (weapons-and-mods.md §3.7.2): Mana cost and
## reload time multipliers (1 = none). Set by the server from HeroCombat.ammo_mod.
var cost_mult: float = 1.0
var reload_mult: float = 1.0


func _init(weapon: WeaponDef, tick_rate: int) -> void:
	def = weapon
	tick_rate_hz = tick_rate


static func create(weapon: WeaponDef, tick_rate: int) -> AmmoFeed:
	if weapon.feed_kind == WeaponDef.FeedKind.MAGAZINE:
		return MagazineFeed.new(weapon, tick_rate)
	return ManaPoolFeed.new(weapon, tick_rate)


## Mana regen per second after mounts (Flux Coil).
func regen_rate() -> float:
	return def.mana_regen * (stats.get_value(StatCatalog.MANA_REGEN) if stats != null else 1.0)


## Regen delay after mounts (Flux Coil) and the Supply Cache cut (C5), never below 0.
func regen_delay_s() -> float:
	if stats == null:
		return maxf(0.0, def.mana_regen_delay_s)
	return maxf(0.0, (def.mana_regen_delay_s + stats.get_value(StatCatalog.REGEN_DELAY)) * stats.get_value(StatCatalog.REGEN_DELAY_MULT))


## Reload time `t` after mounts (Quickload) and Overcharged.
func reload_time(t: float) -> float:
	return t * (stats.get_value(StatCatalog.RELOAD_TIME) if stats != null else 1.0) * reload_mult


## Armory v2 capacity_mult (items-and-armory.md §3.5: pool / magazine / reserve,
## cap +60%); 1.0 without stats.
func capacity_mult() -> float:
	return stats.get_value(StatCatalog.CAPACITY_MULT) if stats != null else 1.0


## `base` scaled by capacity_mult(), rounded down; Mechanical counts gain at least
## AmmoRulesDef.min_capacity_gain when the bonus is above 0 (§3.5.3 Reservoir Frame).
func scaled_capacity(base: int, whole_rounds: bool) -> int:
	var m := capacity_mult()
	if is_equal_approx(m, 1.0):
		return base
	var n := floori(base * m + 1e-4)
	if whole_rounds and m > 1.0:
		n = maxi(n, base + DamageMath.rules().min_capacity_gain)
	return maxi(1 if base > 0 else 0, n)


## Shock Overload Disrupted (weapons-and-mods.md §3.7.1) for `duration_ticks`:
## Mana pauses regen and restarts the delay; Mech adds `penalty_ticks` to the
## current reload, or to the next one started while Disrupted.
func disrupt(_tick: int, _duration_ticks: int, _penalty_ticks: int) -> void:
	pass


## Seconds -> whole ticks (rounded up, at least 1).
func ticks(seconds: float) -> int:
	return maxi(1, ceili(seconds * tick_rate_hz - 1e-6))


## Advance timers to `tick` (call once per tick, before firing).
func step(_tick: int) -> void:
	pass


func can_fire() -> bool:
	return false


## Spend one shot at `tick`.
func consume(_tick: int) -> void:
	pass


## Reload button pressed at `tick`.
func request_reload(_tick: int) -> void:
	pass


## Full refill (respawn, Armory).
func refill() -> void:
	pass


## Mana in the pool, or rounds in the magazine.
func current() -> float:
	return 0.0


## Pool size or magazine size.
func capacity() -> int:
	return 0


## Reserve rounds (0 for Mana).
func reserve_count() -> int:
	return 0


## FLAG_* bits for replication and HUD.
func flags() -> int:
	return 0
