class_name HeroCombat
extends RefCounted
## Server-side combat state of one hero: def, team, health, weapon, death and
## respawn bookkeeping (architecture.md §5.1 HeroSim components, abridged).
## E10: the hero StatBlock (move speed, damage taken/dealt, CDR...), statuses
## and the AbilityRunner with the kit's four SkillInstances.

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
## E10 (ADR-0004): hero-scope stats, statuses and skills.
var stats: StatBlock
var status: StatusComponent
var abilities: AbilityRunner


func _init(hero: HeroDef, team_: int, tick_rate_hz: int, rng_seed: int) -> void:
	def = hero
	team = team_
	health = HealthComponent.new(hero.max_hp, hero.armor, team_)
	if hero.weapon != null:
		weapon = WeaponSim.new(hero.weapon, tick_rate_hz, rng_seed)
	stats = StatCatalog.new_hero_block(hero.move_speed)
	health.stats = stats
	var passive := Modifier.source(Modifier.SRC_PASSIVE, rng_seed)
	for m in hero.passive_modifiers:
		if m != null and m.index() >= 0:
			stats.add_modifier(m.to_modifier(passive))
	var rules := AbilityRulesDef.new()
	status = StatusComponent.new(stats, health, rules, tick_rate_hz, rng_seed)
	abilities = AbilityRunner.new(self, rules, tick_rate_hz)


## heroes.md §3.3 SkillPower(L) × the SKILL_POWER stat.
func skill_power() -> float:
	return stats.get_value(StatCatalog.SKILL_POWER) * (1.0 + abilities.rules.skill_power_per_level * (level - 1))


## Can fire the weapon this tick (not stunned, not in forced motion).
func can_shoot() -> bool:
	return not status.is_stunned() and not abilities.is_dashing()


func reset_for_respawn() -> void:
	dead = false
	health.reset()
	if weapon != null:
		weapon.reset()
	status.clear()
	# heroes.md §3.4: respawning at the HQ Sanctum resets basic cooldowns (every
	# respawn in the slice is at the HQ; Forward Beacons arrive later).
	abilities.on_respawn_at_hq()
