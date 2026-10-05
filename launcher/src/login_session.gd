class_name LauncherLogin
extends Node
## Signs the player in on the game server so the game can start already logged
## in. It reuses the game's own protocol scripts (src/shared/, copies of
## src/networking/... made by tools/sync_shared.sh): LobbyClient, AccountCodec,
## ENetTransport, AuthConfig.
##
## Security rules:
## - A password is only ever sent over an encrypted (DTLS) link. If the server
##   has no certificate the link falls back to plain UDP, `guest_only` becomes
##   true and login() refuses; the launcher then offers "Play" without login.
## - Nothing is written to disk. The launcher's own session token never
##   leaves this object. At Play, `request_launch` asks the server for a
##   single-use launch token (60 s, bound to this account, only on DTLS) and
##   `hand_over_env` passes that to the game through environment variables
##   (LaunchHandoff; not the command line, which other users can read).
## - The link also gives the server round-trip time (`rtt_ms`, ENet's own
##   ping) for the status widget, and carries friends / party requests.

## Seconds to wait for the launch token before starting the game unsigned.
const LAUNCH_TIMEOUT_S: float = 5.0

## The link to the server is ready. `secure` = DTLS (logins allowed).
signal link_ready(secure: bool)
## No connection could be made (message is player-facing).
signal link_failed(message: String)
## Result of login(): ok, player-facing message, display name when ok.
signal login_result(ok: bool, message: String, display_name: String)
## Every ACCOUNT_RESULT other than login ({op, code, ...}): friends, party.
signal account_result(result: Dictionary)
## Answer to request_launch(): the hand-over ({token, server, account}) or {}.
signal launch_ready(handoff: Dictionary)

var server: String = ""
var secure: bool = false
## True once a plain (unencrypted) link is all the server offers.
var guest_only: bool = false
var link_up: bool = false

var _enet: ENetTransport
var _client: LobbyClient
var _token: String = ""
var _display_name: String = ""
var _account_id: String = ""
var _launch_wait: float = -1.0
var _rtt: int = -1
var _ping_sent_us: int = 0


## Connects to `address` ("host:port"). Hostnames try DTLS first and fall back
## to plain UDP when the handshake never completes (guest-only server).
func open(address: String) -> void:
	close()
	server = address
	link_up = false
	secure = false
	_connect()


func _connect() -> void:
	var hp: PackedStringArray = server.rsplit(":", true, 1)
	var host: String = hp[0]
	var port: int = ENetTransport.DEFAULT_PORT
	if hp.size() == 2 and hp[1].is_valid_int():
		port = clampi(hp[1].to_int(), 1, 65535)
	_enet = ENetTransport.connect_to(host, port, AuthConfig.from_os().client_tls_for(host))
	if _enet.error_text != "":
		var msg: String = _enet.error_text
		_enet = null
		link_failed.emit(msg)
		return
	_client = LobbyClient.new(_enet)
	_client.account_result.connect(_on_account)


## True while a session token is held and the link is still up.
func is_logged_in() -> bool:
	return _token != "" and _enet != null and _enet.error_text == "" and link_up


## Display name of the signed-in account ("" when not logged in).
func display_name() -> String:
	return _display_name


## Player id of the signed-in account ("" when not logged in).
func account_id() -> String:
	return _account_id if is_logged_in() else ""


## Sends any account request (friends, party) on the signed-in link. False
## when not logged in on an encrypted link.
func request(op: int, fields: Dictionary = {}) -> bool:
	if not is_logged_in() or not secure:
		return false
	_client.request(op, fields)
	return true


## Round-trip time to the game server in ms: the last OP_PING probe answer
## (falls back to ENet's running average before the first one), -1 while
## there is no link.
func rtt_ms() -> int:
	if _enet == null or not link_up:
		return -1
	return _rtt if _rtt >= 0 else -1


## Sends one RTT probe (OP_PING, no fields; the server answers at once). The
## answer updates rtt_ms(). Works signed in or not, plain or encrypted.
func ping() -> void:
	if _client == null or not link_up or _ping_sent_us > 0:
		return
	_ping_sent_us = Time.get_ticks_usec()
	_client.request(AccountCodec.OP_PING)


## Sends a crash report (gzip bytes) in AccountCodec.CHUNK_MAX chunks. Only on
## an encrypted link (signed in or not); the answer arrives as an
## account_result with op OP_CRASH_CHUNK. False when nothing was sent.
func send_crash_report(payload: PackedByteArray) -> bool:
	if _client == null or not link_up or not secure or not _enet.is_secure or payload.is_empty():
		return false
	var n: int = ceili(float(payload.size()) / AccountCodec.CHUNK_MAX)
	for i in n:
		_client.request(AccountCodec.OP_CRASH_CHUNK, {"seq": i, "total": n,
			"data": payload.slice(i * AccountCodec.CHUNK_MAX, (i + 1) * AccountCodec.CHUNK_MAX)})
	return true


## Asks the server for a single-use launch token; `launch_ready` answers with
## the hand-over or {} (not logged in, not encrypted, refused, timed out).
## Never asks over a plain link: a launch token is an account credential.
func request_launch() -> void:
	if not is_logged_in() or not secure or not _enet.is_secure:
		launch_ready.emit.call_deferred({})
		return
	_launch_wait = LAUNCH_TIMEOUT_S
	_client.request(AccountCodec.OP_LAUNCH_TOKEN)


## Sends the login. Refused on an unencrypted link. The caller should clear its
## password field right after this call; this object never keeps the password.
func login(username: String, password: String) -> void:
	if _client == null or not link_up:
		login_result.emit(false, "Not connected to the server.", "")
		return
	if not secure:
		login_result.emit(false, "This server has no encrypted login. Play as a guest instead.", "")
		return
	_client.request(AccountCodec.OP_LOGIN, {"ver": MsgType.PROTOCOL_VERSION,
		"username": username.strip_edges(), "password": password})


## Signs out (the server forgets the session) and drops the token.
func logout() -> void:
	if _client != null and link_up:
		_client.request(AccountCodec.OP_LOGOUT)
	_token = ""
	_display_name = ""
	_account_id = ""


func _process(delta: float) -> void:
	if _launch_wait >= 0.0:
		_launch_wait -= delta
		if _launch_wait < 0.0:
			launch_ready.emit({})
	if _client == null:
		return
	_client.step()
	if _enet.is_server_connected() and not link_up:
		link_up = true
		secure = _enet.is_secure
		guest_only = not secure
		link_ready.emit(secure)
	if _enet.error_text != "":
		if _enet.is_secure and not link_up and not AuthConfig.plain_hosts.has(_host_of(server)):
			# No certificate on the server yet: retry once in plain UDP (guest only).
			AuthConfig.plain_hosts[_host_of(server)] = true
			_enet.close()
			_enet = null
			_client = null
			_connect()
			return
		var was_up: bool = link_up
		var msg: String = "Cannot reach the game server %s." % server if not was_up else "Lost the connection to the game server."
		close()
		link_failed.emit(msg)


static func _host_of(address: String) -> String:
	return address.rsplit(":", true, 1)[0]


func _on_account(d: Dictionary) -> void:
	var op: int = int(d.get("op", 0))
	if op == AccountCodec.OP_PING:
		if _ping_sent_us > 0:
			_rtt = int((Time.get_ticks_usec() - _ping_sent_us) / 1000)
			_ping_sent_us = 0
		return
	if op == AccountCodec.OP_LAUNCH_TOKEN:
		if _launch_wait < 0.0:
			return  # timed out already
		_launch_wait = -1.0
		var h: Dictionary = {}
		if int(d.code) == AccountCodec.OK:
			h = {"token": str(d.token), "server": server, "account": _account_id}
		launch_ready.emit(h if not LaunchHandoff.parse({LaunchHandoff.ENV_TOKEN: h.get("token", ""),
			LaunchHandoff.ENV_SERVER: server, LaunchHandoff.ENV_ACCOUNT: _account_id}).is_empty() else {})
		return
	if op != AccountCodec.OP_LOGIN:
		account_result.emit(d)
		return
	if int(d.code) == AccountCodec.OK and d.has("token"):
		_token = str(d.token)
		_account_id = str(d.get("id", ""))
		_display_name = str(d.get("display_name", d.get("username", "")))
		login_result.emit(true, "Signed in as %s" % _display_name, _display_name)
	else:
		login_result.emit(false, error_text(int(d.code)), "")


## Player-facing text for an account result code.
static func error_text(code: int) -> String:
	match code:
		AccountCodec.E_CREDENTIALS:
			return "Wrong username or password."
		AccountCodec.E_LOCKED:
			return "Too many failed logins. Try again in a few minutes."
		AccountCodec.E_VERSION:
			return "The launcher and the server versions differ. Update the launcher."
		AccountCodec.E_NOT_SECURE:
			return "This server has no encrypted login."
		AccountCodec.E_BUSY:
			return "The server is busy. Try again."
		AccountCodec.E_BAD_REQUEST:
			return "Enter your username and password."
	return "Login failed (code %d)." % code


## Passes the launch token `h` (from launch_ready) to this process's
## environment so the game started right after inherits it. Call clear_env()
## after starting the child. False when `h` is empty or malformed.
static func hand_over_env(h: Dictionary) -> bool:
	return LaunchHandoff.put_into_os(h)


## Removes the hand-over variables from the launcher's own environment.
static func clear_env() -> void:
	LaunchHandoff.clear_os()


## Stops everything (no logout: the session just expires after the grace).
func close() -> void:
	if _enet != null:
		_enet.close()
	_enet = null
	_client = null
	link_up = false
	_token = ""
	_display_name = ""
	_account_id = ""
	_rtt = -1
	_ping_sent_us = 0
