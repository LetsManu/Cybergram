extends GdUnitTestSuite
## E4/E5 integration: a client shoots a dummy through the loopback server until
## it dies and respawns, with health replicated; server-side occlusion and the
## team filter for scripted (bot-style) shooters.

const HZ: int = 30

var _server: ServerWorld
var _client: ClientWorld
var _link: LoopbackLink
var _net: NetConfig


func _server_world(scene: PackedScene, hero: HeroDef) -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(_net, MovementDef.new(), scene, _link.create_endpoint(1), hero,
		load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)


func _tick(n: int) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		if _client != null:
			_client.session.poll()
			_client.tick()
		_server.step()


func test_client_kills_dummy_which_respawns_with_replicated_health() -> void:
	var scene := CombatFixtures.range_scene(false)
	var vesper := CombatFixtures.vesper()
	_server_world(scene, vesper)
	var dummy_id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1"), vesper)
	_client = auto_free(ClientWorld.new())
	add_child(_client)
	_client.setup(_net, MovementDef.new(), LookSettings.new(), scene, _link.create_endpoint(2),
		ScriptedInputSource.new(CombatFixtures.shooter_input(8.0, 2)), vesper)
	await get_tree().physics_frame
	# Record what the CLIENT sees of the dummy, and the server's death/respawn ticks.
	var seen := {"hp": [], "dead": []}
	_client.session.snapshot_received.connect(func(s: SnapshotData) -> void:
		for e in s.entities:
			if e.net_id == dummy_id:
				seen.hp.append(e.hp)
				seen.dead.append(e.dead))
	var hits: Array[GameEvent] = []
	_client.hit_confirmed.connect(func(e: GameEvent) -> void: hits.append(e))
	var kills: Array[GameEvent] = []
	_client.kill_received.connect(func(e: GameEvent) -> void: kills.append(e))
	var server_ticks := {}
	_server.hero_died.connect(func(_v: int, _k: int) -> void:
		if not server_ticks.has("died"):
			server_ticks.died = _server.tick)
	_server.hero_respawned.connect(func(_id: int) -> void:
		if not server_ticks.has("respawned"):
			server_ticks.respawned = _server.tick)

	# ~160 ticks to the kill, then the C11 timer of the rules under test (the
	# slice's coefficients are E14 slice tuning: design/balance/slice-tuning.md).
	_tick(160 + RespawnSystem.respawn_ticks(_server.rules, 160, HZ))

	# Died to 9 Threadcaster body shots (250 / 29), reported to the shooter.
	assert_bool(server_ticks.has("died")).is_true()
	var to_kill := 0.0
	var kill_hit := -1
	for i in hits.size():
		to_kill += hits[i].amount
		assert_int(hits[i].target_net_id).is_equal(dummy_id)
		if (hits[i].flags & GameEvent.FLAG_KILL) != 0:
			kill_hit = i
			break
	assert_int(kill_hit).is_equal(8)
	assert_float(to_kill).is_equal_approx(250.0, 1e-3)
	assert_int(kills.size()).is_greater_equal(1)
	assert_int(kills[0].target_net_id).is_equal(dummy_id)
	assert_int(kills[0].source_net_id).is_equal(_client.session.own_net_id)
	# Respawn after exactly the C11 timer, at its spawn point, at full health.
	assert_bool(server_ticks.has("respawned")).is_true()
	assert_int(server_ticks.respawned - server_ticks.died).is_equal(
		RespawnSystem.respawn_ticks(_server.rules, server_ticks.died, HZ))
	# Client-side view of the dummy: health falls, it dies, it comes back at full HP.
	var first_dead: int = seen.dead.find(true)
	assert_int(first_dead).is_greater(0)
	assert_int(seen.hp[first_dead]).is_equal(0)
	assert_int(seen.hp[0]).is_equal(250)
	assert_int(seen.hp[first_dead - 1]).is_less(250)
	var back: int = seen.dead.find(false, first_dead)
	assert_int(back).is_greater(first_dead)
	assert_int(seen.hp[back]).is_equal(250)
	assert_int(back - first_dead).is_between(
		RespawnSystem.respawn_ticks(_server.rules, server_ticks.died, HZ) - 1,
		RespawnSystem.respawn_ticks(_server.rules, server_ticks.died, HZ) + 1)
	# Own feed replicated to the owner (mana spent by the volley).
	assert_object(_client.combat).is_not_null()
	assert_int(_client.combat.feed_kind).is_equal(WeaponDef.FeedKind.MANA)
	assert_int(_client.combat.ammo_capacity).is_equal(100)
	assert_float(_client.combat.ammo).is_less(100.0)
	assert_int(_client.combat.hp).is_equal(250)
	# Shooting did not disturb movement prediction.
	assert_int(_client.predictor.corrections).is_equal(0)


func test_wall_blocks_hitscan() -> void:
	var brannoc := CombatFixtures.brannoc()
	_server_world(CombatFixtures.range_scene(true), brannoc)
	var target := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1"), CombatFixtures.vesper(), ServerWorld.TEAM_DUMMIES)
	var shooter := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.shooter_input(8.0, 1)),
		_server.spawn_point("PlayerSpawn"), brannoc, ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	_tick(90)
	assert_int(_server.hero(shooter).combat.weapon.shots_fired).is_greater_equal(3)
	assert_float(_server.hero(target).combat.health.hp).is_equal(250.0)


func test_shots_pass_allies_and_hit_the_enemy_behind() -> void:
	# No friendly fire (weapons-and-mods.md §3.1 rule 5): an ally 8 m ahead takes
	# nothing, and does not shield the enemy 3 m behind it.
	var brannoc := CombatFixtures.brannoc()
	_server_world(CombatFixtures.range_scene(false), brannoc)
	var ally := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1"), CombatFixtures.vesper(), ServerWorld.TEAM_PLAYERS)
	var enemy := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1") + Vector3(0.0, 0.0, -3.0), CombatFixtures.vesper(),
		ServerWorld.TEAM_DUMMIES)
	_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.shooter_input(11.0, 1)),
		_server.spawn_point("PlayerSpawn"), brannoc, ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	_tick(60)
	assert_float(_server.hero(ally).combat.health.hp).is_equal(250.0)
	assert_float(_server.hero(enemy).combat.health.hp).is_less(250.0)
