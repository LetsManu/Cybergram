class_name DamageMath
extends RefCounted
## Weapon damage formulas (design/gdd/weapons-and-mods.md §4.1–§4.3). Pure
## static functions; armor is applied by HealthComponent (§4.1 A_mult) so skill
## damage goes through the same reduction.
##
## Example: DamageMath.hit_damage(def, 30.0, false, 1) -> 29 * F(30) for Threadcaster.

## §4.2 / heroes.md §3.3: k_lvl.
const K_LEVEL: float = 0.025
## §4.1: armor + damage reduction is clamped at 70%.
const MAX_REDUCTION: float = 0.70

## E13 Chamber Ammo Types in the slice (§3.7.1, §3.10).
const AMMO_STANDARD: int = 0
const AMMO_PIERCING: int = 1
const AMMO_SUNDER: int = 2
## Target classes for V_mult (§4.1).
const TARGET_HERO: int = 0
## Wardlings, Sentinels, traps, deployables (Aegis Wall).
const TARGET_CONSTRUCT: int = 1
## Barricades, Ward Generators.
const TARGET_STRUCTURE: int = 2
## Mana Uplink: immune to every ammo effect (C7).
const TARGET_UPLINK: int = 3
## §3.7.1 Piercing: ignores 40% of armor; +25% vs hero-deployed shields.
const PIERCING_ARMOR_PEN: float = 0.40
const PIERCING_SHIELD_MULT: float = 1.25
## §3.7.1 Sunder: +35% constructs, +20% structures, −10% heroes.
const SUNDER_CONSTRUCT_MULT: float = 1.35
const SUNDER_STRUCTURE_MULT: float = 1.20
const SUNDER_HERO_MULT: float = 0.90


## §4.2 L(level) = 1 + k_lvl * (level - 1).
static func level_mult(level: int) -> float:
	return 1.0 + K_LEVEL * (maxi(level, 1) - 1)


## §4.3 F(d): 1 up to r0, linear to f_min at r1, f_min beyond.
## `range_mult` (Barrel FALLOFF_RANGE) stretches the falloff start and end.
static func falloff(def: WeaponDef, distance: float, range_mult: float = 1.0) -> float:
	distance /= maxf(range_mult, 0.1)
	var r0 := def.falloff_start_m
	var r1 := def.falloff_end_m
	if distance <= r0:
		return 1.0
	if distance >= r1 or r1 <= r0:
		return def.falloff_min
	return 1.0 - (1.0 - def.falloff_min) * (distance - r0) / (r1 - r0)


## §4.1 A_mult = 1 - min(0.70, A_eff + DR).
static func armor_mult(armor: float, damage_reduction: float = 0.0) -> float:
	return 1.0 - minf(MAX_REDUCTION, maxf(armor, 0.0) + maxf(damage_reduction, 0.0))


## §4.1 V_mult of `ammo` against a target class (`shield`: a hero-deployed
## shield wall, which Piercing hits +25%).
static func ammo_mult(ammo: int, target_class: int, shield: bool = false) -> float:
	if target_class == TARGET_UPLINK:
		return 1.0
	if ammo == AMMO_SUNDER:
		match target_class:
			TARGET_HERO:
				return SUNDER_HERO_MULT
			TARGET_CONSTRUCT:
				return SUNDER_CONSTRUCT_MULT
			TARGET_STRUCTURE:
				return SUNDER_STRUCTURE_MULT
	if ammo == AMMO_PIERCING and shield:
		return PIERCING_SHIELD_MULT
	return 1.0


## Armor penetration of `ammo` (DamageInfo.armor_pen).
static func ammo_armor_pen(ammo: int) -> float:
	return PIERCING_ARMOR_PEN if ammo == AMMO_PIERCING else 0.0


## Damage of one hit (one pellet) before the target's armor:
## D_base * L(level) * F(d) * H. S_skill, M_dmg, V_mult and Brittle are 1.0
## until skills, mods and ammo types land (E10, E13).
static func hit_damage(def: WeaponDef, distance: float, headshot: bool, level: int = 1, range_mult: float = 1.0) -> float:
	var h := def.headshot_mult if headshot else 1.0
	return def.damage * level_mult(level) * falloff(def, distance, range_mult) * h
