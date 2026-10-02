class_name HeroCombat
extends RefCounted
## Server-side combat state of one hero: def, team, health, weapon, death and
## respawn bookkeeping (architecture.md §5.1 HeroSim components, abridged).

var def: HeroDef
var team: int
var health: HealthComponent
var weapon: WeaponSim  # null for a hero without a weapon
var dead: bool = false
## Server tick on which the hero respawns (valid while dead).
var respawn_tick: int = 0
## Fallback spawn (the hero's first spawn point).
var home_spawn: Vector3
## Applied-command count: the weapon's clock (see WeaponSim).
var local_tick: int = 0
var level: int = 1
var kills: int = 0
var deaths: int = 0


func _init(hero: HeroDef, team_: int, tick_rate_hz: int, rng_seed: int) -> void:
	def = hero
	team = team_
	health = HealthComponent.new(hero.max_hp, hero.armor, team_)
	if hero.weapon != null:
		weapon = WeaponSim.new(hero.weapon, tick_rate_hz, rng_seed)


func reset_for_respawn() -> void:
	dead = false
	health.reset()
	if weapon != null:
		weapon.reset()
