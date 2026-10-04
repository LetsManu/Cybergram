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
## - Nothing is written to disk. The session token lives in this object until
##   `hand_over_env` passes it to the game through environment variables
##   (not the command line, which other users can read) and forgets it.

const ENV_TOKEN: String = "CYBERGRAM_SESSION_TOKEN"
const ENV_SERVER: String = "CYBERGRAM_SESSION_SERVER"
## Milliseconds to wait after closing the link so the server detaches the
## session before the game resumes it (the server keeps it for its grace).
const DETACH_WAIT_MS: int = 400

## The link to the server is ready. `secure` = DTLS (logins allowed).
signal link_ready(secure: bool)
## No connection could be made (message is player-facing).
signal link_failed(message: String)
## Result of login(): ok, player-facing message, display name when ok.
signal login_result(ok: bool, message: String, display_name: String)

var server: String = ""
var secure: bool = false
## True once a plain (unencrypted) link is all the server offers.
var guest_only: bool = false
var link_up: bool = false

var _enet: ENetTransport
var _client: LobbyClient
var _token: String = ""
var _display_name: String = ""


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


func _process(_delta: float) -> void:
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
	if int(d.get("op", 0)) != AccountCodec.OP_LOGIN:
		return
	if int(d.code) == AccountCodec.OK and d.has("token"):
		_token = str(d.token)
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


## Closes the link without logging out. The server keeps the session for its
## grace period (60 s) so the game can resume it with the token.
func detach() -> void:
	if _enet != null:
		_enet.close()
		OS.delay_msec(DETACH_WAIT_MS)
	_enet = null
	_client = null
	link_up = false


## Passes the session to this process's environment (inherited by a child
## started right after) and forgets it here. Returns false when not logged in.
## Call `clear_env` after starting the child.
func hand_over_env() -> bool:
	if not is_logged_in():
		return false
	var token: String = _token
	_token = ""
	detach()
	OS.set_environment(ENV_TOKEN, token)
	OS.set_environment(ENV_SERVER, server)
	return true


## Removes the hand-over variables from the launcher's own environment.
static func clear_env() -> void:
	OS.unset_environment(ENV_TOKEN)
	OS.unset_environment(ENV_SERVER)


## Stops everything (no logout: the session just expires after the grace).
func close() -> void:
	if _enet != null:
		_enet.close()
	_enet = null
	_client = null
	link_up = false
	_token = ""
	_display_name = ""
