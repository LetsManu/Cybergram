extends GdUnitTestSuite
## Hex's kit on a real ServerWorld (design/gdd/heroes.md §3.7, §4.7, §5.4):
## Malfunction categories and post-hack immunity, Breach Spike (gadget hack,
## hero damage + Scramble), Static Field, Relay Hop, Zero Day (ignores
## immunity, Lag) and the +50% weapon damage against gadgets.

const HEX := "res://assets/data/heroes/hero_hex.tres"
const JUNIPER := "res://assets/data/heroes/hero_juniper_quill.tres"
var _server: ServerWorld
var _link: LoopbackLink


class Caster extends ScriptedInputSource:
	var plan: Dictionary = {}
	var yaw: float = 0.0
	var pitch: float = 0.0

	func _init() -> void:
		super(CombatFixtures.idle_input())

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		out.yaw = yaw
		out.pitch = pitch
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
		load(HEX) as HeroDef, load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	_server.abilities.grant_ult = true


func _hex(src: Caster = null) -> HeroBody:
	var c := src if src != null else Caster.new()
	return _server.hero(_server.add_scripted_hero(c, Vector3(0.0, 0.05, 0.0), load(HEX) as HeroDef, ServerWorld.TEAM_PLAYERS))


## An enemy Juniper (owns gadgets); returns her.
func _juniper(at: Vector3) -> HeroBody:
	return _server.hero(_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()), at,
		load(JUNIPER) as HeroDef, ServerWorld.TEAM_DUMMIES))


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


func _enemy_mine(j: HeroBody, at: Vector3) -> AbilityWorld.Deployable:
	_ctx(j, 2, at).run(j.combat.abilities.skill(2).effects())
	return _server.abilities.deployables[-1]


func test_signal_sight_gives_hex_plus_fifty_percent_vs_gadgets() -> void:
	_world()
	var h := _hex()
	var j := _juniper(Vector3(0.0, 0.05, -30.0))
	await get_tree().physics_frame
	var m := _enemy_mine(j, Vector3(0.0, 0.0, -6.0))
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var dir := (m.pos + Vector3(0.0, 0.4, 0.0) - eye).normalized()
	var clip := _server.abilities.clip_shot(eye, dir, 15.0, h.combat.team)
	assert_object(clip[1]).is_same(m)
	var removed := _server.abilities.damage_deployable(clip[1], 10.0)
	assert_float(removed).is_equal_approx(15.0, 0.001)
	# Anyone else (the next hit with no shooter) takes plain damage.
	assert_float(_server.abilities.damage_deployable(m, 10.0)).is_equal_approx(10.0, 0.001)
	assert_float((load(HEX) as HeroDef).gadget_damage_mult).is_equal(1.5)


func test_malfunction_has_post_hack_immunity_but_ultimate_ignores_it() -> void:
	_world()
	var h := _hex()
	var j := _juniper(Vector3(0.0, 0.05, -30.0))
	await get_tree().physics_frame
	var m := _enemy_mine(j, Vector3(0.0, 0.0, -6.0))
	var tw := _server.abilities.traps
	assert_bool(tw.hack(m, 30, 120)).is_true()  # 1 s down, then 4 s immune
	assert_bool(tw.is_down(m)).is_true()
	_run(40)
	assert_bool(tw.is_down(m)).is_false()
	assert_bool(tw.hack(m, 30, 120)).is_false()  # immune
	assert_bool(tw.hack(m, 30, 120, true)).is_true()  # Zero Day / Static Field ignore it
	assert_object(h).is_not_null()


func test_breach_spike_hacks_a_trap_with_the_category_duration() -> void:
	_world()
	var c := Caster.new()
	var h := _hex(c)
	var j := _juniper(Vector3(0.0, 0.05, -30.0))
	await get_tree().physics_frame
	var m := _enemy_mine(j, Vector3(0.0, 0.0, -8.0))
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var aim := (m.pos + Vector3(0.0, 0.45, 0.0) - eye).normalized()
	c.pitch = asin(aim.y)
	c.plan = {3: InputCommand.BTN_SKILL1}
	_run(30)
	var tw := _server.abilities.traps
	assert_bool(tw.is_down(m)).is_true()
	# Trap category = 6 s (heroes.md §3.7), not the 3 s of a deployable.
	var left: int = int(tw.hacks[m][0]) - _server.tick
	assert_int(left).is_between(6 * 30 - 40, 6 * 30)
	assert_float(h.combat.abilities.skill(0).param(&"scramble")).is_equal(3.0)


func test_spike_on_an_enemy_hero_does_damage_and_scramble() -> void:
	_world()
	var h := _hex()
	var j := _juniper(Vector3(0.0, 0.05, -10.0))
	await get_tree().physics_frame
	_run(2)
	var ctx := _ctx(h, 0, j.state.position).with_target(j, j.state.position)
	(h.combat.abilities.skill(0).def.effects[0] as ProjectileEffectDef).on_hit[0].apply(ctx)
	assert_float(j.combat.health.hp).is_equal_approx(210.0, 0.5)
	assert_bool(_server.abilities.traps.is_scrambled(j)).is_true()


func test_boost_extends_malfunction_by_a_quarter() -> void:
	var s := SkillInstance.new(load("res://assets/data/skills/skill_hex_breach_spike.tres") as SkillDef, 0)
	assert_float(s.param(&"duration")).is_equal(1.0)
	s.learn(s.node_of(SkillNodeDef.Kind.BOOST))
	assert_float(s.param(&"duration")).is_equal(1.25)  # 6 s -> 7.5 s (heroes.md §5.4)
	assert_float(s.param(&"cooldown")).is_equal(8.0)


func test_static_field_keeps_enemy_gadgets_down_and_blocks_placing() -> void:
	_world()
	var h := _hex()
	var j := _juniper(Vector3(0.0, 0.05, -30.0))
	await get_tree().physics_frame
	var m := _enemy_mine(j, Vector3(0.0, 0.0, -10.0))
	_ctx(h, 1, Vector3(0.0, 0.0, -10.0)).run(h.combat.abilities.skill(1).effects())
	_run(5)
	assert_bool(_server.abilities.traps.is_down(m)).is_true()
	# No placing inside it.
	var before := _server.abilities.deployables.size()
	_ctx(j, 2, Vector3(1.0, 0.0, -10.0)).run(j.combat.abilities.skill(2).effects())
	assert_int(_server.abilities.deployables.size()).is_equal(before)
	_run(6 * 30 + 45)  # field expired; the linger is over
	assert_bool(_server.abilities.traps.is_down(m)).is_false()


func test_hacked_wall_does_not_block_shots() -> void:
	_world()
	var h := _hex()
	var b := _server.hero(_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		Vector3(0.0, 0.05, -20.0), CombatFixtures.brannoc(), ServerWorld.TEAM_DUMMIES))
	await get_tree().physics_frame
	_ctx(b, 0, Vector3(0.0, 0.0, -6.0)).run(b.combat.abilities.skill(0).effects())
	var wall: AbilityWorld.Deployable = _server.abilities.deployables[0]
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	assert_bool(_server.abilities.block_distance(eye, Vector3.FORWARD, 30.0, h.combat.team).is_empty()).is_false()
	_server.abilities.traps.hack(wall, 60, 120)
	assert_bool(_server.abilities.block_distance(eye, Vector3.FORWARD, 30.0, h.combat.team).is_empty()).is_true()


func test_zero_day_ignores_immunity_scrambles_and_lags_ready_skills() -> void:
	_world()
	var h := _hex()
	var j := _juniper(Vector3(0.0, 0.05, -10.0))
	await get_tree().physics_frame
	_run(2)
	var m := _enemy_mine(j, Vector3(0.0, 0.0, -12.0))
	var tw := _server.abilities.traps
	tw.hack(m, 5, 600)
	_run(10)  # the hack ended; 20 s of immunity remain
	assert_bool(tw.hack(m, 5, 0)).is_false()
	_ctx(h, 3, Vector3(0.0, 0.0, -10.0)).run(h.combat.abilities.skill(3).effects())
	assert_bool(tw.is_down(m)).is_true()
	assert_bool(tw.is_scrambled(j)).is_true()
	var lagged := j.combat.abilities.skill(1)  # Tripwire was ready: 3 s Lag
	assert_bool(lagged.on_cooldown(_server.tick)).is_true()
	assert_int(lagged.cooldown_ticks_left(_server.tick)).is_between(80, 90)
	assert_bool(j.combat.abilities.skill(3).on_cooldown(_server.tick)).is_false()  # ults untouched


func test_relay_hop_teleports_to_a_malfunctioning_enemy_gadget() -> void:
	_world()
	var c := Caster.new()
	var h := _hex(c)
	var j := _juniper(Vector3(0.0, 0.05, -30.0))
	await get_tree().physics_frame
	var m := _enemy_mine(j, Vector3(0.0, 0.0, -12.0))
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	c.pitch = asin(((m.pos + Vector3(0.0, 0.5, 0.0)) - eye).normalized().y)
	c.plan = {5: InputCommand.BTN_SKILL3}
	_run(15)
	assert_vector(h.state.position).is_equal_approx(Vector3(0.0, 0.05, 0.0), Vector3(0.5, 0.5, 0.5))  # healthy gadget: no hop
	assert_int(h.combat.abilities.last_reject).is_equal(AbilityRunner.Reject.NO_TARGET)
	_server.abilities.traps.hack(m, 300, 0)
	c.plan = {20: InputCommand.BTN_SKILL3}
	_run(40)  # 0.5 s channel
	assert_float(h.state.position.z).is_equal_approx(-12.0, 0.6)
