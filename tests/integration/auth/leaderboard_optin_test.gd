extends GdUnitTestSuite
## W20-WEB public leaderboard opt-in through AccountService.handle(): off by
## default, on / off / query, stored with the account (survives a profile
## update and a reload), guests and plain links refused, bad values refused,
## and account deletion removes the flag with the account.

const DIR := "user://test_leaderboard_optin"
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
	s.step(DT)
	return t.last(peer, op)


func _register(s: AccountService, t: FakeTransport, peer: int, user: String) -> Dictionary:
	return _send(s, t, peer, AccountCodec.OP_REGISTER, {"ver": V, "username": user, "password": "correct horse",
		"display_name": user.capitalize(), "emblem": 1, "accent": 2, "flags": 3})


func _lb(s: AccountService, t: FakeTransport, peer: int, set_: int) -> Dictionary:
	return _send(s, t, peer, AccountCodec.OP_LEADERBOARD, {"set": set_})


func test_codec_roundtrip_keeps_fields_and_is_strict() -> void:
	var req := AccountCodec.decode_request(AccountCodec.encode_request(AccountCodec.OP_LEADERBOARD, {"set": 1}))
	assert_int(int(req.set)).is_equal(1)
	var res := AccountCodec.decode_result(AccountCodec.encode_result(AccountCodec.OP_LEADERBOARD, AccountCodec.OK,
		{"public": 1}))
	assert_int(int(res.public)).is_equal(1)
	# Strict: a trailing byte is refused.
	var b := AccountCodec.encode_request(AccountCodec.OP_LEADERBOARD, {"set": 0})
	b.append(0)
	assert_dict(AccountCodec.decode_request(b)).is_empty()


func test_default_off_then_on_query_off_and_stored() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var reg := _register(s, t, 2, "alice")
	var id := str(reg.id)
	assert_int(int(_lb(s, t, 2, AccountCodec.LB_QUERY).public)).is_equal(0)
	assert_bool(AccountService.is_leaderboard_public(s.store.get_by_id(id))).is_false()
	assert_bool((s.store.get_by_id(id).profile as Dictionary).has(AccountService.PROFILE_LEADERBOARD)).is_false()
	var on := _lb(s, t, 2, AccountCodec.LB_ON)
	assert_int(int(on.code)).is_equal(AccountCodec.OK)
	assert_int(int(on.public)).is_equal(1)
	assert_int(int(_lb(s, t, 2, AccountCodec.LB_QUERY).public)).is_equal(1)
	# Stored on disk: a fresh store sees it.
	var again := FileAccountStore.new(DIR)
	again.open()
	assert_bool(AccountService.is_leaderboard_public(again.get_by_id(id))).is_true()
	var off := _lb(s, t, 2, AccountCodec.LB_OFF)
	assert_int(int(off.public)).is_equal(0)
	assert_bool((s.store.get_by_id(id).profile as Dictionary).has(AccountService.PROFILE_LEADERBOARD)).is_false()


func test_profile_update_keeps_the_flag_on() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var id := str(_register(s, t, 2, "alice").id)
	_lb(s, t, 2, AccountCodec.LB_ON)
	var up := _send(s, t, 2, AccountCodec.OP_UPDATE_PROFILE, {"display_name": "Alicia", "emblem": 2, "accent": 1,
		"favourite_hero": ""})
	assert_int(int(up.code)).is_equal(AccountCodec.OK)
	var a := s.store.get_by_id(id)
	assert_str(str(a.profile.display_name)).is_equal("Alicia")
	assert_bool(AccountService.is_leaderboard_public(a)).is_true()


func test_bad_value_guest_and_plain_link_are_refused() -> void:
	var s := _service()
	var t := FakeTransport.new()
	_register(s, t, 2, "alice")
	assert_int(int(_lb(s, t, 2, 7).code)).is_equal(AccountCodec.E_BAD_REQUEST)
	assert_int(int(_lb(s, t, 9, AccountCodec.LB_ON).code)).is_equal(AccountCodec.E_NOT_LOGGED_IN)
	_send(s, t, 3, AccountCodec.OP_GUEST, {"ver": V, "display_name": "Guesty", "emblem": 0, "accent": 0,
		"flags": AccountCodec.FLAG_PRIVACY})
	assert_int(int(_lb(s, t, 3, AccountCodec.LB_ON).code)).is_equal(AccountCodec.E_GUEST)
	var plain := _service(false)
	var t2 := FakeTransport.new()
	_send(plain, t2, 4, AccountCodec.OP_GUEST, {"ver": V, "display_name": "Plainy", "emblem": 0, "accent": 0,
		"flags": AccountCodec.FLAG_PRIVACY})
	assert_int(int(_lb(plain, t2, 4, AccountCodec.LB_ON).code)).is_equal(AccountCodec.E_GUEST)


func test_account_deletion_removes_the_flag() -> void:
	var s := _service()
	var t := FakeTransport.new()
	var id := str(_register(s, t, 2, "alice").id)
	_lb(s, t, 2, AccountCodec.LB_ON)
	var deleted: Array = []
	s.account_deleted.connect(func(x: String) -> void: deleted.append(x))
	var del := _send(s, t, 2, AccountCodec.OP_DELETE_ACCOUNT, {"password": "correct horse"})
	assert_int(int(del.code)).is_equal(AccountCodec.OK)
	assert_array(deleted).contains_exactly([id])
	assert_dict(s.store.get_by_id(id)).is_empty()
	assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(DIR).path_join(id + ".json"))).is_false()


func test_export_shows_the_flag_when_on() -> void:
	var s := _service()
	var t := FakeTransport.new()
	_register(s, t, 2, "alice")
	_lb(s, t, 2, AccountCodec.LB_ON)
	var ex := _send(s, t, 2, AccountCodec.OP_EXPORT)
	assert_str(str(ex.json)).contains("\"leaderboard_public\": true")
