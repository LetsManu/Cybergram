class_name OpsLog
extends RefCounted
## Structured server log lines (P1, docs/monitoring.md). One record per call:
##   {ts, level, comp, event, msg, player?, party?, lobby?, match?, ...}
## CYBERGRAM_LOG_FORMAT=json prints one JSON object per line (Docker / log
## shippers); anything else prints the classic text line "[comp] msg" so
## existing log greps keep working.
##
## Privacy (PRIVACY.md "Server logs"): account ids never appear in clear.
## `tag(id)` is a short salted hash, stable for the process (or across
## restarts when CYBERGRAM_LOG_SALT is set), enough to follow one player
## through the log without naming them. Party, lobby and match ids are random
## ids with no personal data and appear as they are. Never pass names, chat
## text, passwords, tokens or recovery codes in `fields`.
##
## Example:
##   OpsLog.emit(OpsLog.record("front", OpsLog.INFO, "queue_join", "party of 2 joined",
##       {"player": OpsLog.tag(id), "party": pid}))

const DEBUG := "debug"
const INFO := "info"
const WARN := "warn"
const ERROR := "error"

const ENV_FORMAT := "CYBERGRAM_LOG_FORMAT"
const ENV_SALT := "CYBERGRAM_LOG_SALT"

static var _json: int = -1  # -1 = not read yet
static var _salt: String = ""


## True when JSON lines are on (CYBERGRAM_LOG_FORMAT=json).
static func json_mode() -> bool:
	if _json < 0:
		_json = 1 if OS.get_environment(ENV_FORMAT).strip_edges().to_lower() == "json" else 0
	return _json == 1


## Tests: force a format (true = JSON) or -1 to re-read the environment.
static func set_json_mode(on: int) -> void:
	_json = on


## Pseudonymous tag of an account id ("" for "").
static func tag(account_id: String) -> String:
	if account_id == "":
		return ""
	if _salt == "":
		_salt = OS.get_environment(ENV_SALT)
		if _salt == "":
			_salt = Crypto.new().generate_random_bytes(16).hex_encode()
	return (_salt + ":" + account_id).sha256_text().left(10)


## A log record. `fields` with empty values are dropped.
static func record(comp: String, level: String, event: String, msg: String, fields: Dictionary = {},
		ts: float = -1.0) -> Dictionary:
	var r := {"ts": Time.get_unix_time_from_system() if ts < 0.0 else ts, "level": level, "comp": comp,
		"event": event, "msg": msg}
	for k in fields:
		var v: Variant = fields[k]
		if v == null or (v is String and v == "") or (v is StringName and v == &""):
			continue
		r[k] = v
	return r


## The printable line of a record in the current format.
static func format(r: Dictionary) -> String:
	if json_mode():
		var o := r.duplicate()
		o.ts = Time.get_datetime_string_from_unix_time(int(float(r.ts)), true) + "Z"
		return JSON.stringify(o)
	return "[%s] %s" % [r.comp, r.msg]


## Prints a record (stdout; Docker keeps it).
static func emit(r: Dictionary) -> void:
	print(format(r))
