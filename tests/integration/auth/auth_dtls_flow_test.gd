extends GdUnitTestSuite
## End-to-end accounts over real ENet with DTLS on 127.0.0.1 (one process):
## a self-signed certificate generated at runtime and pinned by the clients
## (TLSOptions.client(cert), never client_unsafe). Register, friend request /
## accept, presence (online / in lobby), export, delete; a client without
## DTLS gets no session at all. Ports 7850-7859 (chunk L1).

const PORT := 7853
const DIR := "user://test_auth_dtls"
const DT := 1.0 / 60.0

var _cert: X509Certificate
var _key: CryptoKey


func before() -> void:
	var c := Crypto.new()
	_key = c.generate_rsa(2048)
	_cert = c.generate_self_signed_certificate(_key, "CN=localhost,O=Cybergram Test,C=AT")


func after_test() -> void:
	var d := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


func _pump(lobby: LobbyServer, clients: Array, until: Callable, max_s := 6.0) -> bool:
	var t := 0.0
	while t < max_s:
		lobby.step(DT)
		for c: LobbyClient in clients:
			c.step()
		if until.call():
			return true
		OS.delay_msec(4)
		t += DT
	return false


func _client() -> LobbyClient:
	var t := ENetTransport.connect_to("127.0.0.1", PORT, TLSOptions.client(_cert, "localhost"), "localhost")
	assert_str(t.error_text).is_empty()
	return LobbyClient.new(t)


func test_register_friends_presence_export_delete_over_dtls() -> void:
	var enet := ENetTransport.listen(PORT, 8, TLSOptions.server(_key, _cert))
	assert_str(enet.error_text).is_empty()
	assert_bool(enet.is_secure).is_true()
	var store := FileAccountStore.new(DIR)
	store.open()
	var rules := AuthRulesDef.new()
	rules.pbkdf2_iterations = 2000
	var reg := PresenceRegistry.new()
	var svc := AccountService.new(store, rules, enet.is_secure, reg)
	svc.allow_guests = false
	var lobby := LobbyServer.new(enet, 3, reg, svc)
	var a := _client()
	var b := _client()
	var res := {}
	a.account_result.connect(func(d: Dictionary) -> void: res["a%d" % d.op] = d)
	b.account_result.connect(func(d: Dictionary) -> void: res["b%d" % d.op] = d)
	for p in [[a, "alice", "correct horse"], [b, "bobby", "battery staple"]]:
		(p[0] as LobbyClient).request(AccountCodec.OP_REGISTER, {"ver": MsgType.PROTOCOL_VERSION, "username": p[1],
			"password": p[2], "display_name": String(p[1]).capitalize(), "emblem": 2, "accent": 3,
			"flags": AccountCodec.FLAG_PRIVACY | AccountCodec.FLAG_AGE})
	assert_bool(_pump(lobby, [a, b], func() -> bool: return not a.session.is_empty() and not b.session.is_empty())).is_true()
	assert_int(store.count()).is_equal(2)
	a.request(AccountCodec.OP_FRIEND_REQUEST, {"username": "bobby", "id": ""})
	assert_bool(_pump(lobby, [a, b], func() -> bool: return res.has("a%d" % AccountCodec.OP_FRIEND_REQUEST))).is_true()
	b.request(AccountCodec.OP_FRIEND_ACCEPT, {"id": a.session.id})
	assert_bool(_pump(lobby, [a, b], func() -> bool: return res.has("b%d" % AccountCodec.OP_FRIEND_ACCEPT))).is_true()
	assert_int(res["b%d" % AccountCodec.OP_FRIEND_ACCEPT].code).is_equal(AccountCodec.OK)
	# B joins the lobby: A sees B "in lobby".
	b.join(1)
	assert_bool(_pump(lobby, [a, b], func() -> bool: return not b.state.is_empty())).is_true()
	a.request(AccountCodec.OP_FRIENDS)
	assert_bool(_pump(lobby, [a, b], func() -> bool: return res.has("a%d" % AccountCodec.OP_FRIENDS))).is_true()
	var fl: Array = res["a%d" % AccountCodec.OP_FRIENDS].friends
	assert_int(fl.size()).is_equal(1)
	assert_int(fl[0].status).is_equal(LobbyCodec.STATUS_IN_LOBBY)
	# Export over the encrypted link.
	a.request(AccountCodec.OP_EXPORT)
	assert_bool(_pump(lobby, [a, b], func() -> bool: return res.has("a%d" % AccountCodec.OP_EXPORT))).is_true()
	var ex: Dictionary = JSON.parse_string(res["a%d" % AccountCodec.OP_EXPORT].json)
	assert_array(ex.friends).contains_exactly([b.session.id])
	assert_bool(ex.password.has("hash")).is_false()
	# Delete: the account file is gone and B's friends list is clean.
	a.request(AccountCodec.OP_DELETE_ACCOUNT, {"password": "correct horse"})
	assert_bool(_pump(lobby, [a, b], func() -> bool: return res.has("a%d" % AccountCodec.OP_DELETE_ACCOUNT))).is_true()
	assert_int(res["a%d" % AccountCodec.OP_DELETE_ACCOUNT].code).is_equal(AccountCodec.OK)
	assert_dict(store.find_username("alice")).is_empty()
	assert_array(store.find_username("bobby").friends).is_empty()
	# Guests are off on this server.
	a.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": "Visitor", "emblem": 0,
		"accent": 0, "flags": AccountCodec.FLAG_PRIVACY})
	assert_bool(_pump(lobby, [a, b], func() -> bool: return res.has("a%d" % AccountCodec.OP_GUEST))).is_true()
	assert_int(res["a%d" % AccountCodec.OP_GUEST].code).is_equal(AccountCodec.E_GUESTS_OFF)
	# A plain (non-DTLS) client cannot get a session from a DTLS server.
	var plain := LobbyClient.new(ENetTransport.connect_to("127.0.0.1", PORT))
	var plain_res: Array = []
	plain.account_result.connect(func(d: Dictionary) -> void: plain_res.append(d))
	plain.request(AccountCodec.OP_LOGIN, {"ver": MsgType.PROTOCOL_VERSION, "username": "bobby", "password": "battery staple"})
	_pump(lobby, [a, b, plain], func() -> bool: return not plain_res.is_empty(), 1.5)
	assert_array(plain_res).is_empty()
	for c: LobbyClient in [a, b, plain]:
		(c.transport as ENetTransport).close()
	svc.hasher.drain()
	enet.close()
