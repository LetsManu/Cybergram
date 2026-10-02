extends GdUnitTestSuite
## StatBlock / Modifier (ADR-0004 §1, architecture.md §7.1): order of
## operations value = clamp(OVERRIDE ?? (base + ΣADD) × (1 + ΣPCT) × ΠMUL),
## latest OVERRIDE wins, remove_by_source, expiry by tick, limits.

const S: int = 0


func _block(base: float) -> StatBlock:
	return StatBlock.new(PackedFloat32Array([base, 1.0]))


func test_order_of_operations_add_then_pct_then_mul() -> void:
	var b := _block(10.0)
	b.add_modifier(Modifier.make(S, Modifier.Op.MUL, 0.5))
	b.add_modifier(Modifier.make(S, Modifier.Op.PCT, 0.5))
	b.add_modifier(Modifier.make(S, Modifier.Op.ADD, 5.0))
	b.add_modifier(Modifier.make(S, Modifier.Op.PCT, 0.5))
	# (10 + 5) × (1 + 0.5 + 0.5) × 0.5 = 15, whatever the insertion order.
	assert_float(b.get_value(S)).is_equal_approx(15.0, 1e-5)
	b.add_modifier(Modifier.make(S, Modifier.Op.MUL, 2.0))
	assert_float(b.get_value(S)).is_equal_approx(30.0, 1e-5)
	assert_float(b.get_value(1)).is_equal(1.0)  # other stats untouched


func test_latest_override_wins_and_falls_back_when_removed() -> void:
	var b := _block(6.0)
	b.add_modifier(Modifier.make(S, Modifier.Op.PCT, -0.25))
	var first := b.add_modifier(Modifier.make(S, Modifier.Op.OVERRIDE, 2.0))
	var second := b.add_modifier(Modifier.make(S, Modifier.Op.OVERRIDE, 0.0))
	assert_float(b.get_value(S)).is_equal(0.0)
	b.remove_modifier(second)
	assert_float(b.get_value(S)).is_equal(2.0)
	b.remove_modifier(first)
	assert_float(b.get_value(S)).is_equal_approx(4.5, 1e-5)


func test_remove_by_source_drops_every_modifier_of_that_source() -> void:
	var b := _block(100.0)
	var crystal := Modifier.source(Modifier.SRC_MOD, 3)
	var status := Modifier.source(Modifier.SRC_STATUS, 3)
	b.add_modifier(Modifier.make(S, Modifier.Op.ADD, 20.0, crystal))
	b.add_modifier(Modifier.make(S, Modifier.Op.PCT, 0.1, crystal))
	b.add_modifier(Modifier.make(S, Modifier.Op.PCT, -0.5, status))
	assert_float(b.get_value(S)).is_equal_approx(120.0 * 0.6, 1e-4)
	b.remove_by_source(crystal)
	assert_float(b.get_value(S)).is_equal_approx(50.0, 1e-4)
	assert_bool(b.has_source(crystal)).is_false()
	assert_bool(b.has_source(status)).is_true()


func test_timed_modifiers_expire_on_their_tick() -> void:
	var b := _block(6.0)
	b.add_modifier(Modifier.make(S, Modifier.Op.PCT, -0.3, 1, 90))
	b.add_modifier(Modifier.make(S, Modifier.Op.ADD, 1.0, 2))  # permanent
	b.expire(89)
	assert_float(b.get_value(S)).is_equal_approx(7.0 * 0.7, 1e-5)
	b.expire(90)
	assert_float(b.get_value(S)).is_equal_approx(7.0, 1e-5)
	assert_int(b.modifier_count()).is_equal(1)


func test_limits_clamp_the_result() -> void:
	var b := StatCatalog.new_hero_block(6.0)
	b.add_modifier(Modifier.make(StatCatalog.MOVE_SPEED, Modifier.Op.ADD, -20.0))
	assert_float(b.get_value(StatCatalog.MOVE_SPEED)).is_equal(0.0)
	b.add_modifier(Modifier.make(StatCatalog.COOLDOWN_REDUCTION, Modifier.Op.ADD, 3.0))
	assert_float(b.get_value(StatCatalog.COOLDOWN_REDUCTION)).is_equal(1.0)
	# Catalog defaults: multipliers start at 1.
	assert_float(b.get_value(StatCatalog.DAMAGE_TAKEN)).is_equal(1.0)
	assert_float(b.get_value(StatCatalog.SKILL_POWER)).is_equal(1.0)


func test_skill_block_is_seeded_from_params_by_name() -> void:
	var b := StatCatalog.new_skill_block({&"cooldown": 10.0, &"damage": 40.0, &"unknown": 3.0})
	assert_float(b.get_value(StatCatalog.skill_index(&"cooldown"))).is_equal(10.0)
	assert_float(b.get_value(StatCatalog.skill_index(&"damage"))).is_equal(40.0)
	assert_float(b.get_value(StatCatalog.skill_index(&"radius"))).is_equal(0.0)
