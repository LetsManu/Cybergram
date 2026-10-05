class_name CrashReporter
extends Node
## Watches the game's exit code and, after a crash (any non-zero
## code: an error exit or a signal such as 11 = SIGSEGV), handles the opt-in
## crash report (W15):
## - OnlinePrefs.crash_mode "ask" (default): a prompt "Send crash report?"
##   with SEND / DON'T SEND and an "Always ask" box, plus the privacy note;
## - "always": sent without asking (the player opted in); "never": nothing.
## The payload is LauncherDiagnostics.crash_payload (strictly redacted logs +
## system info, gzip, <= MAX_BYTES), sent in 1 KB chunks on the launcher's
## link to the game server, and ONLY when that link is DTLS-encrypted.

signal game_exited(code: int)
## A report was sent (ok) or failed (message is player-facing).
signal report_done(ok: bool, message: String)

const POLL_S: float = 0.5
## Must not exceed the server's OnlineRulesDef.crash_max_bytes.
const MAX_BYTES: int = 65536
const SEND_TIMEOUT_S: float = 30.0
const PRIVACY_NOTE: String = "The report holds the game and launcher logs with passwords, tokens, IP addresses and player ids removed, plus basic system info (OS, CPU, GPU, RAM). It is sent encrypted to the Cybergram server, used only to fix crashes, and deleted after 30 days. Legal basis: your consent. See PRIVACY.md."

var prefs: OnlinePrefs
var login: LauncherLogin
var server: String = ""
var launcher_version: String = ""
var game_version: Callable = Callable()
## Where prompts go (the launcher root).
var ui_parent: Control
var pid: int = -1
var last_exit: int = 0
var sending: bool = false
var _since: float = 0.0
var _wait: float = -1.0


## Watches the game process `pid_` (started by LauncherUx.launch) for its
## exit code. Godot keeps the code of a reaped child, so both watchers see it.
func watch(pid_: int) -> void:
	pid = pid_ if pid_ > 0 else -1
	_since = 0.0


## True while the started game runs.
func running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func _process(delta: float) -> void:
	if _wait >= 0.0:
		_wait -= delta
		if _wait < 0.0:
			_finish(false, "The crash report could not be sent (no answer from the server).")
	if pid <= 0:
		return
	_since += delta
	if _since < POLL_S:
		return
	_since = 0.0
	if OS.is_process_running(pid):
		return
	last_exit = OS.get_process_exit_code(pid)
	pid = -1
	game_exited.emit(last_exit)
	if is_crash(last_exit):
		after_crash(last_exit)


## Any non-zero exit is a crash (-1 = unknown is not).
static func is_crash(code: int) -> bool:
	return code != 0 and code != -1


## Applies the player's choice for a crash with `code`.
func after_crash(code: int) -> void:
	match OnlinePrefs.crash_action(prefs.crash_mode):
		"send":
			send(code)
		"ask":
			prompt(code)


## The consent prompt. Returns it (screenshots, tests).
func prompt(code: int, preview: bool = false) -> UiModal:
	var t: UiKitTokens = UiKit.tokens()
	var keep: CheckBox = CheckBox.new()
	var m: UiModal = UiKit.modal(ui_parent, "THE GAME CLOSED UNEXPECTEDLY",
		"Cybergram stopped with error code %d. Send a crash report to help fix it?" % code, "SEND",
		func() -> void:
			_remember(true, keep.button_pressed)
			if not preview:
				send(code),
		"DON'T SEND", func() -> void: _remember(false, keep.button_pressed))
	m.card.custom_minimum_size.x = 520
	var note: Label = UiKit.label(PRIVACY_NOTE, &"small", t.text_off)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.card.body.add_child(note)
	m.card.body.move_child(note, 1)
	keep.text = "Always ask (untick to remember this choice; change it in Settings > Privacy)"
	keep.button_pressed = true
	m.card.body.add_child(keep)
	m.card.body.move_child(keep, 2)
	return m


func _remember(send_: bool, keep_asking: bool) -> void:
	prefs.crash_mode = OnlinePrefs.mode_after_prompt(send_, keep_asking)
	prefs.save_file()


## Builds and sends the report (needs an encrypted link; opens one if needed).
func send(code: int) -> void:
	if sending:
		return
	var gv: String = String(game_version.call()) if game_version.is_valid() else ""
	var payload: PackedByteArray = LauncherDiagnostics.crash_payload(LauncherDiagnostics.default_log_dirs(),
		LauncherDiagnostics.system_info(launcher_version, gv), code, MAX_BYTES)
	if payload.is_empty():
		_finish(false, "The crash report was too large to send.")
		return
	sending = true
	_wait = SEND_TIMEOUT_S
	if login.link_up:
		_upload(payload)
		return
	login.link_ready.connect(func(_secure: bool) -> void: _upload(payload), CONNECT_ONE_SHOT)
	login.open(server)


func _upload(payload: PackedByteArray) -> void:
	if not login.secure:
		_finish(false, "The server has no encrypted connection, so the crash report was not sent.")
		return
	if not login.account_result.is_connected(_on_result):
		login.account_result.connect(_on_result)
	if not login.send_crash_report(payload):
		_finish(false, "The crash report could not be sent.")


func _on_result(d: Dictionary) -> void:
	if int(d.get("op", 0)) != AccountCodec.OP_CRASH_CHUNK or not sending:
		return
	match int(d.code):
		AccountCodec.OK:
			_finish(true, "Crash report sent. Thank you.")
		AccountCodec.E_RATE:
			_finish(false, "Too many crash reports from this computer today; this one was not sent.")
		_:
			_finish(false, "The server did not accept the crash report (code %d)." % int(d.code))


func _finish(ok: bool, message: String) -> void:
	sending = false
	_wait = -1.0
	report_done.emit(ok, message)
	if ui_parent != null and DisplayServer.get_name() != "headless":
		UiKit.toast(ui_parent, message, &"info" if ok else &"warn", 4.0)
