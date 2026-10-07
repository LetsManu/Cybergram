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
## E13: Chamber Ammo Type (DamageMath.AMMO_*), set by the Armory.
var ammo_type: int = DamageMath.AMMO_STANDARD
## Armory v2: Chamber Ammo Mod (DamageMath MOD_*, 0 = none), set by ItemShop.
var ammo_mod: int = 0
## Liora's heal beam is held: the weapon does not fire (SkillEntities sets it).
var beaming: bool = false
## Armory v2 Signature passives (items-and-armory.md §3.5.3); none are on until
## the server sets them from the hero's active items.
var passives: SignaturePassives


func _init(hero: HeroDef, team_: int, tick_rate_hz: int, rng_seed: int) -> void:
	def = hero
	team = team_
	health = HealthComponent.new(hero.max_hp, hero.armor, team_)
	if hero.weapon != null:
		weapon = WeaponSim.new(hero.weapon, tick_rate_hz, rng_seed)
	stats = StatCatalog.new_hero_block(hero.move_speed, hero.max_hp)
	health.stats = stats
	if weapon != null:
		weapon.feed.stats = stats  # E13 Frame mounts
	var passive := Modifier.source(Modifier.SRC_PASSIVE, rng_seed)
	for m in hero.passive_modifiers:
		if m != null and m.index() >= 0:
			stats.add_modifier(m.to_modifier(passive))
	var rules := AbilityRulesDef.new()
	status = StatusComponent.new(stats, health, rules, tick_rate_hz, rng_seed)
	abilities = AbilityRunner.new(self, rules, tick_rate_hz)
	passives = SignaturePassives.new(self, tick_rate_hz)


## heroes.md §3.3 SkillPower(L): the SKILL_POWER stat (apply_level writes the
## per-level MUL).
func skill_power() -> float:
	return stats.get_value(StatCatalog.SKILL_POWER)


## E15 level scaling (heroes.md §3.3) as SRC_LEVEL MUL modifiers on the hero
## StatBlock: MaxHP +4%/level, weapon damage +2.5%/level (weapons-and-mods.md
## §4.2), SkillPower +2%/level. Current HP rises by the max-HP gain.
func apply_level(new_level: int, hp_per_level: float = 0.04, weapon_per_level: float = DamageMath.K_LEVEL) -> void:
	level = clampi(new_level, 1, 99)
	var src := Modifier.source(Modifier.SRC_LEVEL, 0)
	stats.remove_by_source(src)
	var k := float(level - 1)
	if level > 1:
		stats.add_modifier(Modifier.make(StatCatalog.MAX_HP, Modifier.Op.MUL, 1.0 + hp_per_level * k, src))
		stats.add_modifier(Modifier.make(StatCatalog.WEAPON_DAMAGE, Modifier.Op.MUL, 1.0 + weapon_per_level * k, src))
		stats.add_modifier(Modifier.make(StatCatalog.SKILL_POWER, Modifier.Op.MUL,
			1.0 + abilities.rules.skill_power_per_level * k, src))
	sync_max_hp()


## Re-reads max HP = MAX_HP(L) + item HP (items-and-armory.md §3.7, cap +200).
## A gain raises current HP by the same amount; a loss only clamps it.
func sync_max_hp() -> void:
	var old_max := health.max_hp
	health.max_hp = stats.get_value(StatCatalog.MAX_HP) + stats.get_value(StatCatalog.ITEM_MAX_HP)
	if health.is_alive():
		health.hp = minf(health.max_hp, health.hp + maxf(0.0, health.max_hp - old_max))


## Weapon damage multiplier before falloff/headshot/armor: L(level) × (1 + M_dmg)
## (weapons-and-mods.md §4.1; M_dmg capped at +0.25 by the stat limit).
func weapon_damage_mult() -> float:
	return stats.get_value(StatCatalog.WEAPON_DAMAGE) * (1.0 + stats.get_value(StatCatalog.MOD_DAMAGE))


## Can fire the weapon this tick (not stunned, not in forced motion).
func can_shoot() -> bool:
	return not status.is_stunned() and not abilities.is_dashing() and not beaming


func reset_for_respawn(at_hq: bool = true) -> void:
	dead = false
	health.reset()
	if weapon != null:
		weapon.reset()
	status.clear()
	# heroes.md §3.4: respawning at the HQ Sanctum resets basic cooldowns; a
	# Forward Beacon spawn (E13) does not.
	if at_hq:
		abilities.on_respawn_at_hq()
