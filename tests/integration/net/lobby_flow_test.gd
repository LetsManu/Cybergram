extends GdUnitTestSuite
## Online lobby (LoL-style flow on one server) over loopback, with guest
## sessions (accounts over DTLS: auth_dtls_flow_test): players log in, sit in
## teams, pick heroes and ready up; after the countdown (and its locked final
## seconds) each gets a slot token, and joining the match with it lands them
## on their reserved team with their hero and name. Also: chat (sanitised,
## rate-limited), team switch, party seating, reconnect, validation /
## rejection, and that the server keeps nothing after a disconnect.

const DT := 1.0 / 30.0

var _link: LoopbackLink
var _net: NetConfig
var _reg: PresenceRegistry
var _acc: AccountService


func before_test() -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	_reg = PresenceRegistry.new()
	_acc = AccountService.new(null, AuthRulesDef.new(), false, _reg)


func _step(server: LobbyServer, clients: Array, seconds: float) -> void:
	for i in maxi(1, roundi(seconds / DT)):
		_link.advance(_net.tick_dt())
		server.step(DT)
		for c: LobbyClient in clients:
			c.step()


func _hero(id: String) -> int:
	return ContentDB.shared().index_of(ContentDB.HERO, StringName(id))


## A guest session on a new connection, then LOBBY_JOIN (same reliable channel, in order).
func _client(peer: int, name: String, hero := &"hero_vesper_loom", party := "", join := true) -> LobbyClient:
	var c := LobbyClient.new(_link.create_endpoint(peer))
	c.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": name, "emblem": peer % 12,
		"accent": peer % 10, "flags": AccountCodec.FLAG_PRIVACY})
	if join:
		c.join(_hero(hero), party)
	return c


func _lobby(team_size := 3) -> LobbyServer:
	return LobbyServer.new(_link.create_endpoint(1), team_size, _reg, _acc)


func test_teams_ready_countdown_tokens_and_reserved_join_with_name() -> void:
	var lobby := _lobby()
	var started: Array = []
	lobby.match_started.connect(func(slots: Array) -> void: started.append_array(slots))
	var a := _client(2, "Ann")
	var b := _client(3, "Bo Bee")
	var tokens := {}
	a.match_starting.connect(func(t: int, team: int, _h: int) -> void: tokens["a"] = [t, team])
	b.match_starting.connect(func(t: int, team: int, _h: int) -> void: tokens["b"] = [t, team])
	_step(lobby, [a, b], 0.3)
	assert_int(a.state.slots.size()).is_equal(2)
	assert_int(a.state.slots[0].team).is_equal(0)
	assert_int(a.state.slots[1].team).is_equal(1)
	assert_str(a.state.slots[1].name).is_equal("Bo Bee")
	assert_str(b.own_slot().id).is_equal(b.session.id)
	a.pick(_hero(&"hero_vesper_loom"), true)
	_step(lobby, [a, b], 1.0)
	assert_int(lobby.phase).is_equal(LobbyCodec.PHASE_WAITING)
	b.pick(_hero(&"hero_brannoc"), true)
	_step(lobby, [a, b], 0.3)
	assert_int(lobby.phase).is_equal(LobbyCodec.PHASE_COUNTDOWN)
	_step(lobby, [a, b], LobbyServer.COUNTDOWN_S - LobbyServer.LOCK_S)
	assert_int(lobby.phase).is_equal(LobbyCodec.PHASE_LOCKED)
	a.pick(_hero(&"hero_vesper_loom"), false)  # ignored while locked
	_step(lobby, [a, b], LobbyServer.LOCK_S + 0.5)
	assert_int(started.size()).is_equal(2)
	assert_bool(tokens.has("a") and tokens.has("b")).is_true()
	assert_int(tokens.b[1]).is_equal(1)
	assert_str(started[1].name).is_equal("Bo Bee")
	assert_int(_reg.status_of(b.session.id, 0.0)).is_equal(LobbyCodec.STATUS_IN_MATCH)
	assert_int(lobby.history.size()).is_equal(0)  # chat is not kept beyond the lobby

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	var server := ServerWorld.new()
	vp.add_child(server)
	var link2 := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	server.setup(_net, MovementDef.new(), CombatFixtures.range_scene(false), link2.create_endpoint(1),
		CombatFixtures.vesper(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	server.session.registry = _reg
	server.session.accounts = _acc
	for sl: Dictionary in started:
		server.reserved_slots[sl.token] = {"team": sl.team, "hero_index": sl.hero_index}
		server.session.token_names[sl.token] = {"name": sl.name, "id": sl.id, "accent": sl.accent}
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
	assert_str(str(cw.session.player_names.get(cw.session.own_net_id, {}).get("name", ""))).is_equal("Bo Bee")
	server.on_peer_left(2)
	assert_bool(server.session.names.has(h.net_id)).is_false()
	assert_bool(server.session.token_names.has(tokens.b[0])).is_false()
	assert_bool(_reg.entries.has(b.session.id)).is_false()


func test_chat_is_sanitised_relayed_and_rate_limited() -> void:
	var lobby := _lobby()
	var a := _client(2, "Ann")
	var b := _client(3, "Bob")
	_step(lobby, [a, b], 0.3)
	a.chat.clear()
	b.chat.clear()
	a.say(("gl" + String.chr(0x200B) + "  hf\u0007 " + String.chr(0x202E) + "all"))
	_step(lobby, [a, b], 0.2)
	var lines := b.chat.filter(func(c: Dictionary) -> bool: return c.kind == LobbyCodec.CHAT_PLAYER)
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0].text).is_equal("gl hf all")
	assert_str(lines[0].name).is_equal("Ann")
	assert_str(lines[0].id).is_equal(a.session.id)
	for i in 6:
		a.say("spam %d" % i)
	_step(lobby, [a, b], 0.2)
	var b_player := b.chat.filter(func(c: Dictionary) -> bool: return c.kind == LobbyCodec.CHAT_PLAYER)
	assert_int(b_player.size()).is_equal(ChatFilter.BURST)
	var slow := func(c: Dictionary) -> bool: return c.code == LobbyCodec.SYS_SLOW_DOWN
	assert_bool(a.chat.any(slow)).is_true()
	assert_bool(b.chat.any(slow)).is_false()
	var c := _client(4, "Cyd")
	_step(lobby, [a, b, c], 0.2)
	assert_bool(c.chat.any(func(l: Dictionary) -> bool: return l.text == "gl hf all")).is_true()


func test_team_switch_party_and_full_team() -> void:
	var lobby := _lobby(2)
	var a := _client(2, "Ann")
	var b := _client(3, "Bob")
	_step(lobby, [a, b], 0.2)
	var c := _client(4, "Cyd", &"hero_vesper_loom", b.session.id)
	_step(lobby, [a, b, c], 0.2)
	assert_int(c.own_slot().team).is_equal(1)
	a.pick(_hero(&"hero_vesper_loom"), true)
	a.switch_team(1)
	_step(lobby, [a, b, c], 0.2)
	assert_int(a.own_slot().team).is_equal(0)
	assert_bool(a.chat.any(func(l: Dictionary) -> bool: return l.code == LobbyCodec.SYS_TEAM_FULL)).is_true()
	b.pick(_hero(&"hero_brannoc"), true)
	_step(lobby, [a, b, c], 0.1)
	b.switch_team(0)
	_step(lobby, [a, b, c], 0.2)
	assert_int(b.own_slot().team).is_equal(0)
	assert_bool(b.own_slot().ready).is_false()
	assert_int(lobby.team_count(0)).is_equal(2)


func test_ready_player_cannot_change_hero() -> void:
	var lobby := _lobby()
	var a := _client(2, "Ann")
	_step(lobby, [a], 0.2)
	a.pick(_hero(&"hero_vesper_loom"), true)
	_step(lobby, [a], 0.1)
	a.pick(_hero(&"hero_brannoc"), true)
	_step(lobby, [a], 0.1)
	assert_int(a.own_slot().hero_index).is_equal(_hero(&"hero_vesper_loom"))


func test_reconnect_resumes_session_and_seat_then_server_forgets() -> void:
	var lobby := _lobby()
	var a := _client(2, "Ann", &"hero_brannoc")
	var b := _client(3, "Bob")
	_step(lobby, [a, b], 0.2)
	b.switch_team(0)
	_step(lobby, [a, b], 0.2)
	var token: String = b.session.token
	var bid: String = b.session.id
	lobby.on_peer_left(3)
	assert_bool(_reg.entries.has(bid)).is_false()
	assert_bool(lobby.players[1].peer < 0).is_true()
	# B comes back on a new connection with its in-memory token: same seat.
	var b2 := LobbyClient.new(_link.create_endpoint(7))
	b2.request(AccountCodec.OP_RESUME, {"ver": MsgType.PROTOCOL_VERSION, "token": token})
	b2.join(_hero(&"hero_vesper_loom"))
	_step(lobby, [a, b2], 0.2)
	assert_int(lobby.players.size()).is_equal(2)
	assert_str(b2.own_slot().id).is_equal(bid)
	assert_int(b2.own_slot().team).is_equal(0)
	lobby.on_peer_left(2)
	lobby.on_peer_left(7)
	_step(lobby, [], LobbyServer.RECONNECT_GRACE_S + 0.5)
	assert_int(lobby.players.size()).is_equal(0)
	assert_int(_reg.entries.size()).is_equal(0)
	_acc.step(AuthRulesDef.new().session_grace_s + 1.0)
	assert_int(_acc.sessions.size()).is_equal(0)
	assert_int(_acc.peers.size()).is_equal(0)


func test_disconnected_seat_does_not_block_start() -> void:
	var lobby := _lobby()
	var started: Array = []
	lobby.match_started.connect(func(slots: Array) -> void: started.append_array(slots))
	var a := _client(2, "Ann")
	var b := _client(3, "Bob")
	_step(lobby, [a, b], 0.2)
	lobby.on_peer_left(3)
	a.pick(_hero(&"hero_vesper_loom"), true)
	_step(lobby, [a], LobbyServer.COUNTDOWN_S + 0.5)
	assert_int(started.size()).is_equal(1)
	assert_str(started[0].name).is_equal("Ann")


func test_join_without_session_bad_name_old_version_and_garbage_rejected() -> void:
	var lobby := _lobby()
	var anon := LobbyClient.new(_link.create_endpoint(2))
	var anon_fail: Array = []
	anon.failed.connect(func(r: String) -> void: anon_fail.append(r))
	anon.join(1)
	var rude := _client(3, "TheAdmin")
	var rude_res: Array = []
	rude.account_result.connect(func(d: Dictionary) -> void: rude_res.append(d.code))
	var old_t := _link.create_endpoint(4)
	old_t.send(1, Transport.CH_CONTROL, PackedByteArray([MsgType.LOBBY_JOIN, 10, 0, 1, 0]))
	var junk_t := _link.create_endpoint(5)
	junk_t.send(1, Transport.CH_CONTROL, PackedByteArray([MsgType.LOBBY_JOIN, 1]))
	var huge := PackedByteArray()
	huge.resize(LobbyCodec.MAX_C2S_BYTES + 10)
	huge.encode_u8(0, MsgType.LOBBY_CHAT_SEND)
	junk_t.send(1, Transport.CH_CONTROL, huge)
	junk_t.send(1, Transport.CH_CONTROL, PackedByteArray([99]))
	_step(lobby, [anon, rude], 0.2)
	old_t.poll()
	var old_reply := old_t.pop_packet()
	assert_array(anon_fail).contains_exactly(["HUD_LOBBY_REJECT_LOGIN"])
	assert_array(rude_res).contains_exactly([AccountCodec.E_BAD_NAME])
	assert_object(old_reply).is_not_null()
	assert_int(ControlCodec.decode_reject(old_reply.data).reason).is_equal(MsgType.REJECT_PROTOCOL_MISMATCH)
	assert_int(lobby.players.size()).is_equal(0)
	assert_int(lobby._violations.get(5, 0)).is_equal(3)
	assert_int(_reg.entries.size()).is_equal(0)


func test_lobby_full_rejects_extra_player() -> void:
	var lobby := _lobby(1)
	var a := _client(2, "Ann")
	var b := _client(3, "Bob")
	var c := _client(4, "Cyd")
	var fail: Array = []
	c.failed.connect(func(r: String) -> void: fail.append(r))
	_step(lobby, [a, b, c], 0.2)
	assert_array(fail).contains_exactly(["HUD_LOBBY_REJECT_FULL"])
	assert_int(lobby.players.size()).is_equal(2)
	assert_bool(_reg.entries.has(c.session.id)).is_false()  # a rejected joiner is not kept
