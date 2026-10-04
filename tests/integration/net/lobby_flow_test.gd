extends GdUnitTestSuite
## Online lobby (LoL-style flow on one server) over loopback: players join
## with their profile, sit in teams, pick heroes and ready up; after the
## countdown (and its locked final seconds) each gets a slot token, and joining
## the match with it lands them on their reserved team with their hero and
## name. Also: chat (sanitised, rate-limited), team switch, party seating,
## presence, reconnect, validation / rejection, and that the server keeps
## nothing about a player after they disconnect.

const DT := 1.0 / 30.0

var _link: LoopbackLink
var _net: NetConfig
var _reg: PresenceRegistry


func before_test() -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	_reg = PresenceRegistry.new()


func _step(server: LobbyServer, clients: Array, seconds: float) -> void:
	for i in maxi(1, roundi(seconds / DT)):
		_link.advance(_net.tick_dt())
		server.step(DT)
		for c: LobbyClient in clients:
			c.step()


func _hero(id: String) -> int:
	return ContentDB.shared().index_of(ContentDB.HERO, StringName(id))


func _client(peer: int, n: int, name: String, hero := &"hero_vesper_loom", party := "") -> LobbyClient:
	return LobbyClient.new(_link.create_endpoint(peer), ProfileFixtures.wire(n, name), _hero(hero), party)


func _lobby(team_size := 3) -> LobbyServer:
	return LobbyServer.new(_link.create_endpoint(1), team_size, _reg)


func test_teams_ready_countdown_tokens_and_reserved_join_with_name() -> void:
	var lobby := _lobby()
	var started: Array = []
	lobby.match_started.connect(func(slots: Array) -> void: started.append_array(slots))
	var a := _client(2, 1, "Ann")
	var b := _client(3, 2, "Bo Bee")
	var tokens := {}
	a.match_starting.connect(func(t: int, team: int, _h: int) -> void: tokens["a"] = [t, team])
	b.match_starting.connect(func(t: int, team: int, _h: int) -> void: tokens["b"] = [t, team])
	_step(lobby, [a, b], 0.3)
	# Smaller team first: one each side; both see names.
	assert_int(a.state.slots.size()).is_equal(2)
	assert_int(a.state.slots[0].team).is_equal(0)
	assert_int(a.state.slots[1].team).is_equal(1)
	assert_str(a.state.slots[1].name).is_equal("Bo Bee")
	assert_str(b.own_slot().name).is_equal("Bo Bee")
	# Only A ready: no countdown.
	a.pick(_hero(&"hero_vesper_loom"), true)
	_step(lobby, [a, b], 1.0)
	assert_int(lobby.phase).is_equal(LobbyCodec.PHASE_WAITING)
	# B picks Brannoc and readies: countdown, then the locked seconds, then the match.
	b.pick(_hero(&"hero_brannoc"), true)
	_step(lobby, [a, b], 0.3)
	assert_int(lobby.phase).is_equal(LobbyCodec.PHASE_COUNTDOWN)
	_step(lobby, [a, b], LobbyServer.COUNTDOWN_S - LobbyServer.LOCK_S)
	assert_int(lobby.phase).is_equal(LobbyCodec.PHASE_LOCKED)
	# Un-readying is ignored while locked.
	a.pick(_hero(&"hero_vesper_loom"), false)
	_step(lobby, [a, b], LobbyServer.LOCK_S + 0.5)
	assert_int(started.size()).is_equal(2)
	assert_bool(tokens.has("a") and tokens.has("b")).is_true()
	assert_int(tokens.b[1]).is_equal(1)
	assert_str(started[1].name).is_equal("Bo Bee")
	assert_int(_reg.status_of(ProfileFixtures.id(2), 0.0)).is_equal(LobbyCodec.STATUS_IN_MATCH)
	assert_int(lobby.history.size()).is_equal(0)  # chat is not kept beyond the lobby

	# The match: B joins with its token and gets its team, hero and name.
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
	# PLAYER_NAMES reached the client (scoreboard / kill feed names).
	assert_str(str(cw.session.player_names.get(cw.session.own_net_id, {}).get("name", ""))).is_equal("Bo Bee")
	# Leaving the match: the server forgets the player's name and presence.
	server.on_peer_left(2)
	assert_bool(server.session.names.has(h.net_id)).is_false()
	assert_bool(server.session.token_names.has(tokens.b[0])).is_false()
	assert_bool(_reg.entries.has(ProfileFixtures.id(2))).is_false()


func test_chat_is_sanitised_relayed_and_rate_limited() -> void:
	var lobby := _lobby()
	var a := _client(2, 1, "Ann")
	var b := _client(3, 2, "Bob")
	_step(lobby, [a, b], 0.3)
	a.chat.clear()
	b.chat.clear()
	a.say(("gl" + String.chr(0x200B) + "  hf\u0007 " + String.chr(0x202E) + "all"))
	_step(lobby, [a, b], 0.2)
	var lines := b.chat.filter(func(c: Dictionary) -> bool: return c.kind == LobbyCodec.CHAT_PLAYER)
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0].text).is_equal("gl hf all")
	assert_str(lines[0].name).is_equal("Ann")
	assert_str(lines[0].id).is_equal(ProfileFixtures.id(1))
	# Spam: 3 more fit the burst, the rest are dropped; only the sender is told.
	for i in 6:
		a.say("spam %d" % i)
	_step(lobby, [a, b], 0.2)
	var b_player := b.chat.filter(func(c: Dictionary) -> bool: return c.kind == LobbyCodec.CHAT_PLAYER)
	assert_int(b_player.size()).is_equal(ChatFilter.BURST)
	var slow := func(c: Dictionary) -> bool: return c.code == LobbyCodec.SYS_SLOW_DOWN
	assert_bool(a.chat.any(slow)).is_true()
	assert_bool(b.chat.any(slow)).is_false()
	# A late joiner gets the recent lines (replay buffer).
	var c := _client(4, 3, "Cyd")
	_step(lobby, [a, b, c], 0.2)
	assert_bool(c.chat.any(func(l: Dictionary) -> bool: return l.text == "gl hf all")).is_true()


func test_team_switch_party_and_full_team() -> void:
	var lobby := _lobby(2)
	var a := _client(2, 1, "Ann")
	var b := _client(3, 2, "Bob")
	_step(lobby, [a, b], 0.2)
	# C asks to sit with B (party): goes to B's team although team 0 is not smaller.
	var c := _client(4, 3, "Cyd", &"hero_vesper_loom", ProfileFixtures.id(2))
	_step(lobby, [a, b, c], 0.2)
	assert_int(c.own_slot().team).is_equal(1)
	# Team 1 is now full (2/2): A cannot switch, and is told so.
	a.pick(_hero(&"hero_vesper_loom"), true)
	a.switch_team(1)
	_step(lobby, [a, b, c], 0.2)
	assert_int(a.own_slot().team).is_equal(0)
	assert_bool(a.chat.any(func(l: Dictionary) -> bool: return l.code == LobbyCodec.SYS_TEAM_FULL)).is_true()
	# B switches to team 0 (room): allowed, and un-readies.
	b.pick(_hero(&"hero_brannoc"), true)
	_step(lobby, [a, b, c], 0.1)
	b.switch_team(0)
	_step(lobby, [a, b, c], 0.2)
	assert_int(b.own_slot().team).is_equal(0)
	assert_bool(b.own_slot().ready).is_false()
	assert_int(lobby.team_count(0)).is_equal(2)


func test_ready_player_cannot_change_hero() -> void:
	var lobby := _lobby()
	var a := _client(2, 1, "Ann")
	_step(lobby, [a], 0.2)
	a.pick(_hero(&"hero_vesper_loom"), true)
	_step(lobby, [a], 0.1)
	a.pick(_hero(&"hero_brannoc"), true)  # locked in: ignored
	_step(lobby, [a], 0.1)
	assert_int(a.own_slot().hero_index).is_equal(_hero(&"hero_vesper_loom"))


func test_presence_over_any_connection_and_name_lookup() -> void:
	var lobby := _lobby()
	var a := _client(2, 1, "Ann")
	_step(lobby, [a], 0.2)
	# A menu client (no lobby join) asks for Ann by id and "Bob" by name.
	var menu_t := _link.create_endpoint(5)
	var pc := PresenceClient.new(menu_t, ProfileFixtures.wire(9, "Zed"),
		PackedStringArray([ProfileFixtures.id(1)]), PackedStringArray(["ann"]))
	var got: Array = []
	pc.finished.connect(func(e: Array, ok: bool) -> void:
		if ok:
			got.append_array(e))
	for i in 10:
		_link.advance(_net.tick_dt())
		lobby.step(DT)
		pc.step(DT)
	assert_bool(pc.done).is_true()
	assert_int(got.size()).is_equal(1)  # by id and by name = the same player, once
	assert_int(got[0].status).is_equal(LobbyCodec.STATUS_IN_LOBBY)
	assert_str(got[0].name).is_equal("Ann")
	# The asker checked in as online (menu).
	assert_int(_reg.status_of(ProfileFixtures.id(9), PresenceRegistry.now_s())).is_equal(LobbyCodec.STATUS_ONLINE)
	# Lobby clients can ask too.
	var seen: Array = []
	a.presence_received.connect(func(e: Array) -> void: seen.append_array(e))
	a.query_presence(PackedStringArray([ProfileFixtures.id(9)]), PackedStringArray())
	_step(lobby, [a], 0.1)
	assert_int(seen.size()).is_equal(1)
	assert_int(seen[0].status).is_equal(LobbyCodec.STATUS_ONLINE)


func test_reconnect_keeps_seat_and_server_forgets_after_grace() -> void:
	var lobby := _lobby()
	var a := _client(2, 1, "Ann", &"hero_brannoc")
	var b := _client(3, 2, "Bob")
	_step(lobby, [a, b], 0.2)
	b.switch_team(0)
	_step(lobby, [a, b], 0.2)
	# B drops: the seat stays (team 0, Brannoc pick kept for A irrelevant), presence forgotten at once.
	lobby.on_peer_left(3)
	assert_bool(_reg.entries.has(ProfileFixtures.id(2))).is_false()
	assert_int(lobby.players.size()).is_equal(2)
	assert_bool(lobby.players[1].peer < 0).is_true()
	# A copied id with another key cannot take the held seat.
	var thief_wire := ProfileFixtures.wire(2, "Bob")
	thief_wire.key = ProfileFixtures.id(77)
	var thief := LobbyClient.new(_link.create_endpoint(6), thief_wire, 1)
	var thief_fail: Array = []
	thief.failed.connect(func(r: String) -> void: thief_fail.append(r))
	_step(lobby, [a, thief], 0.2)
	assert_array(thief_fail).contains_exactly(["HUD_LOBBY_REJECT_ID"])
	# The real B reconnects on a new connection: same seat, same team.
	var b2 := _client(7, 2, "Bob")
	_step(lobby, [a, b2], 0.2)
	assert_int(lobby.players.size()).is_equal(2)
	assert_int(b2.own_slot().team).is_equal(0)
	assert_bool(b2.own_slot().connected).is_true()
	# Both leave; after the grace the lobby holds nothing about anyone.
	lobby.on_peer_left(2)
	lobby.on_peer_left(7)
	_step(lobby, [], LobbyServer.RECONNECT_GRACE_S + 0.5)
	assert_int(lobby.players.size()).is_equal(0)
	assert_int(_reg.entries.size()).is_equal(0)


func test_disconnected_seat_does_not_block_start() -> void:
	var lobby := _lobby()
	var started: Array = []
	lobby.match_started.connect(func(slots: Array) -> void: started.append_array(slots))
	var a := _client(2, 1, "Ann")
	var b := _client(3, 2, "Bob")
	_step(lobby, [a, b], 0.2)
	lobby.on_peer_left(3)
	a.pick(_hero(&"hero_vesper_loom"), true)
	_step(lobby, [a], LobbyServer.COUNTDOWN_S + 0.5)
	assert_int(started.size()).is_equal(1)
	assert_str(started[0].name).is_equal("Ann")


func test_invalid_profile_old_version_and_garbage_rejected() -> void:
	var lobby := _lobby()
	var bad := LobbyClient.new(_link.create_endpoint(2), ProfileFixtures.wire(1, "<b>x</b>"), 1)
	var bad_fail: Array = []
	bad.failed.connect(func(r: String) -> void: bad_fail.append(r))
	var rude := LobbyClient.new(_link.create_endpoint(3), ProfileFixtures.wire(2, "TheAdmin"), 1)
	var rude_fail: Array = []
	rude.failed.connect(func(r: String) -> void: rude_fail.append(r))
	# A v10 client's 5-byte join.
	var old_t := _link.create_endpoint(4)
	old_t.send(1, Transport.CH_CONTROL, PackedByteArray([MsgType.LOBBY_JOIN, 10, 0, 1, 0]))
	# Garbage and an oversized packet from another peer.
	var junk_t := _link.create_endpoint(5)
	junk_t.send(1, Transport.CH_CONTROL, PackedByteArray([MsgType.LOBBY_JOIN, 1, 2]))
	var huge := PackedByteArray()
	huge.resize(LobbyCodec.MAX_C2S_BYTES + 10)
	huge.encode_u8(0, MsgType.LOBBY_CHAT_SEND)
	junk_t.send(1, Transport.CH_CONTROL, huge)
	junk_t.send(1, Transport.CH_CONTROL, PackedByteArray([99]))
	_step(lobby, [bad, rude], 0.2)
	old_t.poll()
	var old_reply := old_t.pop_packet()
	assert_array(bad_fail).contains_exactly(["HUD_LOBBY_REJECT_PROFILE"])
	assert_array(rude_fail).contains_exactly(["HUD_LOBBY_REJECT_PROFILE"])
	assert_object(old_reply).is_not_null()
	assert_int(ControlCodec.decode_reject(old_reply.data).reason).is_equal(MsgType.REJECT_PROTOCOL_MISMATCH)
	assert_int(lobby.players.size()).is_equal(0)
	assert_int(lobby._violations.get(5, 0)).is_equal(3)
	assert_int(_reg.entries.size()).is_equal(0)


func test_lobby_full_rejects_seventh_player() -> void:
	var lobby := _lobby(1)
	var a := _client(2, 1, "Ann")
	var b := _client(3, 2, "Bob")
	var c := _client(4, 3, "Cyd")
	var fail: Array = []
	c.failed.connect(func(r: String) -> void: fail.append(r))
	_step(lobby, [a, b, c], 0.2)
	assert_array(fail).contains_exactly(["HUD_LOBBY_REJECT_FULL"])
	assert_int(lobby.players.size()).is_equal(2)
	assert_bool(_reg.entries.has(ProfileFixtures.id(3))).is_false()  # a rejected joiner is not kept
