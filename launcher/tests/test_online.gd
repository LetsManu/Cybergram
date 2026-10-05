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
