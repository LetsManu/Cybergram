extends GdUnitTestSuite
## W15 party through AccountService.handle() (friends only, OP_PARTY state,
## accept, leave, cleanup when the sessions are gone) and the lobby seating
## party members on the same team.

const DIR := "user://test_party_flow_store"
const DT := 1.0 / 30.0
const V := MsgType.PROTOCOL_VERSION


class FakeTransport:
	extends Transport
	var sent: Array = []

	func send(to_peer: int, _channel: int, data: PackedByteArray) -> void:
		sent.append([to_peer, AccountCodec.decode_result(data)])

	func peer_address(peer: int) -> String:
		return "198.51.100.%d" % peer

	func last(peer: int, op: int) -> Dictionary:
		for i in range(sent.size() - 1, -1, -1):
			if sent[i][0] == peer and int(sent[i][1].get("op", -1)) == op:
				return sent[i][1]
		return {}


func before_test() -> void:
	_wipe()


func after_test() -> void:
	_wipe()


func _wipe() -> void:
	var d := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


func _service() -> AccountService:
	var st := FileAccountStore.new(DIR)
	st.open()
	var r := AuthRulesDef.new()
	r.pbkdf2_iterations = 1000
	var s := AccountService.new(st, r, true, PresenceRegistry.new())
	s.hasher.threaded = false
	return s


func _send(s: AccountService, t: FakeTransport, peer: int, op: int, f: Dictionary = {}) -> Dictionary:
	s.handle(t, peer, AccountCodec.encode_request(op, f))
	for i in 3:  # W21-N1: REGISTER / RECOVER chain more than one hash job
		s.step(DT)
	return t.last(peer, op)


func _register(s: AccountService, t: FakeTransport, peer: int, user: String) -> String:
	return str(_send(s, t, peer, AccountCodec.OP_REGISTER, {"ver": V, "username": user, "password": "correct horse",
		"display_name": user.capitalize(), "emblem": 1, "accent": 2, "flags": 3}).id)


func _friends(s: AccountService, t: FakeTransport, pa: int, pb: int, b_name: String, a_id: String) -> void:
	_send(s, t, pa, AccountCodec.OP_FRIEND_REQUEST, {"username": b_name, "id": ""})
	_send(s, t, pb, AccountCodec.OP_FRIEND_ACCEPT, {"id": a_id})


func test_party_between_friends() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var a := _register(s, t, 2, "alice")
	var b := _register(s, t, 3, "bobby")
	var c := _register(s, t, 4, "carol")
	assert_int(int(_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": b}).code)).is_equal(AccountCodec.E_NOT_FOUND)
	_friends(s, t, 2, 3, "bobby", a)
	assert_int(int(_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": b}).code)).is_equal(AccountCodec.OK)
	var pb := _send(s, t, 3, AccountCodec.OP_PARTY)
	assert_int(int(pb.members[0].kind)).is_equal(AccountCodec.PARTY_INVITE_IN)
	assert_str(str(pb.members[0].display_name)).is_equal("Alice")
	assert_int(int(_send(s, t, 3, AccountCodec.OP_PARTY_ACCEPT, {"id": a}).code)).is_equal(AccountCodec.OK)
	var pa := _send(s, t, 2, AccountCodec.OP_PARTY)
	assert_str(str(pa.leader)).is_equal(a)
	assert_int((pa.members as Array).size()).is_equal(2)
	assert_bool(MainMenu.should_join_party(pa)).is_true()
	# Not a friend of carol: cannot invite her.
	assert_int(int(_send(s, t, 3, AccountCodec.OP_PARTY_INVITE, {"id": c}).code)).is_equal(AccountCodec.E_NOT_FOUND)
	# The lobby seats bobby with alice's team.
	var lobby := LobbyServer.new(t, 3, PresenceRegistry.new(), s)
	var seat := LobbyServer.Player.new()
	seat.id = a
	seat.team = 1
	seat.peer = 2
	lobby.players.append(seat)
	assert_int(lobby._team_for_joiner("", b)).is_equal(1)
	assert_int(lobby._team_for_joiner("", c)).is_equal(0)


func test_party_ends_when_sessions_are_gone() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var a := _register(s, t, 2, "alice")
	var b := _register(s, t, 3, "bobby")
	_friends(s, t, 2, 3, "bobby", a)
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": b})
	_send(s, t, 3, AccountCodec.OP_PARTY_ACCEPT, {"id": a})
	s.on_disconnect(3)
	s.step(s.rules.session_grace_s + AccountService.PURGE_EVERY_S + 1.0)
	assert_str(str(_send(s, t, 2, AccountCodec.OP_PARTY).party)).is_equal("00000000000000000000000000000000")
	assert_dict(s.parties.parties).is_empty()


func test_leave() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var a := _register(s, t, 2, "alice")
	var b := _register(s, t, 3, "bobby")
	_friends(s, t, 2, 3, "bobby", a)
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": b})
	_send(s, t, 3, AccountCodec.OP_PARTY_ACCEPT, {"id": a})
	assert_int(int(_send(s, t, 2, AccountCodec.OP_PARTY_LEAVE).code)).is_equal(AccountCodec.OK)
	assert_array(_send(s, t, 3, AccountCodec.OP_PARTY).members).is_empty()
