extends GdUnitTestSuite
## The 14 Signature passives (design/gdd/items-and-armory.md §3.5.3, §5, §7)
## on a bare HeroCombat: each passive with its GDD numbers, the edge cases of
## §5, and "turned off / dead = state cleared". ServerWorld wiring is covered by
## tests/integration/combat/signature_passives_server_test.gd.

const HZ: int = 30


## Vesper's body (250 HP, armor 0, her kit) with `weapon` (null = Threadcaster).
func _hero(weapon: WeaponDef = null) -> HeroCombat:
	var d := CombatFixtures.vesper().duplicate() as HeroDef
	d.passive_modifiers = []
	if weapon != null:
		d.weapon = weapon
	return HeroCombat.new(d, 0, HZ, 7)


func _on(c: HeroCombat, ids: Array, tick: int = 0) -> SignaturePassives:
	c.passives.set_active(ids, tick)
	return c.passives


func _step(p: SignaturePassives, from: int, n: int, pos: Vector3 = Vector3.ZERO, crouching: bool = false) -> int:
	for t in range(from, from + n):
		p.step(t, pos, crouching)
	return from + n


func _weapon_hit(amount: float) -> DamageInfo:
	return DamageInfo.make(amount, 2, 1)


func _rules() -> SignatureRulesDef:
	return SignatureRulesDef.shared()


# --- data -----------------------------------------------------------------------

func test_rules_file_holds_the_gdd_numbers() -> void:
	var r := _rules()
	assert_float(r.kindle_refill_frac).is_equal_approx(0.30, 1e-6)
	assert_float(r.rend_per_hit).is_equal_approx(0.02, 1e-6)
	assert_float(r.rend_max).is_equal_approx(0.08, 1e-6)
	assert_float(r.brace_dr).is_equal_approx(0.15, 1e-6)
	assert_float(r.brace_cooldown_s).is_equal_approx(20.0, 1e-6)
	assert_float(r.lattice_shield).is_equal_approx(80.0, 1e-6)
	assert_float(r.regrowth_frac_s).is_equal_approx(0.02, 1e-6)
	assert_float(r.grounding_mult).is_equal_approx(0.75, 1e-6)
	assert_float(r.resonant_cut).is_equal_approx(0.25, 1e-6)
	assert_float(r.siege_bonus).is_equal_approx(0.15, 1e-6)
	assert_float(r.long_reach_slow).is_equal_approx(0.10, 1e-6)


func test_v22_catalog_names_the_14_passives() -> void:
	var cat := load(ArmoryCatalogDef.V22_PATH) as ArmoryCatalogDef
	var ids := {}
	for it in cat.items:
		if it != null and it.passive != &"":
			ids[it.passive] = true
	for id in [SignaturePassives.KINDLE, SignaturePassives.OVERDRIVE_LOOP, SignaturePassives.TRUE_LINE,
			SignaturePassives.LONG_REACH, SignaturePassives.REND, SignaturePassives.DEEP_RESERVE,
			SignaturePassives.COLD_START, SignaturePassives.PLANTED, SignaturePassives.BRACE,
			SignaturePassives.GROUNDING, SignaturePassives.REGROWTH, SignaturePassives.LATTICE,
			SignaturePassives.RESONANT_CAST, SignaturePassives.SIEGEBREAKER]:
		assert_bool(ids.has(id)).override_failure_message("missing %s" % id).is_true()
	assert_int(ids.size()).is_equal(14)


func test_no_passive_changes_nothing() -> void:
	var c := _hero(CombatFixtures.rifle_mag())
	var p := c.passives
	_step(p, 0, 200)
	assert_float(c.health.overshield).is_equal(0.0)
	assert_float(c.health.brace_dr).is_equal(0.0)
	assert_float(c.status.cc_duration_mult).is_equal(1.0)
	assert_float(c.status.knockback_mult).is_equal(1.0)
	assert_bool((c.weapon.feed as MagazineFeed).instant_reload).is_false()
	assert_float(p.on_kill_or_assist()).is_equal(0.0)
	assert_float(p.on_head_hit()).is_equal(0.0)
	assert_float(p.siege_mult()).is_equal(1.0)
	assert_float(p.refill_mult()).is_equal(1.0)


# --- Kindle -----------------------------------------------------------------------

func test_kindle_mech_refills_30_percent_of_the_magazine_from_nothing() -> void:
	var c := _hero(CombatFixtures.rifle_mag())
	var f := c.weapon.feed as MagazineFeed
	f.rounds = 5
	assert_float(_on(c, [SignaturePassives.KINDLE]).on_kill_or_assist()).is_equal(9.0)
	assert_int(f.rounds).is_equal(14)
	assert_int(f.reserve).is_equal(150)  # no reserve used
	f.rounds = 28
	c.passives.on_kill_or_assist()
	assert_int(f.rounds).is_equal(30)  # never above the magazine


func test_kindle_mana_refills_30_percent_of_the_pool() -> void:
	var c := _hero()
	var f := c.weapon.feed as ManaPoolFeed
	f.mana = 10.0
	_on(c, [SignaturePassives.KINDLE]).on_kill_or_assist()
	assert_float(f.mana).is_equal_approx(40.0, 1e-4)


# --- Overdrive Loop ---------------------------------------------------------------

func test_overdrive_loop_cuts_bloom_after_continuous_fire() -> void:
	var c := _hero(CombatFixtures.rifle_mag())
	var p := _on(c, [SignaturePassives.OVERDRIVE_LOOP])
	var t := 0
	for i in 4:  # shots 0.5 s apart: 0, 0.5, 1.0, 1.5 s
		p.on_fired(t)
		p.step(t)
		if i < 3:
			assert_float(c.weapon.passive_bloom_mult).is_equal(1.0)
		t += 15
	assert_float(c.weapon.passive_bloom_mult).is_equal_approx(0.60, 1e-6)
	assert_float(c.weapon.passive_cone_mult).is_equal(1.0)
	_step(p, t, 30)  # a pause over 0.9 s breaks the loop
	assert_float(c.weapon.passive_bloom_mult).is_equal(1.0)


func test_overdrive_loop_on_pellet_weapon_shrinks_the_cone() -> void:
	var gun := CombatFixtures.rifle_mag()
	gun.pellets = 8
	var c := _hero(gun)
	var p := _on(c, [SignaturePassives.OVERDRIVE_LOOP])
	for t in range(0, 61, 15):
		p.on_fired(t)
		p.step(t)
	assert_float(c.weapon.passive_cone_mult).is_equal_approx(0.90, 1e-6)
	assert_float(c.weapon.passive_bloom_mult).is_equal(1.0)


func test_overdrive_bloom_mult_scales_weapon_bloom() -> void:
	var gun := CombatFixtures.auto_gun(10.0)
	gun.spread_base_deg = 0.0
	gun.spread_bloom_deg = 1.0
	gun.spread_max_deg = 10.0
	var w := WeaponSim.new(gun, HZ, 1)
	w.passive_bloom_mult = 0.6
	var cmd := InputCommand.new()
	cmd.buttons = InputCommand.BTN_FIRE
	w.step(cmd, 0, true)
	assert_float(w.spread_deg).is_equal_approx(0.6, 1e-5)


# --- True Line ----------------------------------------------------------------------

func test_true_line_refunds_one_round_up_to_the_magazine() -> void:
	var c := _hero(CombatFixtures.rifle_mag())
	var f := c.weapon.feed as MagazineFeed
	f.rounds = 20
	var p := _on(c, [SignaturePassives.TRUE_LINE])
	assert_float(p.on_head_hit()).is_equal(1.0)
	assert_int(f.rounds).is_equal(21)
	f.rounds = 30
	assert_float(p.on_head_hit()).is_equal(0.0)  # §5: no refund at a full magazine
	assert_int(f.rounds).is_equal(30)


func test_true_line_refunds_the_shot_mana_cost() -> void:
	var c := _hero()
	var f := c.weapon.feed as ManaPoolFeed
	f.mana = 50.0
	f.cost_mult = 1.2  # Overcharged shot cost is what is refunded
	_on(c, [SignaturePassives.TRUE_LINE]).on_head_hit()
	assert_float(f.mana).is_equal_approx(50.0 + 6.0 * 1.2, 1e-4)


# --- Rend -------------------------------------------------------------------------

func test_rend_stacks_two_points_up_to_eight_and_expires() -> void:
	var c := _hero()
	var p := c.passives
	for i in 5:
		p.add_rend(10)
	assert_float(c.health.rend).is_equal_approx(0.08, 1e-6)
	_step(p, 10, 4 * HZ - 1)
	assert_float(c.health.rend).is_equal_approx(0.08, 1e-6)
	p.step(10 + 4 * HZ)
	assert_float(c.health.rend).is_equal(0.0)


func test_rend_lowers_gear_armor_only() -> void:
	var c := _hero()
	c.stats.add_modifier(Modifier.make(StatCatalog.GEAR_ARMOR, Modifier.Op.ADD, 0.13, 99))
	for i in 4:
		c.passives.add_rend(0)
	# §4.3: A_w = 0 + max(0, 0.13 - 0.08) = 0.05.
	assert_float(c.health.armor_value(_weapon_hit(100.0))).is_equal_approx(0.05, 1e-6)
	assert_float(c.health.apply_damage(_weapon_hit(100.0))).is_equal_approx(95.0, 1e-3)


func test_rend_never_touches_base_armor() -> void:
	var c := _hero()
	c.health.armor = 0.10
	for i in 4:
		c.passives.add_rend(0)
	assert_float(c.health.armor_value(_weapon_hit(100.0))).is_equal_approx(0.10, 1e-6)


# --- Deep Reserve -------------------------------------------------------------------

func test_deep_reserve_empty_pool_never_burns_out() -> void:
	var c := _hero()
	var f := c.weapon.feed as ManaPoolFeed
	var p := _on(c, [SignaturePassives.DEEP_RESERVE])
	p.step(0)
	f.mana = 3.0
	f.consume(0)
	assert_float(f.mana).is_equal(0.0)
	assert_bool(f.burnout).is_false()
	assert_int(f.regen_resume_tick).is_equal(f.ticks(1.0))  # the regen delay still applies, not x1.5


func test_deep_reserve_raises_mech_supply_refills_by_half() -> void:
	var c := _hero(CombatFixtures.rifle_mag())
	assert_float(_on(c, [SignaturePassives.DEEP_RESERVE]).refill_mult()).is_equal_approx(1.5, 1e-6)


# --- Cold Start ---------------------------------------------------------------------

func test_cold_start_doubles_mana_regen_after_three_idle_seconds() -> void:
	var c := _hero()
	var f := c.weapon.feed as ManaPoolFeed
	var p := _on(c, [SignaturePassives.COLD_START])
	p.on_fired(0)
	_step(p, 0, 3 * HZ - 1)
	assert_float(f.regen_scale).is_equal(1.0)
	p.step(3 * HZ)
	assert_float(f.regen_scale).is_equal_approx(2.0, 1e-6)
	p.on_fired(3 * HZ + 1)  # "until you fire"
	assert_float(f.regen_scale).is_equal(1.0)


func test_cold_start_mech_next_reload_is_instant_once() -> void:
	var c := _hero(CombatFixtures.rifle_mag())
	var f := c.weapon.feed as MagazineFeed
	var p := _on(c, [SignaturePassives.COLD_START])
	p.on_fired(0)
	var t := _step(p, 0, 3 * HZ + 1)
	assert_bool(f.instant_reload).is_true()
	f.rounds = 4
	f.request_reload(t)
	assert_int(f.rounds).is_equal(30)
	assert_int(f.reserve).is_equal(124)
	assert_bool(f.is_reloading()).is_false()
	t = _step(p, t, 10)  # same idle spell: not armed again
	assert_bool(f.instant_reload).is_false()
	f.rounds = 4
	f.request_reload(t)
	assert_bool(f.is_reloading()).is_true()


func test_cold_start_per_shell_reload_fills_at_once() -> void:
	var gun := CombatFixtures.rifle_mag()
	gun.reload_per_round = true
	gun.magazine = 6
	var c := _hero(gun)
	var f := c.weapon.feed as MagazineFeed
	var p := _on(c, [SignaturePassives.COLD_START])
	_step(p, 0, 2)
	f.rounds = 1
	f.request_reload(2)
	assert_int(f.rounds).is_equal(6)


# --- Planted ------------------------------------------------------------------------

func test_planted_after_half_a_second_still() -> void:
	var c := _hero(CombatFixtures.rifle_mag())
	var p := _on(c, [SignaturePassives.PLANTED])
	var t := _step(p, 0, 10)  # 1/3 s still
	assert_float(c.status.knockback_mult).is_equal(1.0)
	t = _step(p, t, 8)
	assert_float(c.status.knockback_mult).is_equal_approx(0.5, 1e-6)
	assert_float(p.recoil_mult()).is_equal_approx(0.75, 1e-6)
	p.step(t, Vector3(1.0, 0.0, 0.0))  # moved
	assert_float(c.status.knockback_mult).is_equal(1.0)
	assert_float(p.recoil_mult()).is_equal(1.0)


func test_planted_while_crouched_even_moving() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.PLANTED])
	for t in 3:
		p.step(t, Vector3(t, 0.0, 0.0), true)
	assert_float(c.status.knockback_mult).is_equal_approx(0.5, 1e-6)


# --- Brace --------------------------------------------------------------------------

func test_brace_triggers_after_35_percent_weapon_hp_in_two_seconds() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.BRACE])
	p.on_damaged(DamageInfo.Type.WEAPON, 50.0, 50.0, 0)
	p.on_damaged(DamageInfo.Type.WEAPON, 37.0, 37.0, 30)
	assert_float(c.health.brace_dr).is_equal(0.0)  # 87 < 87.5
	p.on_damaged(DamageInfo.Type.WEAPON, 1.0, 1.0, 40)
	assert_float(c.health.brace_dr).is_equal_approx(0.15, 1e-6)
	# 15% DR vs weapon damage only.
	assert_float(c.health.apply_damage(_weapon_hit(100.0))).is_equal_approx(85.0, 1e-3)
	c.health.hp = 250.0
	assert_float(c.health.apply_damage(DamageInfo.make(100.0, 2, 1, 0, DamageInfo.Type.SKILL))).is_equal_approx(100.0, 1e-3)
	_step(p, 41, roundi(2.5 * HZ))
	assert_float(c.health.brace_dr).is_equal(0.0)


func test_brace_window_is_two_seconds_and_skill_damage_does_not_count() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.BRACE])
	p.on_damaged(DamageInfo.Type.WEAPON, 50.0, 50.0, 0)
	p.on_damaged(DamageInfo.Type.WEAPON, 50.0, 50.0, 2 * HZ)  # first loss left the window
	assert_float(c.health.brace_dr).is_equal(0.0)
	p.on_damaged(DamageInfo.Type.SKILL, 100.0, 100.0, 2 * HZ + 1)
	assert_float(c.health.brace_dr).is_equal(0.0)


func test_brace_cooldown_is_twenty_seconds() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.BRACE])
	p.on_damaged(DamageInfo.Type.WEAPON, 90.0, 90.0, 0)
	var t := _step(p, 1, 5 * HZ)
	p.on_damaged(DamageInfo.Type.WEAPON, 90.0, 90.0, t)
	p.step(t)
	assert_float(c.health.brace_dr).is_equal(0.0)
	t = 20 * HZ
	p.on_damaged(DamageInfo.Type.WEAPON, 90.0, 90.0, t)
	p.step(t)
	assert_float(c.health.brace_dr).is_equal_approx(0.15, 1e-6)


func test_brace_stays_inside_the_070_clamp() -> void:
	var c := _hero()
	c.health.damage_reduction = 0.65  # Fortify-like DR
	c.health.brace_dr = 0.15
	assert_float(c.health.apply_damage(_weapon_hit(100.0))).is_equal_approx(30.0, 1e-3)


# --- Grounding ----------------------------------------------------------------------

func test_grounding_shortens_root_stun_slow_by_a_quarter() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.GROUNDING])
	p.step(0)
	assert_int(c.status.apply(StatusComponent.Kind.ROOT, 40, 0.0, 5, 0)).is_equal(30)
	assert_int(c.status.apply(StatusComponent.Kind.STUN, 40, 0.0, 6, 100)).is_equal(30)
	assert_int(c.status.apply(StatusComponent.Kind.SLOW, 40, 0.2, 7, 0)).is_equal(30)


func test_grounding_leaves_knockback_unchanged() -> void:
	var c := _hero()
	_on(c, [SignaturePassives.GROUNDING]).step(0)
	assert_int(c.status.apply(StatusComponent.Kind.KNOCKBACK, 40, 0.0, 5, 0)).is_equal(40)


func test_grounding_off_restores_full_durations() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.GROUNDING])
	p.step(0)
	p.set_active([], 1)
	assert_int(c.status.apply(StatusComponent.Kind.ROOT, 40, 0.0, 5, 0)).is_equal(40)


# --- Regrowth -----------------------------------------------------------------------

func test_regrowth_heals_two_percent_per_second_after_five_seconds() -> void:
	var c := _hero()
	c.health.hp = 100.0
	var p := _on(c, [SignaturePassives.REGROWTH])
	p.on_damaged(DamageInfo.Type.WEAPON, 1.0, 1.0, 0)
	var t := _step(p, 0, 5 * HZ)
	assert_float(c.health.hp).is_equal(100.0)
	_step(p, t, HZ)
	assert_float(c.health.hp).is_equal_approx(105.0, 1e-3)  # 2% of 250


func test_regrowth_is_cut_by_scorched() -> void:
	var c := _hero()
	c.health.hp = 100.0
	c.health.heal_mult = 0.70
	var p := _on(c, [SignaturePassives.REGROWTH])
	_step(p, 0, HZ)
	assert_float(c.health.hp).is_equal_approx(103.5, 1e-3)


# --- Lattice ------------------------------------------------------------------------

func test_lattice_overshield_absorbs_after_armor_and_refills_after_six_seconds() -> void:
	var c := _hero()
	c.stats.add_modifier(Modifier.make(StatCatalog.GEAR_ARMOR, Modifier.Op.ADD, 0.20, 99))
	var p := _on(c, [SignaturePassives.LATTICE])
	assert_float(c.health.overshield).is_equal(80.0)
	# 50 after 20% armor = 40, all absorbed.
	assert_float(c.health.apply_damage(_weapon_hit(50.0))).is_equal(0.0)
	assert_float(c.health.overshield).is_equal_approx(40.0, 1e-3)
	p.on_damaged(DamageInfo.Type.WEAPON, 0.0, 40.0, 0)
	var t := _step(p, 1, 6 * HZ - 2)
	assert_float(c.health.overshield).is_equal_approx(40.0, 1e-3)
	_step(p, t, 2)
	assert_float(c.health.overshield).is_equal(80.0)


func test_lattice_is_not_healing() -> void:
	var c := _hero()
	c.health.heal_mult = 0.70  # Scorched
	var p := _on(c, [SignaturePassives.LATTICE])
	c.health.overshield = 0.0
	_step(p, 0, 6 * HZ + 1)
	assert_float(c.health.overshield).is_equal(80.0)


func test_lattice_sold_or_dead_clears_the_overshield() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.LATTICE])
	p.set_active([], 1)
	assert_float(c.health.overshield).is_equal(0.0)
	p.set_active([SignaturePassives.LATTICE], 2)
	c.dead = true
	p.on_death()
	assert_float(c.health.overshield).is_equal(0.0)


# --- Resonant Cast ------------------------------------------------------------------

func test_resonant_cast_cuts_remaining_basic_cooldowns_by_a_quarter() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.RESONANT_CAST])
	for slot in 4:
		c.abilities.skill(slot).cooldown_end_tick = 100 + 400
	p.on_ult_cast(100)
	for slot in 3:
		assert_int(c.abilities.skill(slot).cooldown_end_tick).is_equal(100 + 300)
	assert_int(c.abilities.skill(3).cooldown_end_tick).is_equal(500)  # the ultimate itself


func test_resonant_cast_ignores_ready_skills() -> void:
	var c := _hero()
	c.abilities.skill(0).cooldown_end_tick = 50
	_on(c, [SignaturePassives.RESONANT_CAST]).on_ult_cast(100)
	assert_int(c.abilities.skill(0).cooldown_end_tick).is_equal(50)


# --- Siegebreaker -------------------------------------------------------------------

func test_siegebreaker_is_plus_fifteen_percent() -> void:
	var c := _hero()
	assert_float(_on(c, [SignaturePassives.SIEGEBREAKER]).siege_mult()).is_equal_approx(1.15, 1e-6)


# --- Off / death ----------------------------------------------------------------------

func test_turning_passives_off_resets_their_hooks() -> void:
	var c := _hero(CombatFixtures.rifle_mag())
	var p := _on(c, [SignaturePassives.OVERDRIVE_LOOP, SignaturePassives.COLD_START, SignaturePassives.PLANTED,
		SignaturePassives.BRACE])
	for t in range(0, 61, 15):
		p.on_fired(t)
		p.step(t)
	c.health.brace_dr = 0.15
	(c.weapon.feed as MagazineFeed).instant_reload = true
	p.set_active([], 70)
	assert_float(c.weapon.passive_bloom_mult).is_equal(1.0)
	assert_float(c.health.brace_dr).is_equal(0.0)
	assert_float(c.status.knockback_mult).is_equal(1.0)
	assert_bool((c.weapon.feed as MagazineFeed).instant_reload).is_false()


func test_death_clears_timers_and_stacks() -> void:
	var c := _hero()
	var p := _on(c, [SignaturePassives.BRACE, SignaturePassives.REGROWTH])
	p.add_rend(0)
	p.on_damaged(DamageInfo.Type.WEAPON, 90.0, 90.0, 0)
	c.dead = true
	p.on_death()
	assert_float(c.health.brace_dr).is_equal(0.0)
	assert_float(c.health.rend).is_equal(0.0)
	assert_int(p.last_damaged_tick).is_equal(SignaturePassives.NEVER)
	assert_int(p.brace_ready_tick).is_equal(SignaturePassives.NEVER)


# --- Assists (Kindle) -----------------------------------------------------------------

func test_assists_count_damagers_and_heal_beam_helpers_in_the_window() -> void:
	var a := AssistTracker.new(300)
	a.record_damage(11, 99, 0)    # too old at tick 400
	a.record_damage(12, 99, 200)
	a.record_damage(13, 99, 390)  # the killer
	a.record_heal(14, 13, 350)    # healed the killer
	a.record_heal(15, 12, 380)    # healed an assister
	a.record_heal(16, 99, 390)    # healed the victim: no assist
	var out := a.assisters(99, 13, 400)
	out.sort()
	assert_array(out).contains_exactly([12, 14, 15])
	assert_array(a.assisters(99, 0, 401)).is_empty()  # damagers forgotten after the death
