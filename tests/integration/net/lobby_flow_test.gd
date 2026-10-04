extends GdUnitTestSuite
## Online lobby (LoL-style flow on one server): players join, are balanced
## into teams by join order, pick heroes and ready up; after the countdown each
## gets a slot token, and joining the match with it lands them on their
## reserved team with their picked hero.

const DT := 1.0 / 30.0

var _link: LoopbackLink
var _net: NetConfig


func _step(server: LobbyServer, clients: Array, seconds: float) -> void:
	for i in roundi(seconds / DT):
		_link.advance(_net.tick_dt())
		server.step(DT)
		for c: LobbyClient in clients:
			c.step()


func _hero(id: String) -> int:
	return ContentDB.shared().index_of(ContentDB.HERO, StringName(id))


func test_teams_ready_countdown_tokens_and_reserved_join() -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var lobby := LobbyServer.new(_link.create_endpoint(1), 3)
	var started: Array = []
	lobby.match_started.connect(func(slots: Array) -> void: started.append_array(slots))
	var a := LobbyClient.new(_link.create_endpoint(2), _hero(&"hero_vesper_loom"))
	var b := LobbyClient.new(_link.create_endpoint(3), _hero(&"hero_vesper_loom"))
	var tokens := {}
	a.match_starting.connect(func(t: int, team: int, _h: int) -> void: tokens["a"] = [t, team])
	b.match_starting.connect(func(t: int, team: int, _h: int) -> void: tokens["b"] = [t, team])
	_step(lobby, [a, b], 0.3)
	# Join order alternates teams; both see two players.
	assert_int(a.state.slots.size()).is_equal(2)
	assert_int(a.state.slots[0].team).is_equal(0)
	assert_int(a.state.slots[1].team).is_equal(1)
	# Only A ready: no countdown.
	a.pick(_hero(&"hero_vesper_loom"), true)
	_step(lobby, [a, b], 1.0)
	assert_int(lobby.phase).is_equal(LobbyCodec.PHASE_WAITING)
	# B picks Brannoc and readies: countdown, then the match starts.
	b.pick(_hero(&"hero_brannoc"), true)
	_step(lobby, [a, b], 0.3)
	assert_int(lobby.phase).is_equal(LobbyCodec.PHASE_COUNTDOWN)
	_step(lobby, [a, b], LobbyServer.COUNTDOWN_S + 0.5)
	assert_int(started.size()).is_equal(2)
	assert_bool(tokens.has("a") and tokens.has("b")).is_true()
	assert_int(tokens.b[1]).is_equal(1)

	# The match: B joins with its token and gets its team + hero.
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	var server := ServerWorld.new()
	vp.add_child(server)
	var link2 := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	server.setup(_net, MovementDef.new(), CombatFixtures.range_scene(false), link2.create_endpoint(1),
		CombatFixtures.vesper(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	for sl: Dictionary in started:
		server.reserved_slots[sl.token] = {"team": sl.team, "hero_index": sl.hero_index}
	assert_array(server.reserved_per_team()).contains_exactly([1, 1])
	var cw := ClientWorld.new()
	cw.hello_token = tokens.b[0]
	add_child(auto_free(cw))
	cw.setup(_net, MovementDef.new(), LookSettings.new(), CombatFixtures.range_scene(false),
		link2.create_endpoint(2), ScriptedInputSource.new(CombatFixtures.idle_input()),
		load("res://assets/data/heroes/hero_brannoc.tres") as HeroDef)
	await get_tree().physics_frame
	for i in 6:
		link2.advance(_net.tick_dt())
		cw.session.poll()
		cw.tick()
		server.step()
	var h := server.hero(cw.session.own_net_id)
	assert_int(h.combat.team).is_equal(1)
	assert_str(h.combat.def.resource_path).ends_with("hero_brannoc.tres")
	assert_bool(server.reserved_slots.has(tokens.b[0])).is_false()
