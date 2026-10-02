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


## §4.2 L(level) = 1 + k_lvl * (level - 1).
static func level_mult(level: int) -> float:
	return 1.0 + K_LEVEL * (maxi(level, 1) - 1)


## §4.3 F(d): 1 up to r0, linear to f_min at r1, f_min beyond.
static func falloff(def: WeaponDef, distance: float) -> float:
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


## Damage of one hit (one pellet) before the target's armor:
## D_base * L(level) * F(d) * H. S_skill, M_dmg, V_mult and Brittle are 1.0
## until skills, mods and ammo types land (E10, E13).
static func hit_damage(def: WeaponDef, distance: float, headshot: bool, level: int = 1) -> float:
	var h := def.headshot_mult if headshot else 1.0
	return def.damage * level_mult(level) * falloff(def, distance) * h
