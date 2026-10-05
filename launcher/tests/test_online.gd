extends SceneTree
## W15-ONLINE launcher tests (sign-in hand-over, status, diagnostics,
## crash consent, privacy settings, friends / party view models). Run:
##   godot --headless --path launcher -s tests/test_online.gd
## Exits 0 when all checks pass, 1 otherwise.

var _fails: int = 0
var _checks: int = 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("FAIL: ", what)


func _init() -> void:
	_test_handoff()
	_test_status()
	_test_redaction()
	_test_crash_consent()
	_test_social()
	print("launcher online tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _test_handoff() -> void:
	var tok: String = "ab".repeat(32)
	var acc: String = "0123456789abcdef0123456789abcdef"
	var h: Dictionary = {"token": tok, "server": "cyber.example:7777", "account": acc}
	_check(LauncherLogin.hand_over_env(h), "handoff: set")
	_check(OS.get_environment(LaunchHandoff.ENV_TOKEN) == tok, "handoff: token in env")
	LauncherLogin.clear_env()
	for k in LaunchHandoff.SECRET_KEYS:
		_check(not OS.has_environment(k), "handoff: %s cleared" % k)
	_check(not LauncherLogin.hand_over_env({}), "handoff: nothing set without a token")
	_check(not OS.has_environment(LaunchHandoff.ENV_TOKEN), "handoff: empty leaves env clean")
	_check(not LauncherLogin.hand_over_env({"token": tok, "server": "x:1", "account": "bad"}), "handoff: bad account refused")
	# Not logged in (and never on a plain link): request_launch answers {} and sends nothing.
	var login: LauncherLogin = LauncherLogin.new()
	login.secure = false
	_check(login.rtt_ms() == -1, "rtt: -1 without a link")
	_check(not login.request(AccountCodec.OP_FRIENDS), "request: refused when not logged in")
	login.free()


func _test_status() -> void:
	var body: String = '{"online":7,"in_lobby":3,"in_match":4,"motd":"  Hello\\n\\tworld\\u202e!  "}'
	_check(OnlineText.motd_of(body) == "Hello world!", "motd: plain, collapsed, bidi stripped")
	_check(OnlineText.motd_of('{"online":1}') == "", "motd: absent")
	_check(OnlineText.motd_of('{"motd":42}') == "", "motd: wrong type")
	_check(OnlineText.motd_of("garbage") == "", "motd: garbage")
	var long: String = '{"motd":"%s"}' % "x".repeat(900)
	_check(OnlineText.motd_of(long).length() == OnlineText.MOTD_MAX_CHARS, "motd: capped")
	_check(OnlineText.motd_of('{"motd":"[url=http://evil]click[/url]"}') == "[url=http://evil]click[/url]", "motd: markup stays inert text")
	_check(OnlineText.state_word({"reachable": true}) == "ONLINE", "status: online")
	_check(OnlineText.state_word({}) == "OFFLINE", "status: offline")
	_check(OnlineText.players_line({"reachable": true, "has_counts": true, "online": 1}) == "1 player online", "status: singular")
	_check(OnlineText.players_line({"reachable": true, "has_counts": true, "online": 7}) == "7 players online", "status: plural")
	_check(OnlineText.ping_text(-1) == "\u2013 ms" and OnlineText.ping_text(23) == "23 ms", "ping text")
	_check(OnlineText.ping_band(-1) == -1 and OnlineText.ping_band(20) == 0 and OnlineText.ping_band(100) == 1 \
		and OnlineText.ping_band(400) == 2, "ping bands")
	_check(LauncherStatusWidget.REFRESH_S == 30.0, "status refresh every 30 s")


func _test_redaction() -> void:
	var tok: String = "9f".repeat(32)
	var acc: String = "0123456789abcdef0123456789abcdef"
	var log: String = "\n".join([
		"[accounts] OP_RESUME token %s" % tok,
		"CYBERGRAM_LAUNCH_TOKEN=%s" % tok,
		"login {\"username\": \"neo\", \"password\": \"hunter2-secret\"}",
		"password=correct-horse-1 next",
		"session: abcdEF12",
		"peer 203.0.113.7 joined, player %s, mail neo@example.org" % acc,
		"loaded /home/neo/.local/share/godot/app_userdata/Cybergram/logs/godot.log",
	])
	var r: String = LauncherDiagnostics.redact(log)
	_check(not r.contains(tok), "redact: 64-hex token removed")
	_check(not r.contains("hunter2-secret"), "redact: JSON password removed")
	_check(not r.contains("correct-horse-1"), "redact: key=value password removed")
	_check(not r.contains("abcdEF12"), "redact: session value removed")
	_check(r.contains(LauncherDiagnostics.TOKEN_MARK) or r.contains(LauncherDiagnostics.SECRET_MARK), "redact: marks left")
	_check(r.contains("next") and r.contains("[accounts]"), "redact: the rest of the log stays")
	_check(r.contains("203.0.113.7"), "redact (zip): IP kept for the player's own support zip")
	var s: String = LauncherDiagnostics.redact(log, true, "/home/neo")
	_check(not s.contains("203.0.113.7") and not s.contains(acc) and not s.contains("neo@example.org"), "redact strict: ip, id, mail removed")
	_check(not s.contains("/home/neo") and s.contains("~/.local/share"), "redact strict: home folder removed")
	_check(not LauncherDiagnostics.redact("-----BEGIN PRIVATE KEY-----\nMIIabc\n-----END PRIVATE KEY-----").contains("MIIabc"), "redact: PEM key removed")
	# Zip build from a temp log folder.
	var dir: String = OS.get_cache_dir().path_join("cg_diag_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir.path_join("logs"))
	var f: FileAccess = FileAccess.open(dir.path_join("logs/godot.log"), FileAccess.WRITE)
	f.store_string(log)
	f.close()
	var info: Dictionary = LauncherDiagnostics.system_info("1.0.0", "0.11.0")
	_check(not info.has("user") and not info.has("host") and not str(info).contains(OS.get_unique_id()), "sysinfo: no identifiers")
	var files: Dictionary = LauncherDiagnostics.collect({"game": dir.path_join("logs")}, info)
	_check(files.has("system.json") and files.has("logs/game/godot.log"), "collect: logs + system info")
	var zp: String = LauncherDiagnostics.write_zip(dir, files)
	_check(zp != "" and FileAccess.file_exists(zp), "zip written")
	var zr: ZIPReader = ZIPReader.new()
	_check(zr.open(zp) == OK and not zr.read_file("logs/game/godot.log").get_string_from_utf8().contains(tok), "zip: token not inside")
	zr.close()
	var crash: PackedByteArray = LauncherDiagnostics.crash_payload({"game": dir.path_join("logs")}, info, 139, 65536)
	var txt: String = crash.decompress_dynamic(1 << 22, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	_check(crash.size() > 0 and txt.contains("\"exit_code\":139") and not txt.contains(tok) and not txt.contains("203.0.113.7"), "crash payload: strict, gzip")
	_check(LauncherDiagnostics.crash_payload({"game": dir.path_join("logs")}, info, 1, 64).is_empty(), "crash payload: empty when it cannot fit")
	for p in [zp, dir.path_join("logs/godot.log")]:
		DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(dir.path_join("logs"))
	DirAccess.remove_absolute(dir)


func _test_crash_consent() -> void:
	var path: String = OS.get_cache_dir().path_join("cg_privacy_test_%d.cfg" % Time.get_ticks_usec())
	var p: OnlinePrefs = OnlinePrefs.new(path).load_file()
	_check(p.crash_mode == OnlinePrefs.CRASH_ASK, "crash: default asks (never sends on its own)")
	_check(not p.discord_presence, "discord: off by default")
	_check(OnlinePrefs.crash_action(p.crash_mode) == "ask", "crash: default action is the prompt")
	_check(OnlinePrefs.mode_after_prompt(true, true) == OnlinePrefs.CRASH_ASK, "prompt: send + always ask keeps asking")
	_check(OnlinePrefs.mode_after_prompt(false, true) == OnlinePrefs.CRASH_ASK, "prompt: don't send + always ask")
	_check(OnlinePrefs.mode_after_prompt(true, false) == OnlinePrefs.CRASH_ALWAYS, "prompt: send, remember")
	_check(OnlinePrefs.mode_after_prompt(false, false) == OnlinePrefs.CRASH_NEVER, "prompt: don't send, remember")
	p.crash_mode = OnlinePrefs.CRASH_ALWAYS
	p.discord_presence = true
	_check(p.save_file(), "prefs saved")
	var q: OnlinePrefs = OnlinePrefs.new(path).load_file()
	_check(q.crash_mode == OnlinePrefs.CRASH_ALWAYS and q.discord_presence, "prefs reloaded")
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(OnlinePrefs.SECTION, "crash_reports", "sometimes")
	cfg.set_value(OnlinePrefs.SECTION, "discord_presence", "yes")
	cfg.save(path)
	var r: OnlinePrefs = OnlinePrefs.new(path).load_file()
	_check(r.crash_mode == OnlinePrefs.CRASH_ASK and not r.discord_presence, "prefs: junk falls back to private defaults")
	DirAccess.remove_absolute(path)
	_check(CrashReporter.is_crash(11) and CrashReporter.is_crash(1) and not CrashReporter.is_crash(0) \
		and not CrashReporter.is_crash(-1), "crash: exit codes")
	_check(CrashReporter.MAX_BYTES <= 65536, "crash: payload within the server limit")
	# A crash on the watched process is seen (exit code 3 from a shell).
	var cr: CrashReporter = CrashReporter.new()
	var pid: int = OS.create_process("/bin/sh", PackedStringArray(["-c", "exit 3"]))
	cr.watch(pid)
	while OS.is_process_running(pid):
		OS.delay_msec(20)
	_check(OS.get_process_exit_code(pid) == 3, "crash: exit code visible after another watcher reaped it")
	cr.free()
	# No encrypted link: send_crash_report sends nothing.
	var login: LauncherLogin = LauncherLogin.new()
	_check(not login.send_crash_report(PackedByteArray([1, 2, 3])), "crash: nothing sent without an encrypted link")
	login.free()


func _test_social() -> void:
	var list: Array = [
		{"id": "1", "status": 0, "relation": 0, "display_name": "zed"},
		{"id": "2", "status": 3, "relation": 0, "display_name": "Bea"},
		{"id": "3", "status": 1, "relation": 0, "display_name": "amy"},
		{"id": "4", "status": 0, "relation": 1, "display_name": "Req"},
		{"id": "5", "status": 0, "relation": 2, "display_name": "Out"},
		{"id": "6", "status": 0, "relation": 3, "display_name": "Blk"},
	]
	var g: Dictionary = SocialView.group(list)
	_check((g.friends as Array).map(func(e: Dictionary) -> String: return String(e.id)) == ["2", "3", "1"], "friends: sorted by presence")
	_check((g.incoming as Array).size() == 1 and (g.outgoing as Array).size() == 1 and (g.blocked as Array).size() == 1, "friends: grouped")
	var pr: Dictionary = SocialView.party_rows({"members": [
		{"id": "m", "kind": AccountCodec.PARTY_MEMBER}, {"id": "l", "kind": AccountCodec.PARTY_LEADER},
		{"id": "i", "kind": AccountCodec.PARTY_INVITE_IN}, {"id": "o", "kind": AccountCodec.PARTY_INVITE_OUT}]})
	_check(String(pr.members[0].id) == "l" and (pr.members as Array).size() == 2, "party: leader first")
	_check((pr.invites_in as Array).size() == 1 and (pr.invites_out as Array).size() == 1, "party: invites split")
	_check(SocialView.action_text(AccountCodec.OP_PARTY_INVITE, AccountCodec.E_LIMIT) == "The party is full.", "party: full text")
	_check(SocialView.action_text(AccountCodec.OP_FRIEND_REQUEST, AccountCodec.E_NOT_FOUND).begins_with("No player"), "friends: not found text")
	# Party op round trip through the shared codec.
	var b: PackedByteArray = AccountCodec.encode_result(AccountCodec.OP_PARTY, AccountCodec.OK, {"party": "ab".repeat(16),
		"leader": "cd".repeat(16), "members": [{"id": "cd".repeat(16), "kind": 0, "status": 2, "display_name": "Lead", "emblem": 1, "accent": 2}]})
	var d: Dictionary = AccountCodec.decode_result(b)
	_check(String(d.members[0].display_name) == "Lead" and int(d.members[0].status) == 2, "party: codec round trip")
