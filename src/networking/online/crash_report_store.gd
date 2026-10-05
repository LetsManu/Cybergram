class_name CrashReportStore
extends RefCounted
## Server side of the opt-in crash reporter (W15, PRIVACY.md "Crash reports").
## Accepts a gzip-compressed JSON report ({"kind": "crash", ...}) that the
## launcher redacted, and keeps it as one file in `dir`:
## - size limit per report (OnlineRulesDef.crash_max_bytes) and per folder
##   (crash_dir_cap_mb: the oldest reports go first);
## - rate limits per source address (per hour) and per account (per day),
##   kept in memory only and forgotten after a day;
## - deleted automatically after crash_retention_days (sweep() at start and
##   daily from AccountService.step);
## - the file holds only the report: no address, account or player id is
##   added; folder 0700, files 0600 (Unix).
## Time is injected (`now_unix`) so tests are deterministic.

enum Result { OK, TOO_BIG, MALFORMED, RATE_LIMITED, STORE_FAILED }

## Uncompressed size a report may expand to (a zip-bomb guard).
const MAX_UNPACKED: int = 8 * 1024 * 1024
const PREFIX := "crash-"
const SUFFIX := ".json.gz"

var dir: String
var rules: OnlineRulesDef
var _by_source: Dictionary = {}   # source key -> Array[int] unix times (last hour)
var _by_account: Dictionary = {}  # account id -> Array[int] unix times (last day)


func _init(dir_: String, rules_: OnlineRulesDef = null) -> void:
	dir = dir_
	rules = rules_ if rules_ != null else OnlineRulesDef.load_default()


## False when `source` / `account_id` ("" = no account) used up their budget.
func allowed(source: String, account_id: String, now_unix: int) -> bool:
	_trim(now_unix)
	if (_by_source.get(source, []) as Array).size() >= rules.crash_per_ip_per_hour:
		return false
	if account_id != "" and (_by_account.get(account_id, []) as Array).size() >= rules.crash_per_account_per_day:
		return false
	return true


## Validates and stores one report. Counts against the limits when stored.
func accept(payload: PackedByteArray, source: String, account_id: String, now_unix: int) -> Result:
	if payload.is_empty() or payload.size() > rules.crash_max_bytes:
		return Result.TOO_BIG
	if not allowed(source, account_id, now_unix):
		return Result.RATE_LIMITED
	var raw := payload.decompress_dynamic(MAX_UNPACKED, FileAccess.COMPRESSION_GZIP)
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8()) if not raw.is_empty() else null
	if typeof(parsed) != TYPE_DICTIONARY or str((parsed as Dictionary).get("kind", "")) != "crash":
		return Result.MALFORMED
	var abs_dir := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		if DirAccess.make_dir_recursive_absolute(abs_dir) != OK:
			return Result.STORE_FAILED
		_owner_only(abs_dir, 448)  # 0700
	var name := "%s%d-%s%s" % [PREFIX, now_unix, Crypto.new().generate_random_bytes(4).hex_encode(), SUFFIX]
	var path := abs_dir.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return Result.STORE_FAILED
	f.store_buffer(payload)
	f.close()
	_owner_only(path, 384)  # 0600
	(_by_source.get_or_add(source, []) as Array).append(now_unix)
	if account_id != "":
		(_by_account.get_or_add(account_id, []) as Array).append(now_unix)
	enforce_cap()
	return Result.OK


## Deletes reports older than the retention period. Returns how many.
func sweep(now_unix: int) -> int:
	var n := 0
	var limit := now_unix - rules.crash_retention_days * 86400
	for e: Array in _files():
		if int(e[1]) < limit and DirAccess.remove_absolute(e[0]) == OK:
			n += 1
	return n


## Deletes the oldest reports until the folder is under its cap.
func enforce_cap() -> void:
	var files := _files()
	var total := 0
	for e: Array in files:
		total += int(e[2])
	var cap := rules.crash_dir_cap_mb * 1048576
	for e: Array in files:  # oldest first
		if total <= cap:
			break
		if DirAccess.remove_absolute(e[0]) == OK:
			total -= int(e[2])


## Number of stored reports (tests, logs).
func count() -> int:
	return _files().size()


## [[abs path, unix time, size]] of the stored reports, oldest first.
func _files() -> Array:
	var abs_dir := ProjectSettings.globalize_path(dir)
	var out: Array = []
	if not DirAccess.dir_exists_absolute(abs_dir):
		return out
	for f in DirAccess.get_files_at(abs_dir):
		if not (f.begins_with(PREFIX) and f.ends_with(SUFFIX)):
			continue
		var stamp := f.trim_prefix(PREFIX).get_slice("-", 0)
		if not stamp.is_valid_int():
			continue
		var p := abs_dir.path_join(f)
		var fa := FileAccess.open(p, FileAccess.READ)
		out.append([p, stamp.to_int(), fa.get_length() if fa != null else 0])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) < int(b[1]))
	return out


func _trim(now_unix: int) -> void:
	for k in _by_source.keys():
		var l: Array = (_by_source[k] as Array).filter(func(t: int) -> bool: return now_unix - t < 3600)
		if l.is_empty():
			_by_source.erase(k)
		else:
			_by_source[k] = l
	for k in _by_account.keys():
		var l: Array = (_by_account[k] as Array).filter(func(t: int) -> bool: return now_unix - t < 86400)
		if l.is_empty():
			_by_account.erase(k)
		else:
			_by_account[k] = l


static func _owner_only(path: String, mode: int) -> void:
	if OS.get_name() in ["Linux", "macOS", "FreeBSD"]:
		FileAccess.set_unix_permissions(path, mode)
