extends GdUnitTestSuite
## W21-N1 password recovery over loopback (secure forced on): the recovery
## code from REGISTER, RECOVER (right / wrong / used code, rate limit, same
## answer for an unknown user), RECOVERY_CODE (needs the password),
## RECOVERY_INFO, the export without the code hash, the host reset picked up
## by a running service, and the relog fix for passwords longer than
## password_max.

const DIR := "user://test_auth_recovery"
const ADMIN := "user://test_auth_recovery_admin"
const DT := 1.0 / 30.0
const PW := "correct horse"
const NEW_PW := "battery staple 2"

var _link: LoopbackLink
var _res: Array = []


func before_test() -> void:
	_wipe(DIR)
	_wipe(ADMIN)
	_res = []
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))


func after_test() -> void:
	_wipe(DIR)
	_wipe(ADMIN)


func _wipe(dir: String) -> void:
	var d := ProjectSettings.globalize_path(dir)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


func _rules() -> AuthRulesDef:
	var r := AuthRulesDef.new()
	r.pbkdf2_iterations = 1000
	r.max_failures_per_account = 3
	r.admin_poll_s = 1.0
	return r


func _service() -> AccountService:
	var st := FileAccountStore.new(DIR)
	st.open()
	var s := AccountService.new(st, _rules(), true, PresenceRegistry.new())
	s.hasher.threaded = false
	return s


func _client(peer: int) -> LobbyClient:
	var c := LobbyClient.new(_link.create_endpoint(peer))
	c.account_result.connect(func(d: Dictionary) -> void: _res.append([c, d]))
	return c


## Enough rounds for the chained hash stages (register: 2, recover: 3).
func _pump(svc: AccountService, t: Transport, clients: Array, n := 8) -> void:
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


func _last(c: LobbyClient, op: int) -> Dictionary:
	for i in range(_res.size() - 1, -1, -1):
		if _res[i][0] == c and _res[i][1].op == op:
			return _res[i][1]
	return {}


func _register(c: LobbyClient, user: String, pw: String) -> void:
	c.request(AccountCodec.OP_REGISTER, {"ver": MsgType.PROTOCOL_VERSION, "username": user, "password": pw,
		"display_name": user.capitalize(), "emblem": 1, "accent": 2, "flags": 3})


func _login(c: LobbyClient, user: String, pw: String) -> void:
	c.request(AccountCodec.OP_LOGIN, {"ver": MsgType.PROTOCOL_VERSION, "username": user, "password": pw})


func _recover(c: LobbyClient, user: String, code: String, pw: String) -> void:
	c.request(AccountCodec.OP_RECOVER, {"ver": MsgType.PROTOCOL_VERSION, "username": user, "code": code,
		"new_password": pw})


func test_register_returns_a_code_once_and_stores_only_its_hash() -> void:
	var svc := _service()
	var server := _link.create_endpoint(1)
	var a := _client(2)
	_register(a, "alice", PW)
	_pump(svc, server, [a])
	var r := _last(a, AccountCodec.OP_REGISTER)
	assert_int(r.code).is_equal(AccountCodec.OK)
	var code := str(r.recovery_code)
	assert_int(code.length()).is_equal(23)  # 4 x 5 + 3 dashes
	assert_str(RecoveryCode.normalize(code, _rules())).is_not_empty()
	assert_int(RecoveryCode.bits(_rules())).is_greater_equal(90)
	var acct := svc.store.find_username("alice")
	assert_bool(AccountService.has_recovery_code(acct)).is_true()
	var file := FileAccess.get_file_as_string(ProjectSettings.globalize_path(DIR).path_join(acct.id + ".json"))
	assert_bool(file.contains(code) or file.contains(RecoveryCode.normalize(code, _rules()))).is_false()
	assert_bool(AccountStore.is_well_formed(acct)).is_true()
	# The export says a code exists but carries no hash and no salt of it.
	a.request(AccountCodec.OP_EXPORT)
	_pump(svc, server, [a])
	var json := str(_last(a, AccountCodec.OP_EXPORT).json)
	var ex: Dictionary = JSON.parse_string(json)
	assert_bool(ex.password.recovery_code_set).is_true()
	assert_bool(ex.password.has("recovery") or ex.password.has("hash")).is_false()
	assert_bool(json.contains(str(AccountService.recovery_of(acct).hash))).is_false()
	assert_bool(json.contains(str(AccountService.recovery_of(acct).salt))).is_false()
	# A login result never carries a code.
	var b := _client(3)
	_login(b, "alice", PW)
	_pump(svc, server, [b])
	assert_bool(_last(b, AccountCodec.OP_LOGIN).has("recovery_code")).is_false()


func test_recover_right_wrong_and_used_code() -> void:
	var svc := _service()
	var server := _link.create_endpoint(1)
	var a := _client(2)
	_register(a, "alice", PW)
	_pump(svc, server, [a])
	var code := str(_last(a, AccountCodec.OP_REGISTER).recovery_code)
	var x := _client(3)
	# Wrong code, garbage code and an unknown user: the same answer.
	_recover(x, "alice", "AAAAA-AAAAA-AAAAA-AAAAA", NEW_PW)
	_pump(svc, server, [a, x])
	assert_int(_last(x, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.E_CREDENTIALS)
	_recover(x, "nobody", code, NEW_PW)
	_pump(svc, server, [a, x])
	assert_int(_last(x, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.E_CREDENTIALS)
	# A weak new password is refused before any check.
	_recover(x, "alice", code, "short")
	_pump(svc, server, [a, x])
	assert_int(_last(x, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.E_WEAK_PASSWORD)
	# The right code, typed sloppily (lower case, no dashes): new session + new code.
	svc.launch_tokens.issue(svc.store.find_username("alice").id, 0.0)
	_recover(x, "ALICE", code.to_lower().replace("-", " "), NEW_PW)
	_pump(svc, server, [a, x])
	var r := _last(x, AccountCodec.OP_RECOVER)
	assert_int(r.code).is_equal(AccountCodec.OK)
	assert_str(str(r.username)).is_equal("alice")
	assert_int(str(r.token).length()).is_equal(64)
	var code2 := str(r.recovery_code)
	assert_str(code2).is_not_equal(code)
	# Every other session ended, launch tokens revoked.
	assert_bool(svc.sessions.has(str(a.session.get("token", "")))).is_false()
	assert_int(svc.launch_tokens.count()).is_equal(0)
	# Old password out, new password in.
	var y := _client(4)
	_login(y, "alice", PW)
	_pump(svc, server, [y])
	assert_int(_last(y, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.E_CREDENTIALS)
	_login(y, "alice", NEW_PW)
	_pump(svc, server, [y])
	assert_int(_last(y, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.OK)
	# The used code is gone; the new one works.
	var z := _client(5)
	_recover(z, "alice", code, "third password")
	_pump(svc, server, [z])
	assert_int(_last(z, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.E_CREDENTIALS)
	_recover(z, "alice", code2, "third password")
	_pump(svc, server, [z])
	assert_int(_last(z, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.OK)


func test_recover_is_rate_limited_like_login() -> void:
	var svc := _service()
	var server := _link.create_endpoint(1)
	var a := _client(2)
	_register(a, "alice", PW)
	_pump(svc, server, [a])
	var code := str(_last(a, AccountCodec.OP_REGISTER).recovery_code)
	var x := _client(3)
	for i in _rules().max_failures_per_account:
		_recover(x, "alice", "BBBBB-BBBBB-BBBBB-BBBBB", NEW_PW)
		_pump(svc, server, [x])
	_recover(x, "alice", code, NEW_PW)
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.E_LOCKED)
	# Recovery failures and login failures share the lock.
	_login(x, "alice", PW)
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.E_LOCKED)
	# The code was not used up by the locked attempt.
	assert_bool(AccountService.has_recovery_code(svc.store.find_username("alice"))).is_true()


func test_regenerate_needs_the_password_and_replaces_the_code() -> void:
	var svc := _service()
	var server := _link.create_endpoint(1)
	var a := _client(2)
	_register(a, "alice", PW)
	_pump(svc, server, [a])
	var code := str(_last(a, AccountCodec.OP_REGISTER).recovery_code)
	a.request(AccountCodec.OP_RECOVERY_CODE, {"password": "not my password"})
	_pump(svc, server, [a])
	assert_int(_last(a, AccountCodec.OP_RECOVERY_CODE).code).is_equal(AccountCodec.E_CREDENTIALS)
	a.request(AccountCodec.OP_RECOVERY_CODE, {"password": PW})
	_pump(svc, server, [a])
	var r := _last(a, AccountCodec.OP_RECOVERY_CODE)
	assert_int(r.code).is_equal(AccountCodec.OK)
	var fresh := str(r.recovery_code)
	assert_str(fresh).is_not_equal(code)
	var x := _client(3)
	_recover(x, "alice", code, NEW_PW)
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.E_CREDENTIALS)
	# A password change keeps the code.
	a.request(AccountCodec.OP_CHANGE_PASSWORD, {"old_password": PW, "new_password": "changed password"})
	_pump(svc, server, [a])
	assert_int(_last(a, AccountCodec.OP_CHANGE_PASSWORD).code).is_equal(AccountCodec.OK)
	_recover(x, "alice", fresh, NEW_PW)
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.OK)


func test_recovery_info_for_accounts_with_and_without_a_code() -> void:
	var svc := _service()
	var server := _link.create_endpoint(1)
	var a := _client(2)
	_register(a, "alice", PW)
	_pump(svc, server, [a])
	a.request(AccountCodec.OP_RECOVERY_INFO)
	_pump(svc, server, [a])
	assert_int(_last(a, AccountCodec.OP_RECOVERY_INFO).has_code).is_equal(1)
	# An account from before v0.16: no code yet, it still logs in.
	var old := svc.store.find_username("alice")
	(old.password as Dictionary).erase(AccountService.RECOVERY_KEY)
	svc.store.put(old)
	a.request(AccountCodec.OP_RECOVERY_INFO)
	_pump(svc, server, [a])
	assert_int(_last(a, AccountCodec.OP_RECOVERY_INFO).has_code).is_equal(0)
	var x := _client(3)
	_login(x, "alice", PW)
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.OK)


func test_admin_reset_is_picked_up_by_a_running_service() -> void:
	var svc := _service()
	svc.admin_dir = ADMIN
	var server := _link.create_endpoint(1)
	var a := _client(2)
	_register(a, "alice", PW)
	_pump(svc, server, [a])
	var tag := PlayerProfile.tag_of(svc.store.find_username("alice").id)
	# The tool side: read-only lookup, request with the code hash only.
	assert_dict(AccountAdmin.find_username_readonly(DIR, "ALICE")).is_not_empty()
	assert_dict(AccountAdmin.find_username_readonly(DIR, "nobody")).is_empty()
	var made := AccountAdmin.make_reset("alice", _rules(), 1000)
	assert_bool(JSON.stringify(made.request).contains(str(made.code))).is_false()
	var id := AccountAdmin.submit(ADMIN, made.request)
	assert_str(id).is_not_empty()
	assert_bool(AccountAdmin.is_queued(ADMIN, id)).is_true()
	svc.step(_rules().admin_poll_s + 0.1)
	assert_bool(AccountAdmin.is_queued(ADMIN, id)).is_false()
	var res := AccountAdmin.wait_result(ADMIN, id, 0.0)
	assert_bool(bool(res.ok)).is_true()
	assert_str(str(res.tag)).is_equal(tag)
	# The running service now refuses the old password and ended the session.
	assert_dict(svc.peers.get(2, {})).is_empty()
	var x := _client(3)
	_login(x, "alice", PW)
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.E_CREDENTIALS)
	# The printed code sets a new password.
	_recover(x, "alice", str(made.code), NEW_PW)
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_RECOVER).code).is_equal(AccountCodec.OK)
	# The change survives a restart (it went through the store).
	var again := FileAccountStore.new(DIR)
	again.open()
	assert_bool(AccountService.has_recovery_code(again.find_username("alice"))).is_true()
	# Unknown user and a malformed request: refused with an answer.
	var id2 := AccountAdmin.submit(ADMIN, AccountAdmin.make_reset("nobody", _rules(), 1000).request)
	var id3 := AccountAdmin.submit(ADMIN, {"v": 1, "op": "reset_password", "username": "alice"})
	svc.step(_rules().admin_poll_s + 0.1)
	assert_bool(bool(AccountAdmin.wait_result(ADMIN, id2, 0.0).ok)).is_false()
	assert_bool(bool(AccountAdmin.wait_result(ADMIN, id3, 0.0).ok)).is_false()


## Relog bug (W21-N1): a password longer than password_max that a client
## cut at registration must still log in when another client sends it whole.
func test_login_accepts_a_long_password_cut_at_registration() -> void:
	var svc := _service()
	var server := _link.create_endpoint(1)
	var max_len := _rules().password_max
	var full := "p4ssw0rd-from-a-password-manager-".repeat(3)  # 99 characters
	assert_int(full.length()).is_greater(max_len)
	var a := _client(2)
	_register(a, "alice", full.left(max_len))  # what the game's 64-character field sent up to v0.15
	_pump(svc, server, [a])
	assert_int(_last(a, AccountCodec.OP_REGISTER).code).is_equal(AccountCodec.OK)
	var x := _client(3)
	_login(x, "alice", full)  # what the launcher's 128-character field sends
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.OK)
	_login(x, "alice", full.left(max_len))
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.OK)
	# Still exact within the limit: a different prefix is wrong.
	_login(x, "alice", full.left(max_len - 1))
	_pump(svc, server, [x])
	assert_int(_last(x, AccountCodec.OP_LOGIN).code).is_equal(AccountCodec.E_CREDENTIALS)
