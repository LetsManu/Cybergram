class_name LobbyStatusWriter
extends RefCounted
## Publishes a tiny anonymous status file for the launcher (players online / in
## lobby / in match). Only counts are written, never names or ids (GDPR). The
## file lives in the directory the update host serves (TCP 8080), so the
## launcher reads it over plain HTTP: http://<server>:8080/status.json
##
## Enabled by the CYBERGRAM_STATUS_FILE environment variable (absolute path);
## when it is empty the writer does nothing. The file is replaced atomically
## (write a temp file, then rename) so the host never serves half a file.

## Environment variable that names the output file.
const ENV_PATH: String = "CYBERGRAM_STATUS_FILE"
## Minimum seconds between two writes while nothing changes.
const REFRESH_S: float = 10.0

var path: String = ""
var _since: float = REFRESH_S
var _last: String = ""


## `path_` empty reads the environment variable.
func _init(path_: String = "") -> void:
	path = path_ if path_ != "" else OS.get_environment(ENV_PATH)


## True when a target file is configured.
func enabled() -> bool:
	return path != ""


## Builds the status JSON text. `in_match` says whether the running phase is a
## match; `connected` is the number of connected players. `max_players` is the
## capacity (0 = unknown). `now_unix` is injected for tests.
static func build(connected: int, in_match: bool, max_players: int, now_unix: int) -> String:
	var lobby_n: int = 0 if in_match else connected
	var match_n: int = connected if in_match else 0
	return JSON.stringify({
		"online": connected, "in_lobby": lobby_n, "in_match": match_n,
		"max_players": max_players, "updated": now_unix,
	})


## Call every lobby frame. Writes when the counts changed or REFRESH_S passed.
## Returns true when a file write happened.
func tick(delta: float, connected: int, in_match: bool, max_players: int) -> bool:
	if not enabled():
		return false
	_since += delta
	var sig: String = "%d/%s/%d" % [connected, str(in_match), max_players]
	if sig == _last and _since < REFRESH_S:
		return false
	_since = 0.0
	_last = sig
	return write_now(build(connected, in_match, max_players, int(Time.get_unix_time_from_system())))


## Atomically replaces the file with `text`. Returns false on any I/O error
## (the server keeps running; a missing status is not fatal).
func write_now(text: String) -> bool:
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true
