class_name OpsHttpServer
extends RefCounted
## Tiny HTTP/1.0 endpoint for operations (P1, docs/monitoring.md). Runs inside
## the front process, polled from its main loop (no thread, never blocks):
##   GET /health       readiness: 200 {"status":"ok",...} or 503 {"status":"degraded",...}
##   GET /health/live  liveness: 200 while the main loop runs
##   GET /metrics      Prometheus text (OpsMetrics)
##   GET /admin        live parties / queues / matches / last events (HTML)
##   GET /admin.json   the same as JSON
##   GET /admin/accounts(.json)  registered accounts, newest first (no passwords)
## /admin* needs CYBERGRAM_ADMIN_TOKEN: "Authorization: Bearer <token>" or
## HTTP Basic with any user name and the token as password (browsers ask for
## it). Without a configured token the admin pages answer 404.
##
## Off unless CYBERGRAM_OPS_PORT is set. Bind address CYBERGRAM_OPS_BIND
## (default 0.0.0.0 inside the container; publish the port to the LAN /
## monitoring host only, never through the public reverse proxy).
## Limits: OPEN_MAX connections, REQ_MAX bytes per request, TIMEOUT_MS per
## connection; anything else is dropped. Only GET / HEAD.
##
## Example:
##   ops = OpsHttpServer.new()
##   ops.health = func() -> Dictionary: return {"ready": true, "version": "v0.17.0"}
##   ops.metrics = func() -> String: return metrics.render()
##   ops.admin = func() -> Dictionary: return front.admin_snapshot()
##   ops.listen(8090)
##   ops.poll()   # every frame

const ENV_PORT := "CYBERGRAM_OPS_PORT"
const ENV_BIND := "CYBERGRAM_OPS_BIND"
const ENV_TOKEN := "CYBERGRAM_ADMIN_TOKEN"
const OPEN_MAX := 8
const REQ_MAX := 8192
const TIMEOUT_MS := 2000

## func() -> Dictionary with at least "ready": bool.
var health: Callable = func() -> Dictionary: return {"ready": true}
## func() -> String (Prometheus text).
var metrics: Callable = func() -> String: return ""
## func() -> Dictionary (admin snapshot).
var admin: Callable = func() -> Dictionary: return {}
## func() -> Dictionary (accounts list: {total, shown, rows}).
var accounts: Callable = func() -> Dictionary: return {}
## Admin token ("" = admin pages disabled).
var admin_token: String = ""
## Requests answered (tests, metrics).
var served: int = 0

var _server: TCPServer
## [{peer: StreamPeerTCP, buf: PackedByteArray, since: int}]
var _open: Array = []


## Port and token from the environment; returns false when the port is unset.
func listen_from_env() -> bool:
	var p := OS.get_environment(ENV_PORT).strip_edges()
	if p == "" or not p.is_valid_int():
		return false
	admin_token = OS.get_environment(ENV_TOKEN).strip_edges()
	var bind := OS.get_environment(ENV_BIND).strip_edges()
	return listen(int(p), bind if bind != "" else "*") == OK


func listen(port: int, bind: String = "*") -> Error:
	_server = TCPServer.new()
	return _server.listen(port, bind)


## The bound port (tests listen on 0).
func port() -> int:
	return _server.get_local_port() if _server != null else 0


func is_listening() -> bool:
	return _server != null and _server.is_listening()


func stop() -> void:
	for c in _open:
		(c.peer as StreamPeerTCP).disconnect_from_host()
	_open.clear()
	if _server != null:
		_server.stop()


## Accepts, reads and answers; call every frame.
func poll() -> void:
	if _server == null:
		return
	var now := Time.get_ticks_msec()
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _open.size() >= OPEN_MAX:
			peer.disconnect_from_host()
			continue
		_open.append({"peer": peer, "buf": PackedByteArray(), "since": now})
	for c in _open.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		var st := peer.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED or now - int(c.since) > TIMEOUT_MS:
			peer.disconnect_from_host()
			_open.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_partial_data(mini(n, REQ_MAX + 1 - (c.buf as PackedByteArray).size()))
			if int(got[0]) == OK:
				c.buf = (c.buf as PackedByteArray) + (got[1] as PackedByteArray)
		var text := (c.buf as PackedByteArray).get_string_from_ascii()
		var end := text.find("\r\n\r\n")
		if end < 0 and (c.buf as PackedByteArray).size() <= REQ_MAX:
			continue
		var res := respond_raw(text.substr(0, end) if end >= 0 else "")
		peer.put_data(encode_response(res))
		peer.disconnect_from_host()
		_open.erase(c)
		served += 1


## Parses a request head and answers it.
func respond_raw(head: String) -> Dictionary:
	var lines := head.split("\r\n")
	var parts := lines[0].split(" ") if not lines.is_empty() else PackedStringArray()
	if parts.size() < 2:
		return _res(400, "text/plain", "bad request\n")
	var headers := {}
	for i in range(1, lines.size()):
		var c := lines[i].find(":")
		if c > 0:
			headers[lines[i].substr(0, c).strip_edges().to_lower()] = lines[i].substr(c + 1).strip_edges()
	return respond(parts[0], parts[1], headers)


## The answer to one request (pure: no socket). {status, type, body, headers}.
func respond(method: String, path: String, headers: Dictionary) -> Dictionary:
	if method != "GET" and method != "HEAD":
		return _res(405, "text/plain", "method not allowed\n", {"Allow": "GET, HEAD"})
	var q := path.find("?")
	if q >= 0:
		path = path.substr(0, q)
	var r: Dictionary
	match path:
		"/health":
			var h: Dictionary = health.call()
			var ok := bool(h.get("ready", false))
			var body := h.duplicate()
			body.erase("ready")
			body.status = "ok" if ok else "degraded"
			r = _res(200 if ok else 503, "application/json", JSON.stringify(body) + "\n")
		"/health/live":
			r = _res(200, "application/json", "{\"status\":\"alive\"}\n")
		"/metrics":
			r = _res(200, "text/plain; version=0.0.4", str(metrics.call()))
		"/admin", "/admin/", "/admin.json", "/admin/accounts", "/admin/accounts.json":
			if admin_token == "":
				r = _res(404, "text/plain", "not found\n")
			elif not authorized(headers.get("authorization", "")):
				r = _res(401, "text/plain", "unauthorized\n", {"WWW-Authenticate": "Basic realm=\"cybergram admin\""})
			elif path == "/admin.json":
				r = _res(200, "application/json", JSON.stringify(admin.call()) + "\n")
			elif path == "/admin/accounts.json":
				r = _res(200, "application/json", JSON.stringify(accounts.call()) + "\n")
			elif path == "/admin/accounts":
				r = _res(200, "text/html; charset=utf-8", OpsAdminPage.accounts_html(accounts.call()))
			else:
				r = _res(200, "text/html; charset=utf-8", OpsAdminPage.html(admin.call()))
		_:
			r = _res(404, "text/plain", "not found\n")
	if method == "HEAD":
		r.body = ""
	return r


## True when the Authorization header carries the admin token.
func authorized(header: String) -> bool:
	if admin_token == "":
		return false
	var given := ""
	if header.begins_with("Bearer "):
		given = header.substr(7).strip_edges()
	elif header.begins_with("Basic "):
		var dec := Marshalls.base64_to_raw(header.substr(6).strip_edges()).get_string_from_utf8()
		var c := dec.find(":")
		given = dec.substr(c + 1) if c >= 0 else ""
	return constant_time_equal(given, admin_token)


static func constant_time_equal(a: String, b: String) -> bool:
	var x := a.sha256_buffer()
	var y := b.sha256_buffer()
	var diff := 0
	for i in x.size():
		diff |= x[i] ^ y[i]
	return diff == 0


static func encode_response(r: Dictionary) -> PackedByteArray:
	var body := (r.body as String).to_utf8_buffer()
	var reason: String = {200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
		405: "Method Not Allowed", 503: "Service Unavailable"}.get(int(r.status), "OK")
	var head := "HTTP/1.0 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n" % [
		int(r.status), reason, r.type, body.size()]
	for k in r.headers:
		head += "%s: %s\r\n" % [k, r.headers[k]]
	return (head + "\r\n").to_utf8_buffer() + body


static func _res(status: int, type: String, body: String, headers: Dictionary = {}) -> Dictionary:
	return {"status": status, "type": type, "body": body, "headers": headers}
