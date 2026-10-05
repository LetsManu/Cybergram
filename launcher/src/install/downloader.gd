class_name LauncherDownloader
extends Node
## One HTTP(S) download into a `.part` file that survives pause, a crash or a
## closed launcher: a restart asks for the rest with `Range: bytes=<have>-`
## (a server that ignores Range answers 200 and the file starts over).
## Optional speed limit in bytes per second (0 = unlimited). Polls an
## HTTPClient from _process, so it needs no threads (W15-UPD).

## ok = the whole body is in `part_path`. `error` is a short human text.
signal finished(ok: bool, error: String)

const CONNECT_TIMEOUT_MS: int = 10000
const IDLE_TIMEOUT_MS: int = 30000
## Redirects followed per download (GitHub release assets redirect once).
const MAX_REDIRECTS: int = 5

var url: String = ""
var part_path: String = ""
## Bytes per second, 0 = unlimited. May be changed while running.
var limit_bps: int = 0
## Expected size (from the signed manifest), used when the server sends none.
var expected_size: int = 0
## Bytes in the .part file so far (including what an earlier run fetched).
var got: int = 0
## Total size when known (else 0).
var total: int = 0
## True while a request is open.
var active: bool = false
## Set by the response: true when the server honoured the Range request.
var resumed: bool = false

var _client: HTTPClient
var _file: FileAccess
var _host: String = ""
var _port: int = 80
var _tls: bool = false
var _path: String = "/"
var _requested: bool = false
var _budget: float = 0.0
var _last_io: int = 0
var _started: int = 0
var _redirects: int = 0
## Response headers, captured on the first poll that has them (HTTPClient
## drops them once an empty body is finished).
var _hdr: Dictionary = {}


## Splits "http(s)://host[:port]/path". Returns {} when the URL is unusable.
static func split_url(u: String) -> Dictionary:
	var tls: bool = u.begins_with("https://")
	if not tls and not u.begins_with("http://"):
		return {}
	var rest: String = u.substr(8 if tls else 7)
	var slash: int = rest.find("/")
	var hostport: String = rest if slash < 0 else rest.substr(0, slash)
	var path: String = "/" if slash < 0 else rest.substr(slash)
	var port: int = 443 if tls else 80
	var colon: int = hostport.rfind(":")
	if colon > 0 and not hostport.ends_with("]"):
		port = hostport.substr(colon + 1).to_int()
		hostport = hostport.substr(0, colon)
	if hostport == "" or port <= 0:
		return {}
	return {"tls": tls, "host": hostport, "port": port, "path": path}


## Starts (or resumes) the download of `url_` into `part_path_`.
func start(url_: String, part_path_: String, expected: int = 0) -> void:
	_redirects = 0
	_open(url_, part_path_, expected)


func _open(url_: String, part_path_: String, expected: int) -> void:
	stop()
	url = url_
	part_path = part_path_
	expected_size = expected
	var u: Dictionary = split_url(url)
	if u.is_empty():
		_finish(false, "bad download URL")
		return
	_host = u["host"]
	_port = u["port"]
	_tls = u["tls"]
	_path = u["path"]
	DirAccess.make_dir_recursive_absolute(part_path.get_base_dir())
	got = 0
	if FileAccess.file_exists(part_path):
		var f := FileAccess.open(part_path, FileAccess.READ)
		if f != null:
			got = f.get_length()
			f.close()
	if expected_size > 0 and got > expected_size:
		DirAccess.remove_absolute(part_path)
		got = 0
	if expected_size > 0 and got == expected_size:
		total = got
		_finish.call_deferred(true, "")
		return
	_client = HTTPClient.new()
	_client.read_chunk_size = 65536
	var err: Error = _client.connect_to_host(_host, _port, TLSOptions.client() if _tls else null)
	if err != OK:
		_finish(false, "cannot connect (%s)" % error_string(err))
		return
	active = true
	_requested = false
	_hdr = {}
	_budget = 0.0
	_started = Time.get_ticks_msec()
	_last_io = _started


## Closes the connection and keeps the .part file (pause).
func stop() -> void:
	active = false
	if _file != null:
		_file.close()
		_file = null
	if _client != null:
		_client.close()
		_client = null


func _process(delta: float) -> void:
	if not active or _client == null:
		return
	_client.poll()
	if _requested and _hdr.is_empty() and _client.has_response():
		_hdr = _client.get_response_headers_as_dictionary()
	var st: HTTPClient.Status = _client.get_status()
	var now: int = Time.get_ticks_msec()
	match st:
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			if now - _started > CONNECT_TIMEOUT_MS:
				_finish(false, "connection timed out")
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				_requested = true
				var headers := PackedStringArray(["User-Agent: CybergramLauncher", "Accept-Encoding: identity"])
				if got > 0:
					headers.append("Range: bytes=%d-" % got)
				var err: Error = _client.request(HTTPClient.METHOD_GET, _path, headers)
				if err != OK:
					_finish(false, "request failed (%s)" % error_string(err))
			elif _file != null:
				_complete()  # keep-alive: body done, connection back to idle
			elif _client.has_response():
				_open_body()  # a response without a body (redirect, error)
		HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_BODY:
			if _file == null and not _open_body():
				return
			_read_body(delta, now)
		HTTPClient.STATUS_DISCONNECTED:
			if _file != null:
				_complete()
			else:
				_finish(false, "the server closed the connection")
		_:
			_finish(false, "network error (%d)" % st)
	if active and now - _last_io > IDLE_TIMEOUT_MS:
		_finish(false, "the download stalled")


func _open_body() -> bool:
	var code: int = _client.get_response_code()
	var length: int = _client.get_response_body_length()
	if code in [301, 302, 303, 307, 308]:
		var loc: String = ""
		for k: Variant in _hdr:
			if String(k).to_lower() == "location":
				loc = String(_hdr[k]).strip_edges()
		_redirects += 1
		if loc == "" or _redirects > MAX_REDIRECTS or not (loc.begins_with("https://") or loc.begins_with("http://")):
			_finish(false, "bad redirect (HTTP %d)" % code)
			return false
		_open.call_deferred(loc, part_path, expected_size)
		stop()
		return false
	if code == 416 and got > 0:
		# Nothing left to send: the part is already complete (hash decides).
		total = got
		_finish(true, "")
		return false
	if code == 206:
		resumed = true
		_file = FileAccess.open(part_path, FileAccess.READ_WRITE if FileAccess.file_exists(part_path) else FileAccess.WRITE)
		if _file != null:
			_file.seek_end()
		total = got + length if length >= 0 else expected_size
	elif code == 200:
		resumed = false
		got = 0
		_file = FileAccess.open(part_path, FileAccess.WRITE)
		total = length if length >= 0 else expected_size
	else:
		_finish(false, "HTTP %d" % code)
		return false
	if _file == null:
		_finish(false, "cannot write %s" % part_path.get_file())
		return false
	return true


func _read_body(delta: float, now: int) -> void:
	if limit_bps > 0:
		_budget = minf(_budget + limit_bps * delta, float(limit_bps) * 0.25 + 16384.0)
		_client.read_chunk_size = clampi(limit_bps / 20, 4096, 65536)
	else:
		_client.read_chunk_size = 65536
	for _i in range(256):
		if _client.get_status() != HTTPClient.STATUS_BODY:
			break
		if limit_bps > 0 and _budget < float(_client.read_chunk_size):
			break
		var chunk: PackedByteArray = _client.read_response_body_chunk()
		if chunk.is_empty():
			break
		_file.store_buffer(chunk)
		got += chunk.size()
		_budget -= chunk.size()
		_last_io = now
	if _client.get_status() != HTTPClient.STATUS_BODY:
		_complete()


func _complete() -> void:
	if not active:
		return
	if total > 0 and got < total:
		_finish(false, "the download was cut off")
		return
	_finish(true, "")


func _finish(ok: bool, err: String) -> void:
	stop()
	finished.emit(ok, err)
