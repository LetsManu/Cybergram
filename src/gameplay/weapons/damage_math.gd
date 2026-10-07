class_name DamageMath
extends RefCounted
## Weapon damage formulas (design/gdd/weapons-and-mods.md §4.1–§4.3). Pure
## static functions; armor is applied by HealthComponent (§4.1 A_mult) so skill
## damage goes through the same reduction.
##
## Example: DamageMath.hit_damage(def, 30.0, false, 1) -> 29 * F(30) for Threadcaster.

## §4.2 / heroes.md §3.3: k_lvl.
const K_LEVEL: float = 0.025

## E13 Chamber Ammo Types in the slice (§3.7.1, §3.10).
const AMMO_STANDARD: int = 0
const AMMO_PIERCING: int = 1
const AMMO_SUNDER: int = 2
## Armory v2 Ammo Types (weapons-and-mods.md §3.7.1; catalog v22 ammo_type ids).
const AMMO_INCENDIARY: int = 3
const AMMO_SHOCK: int = 4
const AMMO_SIPHON: int = 5
const AMMO_CRYO: int = 6
## Armory v2 Ammo Mods (§3.7.2; catalog v22 ammo_mod ids, 0 = none).
const MOD_NONE: int = 0
const MOD_SATURATED: int = 1
const MOD_LINGERING: int = 2
const MOD_VOLATILE: int = 3
const MOD_TRACER: int = 4
const MOD_OVERCHARGED: int = 5
## Default tuned rules (AmmoRulesDef).
const RULES_PATH := "res://assets/data/weapons/ammo_rules.tres"
## Target classes for V_mult (§4.1).
const TARGET_HERO: int = 0
## Wardlings, Sentinels, traps, deployables (Aegis Wall).
const TARGET_CONSTRUCT: int = 1
## Barricades, Ward Generators.
const TARGET_STRUCTURE: int = 2
## Mana Uplink: immune to every ammo effect (C7).
const TARGET_UPLINK: int = 3


static var _rules: AmmoRulesDef


## The shared Armory v2 combat rules (loaded once; GDD defaults if the file is missing).
static func rules() -> AmmoRulesDef:
	if _rules == null:
		_rules = load(RULES_PATH) as AmmoRulesDef if ResourceLoader.exists(RULES_PATH) else null
		if _rules == null:
			_rules = AmmoRulesDef.new()
	return _rules


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
	return 1.0 - minf(rules().reduction_cap, maxf(armor, 0.0) + maxf(damage_reduction, 0.0))


## §4.1 V_mult of `ammo` against a target class (`shield`: a hero-deployed
## shield wall, which Piercing hits +25%). `potency` scales the Sunder bonus
## (Saturated / Overcharged, §3.7.2); the hero penalty is unchanged.
static func ammo_mult(ammo: int, target_class: int, shield: bool = false, potency: float = 1.0) -> float:
	if target_class == TARGET_UPLINK:
		return 1.0
	var r := rules()
	if ammo == AMMO_SUNDER:
		match target_class:
			TARGET_HERO:
				return r.sunder_hero_mult
			TARGET_CONSTRUCT:
				return 1.0 + r.sunder_construct_bonus * potency
			TARGET_STRUCTURE:
				return 1.0 + r.sunder_structure_bonus * potency
	if ammo == AMMO_PIERCING and shield:
		return r.piercing_shield_mult
	return 1.0


## Armor penetration of `ammo` (DamageInfo.armor_pen), scaled by `potency`
## (Saturated 52%, Overcharged 60% = the cap).
static func ammo_armor_pen(ammo: int, potency: float = 1.0) -> float:
	return rules().piercing_pen * potency if ammo == AMMO_PIERCING else 0.0


## §3.7.2 potency of `mod` (Saturated 1.3, Overcharged 1.5, else 1.0).
static func mod_potency(mod: int) -> float:
	var r := rules()
	match mod:
		MOD_SATURATED:
			return r.saturated_potency
		MOD_OVERCHARGED:
			return r.overcharged_potency
	return 1.0


## §3.7.2 duration multiplier of `mod` (Lingering 1.5, else 1.0).
static func mod_duration(mod: int) -> float:
	return rules().lingering_duration_mult if mod == MOD_LINGERING else 1.0


## items-and-armory.md §4.3: G = (1 + min(cap, M_dmg)) × (1 + min(cap, M_rate)).
static func throughput(m_dmg: float, m_rate: float) -> float:
	var r := rules()
	return (1.0 + clampf(m_dmg, 0.0, r.mod_damage_cap)) * (1.0 + clampf(m_rate, 0.0, r.fire_rate_cap))


## §4.3: G_hit = min(G, 1.333 / (B_brittle × (1 + b_burn))).
static func throughput_hit(g: float, brittle: float = 1.0, b_burn: float = 0.0) -> float:
	return minf(g, rules().throughput_cap / (maxf(brittle, 1e-3) * (1.0 + maxf(b_burn, 0.0))))


## Per-hit damage multiplier of a hero weapon (§4.3), excluding L, F, H, V and armor:
## min(2.25, S_skill × G_hit) × B_brittle, divided by the fire-rate part of G
## (M_rate shortens the shot interval instead; the cap lands on damage).
## `rate_as_damage` (beam weapons): M_rate is tick damage, not interval.
## v1 identity: M_rate 0, no Brittle / Burn -> S × (1 + M_dmg) below the 2.25 clamp.
static func weapon_hit_mult(m_dmg: float, m_rate: float, s_skill: float, brittle: float = 1.0,
		b_burn: float = 0.0, rate_as_damage: bool = false) -> float:
	var r := rules()
	var g := throughput(m_dmg, m_rate)
	var gh := throughput_hit(g, brittle, b_burn)
	var rate_part := 1.0 if rate_as_damage else 1.0 + clampf(m_rate, 0.0, r.fire_rate_cap)
	return minf(r.total_mult_cap, maxf(s_skill, 0.0) * gh) / rate_part * maxf(brittle, 1.0)


## §4.3 weapon hit: A_w = (A_base + max(0, min(0.20, A_gear) − Rend)) × (1 − min(0.60, P)).
static func weapon_armor(a_base: float, a_gear: float, rend: float, pen: float) -> float:
	var r := rules()
	var gear := maxf(0.0, clampf(a_gear, 0.0, r.gear_armor_cap) - maxf(rend, 0.0))
	return (maxf(a_base, 0.0) + gear) * (1.0 - clampf(pen, 0.0, r.pen_cap))


## §4.3 skill hit: A_s = A_base + min(0.20, R_gear) (no penetration).
static func skill_armor(a_base: float, r_gear: float) -> float:
	return maxf(a_base, 0.0) + clampf(r_gear, 0.0, rules().gear_resist_cap)


## Headshot multiplier H with the item bonus (§4.1: +0.30 cap; pellet weapons
## get pellet_headshot_share of it; beams never crit).
static func headshot_mult(def: WeaponDef, bonus: float) -> float:
	var r := rules()
	if r.is_beam(def):
		return def.headshot_mult
	var b := clampf(bonus, 0.0, 10.0)
	if def.pellets > 1:
		b *= r.pellet_headshot_share
	return def.headshot_mult + b


## §3.5 conversions of the falloff-range stat (value 1 + bonus) for `def`:
## [falloff stretch, projectile speed mult, beam range bonus m]. Projectile
## weapons (Liora) and beams (Hex) convert the bonus instead of stretching falloff.
static func range_conversion(def: WeaponDef, falloff_stat: float) -> Array[float]:
	var r := rules()
	var bonus := maxf(0.0, falloff_stat - 1.0)
	if def != null and def.projectile_speed > 0.0:
		return [1.0, 1.0 + AmmoRulesDef.curve(r.projectile_curve_in, r.projectile_curve_out, bonus), 0.0]
	if r.is_beam(def):
		return [1.0, 1.0, AmmoRulesDef.curve(r.beam_curve_in, r.beam_curve_out, bonus)]
	return [maxf(falloff_stat, 0.1), 1.0, 0.0]


## Damage of one hit (one pellet) before the target's armor:
## D_base * L(level) * F(d) * H (H includes the item headshot bonus).
## S_skill, G_hit, V_mult and Brittle are applied by the caller
## (weapon_hit_mult, ammo_mult).
static func hit_damage(def: WeaponDef, distance: float, headshot: bool, level: int = 1, range_mult: float = 1.0,
		headshot_bonus: float = 0.0) -> float:
	var h := headshot_mult(def, headshot_bonus) if headshot else 1.0
	return def.damage * level_mult(level) * falloff(def, distance, range_mult) * h
