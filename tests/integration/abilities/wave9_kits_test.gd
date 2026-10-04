extends GdUnitTestSuite
## Ryker Vance, Sable and Liora Vale on a real ServerWorld (design/gdd/heroes.md
## §4.4 / §4.2 / §4.6), casting through AbilityRunner.try_activate (the same path
## as the InputCommand skill buttons): every basic skill, the ultimates (the
## --grant-ult debug flag) and the passives that have server behaviour.

const HZ: int = 30
const RYKER := "res://assets/data/heroes/hero_ryker_vance.tres"
const SABLE := "res://assets/data/heroes/hero_sable.tres"
const LIORA := "res://assets/data/heroes/hero_liora_vale.tres"

var _server: ServerWorld
var _link: LoopbackLink


## Scripted hero: holds `buttons` for ticks [from, to) with a fixed aim.
class Holder extends ScriptedInputSource:
	var from_tick: int = 0
	var to_tick: int = 0
	var buttons: int = 0
	var yaw: float = 0.0
	var pitch: float = 0.0

	func _init(def: ScriptedInputDef) -> void:
		super(def)

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		out.yaw = yaw
		out.pitch = pitch
		if seq >= from_tick and seq < to_tick:
			out.buttons |= buttons
		out.quantize()


func _world() -> void:
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(NetFixtures.net_config(), MovementDef.new(), CombatFixtures.range_scene(false), _link.create_endpoint(1),
		CombatFixtures.brannoc(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	_server.abilities.grant_ult = true


func _hero(path: String, at: Vector3, team: int, yaw_deg: float = 0.0) -> HeroBody:
	var def := ScriptedInputDef.new()
	def.segments = PackedVector2Array([Vector2.ZERO])
	def.start_yaw_deg = yaw_deg
	var h := _server.hero(_server.add_scripted_hero(Holder.new(def), at, load(path) as HeroDef, team))
	h.combat.abilities.debug_grant_ult = true
	return h


func _holder(h: HeroBody) -> Holder:
	for d in _server._dummies:
		if d[0] == h:
			return d[1] as Holder
	return null


func _cast(h: HeroBody, slot: int, pitch: float = 0.0, yaw: float = 0.0) -> bool:
	var cmd := InputCommand.new()
	cmd.yaw = yaw
	cmd.pitch = pitch
	return h.combat.abilities.try_activate(slot, h, cmd, _server.tick, _server.abilities)


func _run(n: int) -> void:
	for i in n:
		_server.step()


func _start(spawn_marker: String = "PlayerSpawn") -> Vector3:
	await get_tree().physics_frame
	return _server.spawn_point(spawn_marker)


# ------------------------------------------------------------------ Ryker Vance

func test_frag_grenade_two_charges_recharge_and_damage() -> void:
	_world()
	var ryker := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -12.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var s := ryker.combat.abilities.skill(0)
	assert_bool(_cast(ryker, 0, 0.08)).is_true()
	assert_int(_server.abilities.extras.thrown.size()).is_equal(1)
	s.sync_charges(_server.tick)
	assert_int(s.charges_left).is_equal(1)
	assert_bool(s.on_cooldown(_server.tick)).is_false()  # a charge is left
	_run(60)  # fuse 1.2 s = 36 ticks
	assert_int(_server.abilities.extras.thrown.size()).is_equal(0)
	var hp := foe.combat.health.hp
	assert_float(hp).is_less(250.0)
	assert_float(hp).is_greater_equal(250.0 - 110.0 - 1e-3)  # full damage at most
	# Second charge, then none: the third press is rejected on cooldown.
	assert_bool(_cast(ryker, 0, 0.08)).is_true()
	s.sync_charges(_server.tick)
	assert_int(s.charges_left).is_equal(0)
	assert_bool(s.on_cooldown(_server.tick)).is_true()
	_run(10)
	assert_bool(_cast(ryker, 0, 0.08)).is_false()
	assert_int(ryker.combat.abilities.last_reject).is_equal(AbilityRunner.Reject.COOLDOWN)
	# One charge returns 9 s after the first spend.
	_run(9 * HZ)
	s.sync_charges(_server.tick)
	assert_int(s.charges_left).is_equal(1)
	assert_bool(s.on_cooldown(_server.tick)).is_false()


func test_grenade_blast_falloff_and_wardling_multiplier() -> void:
	_world()
	var ryker := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var near := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(10.0, 0.05, 0.0), ServerWorld.TEAM_DUMMIES)
	var edge := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(10.0, 0.05, 4.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ctx := EffectContext.new()
	ctx.world = _server.abilities
	ctx.caster = ryker
	ctx.skill = ryker.combat.abilities.skill(0)
	ctx.team = ryker.combat.team
	ctx.point = Vector3(10.0, 0.05, 0.0)
	var blast := (ryker.combat.abilities.skill(0).def.effects[0] as ThrownEffectDef).on_detonate[0]
	ctx.run([blast])
	assert_float(near.combat.health.hp).is_equal_approx(250.0 - 110.0, 0.6)
	# 4 m of 5 m: 1 - 0.6 * 0.8 = 52% (chest-distance based, so allow slack).
	var took := 250.0 - edge.combat.health.hp
	assert_float(took).is_between(110.0 * 0.4, 110.0 * 0.62)


func test_combat_stim_costs_hp_and_boosts_rate_and_speed() -> void:
	_world()
	var ryker := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := ryker.combat.abilities.skill(1)
	assert_bool(_cast(ryker, 1)).is_true()
	assert_float(ryker.combat.health.hp).is_equal(230.0)
	assert_float(ryker.combat.weapon.rate_mult).is_equal_approx(1.25, 1e-4)
	_run(2)
	assert_float(ryker.state.speed_scale).is_equal_approx(1.15, 1e-3)
	assert_bool(s.active).is_true()
	_run(5 * HZ + 2)
	assert_float(ryker.combat.weapon.rate_mult).is_equal(1.0)
	assert_float(ryker.state.speed_scale).is_equal_approx(1.0, 1e-3)
	assert_int(s.cooldown_ticks_left(_server.tick)).is_between(16 * HZ - 4, 16 * HZ)  # starts at the end
	# Never below 1 HP.
	ryker.combat.health.hp = 10.0
	s.cooldown_end_tick = 0
	_run(10)
	assert_bool(_cast(ryker, 1)).is_true()
	assert_float(ryker.combat.health.hp).is_equal(1.0)


func test_tactical_slide_moves_7_m_and_reloads_30_percent() -> void:
	_world()
	var ryker := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var feed := ryker.combat.weapon.feed as MagazineFeed
	feed.rounds = 5
	var start := ryker.state.position
	assert_bool(_cast(ryker, 2)).is_true()
	assert_int(feed.rounds).is_equal(5 + 9)
	assert_int(feed.reserve).is_equal(150 - 9)
	_run(30)
	assert_float(start.z - ryker.state.position.z).is_between(6.0, 7.6)


func test_overdrive_protocol_bottomless_damage_and_kill_extension() -> void:
	_world()
	var ryker := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -8.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ult := ryker.combat.abilities.skill(3)
	for n in ult.def.nodes:  # rank 3: the kill-extension rider
		ult.learn(n)
	assert_bool(_cast(ryker, 3)).is_true()
	assert_float(ryker.combat.stats.get_value(StatCatalog.WEAPON_DAMAGE)).is_equal_approx(1.4, 1e-4)
	var feed := ryker.combat.weapon.feed as MagazineFeed
	feed.rounds = 3
	feed.reserve = 0
	_run(2)
	assert_int(feed.rounds).is_equal(30)  # bottomless: no reload, no reserve drain
	assert_int(feed.reserve).is_equal(0)
	var until := _server.abilities.extras.buffs[ryker].bottomless_until
	_server.hero_died.emit(foe.net_id, ryker.net_id)  # a kill extends it 2 s
	assert_int(_server.abilities.extras.buffs[ryker].bottomless_until).is_equal(until + 2 * HZ)
	for i in 5:  # capped at +6 s in total
		_server.hero_died.emit(foe.net_id, ryker.net_id)
	assert_int(_server.abilities.extras.buffs[ryker].bottomless_until).is_equal(until + 6 * HZ)
	_run(20 * HZ)
	assert_float(ryker.combat.stats.get_value(StatCatalog.WEAPON_DAMAGE)).is_equal(1.0)
	assert_bool(ult.on_cooldown(_server.tick)).is_true()


func test_battle_rhythm_refills_half_the_magazine_and_speeds_up_on_a_kill() -> void:
	_world()
	var ryker := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -8.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var feed := ryker.combat.weapon.feed as MagazineFeed
	feed.rounds = 6
	_server.hero_died.emit(foe.net_id, ryker.net_id)
	assert_int(feed.rounds).is_equal(21)
	_run(2)
	assert_float(ryker.state.speed_scale).is_equal_approx(1.15, 1e-3)
	_run(3 * HZ + 2)
	assert_float(ryker.state.speed_scale).is_equal_approx(1.0, 1e-3)


# ---------------------------------------------------------------------- Sable

func test_veilwalk_stealth_speed_visibility_and_breaks_on_fire_or_damage() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -20.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ex := _server.abilities.extras
	var s := sable.combat.abilities.skill(0)
	assert_bool(_cast(sable, 0)).is_true()
	_run(2)
	assert_int(_server.abilities.status_bits(sable) & SkillStatusBits.STEALTH).is_equal(SkillStatusBits.STEALTH)
	assert_float(sable.state.speed_scale).is_equal_approx(1.15, 1e-3)
	assert_bool(ex.hidden_from(sable, foe.state.position)).is_true()  # 20 m: invisible
	assert_bool(ex.hidden_from(sable, Vector3(0.0, 0.0, -5.0))).is_false()  # inside the 8 m shimmer
	# Firing ends it and starts the cooldown.
	_holder(sable).buttons = InputCommand.BTN_FIRE
	_holder(sable).from_tick = 0
	_holder(sable).to_tick = 100000
	_run(3)
	assert_bool(ex.stealth.has(sable)).is_false()
	assert_bool(s.active).is_false()
	assert_bool(s.on_cooldown(_server.tick)).is_true()
	# Taking damage ends it too.
	_holder(sable).to_tick = 0
	s.cooldown_end_tick = 0
	_run(10)
	assert_bool(_cast(sable, 0)).is_true()
	_run(2)
	assert_bool(ex.stealth.has(sable)).is_true()
	_server.damage_hero(sable, DamageInfo.make(10.0, foe.net_id, foe.combat.team, 0, DamageInfo.Type.WEAPON))
	assert_bool(ex.stealth.has(sable)).is_false()
	# A natural end after 6 s starts the 16 s cooldown.
	s.cooldown_end_tick = 0
	_run(10)
	assert_bool(_cast(sable, 0)).is_true()
	_run(6 * HZ + 2)
	assert_bool(ex.stealth.has(sable)).is_false()
	assert_int(s.cooldown_ticks_left(_server.tick)).is_between(16 * HZ - 4, 16 * HZ)


func test_phase_shift_dashes_8_m_intangible_for_0_4_s() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -4.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var start := sable.state.position
	var mask := sable.collision_mask
	assert_bool(_cast(sable, 1)).is_true()
	_run(1)
	# Intangible: no damage, and the body passes through the hero standing in the way.
	assert_float(sable.combat.health.apply_damage(DamageInfo.make(50.0, foe.net_id, foe.combat.team))).is_equal(0.0)
	assert_bool((sable.collision_mask & HeroBody.LAYER_HEROES) == 0).is_true()
	_run(20)
	assert_float(start.z - sable.state.position.z).is_between(7.0, 8.6)
	assert_int(sable.collision_mask).is_equal(mask)
	assert_float(sable.combat.health.apply_damage(DamageInfo.make(50.0, foe.net_id, foe.combat.team))).is_greater(0.0)
	assert_bool(sable.combat.abilities.skill(1).on_cooldown(_server.tick)).is_true()


func test_sabotage_charge_plant_arm_trigger_and_remote_blast() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -30.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ex := _server.abilities.extras
	assert_bool(_cast(sable, 2, -0.3)).is_true()
	assert_bool(sable.combat.abilities.is_casting()).is_true()  # 1.0 s plant
	assert_int(ex.charges.size()).is_equal(0)
	_run(HZ + 1)
	assert_int(ex.charges.size()).is_equal(1)
	var ch: SkillEntities.SabCharge = ex.charges[0]
	assert_float(ch.pos.distance_to(sable.state.position)).is_less(3.6)
	# Not armed for 1.5 s: an enemy walking up does nothing yet; the recast needs it armed.
	foe.state.position = ch.pos + Vector3(0.0, 0.0, -3.4)  # outside the 3 m trigger, inside the 4 m blast
	foe.motor.restore(foe.state)
	_run(HZ)
	assert_int(ex.charges.size()).is_equal(1)
	assert_float(foe.combat.health.hp).is_equal(250.0)
	_run(HZ)  # armed now; the skill is on cooldown, so a second press is the remote detonation
	assert_bool(_cast(sable, 2)).is_true()
	assert_int(ex.charges.size()).is_equal(0)
	assert_float(foe.combat.health.hp).is_equal_approx(250.0 - 120.0, 1.0)


func test_sabotage_charge_triggers_on_an_enemy_hero_within_3_m() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -30.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ex := _server.abilities.extras
	_cast(sable, 2, -0.3)
	_run(HZ + 1)
	var ch: SkillEntities.SabCharge = ex.charges[0]
	_run(int(1.6 * HZ))  # armed
	foe.state.position = ch.pos + Vector3(0.0, 0.0, -2.0)
	foe.motor.restore(foe.state)
	_run(2)
	assert_int(ex.charges.size()).is_equal(0)
	assert_float(foe.combat.health.hp).is_less(250.0)


func test_sabotage_max_placed_removes_the_oldest() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var ex := _server.abilities.extras
	var s := sable.combat.abilities.skill(2)
	for i in 3:
		s.cooldown_end_tick = 0
		_run(12)
		assert_bool(_cast(sable, 2, -0.3)).is_true()
		_run(HZ + 2)
	assert_int(ex.charges.size()).is_equal(2)


func test_eclipse_step_silences_marks_and_teleports_behind() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -8.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ex := _server.abilities.extras
	# Aim at the chest (eye 1.62 m vs chest 1.2 m, 8 m away).
	assert_bool(_cast(sable, 3, atan2(1.2 - 1.62, 8.0))).is_true()
	_run(8)  # 8 m at 80 m/s = 3 ticks
	assert_bool(ex.is_silenced(foe)).is_true()
	assert_int(_server.abilities.status_bits(foe) & SkillStatusBits.SILENCE).is_equal(SkillStatusBits.SILENCE)
	assert_bool(_cast(foe, 0)).is_false()  # Silence: no skills
	# Mark: +40% weapon, plus Shadowgraph +20% (the target faces away: -Z, Sable is behind it).
	assert_float(ex.shot_mult(sable, foe)).is_equal_approx(1.6, 1e-4)
	_run(HZ)  # 0.5 s later she is behind it (1.5 m on the side she came from)
	assert_float(sable.state.position.z).is_between(-7.5, -5.5)
	assert_bool(sable.combat.abilities.skill(3).on_cooldown(_server.tick)).is_true()
	_run(3 * HZ)
	assert_bool(ex.is_silenced(foe)).is_false()
	assert_float(ex.shot_mult(sable, foe)).is_equal_approx(1.2, 1e-4)  # mark over, Shadowgraph stays


func test_eclipse_step_on_terrain_teleports_there() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	# Aim at the floor 10 m ahead: the dart hits terrain.
	assert_bool(_cast(sable, 3, -atan2(1.62, 10.0))).is_true()
	_run(HZ)
	assert_float(sable.state.position.z).is_between(-11.5, -8.0)


func test_eclipse_step_rank_3_rider_reenters_veilwalk_and_refunds_cooldown() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -8.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ex := _server.abilities.extras
	var ult := sable.combat.abilities.skill(3)
	for n in ult.def.nodes:
		ult.learn(n)
	_cast(sable, 3, atan2(1.2 - 1.62, 8.0))
	_run(6)
	assert_bool(ex.marks.has(foe)).is_true()
	var left_before := ult.cooldown_ticks_left(_server.tick)
	_server.hero_died.emit(foe.net_id, sable.net_id)  # a kill inside the 3 s window
	assert_bool(ex.stealth.has(sable)).is_true()
	assert_bool(sable.combat.abilities.skill(0).active).is_true()
	var refunded := left_before - ult.cooldown_ticks_left(_server.tick)
	assert_int(refunded).is_between(roundi(80.0 * HZ * 0.3) - 2, roundi(80.0 * HZ * 0.3) + 2)


func test_shadowgraph_only_vs_targets_facing_away() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var away := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -8.0), ServerWorld.TEAM_DUMMIES, 0.0)
	var toward := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(4.0, 0.05, -8.0), ServerWorld.TEAM_DUMMIES, 180.0)
	await get_tree().physics_frame
	_run(2)
	assert_float(_server.abilities.extras.shot_mult(sable, away)).is_equal_approx(1.2, 1e-4)
	assert_float(_server.abilities.extras.shot_mult(sable, toward)).is_equal_approx(1.0, 1e-4)


# ---------------------------------------------------------------------- Liora

func test_heal_beam_heals_drains_mana_and_blocks_the_gun() -> void:
	_world()
	var liora := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -6.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var h := _holder(liora)
	h.pitch = atan2(1.2 - 1.62, 6.0)
	h.buttons = InputCommand.BTN_ALT | InputCommand.BTN_FIRE
	h.to_tick = 100000
	ally.combat.health.hp = 100.0
	var feed := liora.combat.weapon.feed as ManaPoolFeed
	_run(HZ)
	assert_float(ally.combat.health.hp).is_equal_approx(160.0, 4.0)  # 60 HP/s
	assert_float(100.0 - feed.mana).is_equal_approx(25.0, 3.0)  # 25 mana/s
	assert_int(liora.combat.weapon.shots_fired).is_equal(0)  # beam and bolts are exclusive
	assert_bool(_server.abilities.extras.beams.has(liora)).is_true()
	# Full HP target: no heal, no drain.
	ally.combat.health.hp = ally.combat.health.max_hp
	var mana := feed.mana
	_run(HZ)
	assert_float(feed.mana).is_greater_equal(mana)
	# Releasing ALT ends the beam and the gun works again.
	h.buttons = InputCommand.BTN_FIRE
	_run(5)
	assert_bool(_server.abilities.extras.beams.has(liora)).is_false()
	assert_int(liora.combat.weapon.shots_fired).is_greater(0)


func test_heal_beam_heals_wardlings_at_half_rate_and_ignores_enemies() -> void:
	_world()
	var liora := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -6.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var h := _holder(liora)
	h.pitch = atan2(1.2 - 1.62, 6.0)
	h.buttons = InputCommand.BTN_ALT
	h.to_tick = 100000
	foe.combat.health.hp = 100.0
	_run(HZ)
	assert_float(foe.combat.health.hp).is_equal(100.0)
	assert_bool(_server.abilities.extras.beams.has(liora)).is_false()


func test_med_pack_drone_heals_the_most_injured_ally_over_2_s() -> void:
	_world()
	var liora := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var hurt := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -4.0), ServerWorld.TEAM_PLAYERS)
	var fine := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(2.0, 0.05, -4.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	hurt.combat.health.hp = 100.0
	fine.combat.health.hp = 200.0
	assert_bool(_cast(liora, 0, -atan2(1.62, 4.0))).is_true()
	assert_int(_server.abilities.extras.drones.size()).is_equal(1)
	_run(HZ)
	assert_float(hurt.combat.health.hp).is_between(150.0, 170.0)  # 60 HP/s, one second in
	_run(2 * HZ)
	assert_float(hurt.combat.health.hp).is_equal_approx(220.0, 2.0)  # 120 over 2 s
	assert_float(fine.combat.health.hp).is_equal_approx(200.0, 1e-3)
	assert_int(_server.abilities.extras.drones.size()).is_equal(0)
	var ds := liora.combat.abilities.skill(0)
	ds.sync_charges(_server.tick)
	assert_int(ds.charges_left).is_equal(1)


func test_prism_ward_shields_the_aimed_ally_else_self() -> void:
	_world()
	var liora := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -6.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	assert_bool(_cast(liora, 1, atan2(1.2 - 1.62, 6.0))).is_true()
	assert_float(ally.combat.health.shield).is_equal(150.0)
	assert_float(liora.combat.health.shield).is_equal(0.0)
	_run(4 * HZ + 2)
	assert_float(ally.combat.health.shield).is_equal(0.0)  # 4 s
	# Aimed at nobody: the caster is shielded.
	liora.combat.abilities.skill(1).cooldown_end_tick = 0
	_run(10)
	assert_bool(_cast(liora, 1, 0.9)).is_true()
	assert_float(liora.combat.health.shield).is_equal(150.0)


func test_flash_bloom_blinds_and_knocks_back_enemies_facing_it() -> void:
	_world()
	var liora := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var facing := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -6.0), ServerWorld.TEAM_DUMMIES, 180.0)
	var turned := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(3.0, 0.05, -6.0), ServerWorld.TEAM_DUMMIES, 0.0)
	await get_tree().physics_frame
	_run(2)
	assert_bool(_cast(liora, 2, -atan2(1.62, 6.0))).is_true()
	assert_bool(_server.abilities.extras.is_blinded(facing)).is_false()  # 0.3 s fuse
	_run(12)
	assert_bool(_server.abilities.extras.is_blinded(facing)).is_true()
	assert_int(_server.abilities.status_bits(facing) & SkillStatusBits.BLIND).is_equal(SkillStatusBits.BLIND)
	assert_bool(_server.abilities.extras.is_blinded(turned)).is_false()  # looked away
	assert_float(facing.state.position.z).is_less(-6.0 - 1.5)  # pushed away from the bloom
	_run(HZ + 2)
	assert_bool(_server.abilities.extras.is_blinded(facing)).is_false()  # 1.0 s


func test_aurora_heals_allies_floors_hp_for_2_s_and_ends() -> void:
	_world()
	var liora := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -5.0), ServerWorld.TEAM_PLAYERS)
	var far := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -20.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -25.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	ally.combat.health.hp = 100.0
	far.combat.health.hp = 100.0
	assert_bool(_cast(liora, 3)).is_true()
	_run(HZ)
	assert_float(ally.combat.health.hp).is_equal_approx(180.0, 4.0)  # 80 HP/s
	assert_float(far.combat.health.hp).is_equal(100.0)  # outside the 12 m dome
	# First 2 s: cannot drop below 1 HP.
	_server.damage_hero(ally, DamageInfo.make(5000.0, foe.net_id, foe.combat.team, 0, DamageInfo.Type.WEAPON))
	assert_bool(ally.combat.dead).is_false()
	assert_float(ally.combat.health.hp).is_greater_equal(1.0)
	_run(6 * HZ)
	assert_int(_server.abilities.extras.auras.size()).is_equal(0)
	assert_float(ally.combat.health.floor_hp).is_equal(0.0)
	assert_bool(liora.combat.abilities.skill(3).on_cooldown(_server.tick)).is_true()


func test_aurora_floor_lapses_after_2_s() -> void:
	_world()
	var liora := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -5.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -25.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	_cast(liora, 3)
	_run(2 * HZ + 5)
	assert_float(ally.combat.health.floor_hp).is_equal(0.0)
	_server.damage_hero(ally, DamageInfo.make(5000.0, foe.net_id, foe.combat.team, 0, DamageInfo.Type.WEAPON))
	assert_bool(ally.combat.dead).is_true()


func test_triage_kit_regenerates_a_free_med_pack_every_30_s() -> void:
	_world()
	_server.enable_progression(load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef,
		load("res://assets/data/economy/armory_catalog_slice.tres") as ArmoryCatalogDef)
	var liora := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var p := _server.progression.progress_of(liora)
	var base := p.medpacks
	_run(31 * HZ)
	assert_int(p.medpacks).is_equal(base + 1)
	_run(30 * HZ)
	assert_int(p.medpacks).is_equal(base + 2)
	_run(30 * HZ)
	assert_int(p.medpacks).is_equal(base + 2)  # free ones hold max 2


func test_silenced_hero_cannot_cast_but_can_shoot_and_dead_heroes_clear_flags() -> void:
	_world()
	var sable := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero("res://assets/data/heroes/hero_vesper_loom.tres", Vector3(0.0, 0.05, -8.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	_server.abilities.extras.silence(foe, 3 * HZ)
	assert_bool(_cast(foe, 0)).is_false()
	assert_bool(foe.combat.can_shoot()).is_true()
	_server.damage_hero(foe, DamageInfo.make(5000.0, sable.net_id, sable.combat.team, 0, DamageInfo.Type.TRUE))
	_run(3)
	assert_bool(_server.abilities.extras.is_silenced(foe)).is_false()
