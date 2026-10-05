extends GdUnitTestSuite
## W15 "sign in once" through AccountService.handle(): a logged-in launcher
## gets a launch token (DTLS only), the game redeems it once for its own
## session; expiry, reuse, wrong account and the plain-link refusal.

const DIR := "user://test_launch_token_store"
const DT := 1.0 / 30.0
const V := MsgType.PROTOCOL_VERSION


class FakeTransport:
	extends Transport
	var sent: Array = []

	func send(to_peer: int, _channel: int, data: PackedByteArray) -> void:
		sent.append([to_peer, AccountCodec.decode_result(data)])

	func peer_address(_peer: int) -> String:
		return "203.0.113.9"

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


func _service(secure: bool = true) -> AccountService:
	var st := FileAccountStore.new(DIR)
	st.open()
	var r := AuthRulesDef.new()
	r.pbkdf2_iterations = 1000
	var s := AccountService.new(st, r, secure, PresenceRegistry.new())
	s.hasher.threaded = false
	return s


func _send(s: AccountService, t: FakeTransport, peer: int, op: int, f: Dictionary = {}) -> Dictionary:
	s.handle(t, peer, AccountCodec.encode_request(op, f))
	for i in 3:  # W21-N1: REGISTER / RECOVER chain more than one hash job
		s.step(DT)
	return t.last(peer, op)


func _register(s: AccountService, t: FakeTransport, peer: int, user: String) -> Dictionary:
	return _send(s, t, peer, AccountCodec.OP_REGISTER, {"ver": V, "username": user, "password": "correct horse",
		"display_name": user.capitalize(), "emblem": 1, "accent": 2, "flags": 3})


func _redeem(s: AccountService, t: FakeTransport, peer: int, tok: String, id: String) -> Dictionary:
	return _send(s, t, peer, AccountCodec.OP_REDEEM, {"ver": V, "token": tok, "id": id})


func test_issue_and_redeem_signs_the_game_in() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var reg := _register(s, t, 2, "alice")
	var lt := _send(s, t, 2, AccountCodec.OP_LAUNCH_TOKEN)
	assert_int(int(lt.code)).is_equal(AccountCodec.OK)
	assert_int(int(lt.ttl)).is_equal(60)
	assert_str(str(lt.token)).is_not_equal(str(reg.token))  # not the launcher's own session
	var r := _redeem(s, t, 3, str(lt.token), str(reg.id))
	assert_int(int(r.code)).is_equal(AccountCodec.OK)
	assert_str(str(r.display_name)).is_equal("Alice")
	assert_str(str(r.token)).is_not_equal(str(reg.token))
	assert_str(str(s.identity(3).id)).is_equal(str(reg.id))
	assert_bool(s.launch_tokens.holds_plain(str(lt.token))).is_false()


func test_reuse_rejected() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var reg := _register(s, t, 2, "alice")
	var tok := str(_send(s, t, 2, AccountCodec.OP_LAUNCH_TOKEN).token)
	assert_int(int(_redeem(s, t, 3, tok, str(reg.id)).code)).is_equal(AccountCodec.OK)
	assert_int(int(_redeem(s, t, 4, tok, str(reg.id)).code)).is_equal(AccountCodec.E_SESSION)
	assert_dict(s.identity(4)).is_empty()


func test_expiry() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var reg := _register(s, t, 2, "alice")
	var tok := str(_send(s, t, 2, AccountCodec.OP_LAUNCH_TOKEN).token)
	s.step(s.online.launch_token_ttl_s + 1.0)
	assert_int(int(_redeem(s, t, 3, tok, str(reg.id)).code)).is_equal(AccountCodec.E_SESSION)


func test_wrong_account_rejected() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var a := _register(s, t, 2, "alice")
	var b := _register(s, t, 5, "bobby")
	var tok := str(_send(s, t, 2, AccountCodec.OP_LAUNCH_TOKEN).token)
	assert_int(int(_redeem(s, t, 3, tok, str(b.id)).code)).is_equal(AccountCodec.E_SESSION)
	assert_dict(s.identity(3)).is_empty()
	# Burned by the failed attempt: the right account cannot use it either.
	assert_int(int(_redeem(s, t, 3, tok, str(a.id)).code)).is_equal(AccountCodec.E_SESSION)


func test_plain_server_never_issues_or_redeems() -> void:
	var s := _service(false)  # no DTLS: guest-only
	var t := FakeTransport.new()
	var g := _send(s, t, 2, AccountCodec.OP_GUEST, {"ver": V, "display_name": "Guesty", "emblem": 0, "accent": 0,
		"flags": AccountCodec.FLAG_PRIVACY})
	assert_int(int(g.code)).is_equal(AccountCodec.OK)
	assert_int(int(_send(s, t, 2, AccountCodec.OP_LAUNCH_TOKEN).code)).is_equal(AccountCodec.E_GUEST)
	assert_int(s.launch_tokens.count()).is_equal(0)
	assert_int(int(_redeem(s, t, 3, "ab".repeat(32), "%032x" % 7).code)).is_equal(AccountCodec.E_NOT_SECURE)


func test_secure_service_refuses_guests_and_anonymous() -> void:
	var s := _service()
	var t := FakeTransport.new()
	assert_int(int(_send(s, t, 2, AccountCodec.OP_LAUNCH_TOKEN).code)).is_equal(AccountCodec.E_NOT_LOGGED_IN)
	_send(s, t, 3, AccountCodec.OP_GUEST, {"ver": V, "display_name": "Guesty", "emblem": 0, "accent": 0,
		"flags": AccountCodec.FLAG_PRIVACY})
	assert_int(int(_send(s, t, 3, AccountCodec.OP_LAUNCH_TOKEN).code)).is_equal(AccountCodec.E_GUEST)


func test_password_change_revokes_outstanding_tokens() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var reg := _register(s, t, 2, "alice")
	var tok := str(_send(s, t, 2, AccountCodec.OP_LAUNCH_TOKEN).token)
	_send(s, t, 2, AccountCodec.OP_CHANGE_PASSWORD, {"old_password": "correct horse", "new_password": "battery staple"})
	s.step(DT)
	assert_int(int(t.last(2, AccountCodec.OP_CHANGE_PASSWORD).code)).is_equal(AccountCodec.OK)
	assert_int(int(_redeem(s, t, 3, tok, str(reg.id)).code)).is_equal(AccountCodec.E_SESSION)
