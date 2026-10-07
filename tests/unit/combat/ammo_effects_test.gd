extends GdUnitTestSuite
## Ammo Types and Ammo Mods (weapons-and-mods.md §3.7.1, §3.7.2, §4.5, §5) on
## AmmoEffects / AmmoTargetState, with the GDD numbers (AmmoRulesDef defaults).

const HZ: int = 60
const SHOOTER: int = 11
const OTHER: int = 12

var fx: AmmoEffects


func before_test() -> void:
	fx = AmmoEffects.new(AmmoRulesDef.new(), HZ)


func _hit(ammo: int, damage: float, tick: int = 0, mod: int = DamageMath.MOD_NONE,
		cls: int = DamageMath.TARGET_HERO, shooter: int = SHOOTER, mana: bool = false) -> AmmoEffects.Hit:
	var h := AmmoEffects.Hit.new()
	h.shooter_id = shooter
	h.team = 0
	h.ammo = ammo
	h.mod = mod
	h.target_class = cls
	h.damage = damage
	h.tick = tick
	h.mana_gun = mana
	return h


func _sum_burn(st: AmmoTargetState, ticks: int, from_tick: int = 0) -> float:
	var total := 0.0
	for t in ticks:
		for d in fx.step_target(st, from_tick + t):
			total += float(d[2])
	return total


func test_incendiary_pool_deals_itself_out_over_3_s() -> void:
	var st := AmmoTargetState.new()
	fx.apply_hit(st, _hit(DamageMath.AMMO_INCENDIARY, 100.0))
	assert_float(st.burn_left(SHOOTER)).is_equal_approx(12.0, 1e-4)
	assert_bool(st.is_burning()).is_true()
	assert_float(_sum_burn(st, 3 * HZ)).is_equal_approx(12.0, 1e-3)
	assert_bool(st.is_burning()).is_false()


func test_incendiary_burn_dps_capped_at_35() -> void:
	var st := AmmoTargetState.new()
	fx.apply_hit(st, _hit(DamageMath.AMMO_INCENDIARY, 5000.0))  # pool 600
	assert_float(_sum_burn(st, 3 * HZ)).is_equal_approx(105.0, 1e-2)  # 35 DPS × 3 s


func test_separate_burn_pools_per_shooter() -> void:
	var st := AmmoTargetState.new()
	fx.apply_hit(st, _hit(DamageMath.AMMO_INCENDIARY, 100.0))
	fx.apply_hit(st, _hit(DamageMath.AMMO_INCENDIARY, 50.0, 0, DamageMath.MOD_NONE, DamageMath.TARGET_HERO, OTHER))
	assert_float(st.burn_left(SHOOTER)).is_equal_approx(12.0, 1e-4)
	assert_float(st.burn_left(OTHER)).is_equal_approx(6.0, 1e-4)


func test_shock_overloads_on_ryker_hit_10_with_icd() -> void:
	# §4.5: 18 per hit -> 10.8 Charge -> Overload on hit 10.
	var st := AmmoTargetState.new()
	var overloads: Array[int] = []
	for i in 10:
		var out := fx.apply_hit(st, _hit(DamageMath.AMMO_SHOCK, 18.0, i * 6))
		if out.overload:
			overloads.append(i + 1)
			assert_float(out.arc_damage).is_equal(30.0)
			assert_int(out.arc_targets).is_equal(2)
			assert_float(out.arc_radius).is_equal(6.0)
			assert_float(out.disrupt_s).is_equal_approx(1.0, 1e-6)
			assert_float(out.reload_penalty_s).is_equal_approx(0.5, 1e-6)
	assert_array(overloads).is_equal([10])
	# Same shooter cannot Overload again within 3 s (AC 12).
	var again := false
	for i in 20:
		again = again or fx.apply_hit(st, _hit(DamageMath.AMMO_SHOCK, 18.0, 60 + i)).overload
	assert_bool(again).is_false()
	assert_bool(fx.apply_hit(st, _hit(DamageMath.AMMO_SHOCK, 18.0, 54 + 3 * HZ)).overload).is_true()


func test_shock_ironmaw_overloads_on_second_shot_and_decays() -> void:
	var st := AmmoTargetState.new()
	assert_bool(fx.apply_hit(st, _hit(DamageMath.AMMO_SHOCK, 150.0)).overload).is_false()
	assert_float(st.charge_of(SHOOTER)).is_equal_approx(90.0, 1e-4)
	# Decays 25/s after 1 s without hits.
	for t in range(1, 2 * HZ + 1):
		fx.step_target(st, t)
	assert_float(st.charge_of(SHOOTER)).is_less(90.0)
	assert_float(st.charge_of(SHOOTER)).is_greater(60.0)


func test_siphon_heroes_wardlings_structures() -> void:
	var st := AmmoTargetState.new()
	var o := fx.apply_hit(st, _hit(DamageMath.AMMO_SIPHON, 100.0, 0, DamageMath.MOD_NONE, DamageMath.TARGET_HERO, SHOOTER, true))
	assert_float(o.heal).is_equal_approx(8.0, 1e-4)
	assert_float(o.mana).is_equal_approx(6.0, 1e-4)
	o = fx.apply_hit(st, _hit(DamageMath.AMMO_SIPHON, 100.0, 0, DamageMath.MOD_NONE, DamageMath.TARGET_CONSTRUCT))
	assert_float(o.heal).is_equal_approx(4.0, 1e-4)
	assert_float(o.mana).is_equal(0.0)  # Mechanical gun
	o = fx.apply_hit(st, _hit(DamageMath.AMMO_SIPHON, 100.0, 0, DamageMath.MOD_NONE, DamageMath.TARGET_STRUCTURE))
	assert_float(o.heal).is_equal(0.0)


func test_cryo_chill_slow_brittle_reset_and_lock() -> void:
	var st := AmmoTargetState.new()
	fx.apply_hit(st, _hit(DamageMath.AMMO_CRYO, 18.0))
	assert_float(st.chill).is_equal_approx(9.0, 1e-4)
	assert_float(fx.chill_slow(st)).is_equal_approx(0.25 * 0.09, 1e-5)
	fx.apply_hit(st, _hit(DamageMath.AMMO_CRYO, 400.0, 1))
	assert_float(st.chill).is_equal(100.0)
	assert_float(fx.chill_slow(st)).is_equal_approx(0.25, 1e-6)  # Cryo alone never above 25% (AC 13)
	assert_float(fx.brittle(st, 2)).is_equal_approx(1.08, 1e-6)
	# Brittle 2 s, then the meter resets.
	for t in range(2, 2 * HZ + 3):
		fx.step_target(st, t)
	assert_float(fx.brittle(st, 2 * HZ + 2)).is_equal(1.0)
	assert_float(st.chill).is_equal(0.0)
	# Locked for 4 s: filling the meter again does not re-trigger.
	fx.apply_hit(st, _hit(DamageMath.AMMO_CRYO, 400.0, 3 * HZ))
	assert_bool(st.is_brittle(3 * HZ + 1)).is_false()
	fx.apply_hit(st, _hit(DamageMath.AMMO_CRYO, 400.0, 7 * HZ))
	assert_bool(st.is_brittle(7 * HZ + 1)).is_true()


func test_chill_decays_after_delay() -> void:
	var st := AmmoTargetState.new()
	fx.apply_hit(st, _hit(DamageMath.AMMO_CRYO, 100.0))  # 50
	for t in range(1, 45):  # 0.75 s delay: nothing yet
		fx.step_target(st, t)
	assert_float(st.chill).is_equal_approx(50.0, 1e-4)
	for t in range(45, 45 + HZ):
		fx.step_target(st, t)
	assert_float(st.chill).is_less(25.0)


func test_structures_and_uplink_take_no_effects() -> void:
	for cls in [DamageMath.TARGET_STRUCTURE, DamageMath.TARGET_UPLINK]:
		var st := AmmoTargetState.new()
		for ammo in [3, 4, 5, 6]:
			var o := fx.apply_hit(st, _hit(ammo, 500.0, 0, DamageMath.MOD_TRACER, cls))
			assert_float(o.heal + o.mark_s).is_equal(0.0)
		assert_bool(st.is_burning()).is_false()
		assert_float(st.chill).is_equal(0.0)
		assert_float(fx.burn_share(DamageMath.AMMO_INCENDIARY, 0, cls)).is_equal(0.0)
	# Uplink: no Sunder bonus either.
	assert_float(DamageMath.ammo_mult(DamageMath.AMMO_SUNDER, DamageMath.TARGET_UPLINK, false, 1.5)).is_equal(1.0)


func test_wardlings_take_every_effect() -> void:
	var st := fx.state_for(RefCounted.new())
	fx.apply_hit(st, _hit(DamageMath.AMMO_INCENDIARY, 100.0, 0, 0, DamageMath.TARGET_CONSTRUCT))
	fx.apply_hit(st, _hit(DamageMath.AMMO_CRYO, 100.0, 0, 0, DamageMath.TARGET_CONSTRUCT))
	assert_bool(st.is_burning()).is_true()
	assert_float(st.chill).is_equal(50.0)


func test_potency_table() -> void:
	var sat := DamageMath.MOD_SATURATED
	var over := DamageMath.MOD_OVERCHARGED
	assert_float(fx.potency(DamageMath.AMMO_PIERCING, sat) * 0.40).is_equal_approx(0.52, 1e-6)
	assert_float(DamageMath.ammo_armor_pen(DamageMath.AMMO_PIERCING, fx.potency(1, over))).is_equal_approx(0.60, 1e-6)
	assert_float(fx.burn_share(DamageMath.AMMO_INCENDIARY, sat, 0)).is_equal_approx(0.156, 1e-6)
	assert_float(fx.burn_share(DamageMath.AMMO_INCENDIARY, over, 0)).is_equal_approx(0.18, 1e-6)
	var st := AmmoTargetState.new()
	fx.apply_hit(st, _hit(DamageMath.AMMO_SHOCK, 10.0, 0, sat))
	assert_float(st.charge_of(SHOOTER)).is_equal_approx(7.8, 1e-4)
	var o := fx.apply_hit(st, _hit(DamageMath.AMMO_SIPHON, 100.0, 0, sat, 0, SHOOTER, true))
	assert_float(o.heal).is_equal_approx(10.4, 1e-4)
	assert_float(o.mana).is_equal_approx(7.8, 1e-4)
	o = fx.apply_hit(st, _hit(DamageMath.AMMO_SIPHON, 100.0, 0, over, 0, SHOOTER, true))
	assert_float(o.heal).is_equal_approx(12.0, 1e-4)
	assert_float(o.mana).is_equal_approx(9.0, 1e-4)
	var c := AmmoTargetState.new()
	fx.apply_hit(c, _hit(DamageMath.AMMO_CRYO, 10.0, 0, over))
	assert_float(c.chill).is_equal_approx(7.5, 1e-4)
	assert_float(DamageMath.ammo_mult(DamageMath.AMMO_SUNDER, DamageMath.TARGET_CONSTRUCT, false, 1.3)).is_equal_approx(1.455, 1e-6)
	assert_float(DamageMath.ammo_mult(DamageMath.AMMO_SUNDER, DamageMath.TARGET_CONSTRUCT, false, 1.5)).is_equal_approx(1.525, 1e-6)
	assert_float(DamageMath.ammo_mult(DamageMath.AMMO_SUNDER, DamageMath.TARGET_HERO, false, 1.5)).is_equal_approx(0.90, 1e-6)


func test_mods_do_nothing_on_standard_or_incompatible_types() -> void:
	assert_float(fx.potency(DamageMath.AMMO_STANDARD, DamageMath.MOD_OVERCHARGED)).is_equal(1.0)
	assert_array(fx.feed_costs(DamageMath.AMMO_STANDARD, DamageMath.MOD_OVERCHARGED)).is_equal([1.0, 1.0])
	assert_bool(fx.mod_fits(DamageMath.MOD_LINGERING, DamageMath.AMMO_PIERCING)).is_false()
	assert_bool(fx.mod_fits(DamageMath.MOD_LINGERING, DamageMath.AMMO_SIPHON)).is_false()
	assert_bool(fx.mod_fits(DamageMath.MOD_VOLATILE, DamageMath.AMMO_PIERCING)).is_false()
	assert_float(fx.duration(DamageMath.AMMO_SIPHON, DamageMath.MOD_LINGERING)).is_equal(1.0)
	var o := fx.volatile_burst(AmmoTargetState.new(), SHOOTER, DamageMath.AMMO_PIERCING, DamageMath.MOD_VOLATILE)
	assert_float(o.burst_radius).is_equal(0.0)


func test_overcharged_feed_costs() -> void:
	var c := fx.feed_costs(DamageMath.AMMO_CRYO, DamageMath.MOD_OVERCHARGED)
	assert_float(c[0]).is_equal_approx(1.2, 1e-6)
	assert_float(c[1]).is_equal_approx(1.15, 1e-6)


func test_lingering_durations() -> void:
	var st := AmmoTargetState.new()
	fx.apply_hit(st, _hit(DamageMath.AMMO_INCENDIARY, 100.0, 0, DamageMath.MOD_LINGERING))
	assert_float(_sum_burn(st, 3 * HZ)).is_less(12.0)  # still burning past 3 s
	assert_float(_sum_burn(st, 2 * HZ, 3 * HZ)).is_greater(0.0)
	var sh := AmmoTargetState.new()
	var o := fx.apply_hit(sh, _hit(DamageMath.AMMO_SHOCK, 200.0, 0, DamageMath.MOD_LINGERING))
	assert_float(o.disrupt_s).is_equal_approx(1.5, 1e-6)
	var cr := AmmoTargetState.new()
	fx.apply_hit(cr, _hit(DamageMath.AMMO_CRYO, 400.0, 0, DamageMath.MOD_LINGERING))
	assert_bool(cr.is_brittle(3 * HZ - 1)).is_true()  # Brittle 3 s
	assert_bool(cr.is_brittle(3 * HZ)).is_false()
	assert_int(cr.chill_delay_ticks).is_equal(roundi(0.75 * 1.5 * HZ))


func test_tracer_marks_effect_hits_and_sunder_only_heroes() -> void:
	var st := AmmoTargetState.new()
	assert_float(fx.apply_hit(st, _hit(DamageMath.AMMO_CRYO, 10.0, 0, DamageMath.MOD_TRACER)).mark_s).is_equal_approx(1.5, 1e-6)
	assert_float(fx.apply_hit(st, _hit(DamageMath.AMMO_SUNDER, 10.0, 0, DamageMath.MOD_TRACER)).mark_s).is_equal_approx(1.5, 1e-6)
	assert_float(fx.apply_hit(st, _hit(DamageMath.AMMO_SUNDER, 10.0, 0, DamageMath.MOD_TRACER,
		DamageMath.TARGET_CONSTRUCT)).mark_s).is_equal(0.0)
	assert_float(fx.apply_hit(st, _hit(DamageMath.AMMO_CRYO, 10.0)).mark_s).is_equal(0.0)


func test_volatile_bursts_per_type() -> void:
	var victim := AmmoTargetState.new()
	fx.apply_hit(victim, _hit(DamageMath.AMMO_INCENDIARY, 100.0))  # pool 12
	var v := DamageMath.MOD_VOLATILE
	var o := fx.volatile_burst(victim, SHOOTER, DamageMath.AMMO_INCENDIARY, v)
	assert_float(o.burst_radius).is_equal(4.0)
	assert_float(o.burst_burn).is_equal_approx(4.8, 1e-4)
	o = fx.volatile_burst(victim, SHOOTER, DamageMath.AMMO_SHOCK, v)
	assert_bool(o.overload).is_true()
	assert_float(o.arc_damage).is_equal(30.0)
	assert_int(o.arc_targets).is_equal(2)
	o = fx.volatile_burst(victim, SHOOTER, DamageMath.AMMO_SIPHON, v)
	assert_float(o.burst_heal).is_equal(40.0)
	assert_float(o.burst_heal_radius).is_equal(8.0)
	assert_float(fx.volatile_burst(victim, SHOOTER, DamageMath.AMMO_CRYO, v).burst_chill).is_equal(50.0)
	assert_float(fx.volatile_burst(victim, SHOOTER, DamageMath.AMMO_SUNDER, v).burst_construct_damage).is_equal(30.0)
