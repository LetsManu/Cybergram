extends GdUnitTestSuite
## Vesper Loom's kit driven by a client through the loopback (design/gdd/
## heroes.md §4.1): the ClientWorld's InputCommands carry the skill buttons,
## the server validates and executes, and the client sees the result.
## - Conductor: her squad mints at 3 + 2 = 5, with +15% HP.
## - Marionette Thread (Q): 40 damage and an instant 4 s squad Attack Target.
## - Rewrite (G, --grant-ult at level 1): after the 0.8 s cast every own
##   Wardling within 18 m is Elite (HP ×1.3, bolts ×1.214, gold) and the client
##   receives the Elite bit and the 120 s cooldown.

const HZ: int = 30
const THREAD_SEQ: int = 150
const REWRITE_SEQ: int = 300


## Client input: stands still, aims down -Z at a target `dist` m ahead, and
## presses Q / G on fixed client ticks.
class SkillScript extends RefCounted:
	var presses: Dictionary = {}
	var pitch: float = 0.0

	func sample(seq: int, out: InputCommand) -> void:
		out.seq = seq
		out.move = Vector2.ZERO
		out.yaw = 0.0
		out.pitch = pitch
		out.buttons = presses.get(seq, 0)
		out.squad_cmd = InputCommand.SQUAD_NONE
		out.quantize()


func test_vesper_skills_change_her_squad_through_the_loopback() -> void:
	var rules := WardlingFixtures.rules()
	var built := WardlingFixtures.slice_server(self, rules, false)
	var server: ServerWorld = built[0]
	var link: LoopbackLink = built[1]
	auto_free(built[3])
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server)).is_true()
	server.abilities.grant_ult = true
	var input := SkillScript.new()
	input.pitch = atan2(1.0 - 1.62, 10.0)
	input.presses = {THREAD_SEQ: InputCommand.BTN_SKILL1, REWRITE_SEQ: InputCommand.BTN_SKILL4}
	var client: ClientWorld = auto_free(ClientWorld.new())
	add_child(client)
	client.setup(server.net, load("res://assets/data/movement/movement_default.tres") as MovementDef,
		LookSettings.new(), WardlingFixtures.map_def().scene, link.create_endpoint(2), input, CombatFixtures.vesper())
	await get_tree().physics_frame
	var tick := func(n: int) -> void:
		for i in n:
			link.advance(server.net.tick_dt())
			client.session.poll()
			client.tick()
			server.step()
	tick.call(120)
	var me := server.hero(client.session.own_net_id)
	assert_object(me).is_not_null()
	# Conductor: squad cap 3 + 2, own Wardlings +15% HP (150 -> 172.5).
	var sq := server.wardlings.squad_of(me.net_id)
	assert_object(sq).is_not_null()
	assert_int(sq.size).is_equal(rules.squad_size + 2)
	assert_int(sq.members.size()).is_equal(5)
	for m in sq.members:
		assert_float(m.health.max_hp).is_equal_approx(150.0 * 1.15, 1e-3)
	# An enemy 10 m ahead for the thread.
	var target_id := server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		me.state.position + Vector3(0.0, 0.05, -10.0), HeroDef.new(), ServerWorld.TEAM_DUMMIES)
	var target := server.hero(target_id)
	var confirms: Array[GameEvent] = []
	client.hit_confirmed.connect(func(e: GameEvent) -> void: confirms.append(e))
	while client.client_seq < THREAD_SEQ + 12:
		tick.call(1)
	# The thread's 40 damage, confirmed to the caster's client (the squad's
	# bolts then add their own damage on top).
	assert_int(confirms.size()).is_greater_equal(1)
	assert_int(confirms[0].target_net_id).is_equal(target_id)
	assert_float(confirms[0].amount).is_equal_approx(40.0, 1e-3)
	assert_float(target.combat.health.hp).is_less_equal(250.0 - 40.0)
	assert_int(sq.command).is_equal(Squad.CMD_ATTACK)
	assert_int(sq.attack_target_id).is_equal(target_id)
	assert_int(sq.attack_expire_tick - sq.attack_start_tick).is_equal(4 * HZ)
	assert_int(client.combat.skill_cd_left[0]).is_greater(0)
	# The focus ends after 4 s and the squad reverts.
	tick.call(4 * HZ)
	assert_int(sq.command).is_equal(Squad.CMD_FOLLOW)
	# Rewrite: 0.8 s cast, then the whole squad (within 18 m) is Elite.
	while client.client_seq < REWRITE_SEQ + 2:
		tick.call(1)
	assert_bool(me.combat.abilities.is_casting()).is_true()
	for m in sq.members:
		assert_int(m.elite_until_tick).is_equal(-1)
	tick.call(roundi(0.8 * HZ) + 3)
	assert_bool(me.combat.abilities.is_casting()).is_false()
	var elite := 0
	for m in sq.members:
		if m.elite_until_tick > server.tick:
			elite += 1
			assert_float(m.health.max_hp).is_equal_approx(150.0 * 1.15 * 1.3, 1e-2)
			# Elite bolts ×1.214, and the +10% Conductor aura while she is within 15 m.
			var near := WardlingWorld._flat(m.global_position, me.state.position) <= 15.0
			assert_float(MinionmancerHooks.damage_mult(server.wardlings, m, server.tick)).is_equal_approx(
				rules.elite_damage_mult * (1.1 if near else 1.0), 1e-4)
	assert_int(elite).is_equal(5)
	# Replicated to the owner: Elite bits on the Wardlings, the ult's cooldown on the bar.
	tick.call(2)
	var seen := 0
	for m in sq.members:
		var st := client.wardlings.state(m.net_id)
		if st != null and (st.state & (1 << 6)) != 0:
			seen += 1
			assert_bool(client.wardlings.view(m.net_id).is_elite()).is_true()
	assert_int(seen).is_equal(5)
	assert_int(client.combat.skill_cd_total[3]).is_equal(120 * HZ)
	assert_int(client.combat.skill_cd_left[3]).is_greater(110 * HZ)
	assert_int(client.combat.skill_flags[3] & AbilityRunner.FLAG_LOCKED).is_equal(0)
	# Elite expires after 12 s and HP scales back.
	tick.call(12 * HZ)
	for m in sq.members:
		assert_int(m.elite_until_tick).is_equal(-1)
		assert_float(m.health.max_hp).is_equal_approx(150.0 * 1.15, 1e-2)
