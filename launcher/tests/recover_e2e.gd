extends SceneTree
## W21-N1 "Forgot password?" against a real game server (driven by recover_e2e.sh).
##   godot --headless --path launcher -s tests/recover_e2e.gd -- recover <host:port> --dtls-insecure
##   godot --headless --path launcher -s tests/recover_e2e.gd -- admin <host:port> <code> --dtls-insecure
## recover: register "recuser" (the REGISTER result carries a code), then
##   LauncherLogin.recover(): a wrong code is refused, the right one signs in,
##   hands out the next code once, and the old password stops working.
## admin: after the host ran --admin-reset-password: the old password fails,
##   the printed code sets a new password and signs in.
## Prints "RECOVER-E2E: ..." lines and exits 0 when everything held.

const USER := "recuser"
const PW1 := "first-password-1"
const PW2 := "second-password-2"
const PW3 := "third-password-3"

var _fails: int = 0


func _check(cond: bool, what: String) -> void:
	print("RECOVER-E2E: %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _wait(sig: Signal, seconds: float = 15.0) -> Array:
	var box: Array = []
	var cb: Callable = func(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
		box.assign([a, b, c])
	sig.connect(cb)
	var t: float = 0.0
	while box.is_empty() and t < seconds:
		await create_timer(0.05).timeout
		t += 0.05
	sig.disconnect(cb)
	return box


func _open(addr: String) -> LauncherLogin:
	var login: LauncherLogin = LauncherLogin.new()
	root.add_child(login)
	login.open(addr)
	var ready: Array = await _wait(login.link_ready)
	_check(not ready.is_empty() and ready[0] == true, "encrypted link up")
	return login


func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = a[0]
	var addr: String = a[1]
	if mode == "recover":
		await _recover_flow(addr)
	else:
		await _admin_flow(addr, a[2])
	print("RECOVER-E2E: %s" % ("PASS" if _fails == 0 else "FAILED (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func _recover_flow(addr: String) -> void:
	var port: int = int(addr.split(":")[1])
	var enet: ENetTransport = ENetTransport.connect_to("127.0.0.1", port, AuthConfig.from_os().client_tls_for("127.0.0.1"))
	var lc: LobbyClient = LobbyClient.new(enet)
	var reg: Array = []
	lc.account_result.connect(func(d: Dictionary) -> void: reg.append(d))
	lc.request(AccountCodec.OP_REGISTER, {"ver": MsgType.PROTOCOL_VERSION, "username": USER, "password": PW1,
		"display_name": "Recover", "emblem": 0, "accent": 0, "flags": AccountCodec.FLAG_PRIVACY | AccountCodec.FLAG_AGE})
	var t: float = 0.0
	while reg.is_empty() and t < 15.0:
		lc.step()
		await create_timer(0.05).timeout
		t += 0.05
	var code: String = str(reg[0].get("recovery_code", "")) if not reg.is_empty() else ""
	_check(not reg.is_empty() and reg[0].code == AccountCodec.OK, "account registered")
	_check(code.length() == 23, "REGISTER result carries a recovery code")
	enet.close()
	OS.delay_msec(300)
	var login: LauncherLogin = await _open(addr)
	login.recover(USER, "AAAAA-AAAAA-AAAAA-AAAAA", PW2)
	var bad: Array = await _wait(login.recover_failed)
	_check(not bad.is_empty() and str(bad[0]).contains("recovery code"), "wrong code refused")
	var issued: Array = []
	login.recovery_code_issued.connect(func(c: String) -> void: issued.append(c))
	login.recover(USER, code.to_lower(), PW2)
	var ok: Array = await _wait(login.login_result)
	_check(not ok.is_empty() and ok[0] == true and login.is_logged_in(), "right code signs in")
	_check(issued.size() == 1 and issued[0] != code and str(issued[0]).length() == 23, "next code handed out once")
	login.close()
	login.queue_free()
	var l2: LauncherLogin = await _open(addr)
	l2.login(USER, PW1)
	var r1: Array = await _wait(l2.login_result)
	_check(not r1.is_empty() and r1[0] == false, "old password refused")
	l2.login(USER, PW2)
	var r2: Array = await _wait(l2.login_result)
	_check(not r2.is_empty() and r2[0] == true, "new password works")
	l2.close()


func _admin_flow(addr: String, code: String) -> void:
	var login: LauncherLogin = await _open(addr)
	login.login(USER, PW2)
	var r1: Array = await _wait(login.login_result)
	_check(not r1.is_empty() and r1[0] == false, "after the host reset the password no longer works")
	var issued: Array = []
	login.recovery_code_issued.connect(func(c: String) -> void: issued.append(c))
	login.recover(USER, code, PW3)
	var ok: Array = await _wait(login.login_result)
	_check(not ok.is_empty() and ok[0] == true, "the host's code sets a new password and signs in")
	_check(issued.size() == 1, "a fresh code follows")
	login.close()
