extends SceneTree
## Login hand-over test against a real game server (driven by e2e_update.sh).
##   godot --headless --path launcher -s tests/login_e2e.gd -- <secure|plain> <host:port> <out_dir> <stub_game>
## secure: register an account, log in through LauncherLogin, start <stub_game>
##   with the session in the environment, and prove the token (a) reached the
##   child's environment, (b) is not on its command line, (c) was cleared in
##   this process, (d) still resumes on a new connection after the launcher
##   disconnected (the server's session grace).
## plain: the server has no certificate: login() must refuse, guest_only is set.
## Prints "LOGIN-E2E: ..." lines and exits 0 when everything held.

var _fails: int = 0


func _check(cond: bool, what: String) -> void:
	print("LOGIN-E2E: %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _wait(sig: Signal, seconds: float = 10.0) -> Array:
	var box: Array = []  # lambdas capture bools by value: a non-empty box means done
	var cb: Callable = func(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
		box.assign([a, b, c])
	sig.connect(cb)
	var t: float = 0.0
	while box.is_empty() and t < seconds:
		await create_timer(0.05).timeout
		t += 0.05
	sig.disconnect(cb)
	return box


func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = a[0]
	var addr: String = a[1]
	var out_dir: String = a[2]
	var stub: String = a[3]
	var login: LauncherLogin = LauncherLogin.new()
	root.add_child(login)
	login.open(addr)
	var ready: Array = await _wait(login.link_ready)
	_check(not ready.is_empty(), "link to the server came up")
	if ready.is_empty():
		_finish()
		return
	if mode == "plain":
		_check(ready[0] == false and login.guest_only, "plain link: guest only")
		var r: Array = []
		login.login("someone", "secret-password")
		_check(true, "login() on a plain link did not crash")
		r = [login.is_logged_in()]
		_check(r[0] == false, "plain link: not logged in, password not sent")
		_finish()
		return
	_check(ready[0] == true and not login.guest_only, "link is encrypted")
	login.close()

	# Register the account (the launcher itself has no register screen).
	var enet: ENetTransport = ENetTransport.connect_to("127.0.0.1", int(addr.split(":")[1]), AuthConfig.from_os().client_tls_for("127.0.0.1"))
	var lc: LobbyClient = LobbyClient.new(enet)
	lc.request(AccountCodec.OP_REGISTER, {"ver": MsgType.PROTOCOL_VERSION, "username": "e2euser", "password": "correct-horse-1",
		"display_name": "E2E", "emblem": 0, "accent": 0, "flags": AccountCodec.FLAG_PRIVACY | AccountCodec.FLAG_AGE})
	var reg: Array = []
	var t: float = 0.0
	lc.account_result.connect(func(d: Dictionary) -> void: reg.append(d))
	while reg.is_empty() and t < 10.0:
		lc.step()
		await create_timer(0.05).timeout
		t += 0.05
	_check(not reg.is_empty() and reg[0].code == AccountCodec.OK, "test account registered")
	enet.close()
	OS.delay_msec(400)

	# Wrong password first, then the right one.
	login = LauncherLogin.new()
	root.add_child(login)
	login.open(addr)
	await _wait(login.link_ready)
	login.login("e2euser", "wrong-password-1")
	var bad: Array = await _wait(login.login_result)
	_check(not bad.is_empty() and bad[0] == false, "wrong password refused")
	login.login("e2euser", "correct-horse-1")
	var good: Array = await _wait(login.login_result)
	_check(not good.is_empty() and good[0] == true, "login ok")
	_check(login.is_logged_in(), "launcher holds a session")

	# Hand over to the stub game.
	_check(login.hand_over_env(), "hand_over_env")
	var pid: int = OS.create_process(stub, PackedStringArray([out_dir]))
	LauncherLogin.clear_env()
	_check(pid > 0, "stub game started")
	_check(OS.get_environment(LauncherLogin.ENV_TOKEN) == "", "token cleared from the launcher environment")
	_check(not login.is_logged_in(), "launcher forgot the token")
	var token: String = ""
	t = 0.0
	while t < 10.0 and not FileAccess.file_exists(out_dir.path_join("env_token.txt")):
		await create_timer(0.1).timeout
		t += 0.1
	await create_timer(0.3).timeout
	token = FileAccess.get_file_as_string(out_dir.path_join("env_token.txt")).strip_edges()
	var cmd: String = FileAccess.get_file_as_string(out_dir.path_join("cmdline.txt"))
	_check(token != "", "child got CYBERGRAM_SESSION_TOKEN")
	_check(FileAccess.get_file_as_string(out_dir.path_join("env_server.txt")).strip_edges() == addr, "child got CYBERGRAM_SESSION_SERVER")
	_check(token != "" and not cmd.contains(token), "token is not on the command line")

	# The game resumes the session on a new connection (server grace).
	enet = ENetTransport.connect_to("127.0.0.1", int(addr.split(":")[1]), AuthConfig.from_os().client_tls_for("127.0.0.1"))
	lc = LobbyClient.new(enet)
	lc.request(AccountCodec.OP_RESUME, {"ver": MsgType.PROTOCOL_VERSION, "token": token})
	reg = []
	lc.account_result.connect(func(d: Dictionary) -> void: reg.append(d))
	t = 0.0
	while reg.is_empty() and t < 10.0:
		lc.step()
		await create_timer(0.05).timeout
		t += 0.05
	_check(not reg.is_empty() and reg[0].code == AccountCodec.OK and str(reg[0].display_name) == "E2E", "token resumes after the launcher disconnected")
	enet.close()
	_finish()


func _finish() -> void:
	print("LOGIN-E2E: %s" % ("PASS" if _fails == 0 else "FAILED (%d)" % _fails))
	quit(1 if _fails > 0 else 0)
