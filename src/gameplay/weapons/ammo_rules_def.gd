class_name AmmoRulesDef
extends Resource
## Armory v2 combat numbers (design/gdd/items-and-armory.md §3.7, §4.3;
## weapons-and-mods.md §3.7.1, §3.7.2, §4.1, §4.5). Every value the combat
## code reads lives here; assets/data/weapons/ammo_rules.tres is the tuned copy
## (DamageMath.rules() loads it once, defaults = the GDD values).

@export_group("Caps (items-and-armory.md §3.7)")
## M_dmg cap (also the StatCatalog MOD_DAMAGE limit).
@export_range(0.0, 1.0, 0.01) var mod_damage_cap: float = 0.25
## M_rate cap.
@export_range(0.0, 1.0, 0.01) var fire_rate_cap: float = 0.15
## Throughput cap on G (Brittle and Burn included): body TTK -25%.
@export_range(1.0, 2.0, 0.001) var throughput_cap: float = 1.333
## Total weapon multiplier cap S_skill x G_hit.
@export_range(1.0, 4.0, 0.01) var total_mult_cap: float = 2.25
## Armor penetration cap (cuts base and gear armor).
@export_range(0.0, 1.0, 0.01) var pen_cap: float = 0.60
## Gear Armor / Gear Resist caps.
@export_range(0.0, 1.0, 0.01) var gear_armor_cap: float = 0.20
@export_range(0.0, 1.0, 0.01) var gear_resist_cap: float = 0.20
## Armor + resist + DR clamp (heroes.md §5.1).
@export_range(0.0, 1.0, 0.01) var reduction_cap: float = 0.70

@export_group("Weapon conversions (items-and-armory.md §3.5.1-§3.5.3)")
## Falloff bonus points -> projectile speed bonus (Liora rows: Lens +10% -> +15%,
## Longsight Ring +18% -> +25%, Longsight Lens +30% -> +40%); piecewise linear.
@export var projectile_curve_in: PackedFloat32Array = PackedFloat32Array([0.0, 0.10, 0.18, 0.30])
@export var projectile_curve_out: PackedFloat32Array = PackedFloat32Array([0.0, 0.15, 0.25, 0.40])
## Falloff bonus points -> beam max range metres (Hex rows: +1.5 / +2.5 / +4 m).
@export var beam_curve_in: PackedFloat32Array = PackedFloat32Array([0.0, 0.10, 0.18, 0.30])
@export var beam_curve_out: PackedFloat32Array = PackedFloat32Array([0.0, 1.5, 2.5, 4.0])
## Weapons that are beams (Hex Glitchcaster): falloff -> beam range, fire rate ->
## tick damage, no headshot bonus.
@export var beam_weapon_ids: Array[StringName] = [&"weapon_glitchcaster"]
## Pellet weapons get this share of the item headshot bonus (Ironmaw +0.10 of +0.30).
@export_range(0.0, 1.0, 0.01) var pellet_headshot_share: float = 0.3333
## Mechanical capacity bonus: at least this many extra rounds when the bonus is > 0.
@export_range(0, 10) var min_capacity_gain: int = 1

@export_group("Ammo Types (weapons-and-mods.md §3.7.1)")
## Piercing: armor ignored; damage vs hero-deployed shields.
@export_range(0.0, 1.0, 0.01) var piercing_pen: float = 0.40
@export_range(1.0, 2.0, 0.01) var piercing_shield_mult: float = 1.25
## Sunder bonus vs constructs / structures; multiplier vs heroes (penalty, not scaled by potency).
@export_range(0.0, 1.0, 0.01) var sunder_construct_bonus: float = 0.35
@export_range(0.0, 1.0, 0.01) var sunder_structure_bonus: float = 0.20
@export_range(0.0, 1.0, 0.01) var sunder_hero_mult: float = 0.90
## Incendiary: share of final damage into the Burn pool, pool duration, max burn DPS,
## Scorched healing cut.
@export_range(0.0, 1.0, 0.01) var burn_share: float = 0.12
@export_range(0.1, 10.0, 0.1) var burn_duration_s: float = 3.0
@export_range(1.0, 200.0, 1.0) var burn_max_dps: float = 35.0
@export_range(0.0, 1.0, 0.01) var scorched_heal_cut: float = 0.30
## Shock: Charge per final damage, threshold, arc damage / targets / radius,
## Disrupted duration, Mech reload penalty, decay rate / delay, per-target ICD.
@export_range(0.0, 5.0, 0.01) var shock_k: float = 0.6
@export_range(1.0, 1000.0, 1.0) var shock_threshold: float = 100.0
@export_range(0.0, 500.0, 1.0) var shock_arc_damage: float = 30.0
@export_range(0, 10) var shock_arc_targets: int = 2
@export_range(0.0, 50.0, 0.5) var shock_arc_radius_m: float = 6.0
@export_range(0.0, 10.0, 0.1) var disrupted_s: float = 1.0
@export_range(0.0, 10.0, 0.05) var disrupted_reload_penalty_s: float = 0.5
@export_range(0.0, 500.0, 1.0) var shock_decay_per_s: float = 25.0
@export_range(0.0, 10.0, 0.05) var shock_decay_delay_s: float = 1.0
@export_range(0.0, 30.0, 0.5) var shock_icd_s: float = 3.0
## Siphon: heal share vs heroes / Wardlings (structures 0); Mana-gun mana share.
@export_range(0.0, 1.0, 0.01) var siphon_hero: float = 0.08
@export_range(0.0, 1.0, 0.01) var siphon_wardling: float = 0.04
@export_range(0.0, 1.0, 0.01) var siphon_mana: float = 0.06
## Cryo: Chill per final damage, meter max, max slow, decay rate / delay, Brittle
## damage multiplier / duration / re-trigger lock.
@export_range(0.0, 5.0, 0.01) var cryo_k: float = 0.5
@export_range(1.0, 1000.0, 1.0) var chill_max: float = 100.0
@export_range(0.0, 1.0, 0.01) var chill_max_slow: float = 0.25
@export_range(0.0, 500.0, 1.0) var chill_decay_per_s: float = 30.0
@export_range(0.0, 10.0, 0.05) var chill_decay_delay_s: float = 0.75
@export_range(1.0, 2.0, 0.01) var brittle_mult: float = 1.08
@export_range(0.0, 10.0, 0.1) var brittle_s: float = 2.0
@export_range(0.0, 30.0, 0.5) var brittle_lock_s: float = 4.0

@export_group("Ammo Mods (weapons-and-mods.md §3.7.2)")
## Saturated / Overcharged potency.
@export_range(1.0, 3.0, 0.01) var saturated_potency: float = 1.3
@export_range(1.0, 3.0, 0.01) var overcharged_potency: float = 1.5
## Overcharged costs: Mana cost and Mech reload time multipliers.
@export_range(1.0, 3.0, 0.01) var overcharged_mana_cost_mult: float = 1.2
@export_range(1.0, 3.0, 0.01) var overcharged_reload_mult: float = 1.15
## Lingering: effect duration multiplier (Burn time, Disrupted, Brittle, Chill decay delay).
@export_range(1.0, 3.0, 0.01) var lingering_duration_mult: float = 1.5
## Volatile on-kill burst radius, Burn share passed on, Siphon heal radius / HP,
## Chill added, Sunder construct damage.
@export_range(0.0, 50.0, 0.5) var volatile_radius_m: float = 4.0
@export_range(0.0, 1.0, 0.01) var volatile_burn_share: float = 0.40
@export_range(0.0, 50.0, 0.5) var volatile_heal_radius_m: float = 8.0
@export_range(0.0, 500.0, 1.0) var volatile_heal_hp: float = 40.0
@export_range(0.0, 500.0, 1.0) var volatile_chill: float = 50.0
@export_range(0.0, 500.0, 1.0) var volatile_sunder_damage: float = 30.0
## Ammo Types each mod works with ("—" cells of the §3.7.2 table are left out);
## Saturated, Tracer and Overcharged work with every type.
@export var lingering_types: PackedInt32Array = PackedInt32Array([3, 4, 6])
@export var volatile_types: PackedInt32Array = PackedInt32Array([2, 3, 4, 5, 6])
## Tracer: team mark duration.
@export_range(0.0, 10.0, 0.1) var tracer_mark_s: float = 1.5

@export_group("Movement items (items-and-armory.md §3.5)")
## Out of combat = this long without taking or dealing damage (Stride Rig).
@export_range(0.0, 30.0, 0.5) var out_of_combat_s: float = 4.0


## Piecewise-linear map through (xs, ys); extrapolates the last slope.
static func curve(xs: PackedFloat32Array, ys: PackedFloat32Array, x: float) -> float:
	var n := mini(xs.size(), ys.size())
	if n == 0:
		return 0.0
	if n == 1 or x <= xs[0]:
		return ys[0]
	for i in range(1, n):
		if x <= xs[i] or i == n - 1:
			var span := xs[i] - xs[i - 1]
			var t := (x - xs[i - 1]) / span if span > 0.0 else 0.0
			return ys[i - 1] + (ys[i] - ys[i - 1]) * t
	return ys[n - 1]


## True if `weapon` is a beam (Hex): DamageMath conversions differ.
func is_beam(weapon: WeaponDef) -> bool:
	return weapon != null and beam_weapon_ids.has(weapon.id)
