extends GdUnitTestSuite
## P2 social through AccountService.handle(): promote, kick, ready, party chat,
## direct messages, join requests, away / presence, OP_NOTIFY pushes, rate
## limits, and the edge cases: leader disconnect, stale / duplicate invites,
## simultaneous kick and leave, crash and rejoin, inviter leaves before
## accept, blocked-user invites, chat and DMs.

const DIR := "user://test_social_flow_store"
const DT := 1.0 / 30.0
const V := MsgType.PROTOCOL_VERSION


class FakeTransport:
	extends Transport
	var sent: Array = []

	func send(to_peer: int, _channel: int, data: PackedByteArray) -> void:
		sent.append([to_peer, AccountCodec.decode_result(data)])

	func peer_address(peer: int) -> String:
		return "198.51.100.%d" % peer

	func notes(peer: int, kind: int = -1) -> Array:
		var out: Array = []
		for e in sent:
			if e[0] == peer and int(e[1].get("op", -1)) == AccountCodec.OP_NOTIFY and (kind < 0 or int(e[1].kind) == kind):
				out.append(e[1])
		return out

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


func _three() -> Array:
	var s := _service()
	var t := FakeTransport.new()
	var a := _register(s, t, 2, "alice")
	var b := _register(s, t, 3, "bobby")
	var c := _register(s, t, 4, "carol")
	_friends(s, t, 2, 3, "bobby", a)
	_friends(s, t, 2, 4, "carol", a)
	return [s, t, a, b, c]


func _party_of_three(s: AccountService, t: FakeTransport, a: String, b: String, c: String) -> void:
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": b})
	_send(s, t, 3, AccountCodec.OP_PARTY_ACCEPT, {"id": a})
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": c})
	_send(s, t, 4, AccountCodec.OP_PARTY_ACCEPT, {"id": a})


func test_invite_and_friend_request_are_pushed() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": x[3]})
	var n := t.notes(3, AccountCodec.N_PARTY_INVITE)
	assert_int(n.size()).is_equal(1)
	assert_str(str(n[0].id)).is_equal(x[2])
	assert_str(str(n[0].name)).is_equal("Alice")
	var d := _register(s, t, 5, "dave")
	_send(s, t, 5, AccountCodec.OP_FRIEND_REQUEST, {"username": "alice", "id": ""})
	assert_int(t.notes(2, AccountCodec.N_FRIEND_REQUEST).size()).is_equal(1)


func test_promote_kick_and_ready() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	var a: String = x[2]
	var b: String = x[3]
	var c: String = x[4]
	_party_of_three(s, t, a, b, c)
	assert_int(int(_send(s, t, 3, AccountCodec.OP_PARTY_PROMOTE, {"id": c}).code)).is_equal(AccountCodec.E_NOT_FOUND)  # not the leader
	assert_int(int(_send(s, t, 3, AccountCodec.OP_PARTY_READY, {"ready": 1}).code)).is_equal(AccountCodec.OK)
	var p := _send(s, t, 2, AccountCodec.OP_PARTY)
	var flags := {}
	for m: Dictionary in p.members:
		flags[str(m.id)] = int(m.flags)
	assert_int(flags[b] & AccountCodec.PF_READY).is_equal(AccountCodec.PF_READY)
	assert_int(int(_send(s, t, 2, AccountCodec.OP_PARTY_PROMOTE, {"id": b}).code)).is_equal(AccountCodec.OK)
	assert_str(str(_send(s, t, 4, AccountCodec.OP_PARTY).leader)).is_equal(b)
	assert_bool(t.notes(4, AccountCodec.N_PARTY_CHANGED).any(func(n: Dictionary) -> bool: return n.text == "promoted")).is_true()
	assert_int(int(_send(s, t, 3, AccountCodec.OP_PARTY_KICK, {"id": c}).code)).is_equal(AccountCodec.OK)
	assert_int(t.notes(4, AccountCodec.N_KICKED).size()).is_equal(1)
	assert_str(str(_send(s, t, 4, AccountCodec.OP_PARTY).party)).is_equal(MatchmakingCodec.ID_ZERO)
	# Membership changed: everyone's ready flag is cleared.
	for m: Dictionary in _send(s, t, 2, AccountCodec.OP_PARTY).members:
		assert_int(int(m.flags)).is_equal(0)


func test_simultaneous_kick_and_leave_is_harmless() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	_party_of_three(s, t, x[2], x[3], x[4])
	_send(s, t, 4, AccountCodec.OP_PARTY_LEAVE)
	assert_int(int(_send(s, t, 2, AccountCodec.OP_PARTY_KICK, {"id": x[4]}).code)).is_equal(AccountCodec.E_NOT_FOUND)
	assert_int((_send(s, t, 2, AccountCodec.OP_PARTY).members as Array).size()).is_equal(2)


func test_stale_duplicate_and_expired_invites() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": x[3]})
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": x[3]})  # duplicate: one invite
	assert_int((_send(s, t, 3, AccountCodec.OP_PARTY).members as Array).size()).is_equal(1)
	s.step(s.online.party_invite_ttl_s + 1.0)
	assert_int(int(_send(s, t, 3, AccountCodec.OP_PARTY_ACCEPT, {"id": x[2]}).code)).is_equal(AccountCodec.E_NOT_FOUND)


func test_inviter_leaves_before_accept() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	var a: String = x[2]
	var b: String = x[3]
	var c: String = x[4]
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": b})
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": c})
	_send(s, t, 3, AccountCodec.OP_PARTY_ACCEPT, {"id": a})
	_send(s, t, 2, AccountCodec.OP_PARTY_LEAVE)  # alice leaves; bobby's party of one dissolves
	# carol's old invite from alice is gone: no joining a party alice no longer leads.
	assert_int(int(_send(s, t, 4, AccountCodec.OP_PARTY_ACCEPT, {"id": a}).code)).is_equal(AccountCodec.E_NOT_FOUND)


func test_blocked_users_cannot_invite_message_or_ask_to_join() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	var a: String = x[2]
	var b: String = x[3]
	_send(s, t, 3, AccountCodec.OP_BLOCK, {"id": a})  # bobby blocks alice (also unfriends)
	var before := t.notes(3).size()  # the friend request from the setup
	assert_int(int(_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": b}).code)).is_equal(AccountCodec.E_NOT_FOUND)
	assert_int(int(_send(s, t, 2, AccountCodec.OP_DM, {"id": b, "text": "hi"}).code)).is_equal(AccountCodec.E_NOT_FOUND)
	assert_int(int(_send(s, t, 2, AccountCodec.OP_PARTY_JOIN_REQUEST, {"id": b}).code)).is_equal(AccountCodec.E_NOT_FOUND)
	assert_int(t.notes(3).size()).is_equal(before)


func test_party_chat_reaches_members_sanitized_and_rate_limited() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	_party_of_three(s, t, x[2], x[3], x[4])
	assert_int(int(_send(s, t, 3, AccountCodec.OP_PARTY_CHAT, {"text": "  gl\u200b  hf  "}).code)).is_equal(AccountCodec.OK)
	var n := t.notes(4, AccountCodec.N_PARTY_CHAT)
	assert_int(n.size()).is_equal(1)
	assert_str(str(n[0].text)).is_equal("gl hf")
	assert_str(str(n[0].id)).is_equal(x[3])
	var refused := 0
	for i in 10:
		s.handle(t, 3, AccountCodec.encode_request(AccountCodec.OP_PARTY_CHAT, {"text": "spam %d" % i}))
		if int(t.last(3, AccountCodec.OP_PARTY_CHAT).code) == AccountCodec.E_RATE:
			refused += 1
	assert_int(refused).is_greater(0)
	assert_int(int(_send(s, t, 4, AccountCodec.OP_PARTY_CHAT, {"text": " \u202e "}).code)).is_equal(AccountCodec.E_BAD_REQUEST)


func test_dm_only_to_online_friends_and_never_stored() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	var b: String = x[3]
	assert_int(int(_send(s, t, 2, AccountCodec.OP_DM, {"id": b, "text": "hello"}).code)).is_equal(AccountCodec.OK)
	assert_str(str(t.notes(3, AccountCodec.N_DM)[0].text)).is_equal("hello")
	assert_int(int(_send(s, t, 3, AccountCodec.OP_DM, {"id": x[4], "text": "x"}).code)).is_equal(AccountCodec.E_NOT_FOUND)  # not friends
	s.on_disconnect(3)
	assert_int(int(_send(s, t, 2, AccountCodec.OP_DM, {"id": b, "text": "still there?"}).code)).is_equal(AccountCodec.E_NOT_FOUND)
	var export_json := str(_send(s, t, 2, AccountCodec.OP_EXPORT).json)
	assert_str(export_json).not_contains("hello")


func test_join_request_goes_to_the_party_leader() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	var a: String = x[2]
	var b: String = x[3]
	_send(s, t, 2, AccountCodec.OP_PARTY_INVITE, {"id": b})
	_send(s, t, 3, AccountCodec.OP_PARTY_ACCEPT, {"id": a})
	_friends(s, t, 3, 4, "carol", b)
	assert_int(int(_send(s, t, 4, AccountCodec.OP_PARTY_JOIN_REQUEST, {"id": b}).code)).is_equal(AccountCodec.OK)
	assert_int(t.notes(2, AccountCodec.N_JOIN_REQUEST).size()).is_equal(1)  # alice leads
	assert_int(t.notes(3, AccountCodec.N_JOIN_REQUEST).size()).is_equal(0)


func test_away_and_presence_from_the_front() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	var b: String = x[3]
	var c: String = x[4]
	s.presence_fn = func(id: String) -> Dictionary:
		if id == c:
			return {"status": LobbyCodec.STATUS_IN_QUEUE, "mode": 1}
		return {}
	_send(s, t, 3, AccountCodec.OP_SET_AWAY, {"away": 1})
	var st := {}
	for f: Dictionary in _send(s, t, 2, AccountCodec.OP_FRIENDS).friends:
		st[str(f.id)] = [int(f.status), int(f.mode)]
	assert_array(st[b]).is_equal([LobbyCodec.STATUS_AWAY, 255])
	assert_array(st[c]).is_equal([LobbyCodec.STATUS_IN_QUEUE, 1])
	_send(s, t, 3, AccountCodec.OP_SET_AWAY, {"away": 0})
	assert_int(s.status_of(b)).is_equal(LobbyCodec.STATUS_ONLINE)


func test_leader_disconnect_hands_over_and_crash_rejoin_keeps_the_party() -> void:
	var x := _three()
	var s: AccountService = x[0]
	var t: FakeTransport = x[1]
	var a: String = x[2]
	var b: String = x[3]
	var c: String = x[4]
	_party_of_three(s, t, a, b, c)
	# bobby crashes and comes back within the session grace: still in the party.
	var tok := ""
	for k in s.sessions:
		if s.sessions[k].identity.id == b:
			tok = k
	s.on_disconnect(3)
	s.step(1.0)
	_send(s, t, 7, AccountCodec.OP_RESUME, {"ver": V, "token": tok})
	assert_int((_send(s, t, 7, AccountCodec.OP_PARTY).members as Array).size()).is_equal(3)
	# alice (leader) disconnects for good: leadership moves on after the grace.
	s.on_disconnect(2)
	s.step(s.rules.session_grace_s + AccountService.PURGE_EVERY_S + 1.0)
	var p := _send(s, t, 4, AccountCodec.OP_PARTY)
	assert_int((p.members as Array).size()).is_equal(2)
	assert_str(str(p.leader)).is_not_equal(a)
