class_name ConnectionRejects
extends Logger
## Counts and logs refused connections by reason (owner plan 2026-10-06,
## docs/connecting.md, docs/monitoring.md): /metrics counter
## `cybergram_connections_rejected_total{reason}` and one structured log line
## per reason and interval (rate-limited: a client retrying its handshake would
## otherwise flood the log).
##
## Reasons:
##   plain_udp            a client sent plain (unencrypted) ENet to the DTLS port
##                        (a bare-IP connect); engine "TLS handshake error: -30464"
##   bad_certificate      the client refused our certificate (name mismatch or
##                        untrusted); engine "TLS handshake error: -30592"
##   handshake_other      any other DTLS handshake error (code in the log)
##   version_mismatch     the client runs another protocol version
##   auth                 wrong credentials, locked account or invalid session
## The two DTLS reasons come from the engine's own error log (this Logger is
## added with OS.add_logger): Godot does not report the failed handshake to
## scripts, nor its source address, so those lines carry no IP. Version and
## auth rejections come from AccountService with the peer address, logged
## masked (last IPv4 octet / last 80 bits of IPv6 zeroed, GDPR) unless
## CYBERGRAM_LOG_FULL_IP=1 is set for troubleshooting.
##
## Engine callbacks can arrive on any thread: they only touch a mutex-guarded
## counter; flush() (main thread, from the front's poll) moves them into
## metrics and the log.
##
## Example:
##   var rej := ConnectionRejects.new()
##   OS.add_logger(rej)
##   rej.note("auth", "203.0.113.7")
##   rej.flush(metrics, now_s)   # every poll

const METRIC := "cybergram_connections_rejected_total"
const ENV_FULL_IP := "CYBERGRAM_LOG_FULL_IP"
## mbedtls error codes from the DTLS handshake (engine log text).
const CODE_PLAIN := -30464     # MBEDTLS_ERR_SSL_UNEXPECTED_MESSAGE-class: not a DTLS record
const CODE_CERT := -30592      # MBEDTLS_ERR_SSL_FATAL_ALERT_MESSAGE: the client aborted (certificate)
## Seconds between log lines for the same reason.
const LOG_INTERVAL_S: float = 10.0

var _mutex := Mutex.new()
var _pending: Dictionary = {}   # reason -> count since the last flush
var _since_log: Dictionary = {}  # reason -> count not logged yet
var _sources: Dictionary = {}   # reason -> last masked source ("" = unknown)
var _last_log: Dictionary = {}  # reason -> time of the last log line
var _codes: Dictionary = {}     # handshake_other -> last code
## Where log records go (tests inject a collector).
var log_sink: Callable = func(rec: Dictionary) -> void: OpsLog.emit(rec)


## Reason for an engine error line, or "" when it is not a DTLS handshake error. Pure.
static func reason_of_engine_error(function: String, code: String) -> String:
	if function != "_do_handshake" or not code.begins_with("TLS handshake error"):
		return ""
	var n := int(code.get_slice(":", 1).strip_edges())
	if n == CODE_PLAIN:
		return "plain_udp"
	if n == CODE_CERT:
		return "bad_certificate"
	return "handshake_other"


## `ip` masked for the log (last IPv4 octet, or the IPv6 interface part, zeroed). Pure.
static func mask_ip(ip: String, full: bool = false) -> String:
	if ip == "" or full:
		return ip
	if ip.contains(":"):
		var p := ip.split(":")
		var keep := mini(3, p.size())
		return ":".join(p.slice(0, keep)) + "::"
	var q := ip.split(".")
	if q.size() != 4:
		return ""
	return "%s.%s.%s.0" % [q[0], q[1], q[2]]


func _log_error(function: String, _file: String, _line: int, code: String, _rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var r := reason_of_engine_error(function, code)
	if r == "":
		return
	_mutex.lock()
	_pending[r] = int(_pending.get(r, 0)) + 1
	if r == "handshake_other":
		_codes[r] = code
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


## An application-level rejection (version_mismatch, auth) from `ip`.
func note(reason: String, ip: String = "") -> void:
	_mutex.lock()
	_pending[reason] = int(_pending.get(reason, 0)) + 1
	if ip != "":
		_sources[reason] = mask_ip(ip, OS.get_environment(ENV_FULL_IP) == "1")
	_mutex.unlock()


## Moves the counts into `metrics` and writes at most one log line per reason
## per LOG_INTERVAL_S (`now` in seconds). Main thread.
func flush(metrics: OpsMetrics, now: float) -> void:
	_mutex.lock()
	var batch := _pending
	_pending = {}
	var codes := _codes.duplicate()
	_mutex.unlock()
	for r: String in batch:
		if metrics != null:
			metrics.inc(METRIC, {"reason": r}, float(batch[r]))
		_since_log[r] = int(_since_log.get(r, 0)) + int(batch[r])
	for r: String in _since_log.keys():
		if int(_since_log[r]) <= 0 or now - float(_last_log.get(r, -INF)) < LOG_INTERVAL_S:
			continue
		var fields := {"reason": r, "count": int(_since_log[r]), "source": _sources.get(r, "unknown")}
		if codes.has(r):
			fields["code"] = codes[r]
		log_sink.call(OpsLog.record("front", OpsLog.WARN, "connection_rejected",
			"%d connection(s) rejected: %s" % [int(_since_log[r]), r], fields))
		_since_log[r] = 0
		_last_log[r] = now
