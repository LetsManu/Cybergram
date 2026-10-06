class_name ConnectionWatch
extends RefCounted
## W21-U2: watchdog for the online connection of the menu (link, then login).
## Pure logic (no engine nodes): the owner feeds it events and ticks. It
## guarantees the player never waits forever: a link or login that does not
## complete within the configured time, a transport error, a DTLS failure or a
## version mismatch ends in `failed(reason_key)`, a HUD_ translation key the UI
## shows next to a Retry button.
##
## Logging is privacy-safe: server host:port, phases and reason codes only,
## never a username, password or token.
##
## Example:
##   var w := ConnectionWatch.new()
##   w.failed.connect(func(key: String) -> void: show_error(tr(key)))
##   w.begin("cyber.example:7777", true)
##   w.tick(delta)       # every frame
##   w.on_link_up()      # transport connected
##   w.on_login_ok()     # account result with a session

## The link / login did not complete (or ended); `reason_key` is a HUD_ key.
signal failed(reason_key: String)

## Where a connection attempt stands. LINKED = the link is up and no sign-in
## request is out (the player may be typing on the login form: no timer runs).
enum Phase {
	IDLE,  ## not watching
	CONNECTING,  ## waiting for the UDP / DTLS link (connect timeout runs)
	LINKED,  ## link up, nothing requested yet (no timeout)
	LOGIN,  ## a sign-in request is out (login timeout runs)
	READY,  ## a session was granted
	FAILED,  ## gave up; `failed` was emitted
}
## Why an attempt failed; reason_key() gives the HUD_ translation key.
enum Reason {
	TIMEOUT_CONNECT,  ## no link in time (server down, wrong address, UDP blocked)
	TIMEOUT_LOGIN,  ## link up but the sign-in request got no answer
	DNS,  ## the host name could not be resolved
	DTLS,  ## the encrypted handshake failed
	VERSION,  ## the server runs another protocol version
	DISCONNECTED,  ## the link dropped after it was up
	ERROR,  ## anything else
	PLAIN_IP,  ## no answer to a plain-UDP connect to a bare IP (servers need DTLS + a name)
}

## Timeouts (data: assets/data/net/connection_watch.tres).
var config: ConnectionWatchConfig
## Current phase (see Phase).
var phase: Phase = Phase.IDLE
## Reason of the last failure (valid in Phase.FAILED).
var reason: Reason = Reason.ERROR
## Where log lines go (a Callable taking a String); tests inject a collector.
var log_sink: Callable = func(line: String) -> void: print(line)

var _target: String = ""
var _secure: bool = false
var _elapsed: float = 0.0
var _request_pending: bool = false  # a sign-in request was sent before the link came up


func _init(config_: ConnectionWatchConfig = null) -> void:
	config = config_ if config_ != null else ConnectionWatchConfig.load_default()


## Starts watching a new connection attempt to `target` ("host:port").
func begin(target: String, secure: bool) -> void:
	_target = target
	_secure = secure
	_elapsed = 0.0
	_request_pending = false
	phase = Phase.CONNECTING
	_log("connect start %s (%s)" % [target, "dtls" if secure else "plain udp"])


## True while a timeout is running.
func is_waiting() -> bool:
	return phase == Phase.CONNECTING or phase == Phase.LOGIN


## A sign-in request (login, register, guest, resume, redeem) was sent: the
## login timeout starts now. Before the link is up it starts with the link.
func on_request_sent() -> void:
	if phase == Phase.CONNECTING:
		_request_pending = true
	elif phase == Phase.LINKED or phase == Phase.LOGIN:
		phase = Phase.LOGIN
		_elapsed = 0.0


## The transport reports the server link as up (DTLS handshake done when secure).
func on_link_up() -> void:
	if phase != Phase.CONNECTING:
		return
	_log("link up%s after %.1fs" % [" (dtls handshake ok)" if _secure else "", _elapsed])
	phase = Phase.LOGIN if _request_pending else Phase.LINKED
	_elapsed = 0.0


## A session was granted (login, resume, redeem or guest ok).
func on_login_ok() -> void:
	if phase == Phase.READY or phase == Phase.IDLE:
		return
	_log("login ok after %.1fs" % _elapsed)
	phase = Phase.READY


## The server answered a request with an error code (code number only).
func on_account_error(op: int, code: int) -> void:
	_log("account op %d answered code %d" % [op, code])
	if code == AccountCodec.E_VERSION:
		_fail(Reason.VERSION)
	elif phase == Phase.LOGIN:
		phase = Phase.LINKED  # answered (e.g. wrong password): the player may try again
		_elapsed = 0.0


## The server rejected the client (protocol / version mismatch).
func on_reject(code: int) -> void:
	_log("rejected by server (code %d)" % code)
	_fail(Reason.VERSION)


## The transport reported `error_text`; `link_was_up` = the link had been up.
func on_transport_error(error_text: String, link_was_up: bool) -> void:
	_log("transport error: %s (link was up: %s)" % [error_text, link_was_up])
	_fail(classify_error(error_text, _secure, link_was_up))


## Advances the timeouts by `delta` seconds.
func tick(delta: float) -> void:
	if not is_waiting():
		return
	_elapsed += delta
	if phase == Phase.CONNECTING and _elapsed >= config.connect_timeout_s:
		_fail(timeout_reason(_target, _secure))
	elif phase == Phase.LOGIN and _elapsed >= config.login_timeout_s:
		_fail(Reason.TIMEOUT_LOGIN)


## Stops watching (the player left, or the attempt was replaced).
func stop() -> void:
	phase = Phase.IDLE


func _fail(r: Reason) -> void:
	if phase == Phase.FAILED or phase == Phase.IDLE:
		return
	reason = r
	phase = Phase.FAILED
	_log("failed: %s" % Reason.keys()[r])
	failed.emit(reason_key(r))


func _log(text: String) -> void:
	if log_sink.is_valid():
		log_sink.call("[net] %s" % text)


## Reason for a connect timeout to `target` ("host:port"): a plain-UDP link to
## a bare IP gets its own explanation (an encrypted server never answers it).
static func timeout_reason(target: String, secure: bool) -> Reason:
	var host := target.get_slice(":", 0) if target.count(":") == 1 else target
	if not secure and host.is_valid_ip_address() and not host.begins_with("127.") and host != "::1":
		return Reason.PLAIN_IP
	return Reason.TIMEOUT_CONNECT


## Maps a transport error text to a reason.
static func classify_error(error_text: String, secure: bool, link_was_up: bool) -> Reason:
	if error_text.contains("DNS") or error_text.contains("cannot find server"):
		return Reason.DNS
	if secure and not link_was_up:
		return Reason.DTLS
	if link_was_up:
		return Reason.DISCONNECTED
	return Reason.TIMEOUT_CONNECT  # no link, no DTLS: down, refused or blocked


## HUD_ key of the player-facing message for `r`.
static func reason_key(r: Reason) -> String:
	match r:
		Reason.TIMEOUT_CONNECT:
			return "HUD_NET_ERR_TIMEOUT"
		Reason.TIMEOUT_LOGIN:
			return "HUD_NET_ERR_LOGIN_TIMEOUT"
		Reason.DNS:
			return "HUD_NET_ERR_DNS"
		Reason.DTLS:
			return "HUD_NET_ERR_DTLS"
		Reason.VERSION:
			return "HUD_NET_ERR_VERSION"
		Reason.DISCONNECTED:
			return "HUD_NET_ERR_DISCONNECTED"
		Reason.PLAIN_IP:
			return "HUD_NET_ERR_PLAIN_IP"
	return "HUD_NET_ERR_GENERIC"
