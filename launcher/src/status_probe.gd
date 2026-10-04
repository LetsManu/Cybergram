class_name StatusProbe
extends Node
## Probes the game server through the update host (plain HTTP, no login):
## reachable = the host answered; counts come from the optional status.json
## the game server's lobby writes (anonymous numbers only).

## Emitted with {"reachable": bool, "has_counts": bool, "online": int,
## "in_lobby": int, "in_match": int}.
signal probed(info: Dictionary)

const TIMEOUT_S: float = 5.0

var last: Dictionary = {"reachable": false, "has_counts": false}
var _http: HTTPRequest


## Requests <base>/status.json. Any HTTP answer from the host counts as
## reachable; a 404 simply means no counts are published.
func probe(version_url: String) -> void:
	if _http != null:
		_http.cancel_request()
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	add_child(_http)
	_http.request_completed.connect(_on_done)
	if _http.request(LauncherCore.base_url(version_url) + "status.json") != OK:
		_finish({"reachable": false, "has_counts": false})


func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish({"reachable": false, "has_counts": false})
		return
	var info: Dictionary = LauncherCore.parse_status(body.get_string_from_utf8()) if code == 200 else {}
	if info.is_empty():
		info = {"has_counts": false}
	info["reachable"] = true
	_finish(info)


func _finish(info: Dictionary) -> void:
	last = info
	probed.emit(info)
