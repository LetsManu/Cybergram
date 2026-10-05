extends GdUnitTestSuite
## W11-Q1 security review (docs/security/review-2026-10-05.md): AccountService
## and FileAccountStore regressions for SEC-002, SEC-003 and SEC-006, driven
## through handle() with a recording transport that reports peer addresses.

const DIR := "user://test_sec_review_store"
const DT := 1.0 / 30.0
const V := MsgType.PROTOCOL_VERSION


## Records replies; peer_address() comes from `addr` (peer -> IP).
class FakeTransport:
	extends Transport
	var addr: Dictionary = {}
	var sent: Array = []  # [peer, decoded result]

	func send(to_peer: int, _channel: int, data: PackedByteArray) -> void:
		sent.append([to_peer, AccountCodec.decode_result(data)])

	func peer_address(peer: int) -> String:
		return str(addr.get(peer, ""))

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
	r.max_failures_per_account = 3
	r.max_failures_per_peer = 6
	var s := AccountService.new(st, r, true, PresenceRegistry.new())
	s.hasher.threaded = false
	return s


func _send(s: AccountService, t: FakeTransport, peer: int, op: int, f: Dictionary) -> void:
	s.handle(t, peer, AccountCodec.encode_request(op, f))
	s.step(DT)


func _register(s: AccountService, t: FakeTransport, peer: int) -> void:
	_send(s, t, peer, AccountCodec.OP_REGISTER, {"ver": V, "username": "alice", "password": "correct horse",
		"display_name": "Alice", "emblem": 1, "accent": 2, "flags": 3})


func _login(s: AccountService, t: FakeTransport, peer: int, pw: String) -> int:
	_send(s, t, peer, AccountCodec.OP_LOGIN, {"ver": V, "username": "alice", "password": pw})
	return int(t.last(peer, AccountCodec.OP_LOGIN).code)


# SEC-002: reconnecting (a new peer id) does not reset the failure count.
func test_sec002_reconnect_does_not_reset_limit() -> void:
	var s := _service()
	var t := FakeTransport.new()
	t.addr = {2: "198.51.100.1"}
	_register(s, t, 2)
	for i in 3:
		var p := 10 + i  # a fresh connection for every guess, same address
		t.addr[p] = "203.0.113.7"
		assert_int(_login(s, t, p, "wrong guess")).is_equal(AccountCodec.E_CREDENTIALS)
	t.addr[20] = "203.0.113.7"
	assert_int(_login(s, t, 20, "correct horse")).is_equal(AccountCodec.E_LOCKED)


# SEC-002: a stranger's failures do not lock the owner out from their address.
func test_sec002_attacker_cannot_lock_out_victim() -> void:
	var s := _service()
	var t := FakeTransport.new()
	t.addr = {2: "198.51.100.1", 3: "203.0.113.7", 4: "198.51.100.1"}
	_register(s, t, 2)
	for i in 5:
		_login(s, t, 3, "wrong guess")
	assert_int(_login(s, t, 3, "correct horse")).is_equal(AccountCodec.E_LOCKED)
	assert_int(_login(s, t, 4, "correct horse")).is_equal(AccountCodec.OK)


# SEC-003: a password change ends the account's sessions on other connections.
func test_sec003_password_change_ends_other_sessions() -> void:
	var s := _service()
	var t := FakeTransport.new()
	_register(s, t, 2)
	assert_int(_login(s, t, 3, "correct horse")).is_equal(AccountCodec.OK)
	var stale := str(t.last(3, AccountCodec.OP_LOGIN).token)
	_send(s, t, 2, AccountCodec.OP_CHANGE_PASSWORD, {"old_password": "correct horse",
		"new_password": "battery staple"})
	s.step(DT)
	assert_int(int(t.last(2, AccountCodec.OP_CHANGE_PASSWORD).code)).is_equal(AccountCodec.OK)
	assert_bool(s.identity(3).is_empty()).is_true()
	assert_bool(s.identity(2).is_empty()).is_false()
	s.on_disconnect(3)
	_send(s, t, 5, AccountCodec.OP_RESUME, {"ver": V, "token": stale})
	assert_int(int(t.last(5, AccountCodec.OP_RESUME).code)).is_equal(AccountCodec.E_SESSION)


# SEC-006: account files and their directory are owner-only on Unix.
func test_sec006_account_files_owner_only() -> void:
	if OS.get_name() != "Linux":
		return
	var s := _service()
	var t := FakeTransport.new()
	_register(s, t, 2)
	var d := ProjectSettings.globalize_path(DIR)
	var id := str(s.identity(2).id)
	assert_int(FileAccess.get_unix_permissions(d.path_join(id + ".json")) & 0x1FF).is_equal(0x180)
	assert_int(FileAccess.get_unix_permissions(d) & 0x1FF).is_equal(0x1C0)
