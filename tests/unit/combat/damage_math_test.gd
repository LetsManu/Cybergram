extends GdUnitTestSuite
## Damage formula (weapons-and-mods.md §4.1–§4.3) and HealthComponent armor /
## team filter (heroes.md §3.1, weapons-and-mods.md §3.1 rule 5).


func test_falloff_is_flat_then_linear_then_floor() -> void:
	var t := CombatFixtures.vesper().weapon  # Threadcaster 25–45 m -> 0.60
	assert_float(DamageMath.falloff(t, 0.0)).is_equal(1.0)
	assert_float(DamageMath.falloff(t, 25.0)).is_equal(1.0)
	assert_float(DamageMath.falloff(t, 35.0)).is_equal_approx(0.8, 1e-6)
	assert_float(DamageMath.falloff(t, 45.0)).is_equal_approx(0.6, 1e-6)
	assert_float(DamageMath.falloff(t, 120.0)).is_equal_approx(0.6, 1e-6)


func test_falloff_matches_gdd_halo_example() -> void:
	# §4.3: Halo Repeater (20–35 m -> 0.60) at 30 m = 0.733.
	var w := WeaponDef.new()
	w.falloff_start_m = 20.0
	w.falloff_end_m = 35.0
	w.falloff_min = 0.6
	assert_float(DamageMath.falloff(w, 30.0)).is_equal_approx(0.7333, 1e-4)


func test_level_multiplier() -> void:
	assert_float(DamageMath.level_mult(1)).is_equal(1.0)
	assert_float(DamageMath.level_mult(10)).is_equal_approx(1.225, 1e-6)
	assert_float(DamageMath.level_mult(15)).is_equal_approx(1.35, 1e-6)


func test_headshot_multiplier_and_falloff_combine() -> void:
	var t := CombatFixtures.vesper().weapon
	assert_float(DamageMath.hit_damage(t, 10.0, false)).is_equal_approx(29.0, 1e-6)
	assert_float(DamageMath.hit_damage(t, 10.0, true)).is_equal_approx(29.0 * 1.75, 1e-6)
	assert_float(DamageMath.hit_damage(t, 35.0, true)).is_equal_approx(29.0 * 0.8 * 1.75, 1e-4)
	var maw := CombatFixtures.brannoc().weapon  # Ironmaw 8–15 m -> 0.55, HS 1.25
	assert_float(DamageMath.hit_damage(maw, 20.0, true)).is_equal_approx(15.0 * 0.55 * 1.25, 1e-4)


func test_gdd_worked_example_ryker_vs_brannoc() -> void:
	# §4.1: Ryker L10, Overclock III (+0.16), Piercing (A_eff 0.12), 30 m, body = 18.5.
	var ar := WeaponDef.new()
	ar.damage = 18.0
	ar.falloff_start_m = 22.0
	ar.falloff_end_m = 40.0
	ar.falloff_min = 0.6
	var d := DamageMath.hit_damage(ar, 30.0, false, 10) * 1.16 * DamageMath.armor_mult(0.12)
	assert_float(d).is_equal_approx(18.5, 0.05)


func test_armor_reduction_and_clamp() -> void:
	assert_float(DamageMath.armor_mult(0.2)).is_equal_approx(0.8, 1e-6)
	assert_float(DamageMath.armor_mult(0.2, 0.5)).is_equal_approx(0.3, 1e-6)  # Fortify: 0.70 clamp
	assert_float(DamageMath.armor_mult(0.2, 0.9)).is_equal_approx(0.3, 1e-6)


func test_health_applies_armor_for_brannoc() -> void:
	var b := CombatFixtures.brannoc()
	var h := HealthComponent.new(b.max_hp, b.armor, 1)
	var applied := h.apply_damage(DamageInfo.make(29.0, 7, 0))
	assert_float(applied).is_equal_approx(23.2, 1e-4)
	assert_float(h.hp).is_equal_approx(550.0 - 23.2, 1e-4)
	# Brannoc EHP 687.5 (heroes.md §3.1).
	assert_float(b.max_hp / DamageMath.armor_mult(b.armor)).is_equal_approx(687.5, 1e-3)


func test_true_damage_ignores_armor() -> void:
	var h := HealthComponent.new(550, 0.2, 1)
	assert_float(h.apply_damage(DamageInfo.make(50.0, 7, 0, 0, DamageInfo.Type.TRUE))).is_equal(50.0)


func test_team_filter_blocks_friendly_fire() -> void:
	var h := HealthComponent.new(250, 0.0, 1)
	assert_float(h.apply_damage(DamageInfo.make(100.0, 7, 1))).is_equal(0.0)
	assert_float(h.hp).is_equal(250.0)


func test_death_emits_once_and_clamps_overkill() -> void:
	var h := HealthComponent.new(250, 0.0, 1)
	var deaths := [0]
	h.died.connect(func(_k: int) -> void: deaths[0] += 1)
	assert_float(h.apply_damage(DamageInfo.make(200.0, 7, 0))).is_equal(200.0)
	assert_float(h.apply_damage(DamageInfo.make(200.0, 7, 0))).is_equal(50.0)
	assert_float(h.apply_damage(DamageInfo.make(200.0, 7, 0))).is_equal(0.0)
	assert_bool(h.is_alive()).is_false()
	assert_int(deaths[0]).is_equal(1)
	h.reset()
	assert_float(h.hp).is_equal(250.0)


func test_threadcaster_shots_to_kill_250hp() -> void:
	# §4.4 discrete form: N = ceil(HP / D) = ceil(250 / 29) = 9 body shots.
	var t := CombatFixtures.vesper().weapon
	assert_int(ceili(250.0 / DamageMath.hit_damage(t, 10.0, false))).is_equal(9)


func test_ray_vs_hitbox_shapes() -> void:
	# Sphere 10 m ahead, radius 0.2 -> hit at 9.8.
	assert_float(HitscanTracer.ray_sphere(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -10), 0.2)).is_equal_approx(9.8, 1e-5)
	assert_float(HitscanTracer.ray_sphere(Vector3.ZERO, Vector3.FORWARD, Vector3(1, 0, -10), 0.2)).is_equal(-1.0)
	assert_float(HitscanTracer.ray_sphere(Vector3.ZERO, Vector3.BACK, Vector3(0, 0, -10), 0.2)).is_equal(-1.0)
	# Vertical capsule radius 0.4, axis y 0.4..1.0 at (0, -10): side hit at 9.6.
	var t := HitscanTracer.ray_vertical_capsule(Vector3(0, 0.8, 0), Vector3.FORWARD, 0.4, 1.0, Vector2(0, -10), 0.4)
	assert_float(t).is_equal_approx(9.6, 1e-5)
	# Straight down onto the top cap: hits at y = 1.4.
	var down := HitscanTracer.ray_vertical_capsule(Vector3(0, 5, -10), Vector3.DOWN, 0.4, 1.0, Vector2(0, -10), 0.4)
	assert_float(down).is_equal_approx(3.6, 1e-5)
	# Passing above the head misses.
	assert_float(HitscanTracer.ray_vertical_capsule(Vector3(0, 2.0, 0), Vector3.FORWARD, 0.4, 1.0, Vector2(0, -10), 0.4)).is_equal(-1.0)
