class_name LobbyStatusWriter
extends RefCounted
## Publishes a tiny anonymous status file for the launcher (players online / in
## lobby / in match). Only counts are written, never names or ids (GDPR). The
## file lives in the directory the update host serves (TCP 8080 in the
## container), so the launcher reads it next to version.json, e.g.
## https://cyber-api.djboeck.at/status.json
##
## Enabled by the CYBERGRAM_STATUS_FILE environment variable (absolute path);
## when it is empty the writer does nothing.
##
## W15: the operator's message of the day (MOTD) rides along as "motd". It is
## read from the text file named by CYBERGRAM_MOTD_FILE (re-read on every
## write, so it can change without a restart), made plain text (control,
## invisible and bidi characters removed, whitespace collapsed to single
## spaces) and cut to OnlineRulesDef.motd_max_chars. No file = no "motd". The file is replaced atomically
## (write a temp file, then rename) so the host never serves half a file.

## Environment variable that names the output file.
const ENV_PATH: String = "CYBERGRAM_STATUS_FILE"
## Environment variable that names the MOTD text file (W15).
const ENV_MOTD: String = "CYBERGRAM_MOTD_FILE"
## Bytes read from the MOTD file at most (the rest is ignored).
const MOTD_READ_MAX: int = 8192
## Minimum seconds between two writes while nothing changes.
const REFRESH_S: float = 10.0

var path: String = ""
var motd_path: String = ""
var motd_max_chars: int = 200
var _since: float = REFRESH_S
var _last: String = ""


## `path_` empty reads the environment variable.
func _init(path_: String = "", motd_path_: String = "") -> void:
	path = path_ if path_ != "" else OS.get_environment(ENV_PATH)
	motd_path = motd_path_ if motd_path_ != "" else OS.get_environment(ENV_MOTD)
	motd_max_chars = OnlineRulesDef.load_default().motd_max_chars


## True when a target file is configured.
func enabled() -> bool:
	return path != ""


## Builds the status JSON text. `in_match` says whether the running phase is a
## match; `connected` is the number of connected players. `max_players` is the
## capacity (0 = unknown). `now_unix` is injected for tests.
## `motd`: the already sanitised message of the day ("" = none).
static func build(connected: int, in_match: bool, max_players: int, now_unix: int, motd: String = "") -> String:
	var lobby_n: int = 0 if in_match else connected
	var match_n: int = connected if in_match else 0
	var d := {
		"online": connected, "in_lobby": lobby_n, "in_match": match_n,
		"max_players": max_players, "updated": now_unix,
	}
	if motd != "":
		d["motd"] = motd
	return JSON.stringify(d)


## Plain one-paragraph text of at most `max_chars` characters: control,
## invisible and bidi-override characters removed, any whitespace run
## (newlines too) becomes one space, trimmed.
static func sanitize_motd(raw: String, max_chars: int) -> String:
	var out := ""
	var space := false
	for i in raw.length():
		var c := raw.unicode_at(i)
		if ChatFilter._is_space(c):
			space = true
			continue
		if ChatFilter._is_invisible(c) or c < 0x20 or c == 0x7F:
			continue
		if space and out != "":
			out += " "
		space = false
		out += String.chr(c)
		if out.length() >= max_chars:
			break
	return out.substr(0, max_chars)


## The MOTD from motd_path, sanitised ("" when unset or unreadable).
func read_motd() -> String:
	if motd_path == "" or not FileAccess.file_exists(motd_path):
		return ""
	var f := FileAccess.open(motd_path, FileAccess.READ)
	if f == null:
		return ""
	var raw := f.get_buffer(mini(f.get_length(), MOTD_READ_MAX)).get_string_from_utf8()
	return sanitize_motd(raw, motd_max_chars)


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
	return write_now(build(connected, in_match, max_players, int(Time.get_unix_time_from_system()), read_motd()))


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
