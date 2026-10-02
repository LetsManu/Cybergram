extends GdUnitTestSuite
## Shared skill rules (design/gdd/heroes.md §3.4, §3.6) on AbilityRunner and
## StatusComponent, without a world: cooldowns, the 0.25 s lockout, the 25% CDR
## cap and minimums, cooldown-on-end, cast interruption, HQ respawn reset,
## the ult level gate, the 40% slow cap, hard-CC diminishing returns, DR/armor
## clamp and shields.

const HZ: int = 30

var _bodies: Array[HeroBody] = []


func after_test() -> void:
	for b in _bodies:
		b.free()
	_bodies.clear()


## A skill without effects (gates and timers only).
static func _skill(cd: float, ult: bool = false, extra: Dictionary = {}) -> SkillDef:
	var s := SkillDef.new()
	s.id = &"test_skill"
	s.ultimate = ult
	s.required_level = 6 if ult else 1
	s.params = {&"cooldown": cd}
	s.params.merge(extra, true)
	return s


func _hero(skills: Array[SkillDef]) -> HeroBody:
	var d := HeroDef.new()
	d.skills = skills
	return _body_for(d)


func _body_for(d: HeroDef) -> HeroBody:
	var h := HeroBody.new()
	h.setup(MovementDef.new(), Vector3.ZERO, false)
	h.combat = HeroCombat.new(d, 0, HZ, 1)
	_bodies.append(h)
	return h


func _press(h: HeroBody, slot: int, tick: int) -> bool:
	var cmd := InputCommand.new()
	cmd.buttons = AbilityRunner.SLOT_BUTTONS[slot]
	return h.combat.abilities.try_activate(slot, h, cmd, tick, null)


func test_cooldown_gates_recasts_in_ticks() -> void:
	var h := _hero([_skill(10.0)])
	var r := h.combat.abilities
	assert_bool(_press(h, 0, 0)).is_true()
	assert_int(r.skill(0).cooldown_end_tick).is_equal(300)
	assert_bool(_press(h, 0, 299)).is_false()
	assert_int(r.last_reject).is_equal(AbilityRunner.Reject.COOLDOWN)
	assert_bool(_press(h, 0, 300)).is_true()
	assert_int(r.skill(0).casts).is_equal(2)


func test_shared_lockout_is_a_quarter_second_between_any_two_casts() -> void:
	var h := _hero([_skill(5.0), _skill(5.0)])
	var r := h.combat.abilities
	assert_bool(_press(h, 0, 100)).is_true()
	assert_bool(_press(h, 1, 107)).is_false()  # 0.25 s × 30 Hz = 7.5 -> 8 ticks
	assert_int(r.last_reject).is_equal(AbilityRunner.Reject.LOCKOUT)
	assert_bool(_press(h, 1, 108)).is_true()


func test_cdr_is_capped_at_25_percent_with_3_s_and_45_s_minimums() -> void:
	var h := _hero([_skill(10.0), _skill(3.5), _skill(8.0), _skill(50.0, true)])
	var r := h.combat.abilities
	assert_float(r.effective_cooldown_s(r.skill(0))).is_equal(10.0)
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.COOLDOWN_REDUCTION, Modifier.Op.ADD, 0.4))
	# EffectiveCD = NodeCD × (1 − min(0.25, CDR)).
	assert_float(r.effective_cooldown_s(r.skill(0))).is_equal_approx(7.5, 1e-5)
	assert_float(r.effective_cooldown_s(r.skill(2))).is_equal_approx(6.0, 1e-5)
	assert_float(r.effective_cooldown_s(r.skill(1))).is_equal(3.0)   # 2.625 -> basic minimum
	assert_float(r.effective_cooldown_s(r.skill(3))).is_equal(45.0)  # 37.5 -> ultimate minimum
	assert_bool(_press(h, 0, 0)).is_true()
	assert_int(r.skill(0).cooldown_end_tick).is_equal(225)


func test_cooldown_starts_when_the_effect_ends() -> void:
	var s := _skill(20.0, false, {&"duration": 3.0})
	s.cooldown_on_end = true
	var h := _hero([s])
	var r := h.combat.abilities
	assert_bool(_press(h, 0, 10)).is_true()
	var inst := r.skill(0)
	assert_bool(inst.active).is_true()
	assert_bool(inst.on_cooldown(50)).is_false()
	assert_bool(_press(h, 0, 50)).is_false()  # still active: no recast
	r.process(h, InputCommand.new(), 99, null)
	assert_bool(inst.active).is_true()
	r.process(h, InputCommand.new(), 100, null)  # 3 s after the cast
	assert_bool(inst.active).is_false()
	assert_int(inst.cooldown_end_tick).is_equal(100 + 600)
	# An early end (wall destroyed) starts it at once.
	assert_bool(_press(h, 0, 700)).is_true()
	r.end_active(inst, 720)
	assert_int(inst.cooldown_end_tick).is_equal(720 + 600)


func test_stun_interrupts_a_cast_and_charges_half_the_cooldown() -> void:
	var s := _skill(120.0, false, {&"cast_time": 0.8})
	s.interruptible = true
	var h := _hero([s])
	var r := h.combat.abilities
	assert_bool(_press(h, 0, 0)).is_true()
	assert_bool(r.is_casting()).is_true()
	h.combat.status.apply(StatusComponent.Kind.STUN, 30, 0.0, 99, 5)
	r.process(h, InputCommand.new(), 6, null)
	assert_bool(r.is_casting()).is_false()
	assert_int(r.skill(0).casts).is_equal(0)
	assert_int(r.skill(0).cooldown_end_tick).is_equal(6 + 1800)  # 50% of 120 s
	# Stunned: no new cast either.
	assert_bool(_press(h, 0, 20)).is_false()
	assert_int(r.last_reject).is_equal(AbilityRunner.Reject.STUNNED)


func test_hq_respawn_resets_basic_cooldowns_but_not_the_ultimate() -> void:
	var h := _hero([_skill(10.0), _skill(18.0), _skill(14.0), _skill(110.0, true)])
	var r := h.combat.abilities
	r.debug_grant_ult = true
	for i in 4:
		assert_bool(_press(h, i, i * 10)).is_true()
	h.combat.reset_for_respawn()
	for i in 3:
		assert_bool(r.skill(i).on_cooldown(40)).is_false()
	assert_bool(r.skill(3).on_cooldown(40)).is_true()


func test_ultimate_is_locked_below_level_6() -> void:
	var h := _body_for(CombatFixtures.vesper())
	var r := h.combat.abilities
	assert_int(h.combat.level).is_equal(1)
	assert_bool(r.is_unlocked(0)).is_true()
	assert_bool(r.is_unlocked(3)).is_false()
	assert_bool(_press(h, 3, 0)).is_false()
	assert_int(r.last_reject).is_equal(AbilityRunner.Reject.LOCKED)
	assert_int(r.hud_state(3, 0)[2] & AbilityRunner.FLAG_LOCKED).is_equal(AbilityRunner.FLAG_LOCKED)
	h.combat.level = 5
	assert_bool(r.is_unlocked(3)).is_false()
	h.combat.level = 6
	assert_bool(r.is_unlocked(3)).is_true()
	h.combat.level = 1
	r.debug_grant_ult = true  # --grant-ult
	assert_bool(r.is_unlocked(3)).is_true()
	assert_bool(_press(h, 3, 10)).is_true()  # Rewrite starts its 0.8 s cast
	assert_bool(r.is_casting()).is_true()


func test_slows_sum_but_cap_at_40_percent() -> void:
	var h := _body_for(CombatFixtures.vesper())
	var st := h.combat.status
	var stats := h.combat.stats
	st.apply(StatusComponent.Kind.SLOW, 60, 0.25, 1, 0)
	assert_float(stats.get_value(StatCatalog.MOVE_SPEED)).is_equal_approx(6.0 * 0.75, 1e-4)
	st.apply(StatusComponent.Kind.SLOW, 60, 0.3, 2, 0)
	assert_float(st.slow_total()).is_equal_approx(0.40, 1e-6)
	assert_float(stats.get_value(StatCatalog.MOVE_SPEED)).is_equal_approx(6.0 * 0.6, 1e-4)
	st.step(60)
	assert_float(stats.get_value(StatCatalog.MOVE_SPEED)).is_equal(6.0)
	assert_int(st.visual_bits() & StatusComponent.BIT_SLOW).is_equal(0)


func test_same_type_hard_cc_has_diminishing_returns() -> void:
	var h := _body_for(CombatFixtures.vesper())
	var st := h.combat.status
	# 1st full, 2nd within 4 s 50%, 3rd 0 (immune); after the window full again.
	assert_int(st.apply(StatusComponent.Kind.STUN, 36, 0.0, 1, 0)).is_equal(36)
	assert_float(h.combat.stats.get_value(StatCatalog.MOVE_SPEED)).is_equal(0.0)
	assert_int(st.apply(StatusComponent.Kind.STUN, 36, 0.0, 2, 40)).is_equal(18)
	assert_int(st.apply(StatusComponent.Kind.STUN, 36, 0.0, 3, 80)).is_equal(0)
	# A different hard-CC type has its own counter.
	assert_int(st.apply(StatusComponent.Kind.ROOT, 30, 0.0, 4, 80)).is_equal(30)
	assert_int(st.apply(StatusComponent.Kind.STUN, 36, 0.0, 5, 121)).is_equal(36)


func test_fortify_cc_immunity_and_anchor_knockback_immunity() -> void:
	var h := _body_for(CombatFixtures.brannoc())
	var st := h.combat.status
	st.apply(StatusComponent.Kind.CC_IMMUNE, 90, 1.0, 1, 0)
	assert_int(st.apply(StatusComponent.Kind.STUN, 30, 0.0, 2, 1)).is_equal(0)
	assert_bool(st.is_stunned()).is_false()
	st.step(90)
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.KNOCKBACK_IMMUNE, Modifier.Op.ADD, 1.0, 77))
	assert_int(st.apply(StatusComponent.Kind.KNOCKBACK, 10, 0.0, 3, 100)).is_equal(0)
	assert_int(st.apply(StatusComponent.Kind.STUN, 30, 0.0, 4, 100)).is_equal(30)  # Anchor: stun still lands


func test_damage_reduction_stacks_with_armor_clamped_at_70_percent_and_shields_absorb() -> void:
	var h := _body_for(CombatFixtures.brannoc())  # 550 HP, 20% armor
	var hp := h.combat.health
	assert_float(hp.apply_damage(DamageInfo.make(100.0, 9, 1))).is_equal_approx(80.0, 1e-4)
	h.combat.status.apply(StatusComponent.Kind.DR, 90, 0.4, 1, 0)  # Fortify Unlock
	assert_float(hp.apply_damage(DamageInfo.make(100.0, 9, 1))).is_equal_approx(40.0, 1e-4)
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.DAMAGE_REDUCTION, Modifier.Op.ADD, 0.15, 5))  # Anchor
	assert_float(hp.apply_damage(DamageInfo.make(100.0, 9, 1))).is_equal_approx(30.0, 1e-4)  # 75% -> 70%
	h.combat.status.apply(StatusComponent.Kind.SHIELD, 90, 50.0, 2, 0)
	assert_float(hp.apply_damage(DamageInfo.make(100.0, 9, 1))).is_equal(0.0)  # 30 into the 50 shield
	assert_float(hp.shield).is_equal_approx(20.0, 1e-4)
	assert_float(hp.apply_damage(DamageInfo.make(100.0, 9, 1))).is_equal_approx(10.0, 1e-4)
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.DAMAGE_TAKEN, Modifier.Op.MUL, 2.0, 6))
	assert_float(hp.apply_damage(DamageInfo.make(100.0, 9, 1))).is_equal_approx(60.0, 1e-4)


func test_move_speed_routes_through_the_stat_block() -> void:
	var h := _body_for(CombatFixtures.brannoc())
	assert_float(h.combat.stats.get_value(StatCatalog.MOVE_SPEED)).is_equal_approx(5.4, 1e-5)
	h.combat.status.apply(StatusComponent.Kind.SLOW, 90, 0.25, 1, 0)  # Fortify self-slow
	assert_float(h.combat.stats.get_value(StatCatalog.MOVE_SPEED)).is_equal_approx(4.05, 1e-4)
