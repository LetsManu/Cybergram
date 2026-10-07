extends GdUnitTestSuite
## Armory v2 damage formulas (design/gdd/items-and-armory.md §4.3, §3.7;
## weapons-and-mods.md §4.1): gear armor / resist, penetration on base and gear
## armor, Rend hook, throughput G / G_hit with Brittle and Burn, the 2.25 clamp,
## headshot bonus, range conversions and v1 identity at default stats.

## §4.3 worked example: Ryker L10 at <= 22 m = 18 × 1.225.
const RYKER_L10_HIT: float = 18.0 * 1.225


func _hero_health(gear_armor: float, gear_resist: float = 0.0, base_armor: float = 0.0) -> HealthComponent:
	var hc := HealthComponent.new(10000.0, base_armor, 1)
	hc.stats = StatCatalog.new_hero_block(6.0, 10000.0)
	if gear_armor > 0.0:
		hc.stats.add_modifier(Modifier.make(StatCatalog.GEAR_ARMOR, Modifier.Op.ADD, gear_armor, 1))
	if gear_resist > 0.0:
		hc.stats.add_modifier(Modifier.make(StatCatalog.GEAR_RESIST, Modifier.Op.ADD, gear_resist, 1))
	return hc


func _hit(hc: HealthComponent, amount: float, pen: float = 0.0, rend: float = 0.0,
		type: DamageInfo.Type = DamageInfo.Type.WEAPON) -> float:
	var info := DamageInfo.make(amount, 7, 0, 0, type)
	info.armor_pen = pen
	info.rend = rend
	return hc.apply_damage(info)


func test_gdd_ryker_vs_liora_plate_harness() -> void:
	# Plate Harness A_gear 0.13: 0.87 -> 19.2.
	assert_float(_hit(_hero_health(0.13), RYKER_L10_HIT)).is_equal_approx(19.18, 0.01)
	# Piercing P 0.40: A_w = 0.078 -> 20.3.
	assert_float(_hit(_hero_health(0.13), RYKER_L10_HIT, 0.40)).is_equal_approx(20.33, 0.01)
	# Piercing + Breaker Bore (P 0.60 cap) and 4 Rend stacks (0.08): A_w 0.02 -> 21.6.
	assert_float(_hit(_hero_health(0.13), RYKER_L10_HIT, 0.85, 0.08)).is_equal_approx(21.61, 0.01)


func test_ac11_armor_resist_percentages() -> void:
	assert_float(_hit(_hero_health(0.13), 100.0)).is_equal_approx(87.0, 1e-3)
	assert_float(_hit(_hero_health(0.13), 100.0, 0.40)).is_equal_approx(92.2, 1e-3)
	# Skill hit on R_gear 0.15 deals 85%; gear armor never reduces skill damage.
	assert_float(_hit(_hero_health(0.13, 0.15), 100.0, 0.0, 0.0, DamageInfo.Type.SKILL)).is_equal_approx(85.0, 1e-3)
	# Resist never reduces weapon damage.
	assert_float(_hit(_hero_health(0.0, 0.15), 100.0)).is_equal_approx(100.0, 1e-3)
	# TRUE damage unchanged.
	assert_float(_hit(_hero_health(0.20, 0.20), 100.0, 0.0, 0.0, DamageInfo.Type.TRUE)).is_equal_approx(100.0, 1e-3)


func test_wardling_shot_uses_weapon_formula_with_base_armor_only() -> void:
	# A Wardling bolt is WEAPON damage: gear armor applies, resist does not.
	var hc := _hero_health(0.10, 0.20)
	assert_float(_hit(hc, 50.0)).is_equal_approx(45.0, 1e-3)


func test_caps_gear_and_penetration() -> void:
	# Gear armor / resist cap 0.20, penetration cap 0.60 on base and gear armor.
	assert_float(DamageMath.weapon_armor(0.0, 0.37, 0.0, 0.0)).is_equal_approx(0.20, 1e-6)
	assert_float(DamageMath.skill_armor(0.0, 0.22)).is_equal_approx(0.20, 1e-6)
	assert_float(DamageMath.weapon_armor(0.20, 0.20, 0.0, 0.95)).is_equal_approx(0.16, 1e-6)
	# Rend floors gear armor at 0; base armor untouched.
	assert_float(DamageMath.weapon_armor(0.20, 0.05, 0.08, 0.0)).is_equal_approx(0.20, 1e-6)
	# Armor + resist + DR clamp 0.70.
	assert_float(DamageMath.armor_mult(0.40, 0.50)).is_equal_approx(0.30, 1e-6)


func test_brannoc_base_armor_with_gear_and_pen() -> void:
	# §4.5: Brannoc full plate, P 0.60: A_w = (0.20 + 0.20) × 0.4 = 0.16.
	var hc := _hero_health(0.20, 0.0, 0.20)
	assert_float(_hit(hc, 100.0, 0.60)).is_equal_approx(84.0, 1e-3)
	assert_float(_hit(_hero_health(0.20, 0.0, 0.20), 100.0)).is_equal_approx(60.0, 1e-3)


func test_build_ceiling_example_clamps_to_1333() -> void:
	# §4.5: M_dmg 0.25, M_rate 0.07 -> G 1.3375 -> 1.333.
	assert_float(DamageMath.throughput(0.25, 0.07)).is_equal_approx(1.3375, 1e-6)
	assert_float(DamageMath.throughput_hit(1.3375)).is_equal_approx(1.333, 1e-6)
	# The cap lands on damage: per-hit × rate = 1.333 (Ryker DPS 180 -> 240).
	var per_hit := DamageMath.weapon_hit_mult(0.25, 0.07, 1.0)
	assert_float(per_hit * 1.07).is_equal_approx(1.333, 1e-6)
	assert_float(180.0 * per_hit * 1.07).is_equal_approx(239.94, 0.01)
	# Caps on the inputs: M_dmg 0.40 -> 0.25, M_rate 0.30 -> 0.15.
	assert_float(DamageMath.throughput(0.40, 0.30)).is_equal_approx(1.25 * 1.15, 1e-6)


func test_brittle_example_keeps_total_at_1333() -> void:
	# Capped Ryker (G 1.333) on a Brittle target: G_hit = 1.333 / 1.08 = 1.234.
	assert_float(DamageMath.throughput_hit(1.333, 1.08)).is_equal_approx(1.2343, 1e-4)
	var with_b := DamageMath.weapon_hit_mult(0.25, 0.07, 1.0, 1.08)
	assert_float(with_b * 1.07).is_equal_approx(1.333, 1e-6)  # G_hit × B_brittle = 1.333, not 1.44
	# Uncapped build: Brittle adds its full 8% until the limit.
	assert_float(DamageMath.weapon_hit_mult(0.0, 0.0, 1.0, 1.08)).is_equal_approx(1.08, 1e-6)


func test_burn_counts_toward_the_throughput_limit() -> void:
	# Overcharged Incendiary b_burn 0.18 on a capped build: hit × (1 + b) <= 1.333.
	var m := DamageMath.weapon_hit_mult(0.25, 0.07, 1.0, 1.0, 0.18)
	assert_float(m * 1.07 * 1.18).is_equal_approx(1.333, 1e-6)
	# Brittle and Burn together.
	var mb := DamageMath.weapon_hit_mult(0.25, 0.0, 1.0, 1.08, 0.12)
	assert_float(mb * 1.12).is_equal_approx(1.333, 1e-6)


func test_total_multiplier_clamp_2_25() -> void:
	# Sable ult combo: S 1.80 × G 1.333 = 2.399 -> 2.25.
	assert_float(DamageMath.weapon_hit_mult(0.25, 0.07, 1.80) * 1.07).is_equal_approx(2.25, 1e-6)
	assert_float(DamageMath.weapon_hit_mult(0.10, 0.0, 1.80)).is_equal_approx(1.98, 1e-6)


func test_v1_identity_at_default_stats() -> void:
	# M_rate 0, no Brittle / Burn: S × (1 + M_dmg), exactly as v1.
	for s in [1.0, 1.25, 1.5]:
		for m in [0.0, 0.12, 0.16, 0.25]:
			assert_float(DamageMath.weapon_hit_mult(m, 0.0, s)).is_equal_approx(s * (1.0 + m), 1e-6)
	# No gear: armor exactly as v1 (A × (1 − P)).
	assert_float(_hit(_hero_health(0.0, 0.0, 0.20), 100.0, 0.40)).is_equal_approx(88.0, 1e-3)


func test_beam_rate_is_tick_damage() -> void:
	# Hex: Tempo +4% is tick damage, not interval.
	assert_float(DamageMath.weapon_hit_mult(0.0, 0.04, 1.0, 1.0, 0.0, true)).is_equal_approx(1.04, 1e-6)
	var hex := WeaponDef.new()
	hex.id = &"weapon_glitchcaster"
	assert_float(WeaponSim.item_rate_mult_for(hex, 0.04)).is_equal(1.0)


func test_headshot_bonus_and_conversions() -> void:
	var ar := WeaponDef.new()
	ar.headshot_mult = 2.0
	assert_float(DamageMath.headshot_mult(ar, 0.30)).is_equal_approx(2.30, 1e-6)
	var maw := WeaponDef.new()
	maw.headshot_mult = 1.25
	maw.pellets = 10
	assert_float(DamageMath.headshot_mult(maw, 0.30)).is_equal_approx(1.35, 1e-3)  # Ironmaw +0.10
	var hex := WeaponDef.new()
	hex.id = &"weapon_glitchcaster"
	hex.headshot_mult = 1.0
	assert_float(DamageMath.headshot_mult(hex, 0.30)).is_equal(1.0)  # beams never crit
	assert_float(DamageMath.hit_damage(ar, 1.0, true, 1, 1.0, 0.30)).is_equal_approx(20.0 * 2.3, 1e-4)


func test_range_conversions_match_gdd_rows() -> void:
	var liora := WeaponDef.new()
	liora.projectile_speed = 90.0
	for row in [[1.10, 1.15], [1.18, 1.25], [1.30, 1.40]]:
		assert_float(DamageMath.range_conversion(liora, row[0])[1]).is_equal_approx(row[1], 1e-4)
		assert_float(DamageMath.range_conversion(liora, row[0])[0]).is_equal(1.0)
	var hex := WeaponDef.new()
	hex.id = &"weapon_glitchcaster"
	for row in [[1.10, 1.5], [1.18, 2.5], [1.30, 4.0]]:
		assert_float(DamageMath.range_conversion(hex, row[0])[2]).is_equal_approx(row[1], 1e-4)
	var ar := WeaponDef.new()
	assert_float(DamageMath.range_conversion(ar, 1.18)[0]).is_equal_approx(1.18, 1e-6)
