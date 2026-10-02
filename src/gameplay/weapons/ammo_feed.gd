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


## Regen delay after mounts (Flux Coil), never below 0.
func regen_delay_s() -> float:
	return maxf(0.0, def.mana_regen_delay_s + (stats.get_value(StatCatalog.REGEN_DELAY) if stats != null else 0.0))


## Reload time `t` after mounts (Quickload).
func reload_time(t: float) -> float:
	return t * (stats.get_value(StatCatalog.RELOAD_TIME) if stats != null else 1.0)


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
