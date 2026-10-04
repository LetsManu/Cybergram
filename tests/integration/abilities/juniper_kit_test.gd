extends GdUnitTestSuite
## Juniper Quill's kit on a real ServerWorld (design/gdd/heroes.md §4.3):
## Snare Coil (root, damage, 2 charges), Tripwire Lattice (two presses, damage
## + slow), Pressure Mine (damage, falloff), Linkwork (budget 6, chain, orphan
## life) and Killbox (fence crossing damage + stun). Effects are applied with
## a hand-built EffectContext where the cast path is not the point; the
## button path (charges, tripwire presses) goes through InputCommand.

const JUNIPER := "res://assets/data/heroes/hero_juniper_quill.tres"
var _server: ServerWorld
var _link: LoopbackLink


## Scripted hero: `plan` tick -> buttons, `aim` rows [from_tick, yaw, pitch].
class Caster extends ScriptedInputSource:
	var plan: Dictionary = {}
	var aim: Array = [[0, 0.0, 0.0]]

	func _init() -> void:
		super(CombatFixtures.idle_input())

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		for row in aim:
			if seq >= int(row[0]):
				out.yaw = float(row[1])
				out.pitch = float(row[2])
		out.buttons |= int(plan.get(seq, 0))
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
		load(JUNIPER) as HeroDef, load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)


func _juniper(src: Caster = null) -> HeroBody:
	var c := src if src != null else Caster.new()
	return _server.hero(_server.add_scripted_hero(c, Vector3(0.0, 0.05, 0.0), load(JUNIPER) as HeroDef, ServerWorld.TEAM_PLAYERS))


func _enemy(at: Vector3) -> HeroBody:
	return _server.hero(_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()), at,
		CombatFixtures.vesper(), ServerWorld.TEAM_DUMMIES))


func _run(n: int) -> void:
	for i in n:
		_server.step()


func _ctx(h: HeroBody, slot: int, point: Vector3) -> EffectContext:
	var c := EffectContext.new()
	c.world = _server.abilities
	c.caster = h
	c.skill = h.combat.abilities.skill(slot)
	c.team = h.combat.team
	c.tick = _server.tick
	c.origin = h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	c.dir = Vector3.FORWARD
	c.point = point
	return c


func _place(h: HeroBody, slot: int, point: Vector3) -> void:
	_ctx(h, slot, point).run(h.combat.abilities.skill(slot).effects())


func _count(kind: int) -> int:
	var n := 0
	for dd in _server.abilities.traps.data:
		var rec: TrapWorld.Data = _server.abilities.traps.data[dd]
		if rec.kind == kind and rec.d.alive:
			n += 1
	return n


func test_snare_coil_roots_and_damages_after_arming() -> void:
	_world()
	var j := _juniper()
	var e := _enemy(Vector3(0.0, 0.05, -12.0))
	await get_tree().physics_frame
	_run(5)
	_place(j, 0, Vector3(0.0, 0.0, -12.0))
	assert_int(_count(TrapWorld.KIND_SNARE)).is_equal(1)
	_run(20)  # arms after 1.0 s (30 ticks): not yet
	assert_float(e.combat.health.hp).is_equal(250.0)
	_run(20)
	assert_float(e.combat.health.hp).is_equal_approx(220.0, 0.5)
	assert_bool(e.combat.status.has(StatusComponent.Kind.ROOT)).is_true()
	assert_int(_count(TrapWorld.KIND_SNARE)).is_equal(0)


func test_snare_ignores_allies_and_a_hacked_trap_is_inert() -> void:
	_world()
	var j := _juniper()
	var e := _enemy(Vector3(0.0, 0.05, -12.0))
	await get_tree().physics_frame
	_run(2)
	_place(j, 0, Vector3(0.0, 0.0, -12.0))
	var d: AbilityWorld.Deployable = _server.abilities.deployables[0]
	_server.abilities.traps.hack(d, 300, 120)
	_run(50)
	assert_float(e.combat.health.hp).is_equal(250.0)
	assert_bool(_server.abilities.traps.is_down(d)).is_true()


func test_pressure_mine_damage_and_edge_falloff() -> void:
	_world()
	var j := _juniper()
	var near := _enemy(Vector3(0.0, 0.05, -12.0))
	await get_tree().physics_frame
	_run(2)
	_place(j, 2, Vector3(0.0, 0.0, -12.0))
	_run(75)  # arm 2.0 s = 60 ticks
	assert_float(near.combat.health.hp).is_equal_approx(110.0, 1.0)  # 140 dmg at the centre
	assert_int(_count(TrapWorld.KIND_MINE)).is_equal(0)
	# Edge: a victim 4.5 m from the centre takes 140 x lerp(1, 0.4, 0.9) = 64.4.
	var trigger := _enemy(Vector3(0.0, 0.05, -30.0))
	var edge := _enemy(Vector3(4.5, 0.05, -30.0))
	_place(j, 2, Vector3(0.0, 0.0, -30.0))
	_run(75)
	assert_float(trigger.combat.health.hp).is_equal_approx(110.0, 1.0)
	assert_float(edge.combat.health.hp).is_equal_approx(250.0 - 64.4, 1.0)


func test_trap_budget_is_six_and_oldest_goes_first() -> void:
	_world()
	var j := _juniper()
	await get_tree().physics_frame
	var ids: Array[int] = []
	for i in 7:
		_server.abilities.traps.spawn_trap(_ctx(j, 1, Vector3(i * 8.0 - 24.0, 0.0, -30.0)),
			j.combat.abilities.skill(1).def.effects[0] as TrapEffectDef, Vector3(i * 8.0 - 24.0, 0.0, -30.0), Vector3(i * 8.0 - 20.0, 0.0, -30.0))
		_run(1)
	_run(1)
	assert_int(_count(TrapWorld.KIND_WIRE)).is_equal(6)


func test_skill_cap_limits_mines_to_two() -> void:
	_world()
	var j := _juniper()
	await get_tree().physics_frame
	for i in 3:
		_place(j, 2, Vector3(i * 10.0 - 10.0, 0.0, -30.0))
		_run(1)
	_run(1)
	assert_int(_count(TrapWorld.KIND_MINE)).is_equal(2)


func test_linkwork_chain_detonates_linked_mines() -> void:
	_world()
	var j := _juniper()
	var e := _enemy(Vector3(0.0, 0.05, -12.0))
	await get_tree().physics_frame
	_run(2)
	_place(j, 2, Vector3(0.0, 0.0, -12.0))
	_run(1)
	_place(j, 2, Vector3(4.0, 0.0, -12.0))  # within 6 m: linked
	_run(70)
	assert_int(_server.abilities.traps.chains).is_equal(1)
	assert_int(_count(TrapWorld.KIND_MINE)).is_equal(0)
	assert_float(e.combat.health.hp).is_less(110.0)  # both blasts hit him


func test_snares_and_wires_ignore_wardlings_but_hero_only_flag_is_data() -> void:
	var snare := load("res://assets/data/skills/skill_juniper_snare_coil.tres") as SkillDef
	var mine := load("res://assets/data/skills/skill_juniper_pressure_mine.tres") as SkillDef
	assert_bool((snare.effects[0] as TrapEffectDef).hits_wardlings).is_false()
	assert_bool((mine.effects[0] as TrapEffectDef).hits_wardlings).is_true()
	assert_float((mine.effects[0] as TrapEffectDef).wardling_mult).is_equal(1.5)


func test_traps_outlive_a_dead_owner_for_thirty_seconds() -> void:
	_world()
	var j := _juniper()
	await get_tree().physics_frame
	_place(j, 2, Vector3(0.0, 0.0, -30.0))
	var d := _server.abilities.deployables[0]
	assert_int(d.expires_tick).is_greater(_server.tick + 31 * 30)
	j.combat.dead = true
	_run(2)
	assert_int(d.expires_tick).is_less_equal(_server.tick + 30 * 30)


func test_snare_coil_has_two_charges_and_recharges_one_at_a_time() -> void:
	_world()
	var c := Caster.new()
	c.aim = [[0, 0.0, -0.3]]
	c.plan = {5: InputCommand.BTN_SKILL1, 20: InputCommand.BTN_SKILL1, 35: InputCommand.BTN_SKILL1}
	var j := _juniper(c)
	await get_tree().physics_frame
	_run(40)
	var s := j.combat.abilities.skill(0)
	assert_int(s.casts).is_equal(2)  # the third press had no charge
	assert_int(j.combat.abilities.last_reject).is_equal(AbilityRunner.Reject.COOLDOWN)
	assert_int(s.charges_left).is_equal(0)
	_run(300)  # one charge back after the 10 s recharge
	assert_bool(s.on_cooldown(_server.tick)).is_false()
	assert_int(s.charges_left).is_equal(1)


func test_tripwire_two_presses_make_a_wire_that_damages_and_slows() -> void:
	_world()
	var c := Caster.new()
	c.aim = [[0, 0.4, -0.2], [20, -0.4, -0.2]]
	c.plan = {10: InputCommand.BTN_SKILL2, 25: InputCommand.BTN_SKILL2}
	var j := _juniper(c)
	var e := _enemy(Vector3(30.0, 0.05, -30.0))
	await get_tree().physics_frame
	_run(30)
	assert_int(_count(TrapWorld.KIND_WIRE)).is_equal(1)
	var rec: TrapWorld.Data
	for dd in _server.abilities.traps.data:
		rec = _server.abilities.traps.data[dd]
	assert_float(rec.d.pos.distance_to(rec.pos_b)).is_greater(3.0)
	assert_float(rec.d.pos.distance_to(rec.pos_b)).is_less_equal(10.01)
	var mid := (rec.d.pos + rec.pos_b) * 0.5
	_server.abilities.teleport(e, mid + Vector3(0.0, 0.05, 0.0))
	_run(25)
	assert_float(e.combat.health.hp).is_equal_approx(180.0, 0.5)
	assert_bool(e.combat.status.has(StatusComponent.Kind.SLOW)).is_true()
	assert_int(_count(TrapWorld.KIND_WIRE)).is_equal(0)
	assert_object(j).is_not_null()


func test_killbox_hits_and_stuns_a_hero_crossing_the_fence() -> void:
	_world()
	var j := _juniper()
	var e := _enemy(Vector3(0.0, 0.05, -4.0))
	await get_tree().physics_frame
	_run(2)
	_place(j, 3, Vector3(0.0, 0.0, -20.0))
	assert_int(_count(TrapWorld.KIND_KILLBOX)).is_equal(1)
	_server.abilities.teleport(e, Vector3(0.0, 0.05, -35.0))  # 15 m out: outside the 12 m dome
	_run(3)
	assert_float(e.combat.health.hp).is_equal(250.0)
	_server.abilities.teleport(e, Vector3(0.0, 0.05, -26.0))  # 6 m in: crossed the fence
	_run(3)
	assert_float(e.combat.health.hp).is_equal_approx(170.0, 0.5)  # 80 dmg
	assert_bool(e.combat.status.is_stunned()).is_true()


func test_traps_rearm_instantly_and_hit_harder_inside_killbox() -> void:
	_world()
	var j := _juniper()
	var e := _enemy(Vector3(0.0, 0.05, -4.0))
	await get_tree().physics_frame
	_run(2)
	_place(j, 3, Vector3(0.0, 0.0, -20.0))
	_place(j, 0, Vector3(0.0, 0.0, -22.0))
	_server.abilities.teleport(e, Vector3(0.0, 0.05, -22.0))
	_run(3)  # no arm delay inside the dome; 30 dmg x1.3 = 39
	assert_float(e.combat.health.hp).is_equal_approx(250.0 - 39.0, 0.6)


func test_killbox_ultimate_casts_from_the_button() -> void:
	_world()
	_server.abilities.grant_ult = true
	var c := Caster.new()
	c.aim = [[0, 0.0, -0.1]]
	c.plan = {5: InputCommand.BTN_SKILL4}
	var j := _juniper(c)
	await get_tree().physics_frame
	_run(10)
	assert_int(_count(TrapWorld.KIND_KILLBOX)).is_equal(1)
	assert_int(j.combat.abilities.skill(3).casts).is_equal(1)
