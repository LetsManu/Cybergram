extends GdUnitTestSuite
## FileAccountStore (atomic write, reload, delete cascade, retention sweep)
## and AccountService over loopback (secure forced on: the DTLS path itself
## is covered by auth_dtls_flow_test): register, login, rate limit, friends,
## blocks, export, delete, guest switch, and "accounts need encryption".

const DIR := "user://test_auth_store"
const DT := 1.0 / 30.0

var _link: LoopbackLink
var _net: NetConfig


func before_test() -> void:
	_wipe()
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))


func after_test() -> void:
	_wipe()


func _wipe() -> void:
	var d := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


func _rules() -> AuthRulesDef:
	var r := AuthRulesDef.new()
	r.pbkdf2_iterations = 1000
	r.max_failures_per_account = 3
	return r


func _acct(id_n: int, name: String, now: int) -> Dictionary:
	return AccountStore.new_account(ProfileFixtures.id(id_n), name, {"algo": "x", "hash": "", "salt": "", "iterations": 1},
		{"display_name": name, "emblem": 0, "accent": 0, "favourite_hero": ""}, now)


func test_store_atomic_write_reload_and_no_tmp_left() -> void:
	var st := FileAccountStore.new(DIR)
	assert_int(st.open()).is_equal(OK)
	assert_bool(st.put(_acct(1, "alice", 100))).is_true()
	var d := ProjectSettings.globalize_path(DIR)
	assert_bool(FileAccess.file_exists(d.path_join(ProfileFixtures.id(1) + ".json"))).is_true()
	assert_bool(FileAccess.file_exists(d.path_join(ProfileFixtures.id(1) + ".json.tmp"))).is_false()
	# An interrupted write leaves a .tmp: reopening keeps the old file and drops the tmp.
	var f := FileAccess.open(d.path_join(ProfileFixtures.id(1) + ".json.tmp"), FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	var again := FileAccountStore.new(DIR)
	again.open()
	assert_str(again.find_username("ALICE").username).is_equal("alice")
	assert_bool(FileAccess.file_exists(d.path_join(ProfileFixtures.id(1) + ".json.tmp"))).is_false()
	# Only the account keys are accepted (no e-mail, no IP).
	var bad := _acct(2, "bob", 100)
	bad["email"] = "x@y"
	assert_bool(st.put(bad)).is_false()


func test_store_delete_cascades_into_other_accounts() -> void:
	var st := FileAccountStore.new(DIR)
	st.open()
	var a := _acct(1, "alice", 100)
	var b := _acct(2, "bobby", 100)
	var c := _acct(3, "carol", 100)
	a.friends = [b.id]
	b.friends = [a.id]
	c.requests_out = [a.id]
	a.requests_in = [c.id]
	b.blocks = [c.id]
	c.blocks = [a.id]
	for x in [a, b, c]:
		st.put(x)
	assert_bool(st.delete_cascade(a.id)).is_true()
	assert_dict(st.get_by_id(a.id)).is_empty()
	assert_array(st.get_by_id(b.id).friends).is_empty()
	assert_array(st.get_by_id(c.id).requests_out).is_empty()
	assert_array(st.get_by_id(c.id).blocks).is_empty()
	assert_array(st.get_by_id(b.id).blocks).contains_exactly([c.id])


func test_retention_sweep_deletes_inactive_accounts() -> void:
	var st := FileAccountStore.new(DIR)
	st.open()
	var now := 400 * 86400
	var old := _acct(1, "olduser", 0)
	var fresh := _acct(2, "fresh", now - 10 * 86400)
	fresh.friends = [old.id]
	st.put(old)
	st.put(fresh)
	var gone := st.sweep_inactive(now, 365)
	assert_array(Array(gone)).contains_exactly([old.id])
	assert_int(st.count()).is_equal(1)
	assert_array(st.get_by_id(fresh.id).friends).is_empty()


# --- service over loopback ----------------------------------------------------

func _service(secure := true) -> AccountService:
	var st := FileAccountStore.new(DIR)
	st.open()
	var s := AccountService.new(st, _rules(), secure, PresenceRegistry.new())
	s.hasher.threaded = false
	return s


func _pump(svc: AccountService, t: Transport, clients: Array, n := 4) -> void:
	for k in n:
		_link.advance(DT)
		t.poll()
		var pkt := t.pop_packet()
		while pkt != null:
			svc.handle(t, pkt.from_peer, pkt.data)
			pkt = t.pop_packet()
		svc.step(DT)
		for c: LobbyClient in clients:
			c.step()


func _register(c: LobbyClient, user: String, pw: String, flags := 3) -> void:
	c.request(AccountCodec.OP_REGISTER, {"ver": MsgType.PROTOCOL_VERSION, "username": user, "password": pw,
		"display_name": user.capitalize(), "emblem": 1, "accent": 2, "flags": flags})


func _last(c: LobbyClient, results: Array, op: int) -> Dictionary:
	for i in range(results.size() - 1, -1, -1):
		if results[i][0] == c and results[i][1].op == op:
			return results[i][1]
	return {}


func test_service_register_login_friends_export_delete() -> void:
	var svc := _service()
	var server := _link.create_endpoint(1)
	var a := LobbyClient.new(_link.create_endpoint(2))
	var b := LobbyClient.new(_link.create_endpoint(3))
	var res: Array = []
	a.account_result.connect(func(d: Dictionary) -> void: res.append([a, d]))
	b.account_result.connect(func(d: Dictionary) -> void: res.append([b, d]))
	# Consent and age are required.
	_register(a, "alice", "correct horse", AccountCodec.FLAG_PRIVACY)
	_pump(svc, server, [a, b])
	assert_int(_last(a, res, AccountCodec.OP_REGISTER).code).is_equal(AccountCodec.E_AGE)
	_register(a, "alice", "correct horse")
	_register(b, "bobby", "battery staple")
	_pump(svc, server, [a, b])
	assert_int(_last(a, res, AccountCodec.OP_REGISTER).code).is_equal(AccountCodec.OK)
	assert_str(a.session.username).is_equal("alice")
	assert_int(a.session.token.length()).is_equal(64)
	# Taken username.
	var c := LobbyClient.new(_link.create_endpoint(4))
	c.account_result.connect(func(d: Dictionary) -> void: res.append([c, d]))
	_register(c, "ALICE", "whatever123")
	_pump(svc, server, [a, b, c])
	assert_int(_last(c, res, AccountCodec.OP_REGISTER).code).is_equal(AccountCodec.E_NAME_TAKEN)
	# Friends: request, accept, presence.
	a.request(AccountCodec.OP_FRIEND_REQUEST, {"username": "bobby", "id": ""})
	_pump(svc, server, [a, b])
	b.request(AccountCodec.OP_FRIENDS)
	_pump(svc, server, [a, b])
	var bl: Array = _last(b, res, AccountCodec.OP_FRIENDS).friends
	assert_int(bl.size()).is_equal(1)
	assert_int(bl[0].relation).is_equal(AccountCodec.REL_INCOMING)
	b.request(AccountCodec.OP_FRIEND_ACCEPT, {"id": a.session.id})
	_pump(svc, server, [a, b])
	a.request(AccountCodec.OP_FRIENDS)
	_pump(svc, server, [a, b])
	var al: Array = _last(a, res, AccountCodec.OP_FRIENDS).friends
	assert_int(al[0].relation).is_equal(AccountCodec.REL_FRIEND)
	assert_int(al[0].status).is_equal(LobbyCodec.STATUS_ONLINE)
	assert_str(al[0].display_name).is_equal("Bobby")
	# Export: readable JSON without the hash or salt.
	a.request(AccountCodec.OP_EXPORT)
	_pump(svc, server, [a, b])
	var ex: Dictionary = JSON.parse_string(_last(a, res, AccountCodec.OP_EXPORT).json)
	assert_str(ex.username).is_equal("alice")
	assert_bool(ex.password.has("hash") or ex.password.has("salt")).is_false()
	assert_array(ex.friends).contains_exactly([b.session.id])
	# Delete needs the right password; then the friend's list is clean.
	a.request(AccountCodec.OP_DELETE_ACCOUNT, {"password": "wrong pass"})
	_pump(svc, server, [a, b])
	assert_int(_last(a, res, AccountCodec.OP_DELETE_ACCOUNT).code).is_equal(AccountCodec.E_CREDENTIALS)
	a.request(AccountCodec.OP_DELETE_ACCOUNT, {"password": "correct horse"})
	_pump(svc, server, [a, b])
	assert_int(_last(a, res, AccountCodec.OP_DELETE_ACCOUNT).code).is_equal(AccountCodec.OK)
	assert_dict(a.session).is_empty()
	b.request(AccountCodec.OP_FRIENDS)
	_pump(svc, server, [a, b])
	assert_array(_last(b, res, AccountCodec.OP_FRIENDS).friends).is_empty()
	assert_dict(svc.store.find_username("alice")).is_empty()


func test_service_login_rate_limit_and_session_resume() -> void:
	var svc := _service()
	var server := _link.create_endpoint(1)
	var a := LobbyClient.new(_link.create_endpoint(2))
	var res: Array = []
	a.account_result.connect(func(d: Dictionary) -> void: res.append([a, d]))
	_register(a, "alice", "correct horse")
	_pump(svc, server, [a])
	var token: String = a.session.token
	# A second connection logs in with wrong passwords until locked.
	var c := LobbyClient.new(_link.create_endpoint(5))
	c.account_result.connect(func(d: Dictionary) -> void: res.append([c, d]))
	for i in 3:
		c.request(AccountCodec.OP_LOGIN, {"ver": MsgType.PROTOCOL_VERSION, "username": "alice", "password": "nope nope"})
		_pump(svc, server, [a, c])
	c.request(AccountCodec.OP_LOGIN, {"ver": MsgType.PROTOCOL_VERSION, "username": "alice", "password": "correct horse"})
	_pump(svc, server, [a, c])
	assert_int(_last(c, res, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.E_LOCKED)
	# A disconnects; within the grace its token resumes on a new connection.
	svc.on_disconnect(2)
	var a2 := LobbyClient.new(_link.create_endpoint(6))
	a2.account_result.connect(func(d: Dictionary) -> void: res.append([a2, d]))
	a2.request(AccountCodec.OP_RESUME, {"ver": MsgType.PROTOCOL_VERSION, "token": token})
	_pump(svc, server, [a2])
	assert_int(_last(a2, res, AccountCodec.OP_RESUME).code).is_equal(AccountCodec.OK)
	# After the grace the token is gone (memory only).
	svc.on_disconnect(6)
	svc.step(_rules().session_grace_s + 1.0)
	assert_int(svc.sessions.size()).is_equal(0)


func test_accounts_refused_without_encryption_and_guest_switch() -> void:
	var svc := _service(false)
	var server := _link.create_endpoint(1)
	var a := LobbyClient.new(_link.create_endpoint(2))
	var res: Array = []
	a.account_result.connect(func(d: Dictionary) -> void: res.append([a, d]))
	_register(a, "alice", "correct horse")
	_pump(svc, server, [a])
	assert_int(_last(a, res, AccountCodec.OP_REGISTER).code).is_equal(AccountCodec.E_NOT_SECURE)
	assert_int(svc.store.count()).is_equal(0)
	# Guests: allowed here; refused when switched off on an encrypted server.
	a.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": "Visitor", "emblem": 0,
		"accent": 0, "flags": AccountCodec.FLAG_PRIVACY})
	_pump(svc, server, [a])
	assert_int(_last(a, res, AccountCodec.OP_GUEST).code).is_equal(AccountCodec.OK)
	var strict := _service(true)
	strict.allow_guests = false
	var b := LobbyClient.new(_link.create_endpoint(3))
	b.account_result.connect(func(d: Dictionary) -> void: res.append([b, d]))
	b.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": "Visitor", "emblem": 0,
		"accent": 0, "flags": AccountCodec.FLAG_PRIVACY})
	_pump(strict, server, [b])
	assert_int(_last(b, res, AccountCodec.OP_GUEST).code).is_equal(AccountCodec.E_GUESTS_OFF)


func test_malformed_account_request_rejected() -> void:
	assert_dict(AccountCodec.decode_request(PackedByteArray([MsgType.ACCOUNT_REQ, 99]))).is_empty()
	var b := AccountCodec.encode_request(AccountCodec.OP_LOGIN, {"ver": 12, "username": "alice", "password": "x"})
	assert_dict(AccountCodec.decode_request(b.slice(0, b.size() - 1))).is_empty()
	var longer := b.duplicate()
	longer.append(0)
	assert_dict(AccountCodec.decode_request(longer)).is_empty()
	var ok := AccountCodec.decode_request(b)
	assert_str(ok.username).is_equal("alice")
	var r := AccountCodec.decode_result(AccountCodec.encode_result(AccountCodec.OP_FRIENDS, AccountCodec.OK,
		{"friends": [{"id": ProfileFixtures.id(1), "status": 2, "relation": 0, "username": "a1b", "display_name": "A",
			"emblem": 1, "accent": 2}]}))
	assert_int(r.friends[0].status).is_equal(2)
